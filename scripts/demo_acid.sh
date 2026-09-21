#!/usr/bin/env bash
# Demo 4: ACID — aislamiento (doble reserva), atomicidad (pago rechazado) y durabilidad (restart de la base).
source "$(dirname "$0")/lib.sh"

titulo "DEMO 4 — ACID (transacciones en PostgreSQL)"

paso "Preparación: docente aprobado con 2 horarios y 2 estudiantes mayores"
esperar_sano 120
registrar "docente_$SUFIJO@demo.uy" "Docente ACID" DOCENTE; DOC_ID="$USUARIO_ID"
login "docente_$SUFIJO@demo.uy"; DOC_TOKEN="$TOKEN"
req POST /api/docentes/me/horarios "$(jq -nc --arg i "$(fecha_futura 5 10)" --arg f "$(fecha_futura 5 11)" '{inicio:$i,fin:$f,precio:600}')" "$DOC_TOKEN"
H1=$(echo "$CUERPO" | jq -r '.id')
req POST /api/docentes/me/horarios "$(jq -nc --arg i "$(fecha_futura 5 12)" --arg f "$(fecha_futura 5 13)" '{inicio:$i,fin:$f,precio:600}')" "$DOC_TOKEN"
H2=$(echo "$CUERPO" | jq -r '.id')
aprobar_docente "$DOC_ID"
registrar "estA_$SUFIJO@demo.uy" "Estudiante A" ESTUDIANTE; login "estA_$SUFIJO@demo.uy"; TOK_A="$TOKEN"
registrar "estB_$SUFIJO@demo.uy" "Estudiante B" ESTUDIANTE; login "estB_$SUFIJO@demo.uy"; TOK_B="$TOKEN"

paso "AISLAMIENTO: dos reservas SIMULTÁNEAS sobre el mismo horario ($H1)"
TMP=$(mktemp -d)
BODY=$(jq -nc --argjson d "$DOC_ID" --argjson h "$H1" '{docenteId:$d,horarioId:$h,tokenPago:"tok"}')
for quien in A B; do
  tok=TOK_$quien
  ( curl -s -o "$TMP/$quien.body" -w '%{http_code}' -X POST "$BASE/api/reservas" \
      -H 'Content-Type: application/json' -H "Authorization: Bearer ${!tok}" -d "$BODY" > "$TMP/$quien.code" ) &
done
wait
CA=$(cat "$TMP/A.code"); CB=$(cat "$TMP/B.code")
info "Estudiante A → HTTP $CA  $(cat "$TMP/A.body")"
info "Estudiante B → HTTP $CB  $(cat "$TMP/B.body")"
check "exactamente un 201 y un 409" "201 409" "$(printf '%s\n%s\n' "$CA" "$CB" | sort | tr '\n' ' ' | sed 's/ $//')"
check "una sola fila para el horario en la base" 1 "$(psql_escalar "SELECT count(*) FROM reservas.reservas WHERE horario_id=$H1")"
GANADOR=$( [ "$CA" = 201 ] && cat "$TMP/A.body" || cat "$TMP/B.body" )
RES_ID=$(echo "$GANADOR" | jq -r '.reserva.id')
TOK_GANADOR=$( [ "$CA" = 201 ] && echo "$TOK_A" || echo "$TOK_B" )
rm -rf "$TMP"

paso "ATOMICIDAD: pago rechazado sobre el horario $H2 no deja ninguna fila"
RES_ANTES=$(psql_escalar "SELECT count(*) FROM reservas.reservas")
PAG_ANTES=$(psql_escalar "SELECT count(*) FROM reservas.pagos")
info "Antes: reservas=$RES_ANTES pagos=$PAG_ANTES"
req POST /api/reservas "$(jq -nc --argjson d "$DOC_ID" --argjson h "$H2" '{docenteId:$d,horarioId:$h,tokenPago:"RECHAZAR"}')" "$TOK_A"
check "pago rechazado" 402 "$CODIGO"
RES_DESPUES=$(psql_escalar "SELECT count(*) FROM reservas.reservas")
PAG_DESPUES=$(psql_escalar "SELECT count(*) FROM reservas.pagos")
info "Después: reservas=$RES_DESPUES pagos=$PAG_DESPUES"
check "reservas sin cambios" "$RES_ANTES" "$RES_DESPUES"
check "pagos sin cambios" "$PAG_ANTES" "$PAG_DESPUES"
req POST /api/reservas "$(jq -nc --argjson d "$DOC_ID" --argjson h "$H2" '{docenteId:$d,horarioId:$h,tokenPago:"tok"}')" "$TOK_B"
check "el horario quedó libre: se puede reservar luego" 201 "$CODIGO"

paso "DURABILIDAD: docker compose restart db y la reserva confirmada sigue existiendo"
docker compose restart db 2>&1 | tail -2
esperar_sano 120
CODIGO=000
for _ in $(seq 1 10); do
  req GET "/api/reservas/$RES_ID" "" "$TOK_GANADOR"
  [ "$CODIGO" = 200 ] && break
  sleep 2
done
check "la reserva sobrevivió al reinicio de la base" 200 "$CODIGO"

resumen
