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
esperar_healthy 90
resumen
