#!/usr/bin/env bash
# UT5 — Saga de reserva y pago. Reserva y pago viven en servicios y bases distintos: ya no hay una
# transacción ACID que los abarque. Reservas orquesta: PENDIENTE -> cobro en Pagos -> CONFIRMADA,
# o CANCELADA (compensación), o PENDIENTE hasta que el reconciliador sepa qué pasó con el pago.
source "$(dirname "$0")/lib.sh"
titulo "Saga de reserva y pago"
preparar_docente 5 >/dev/null
set -- $HORARIOS
estado_reserva() { psql_reservas "SELECT estado FROM reservas.reservas WHERE id=$1"; }

paso "1. Pago aprobado => CONFIRMADA"
req POST /api/reservas "{\"docenteId\":$DOC_ID,\"horarioId\":$1,\"tokenPago\":\"tok_ok\"}" "$EST_TOKEN"
check "201 y CONFIRMADA" "201 CONFIRMADA" "$CODIGO $(echo "$CUERPO" | jq -r .reserva.estado)"

paso "2. Doble reserva del mismo horario => 409 (índice único en db-reservas)"
req POST /api/reservas "{\"docenteId\":$DOC_ID,\"horarioId\":$1,\"tokenPago\":\"tok_ok\"}" "$EST_TOKEN"
check "segunda reserva" "409" "$CODIGO"

paso "3. Pago rechazado => compensación: CANCELADA y el horario queda libre"
req POST /api/reservas "{\"docenteId\":$DOC_ID,\"horarioId\":$2,\"tokenPago\":\"RECHAZAR\"}" "$EST_TOKEN"
check "pago rechazado" "402" "$CODIGO"
check "reserva compensada" "CANCELADA" "$(psql_reservas "SELECT estado FROM reservas.reservas WHERE horario_id=$2 ORDER BY id DESC LIMIT 1")"
req POST /api/reservas "{\"docenteId\":$DOC_ID,\"horarioId\":$2,\"tokenPago\":\"tok_ok\"}" "$EST_TOKEN"
check "el mismo horario se puede volver a reservar" "201" "$CODIGO"

paso "4. Pagos tarda más que el timeout (2 s) => 202 PENDIENTE; el reconciliador la resuelve"
T0=$(ahora_ms)
req POST /api/reservas "{\"docenteId\":$DOC_ID,\"horarioId\":$3,\"tokenPago\":\"LENTO\"}" "$EST_TOKEN"
info "respondió en $(( $(ahora_ms) - T0 )) ms (corta en el timeout de 2 s, no espera los 5 s del procesador)"
RID=$(echo "$CUERPO" | jq -r .reserva.id)
check "202 y PENDIENTE" "202 PENDIENTE" "$CODIGO $(echo "$CUERPO" | jq -r .reserva.estado)"
_confirmada() { [ "$(estado_reserva "$RID")" = "CONFIRMADA" ]; }
esperar_hasta 25 _confirmada
check "el reconciliador consultó Pagos (idempotente) y la confirmó" "CONFIRMADA" "$(estado_reserva "$RID")"
check "se cobró una sola vez" "1" "$(psql_en db-pagos "SELECT count(*) FROM pagos.pagos WHERE reserva_id=$RID")"

paso "5. Pagos caído => se compensa en el acto y, tras varias fallas, el circuito se abre"
# El circuito es por réplica y Nginx reparte casi al azar: con 2 réplicas, cada una puede ver menos
# de 5 fallas dentro de la ventana de 10 s y el circuito no abrir. Igual que en la demo de la UT4,
# se usa 1 réplica de Reservas durante este paso (al final se vuelve a 2).
info "se reduce Reservas a 1 réplica para este paso"
docker compose up -d --no-deps --scale reservas=1 reservas >/dev/null 2>&1
esperar_sano 120 >/dev/null; sleep 6 # DNS del gateway (valid=5s) deja de ver la réplica quitada
docker compose stop pagos >/dev/null 2>&1
CODIGOS_PAGOS=""
for i in $(seq 1 12); do
  CODIGOS_PAGOS="$CODIGOS_PAGOS $(curl -s -k -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer $EST_TOKEN" \
    -d "{\"docenteId\":$DOC_ID,\"horarioId\":$4,\"tokenPago\":\"tok_ok\"}" "$BASE/api/reservas" | jq -r .error.codigo)"
done
info "códigos: $CODIGOS_PAGOS"
check "nunca se confirmó sin pago (todas 503)" "0" "$(echo $CODIGOS_PAGOS | tr ' ' '\n' | grep -cvE 'NO_DISPONIBLE|CIRCUITO_ABIERTO')"
check "el circuito hacia Pagos llegó a abrirse" "true" "$(echo "$CODIGOS_PAGOS" | grep -q CIRCUITO_ABIERTO && echo true || echo false)"
check "ninguna reserva de ese horario quedó tomada" "0" "$(psql_reservas "SELECT count(*) FROM reservas.reservas WHERE horario_id=$4 AND estado <> 'CANCELADA'")"
docker compose start pagos >/dev/null 2>&1
docker compose up -d --no-deps --scale reservas=2 reservas >/dev/null 2>&1
esperar_healthy 90
esperar_sano 120 >/dev/null; sleep 6 # el gateway vuelve a ver las 2 réplicas

paso "6. Reserva PENDIENTE sin pago tras 30 s => el reconciliador ANULA el cobro en Pagos y recién ahí cancela"
info "(se simula una reserva que quedó PENDIENTE hace 40 s y cuyo cobro nunca llegó a Pagos)"
RID=$(psql_reservas "WITH n AS (INSERT INTO reservas.reservas (estudiante_id, docente_id, horario_id, estado, monto, creada_en)
  VALUES (0, $DOC_ID, $5, 'PENDIENTE', 500, now() - interval '40 seconds') RETURNING id) SELECT id FROM n")
_cancelada() { [ "$(estado_reserva "$RID")" = "CANCELADA" ]; }
esperar_hasta 20 _cancelada
check "la reserva quedó CANCELADA" "CANCELADA" "$(estado_reserva "$RID")"
check "Pagos tiene el cobro ANULADO (fence)" "ANULADO" "$(psql_en db-pagos "SELECT estado FROM pagos.pagos WHERE reserva_id=$RID")"
info "llega tarde el cobro de esa reserva (p. ej. un pedido que estaba demorado):"
TARDE=$(docker compose exec -T --index 1 reservas node -e '
  fetch("http://pagos:3000/internal/pagos", { method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ reservaId: Number(process.argv[1]), monto: 500, tokenPago: "tok_ok" }) })
    .then((r) => r.json()).then((b) => console.log(b.estado));' "$RID")
check "el cobro tardío no se aprueba" "ANULADO" "$TARDE"
check "ningún pago aprobado para una reserva cancelada" "0" \
  "$(psql_en db-pagos "SELECT count(*) FROM pagos.pagos WHERE reserva_id=$RID AND estado='APROBADO'")"
resumen
