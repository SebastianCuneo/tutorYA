#!/usr/bin/env bash
# Demo 3: servicios sin estado. Se cae la réplica que atendió y el mismo token funciona en otra.
source "$(dirname "$0")/lib.sh"

titulo "DEMO 3 — Servicios sin estado"

paso "Preparación: 2 réplicas de reservas"
docker compose up -d --scale reservas=2 --scale nucleo=2 2>&1 | tail -3
esperar_sano 120; sleep 6

paso "Docente aprobado con un horario y un estudiante"
registrar "docente_$SUFIJO@demo.uy" "Docente SinEstado" DOCENTE; DOC_ID="$USUARIO_ID"
login "docente_$SUFIJO@demo.uy"; DOC_TOKEN="$TOKEN"
req POST /api/docentes/me/horarios "$(jq -nc --arg i "$(fecha_futura 4 10)" --arg f "$(fecha_futura 4 11)" '{inicio:$i,fin:$f,precio:400}')" "$DOC_TOKEN"
HORARIO_ID=$(echo "$CUERPO" | jq -r '.id')
aprobar_docente "$DOC_ID"
registrar "estudiante_$SUFIJO@demo.uy" "Estudiante SinEstado" ESTUDIANTE
login "estudiante_$SUFIJO@demo.uy"; EST_TOKEN="$TOKEN"

paso "Login hecho una sola vez; se crea una reserva"
req POST /api/reservas "$(jq -nc --argjson d "$DOC_ID" --argjson h "$HORARIO_ID" '{docenteId:$d,horarioId:$h,tokenPago:"tok"}')" "$EST_TOKEN"
check "reserva creada" 201 "$CODIGO"
RES_ID=$(echo "$CUERPO" | jq -r '.reserva.id')
INST_A="$INSTANCIA"
info "Atendió la instancia: $INST_A"

paso "docker stop de esa réplica ($INST_A)"
docker stop "$INST_A" >/dev/null && info "contenedor $INST_A detenido"

paso "Mismo token, GET /api/reservas/$RES_ID"
INST_B=""
for _ in 1 2 3 4 5; do
  req GET "/api/reservas/$RES_ID" "" "$EST_TOKEN"
  INST_B="$INSTANCIA"
  [ "$CODIGO" = "200" ] && break
  sleep 2
done
check "el mismo token funciona tras caer la réplica" 200 "$CODIGO"
check "atendió otra instancia" true "$([ -n "$INST_B" ] && [ "$INST_B" != "$INST_A" ] && echo true || echo false)"
info "Instancia original: $INST_A  |  Instancia que respondió: $INST_B"

paso "Restaurando la réplica"
docker start "$INST_A" >/dev/null
esperar_sano 120

resumen
