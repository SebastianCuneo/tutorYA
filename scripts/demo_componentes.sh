#!/usr/bin/env bash
# Demo 1: flujo completo a través de las interfaces de los 5 componentes.
source "$(dirname "$0")/lib.sh"

titulo "DEMO 1 — Componentes e interfaces"

paso "1. Registro de un docente (Usuarios emite docente.registrado → Docentes y Verificación reaccionan)"
DOC_EMAIL="docente_$SUFIJO@demo.uy"
registrar "$DOC_EMAIL" "Docente Demo" DOCENTE
DOC_ID="$USUARIO_ID"
check "registro de docente" 201 "$CODIGO"
login "$DOC_EMAIL"; DOC_TOKEN="$TOKEN"

paso "2. El docente carga materias y un horario (GestionarPerfilDocente, HU8)"
req PUT /api/docentes/me/materias '{"materias":["Matematica","Fisica"]}' "$DOC_TOKEN"
check "carga de materias" 200 "$CODIGO"
req POST /api/docentes/me/horarios "$(jq -nc --arg i "$(fecha_futura 3 15)" --arg f "$(fecha_futura 3 16)" '{inicio:$i,fin:$f,precio:500}')" "$DOC_TOKEN"
check "carga de horario" 201 "$CODIGO"
HORARIO_ID=$(echo "$CUERPO" | jq -r '.id')
req GET /api/docentes/me "" "$DOC_TOKEN"
check "perfil en PENDIENTE_VERIFICACION" PENDIENTE_VERIFICACION "$(echo "$CUERPO" | jq -r '.estado')"

paso "3. Un estudiante busca y el docente NO aparece (BuscarDocentes, HU3)"
EST_EMAIL="estudiante_$SUFIJO@demo.uy"
registrar "$EST_EMAIL" "Estudiante Demo" ESTUDIANTE; EST_ID="$USUARIO_ID"
login "$EST_EMAIL"; EST_TOKEN="$TOKEN"
req GET '/api/docentes?materia=Matematica' "" "$EST_TOKEN"
check "docente pendiente no aparece" 0 "$(echo "$CUERPO" | jq --argjson d "$DOC_ID" '[.[]|select(.id==$d)]|length')"

paso "4. El verificador lista pendientes, agenda la llamada y aprueba (VerificarDocente, HU10)"
login verificador@tutorya.uy verificador123; VER_TOKEN="$TOKEN"
req GET '/api/verificaciones?estado=PENDIENTE' "" "$VER_TOKEN"
SOL_ID=$(echo "$CUERPO" | jq -r --argjson d "$DOC_ID" '.[]|select(.docente_id==$d)|.id')
check "solicitud del docente en la lista de pendientes" true "$([ -n "$SOL_ID" ] && echo true || echo false)"
req POST "/api/verificaciones/$SOL_ID/resolucion" '{"resultado":"APROBADO"}' "$VER_TOKEN"
check "no se puede resolver sin llamada agendada" 409 "$CODIGO"
req POST "/api/verificaciones/$SOL_ID/llamada" "$(jq -nc --arg f "$(fecha_futura 1 10)" '{fecha:$f}')" "$VER_TOKEN"
check "llamada agendada" 200 "$CODIGO"
req POST "/api/verificaciones/$SOL_ID/resolucion" '{"resultado":"APROBADO"}' "$VER_TOKEN"
check "resolución APROBADO (emite docente.verificado)" 200 "$CODIGO"

paso "5. Ahora el docente SÍ aparece en la búsqueda"
req GET '/api/docentes?materia=Matematica' "" "$EST_TOKEN"
check "docente aprobado aparece" 1 "$(echo "$CUERPO" | jq --argjson d "$DOC_ID" '[.[]|select(.id==$d)]|length')"
check "disponibilidad verificada contra Reservas" true "$(echo "$CUERPO" | jq -r --argjson d "$DOC_ID" '.[]|select(.id==$d)|.disponibilidadVerificada')"

paso "6. Estudiante menor: no puede reservar hasta que el adulto autorice (HU7, HU2, HU6)"
MEN_EMAIL="menor_$SUFIJO@demo.uy"
registrar "$MEN_EMAIL" "Menor Demo" ESTUDIANTE true "adulto_$SUFIJO@demo.uy"
check "registro de menor" 201 "$CODIGO"
check "estado PENDIENTE" PENDIENTE "$(echo "$CUERPO" | jq -r '.estado')"
LINK="$LINK_AUTORIZACION"
login "$MEN_EMAIL"; MEN_TOKEN="$TOKEN"
req POST /api/reservas "$(jq -nc --argjson d "$DOC_ID" --argjson h "$HORARIO_ID" '{docenteId:$d,horarioId:$h,tokenPago:"OK"}')" "$MEN_TOKEN"
check "menor sin autorizar no puede reservar" 403 "$CODIGO"
TOKEN_AUT="${LINK##*/}"
req POST "/api/autorizaciones/$TOKEN_AUT"
check "el adulto autoriza con el link (sin login)" 200 "$CODIGO"
req POST "/api/autorizaciones/$TOKEN_AUT"
check "reusar el link (token de un solo uso)" 410 "$CODIGO"

paso "7. Mensajería: el estudiante escribe, el docente responde (HU4, HU9)"
req POST /api/mensajes "$(jq -nc --argjson d "$DOC_ID" '{docenteId:$d,texto:"Hola, ¿tenés lugar para una clase de matemática?"}')" "$EST_TOKEN"
check "estudiante envía mensaje" 201 "$CODIGO"
CONV_ID=$(echo "$CUERPO" | jq -r '.conversacionId')
req GET /api/conversaciones "" "$DOC_TOKEN"
check "el docente ve la conversación" 1 "$(echo "$CUERPO" | jq --argjson c "$CONV_ID" '[.[]|select(.id==$c)]|length')"
req POST "/api/conversaciones/$CONV_ID/mensajes" '{"texto":"¡Hola! Sí, reservá el horario que cargué."}' "$DOC_TOKEN"
check "docente responde" 201 "$CODIGO"
req GET "/api/conversaciones/$CONV_ID/mensajes" "" "$EST_TOKEN"
check "la conversación tiene 2 mensajes" 2 "$(echo "$CUERPO" | jq 'length')"

paso "8. Reserva y pago (HU5), y el docente confirma la clase dictada (HU11)"
req POST /api/reservas "$(jq -nc --argjson d "$DOC_ID" --argjson h "$HORARIO_ID" '{docenteId:$d,horarioId:$h,tokenPago:"tok_visa"}')" "$EST_TOKEN"
check "reserva y pago" 201 "$CODIGO"
RES_ID=$(echo "$CUERPO" | jq -r '.reserva.id')
req PATCH "/api/reservas/$RES_ID/dictada" "" "$DOC_TOKEN"
check "clase marcada como DICTADA" DICTADA "$(echo "$CUERPO" | jq -r '.estado')"

paso "9. /internal no se expone por el gateway"
req GET "/internal/usuarios/$EST_ID/estado"
check "gateway oculta /internal" 404 "$CODIGO"

resumen
