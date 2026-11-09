#!/usr/bin/env bash
# UT5 — Estilo de microservicios: un caso de uso completo que cruza los seis servicios.
# Registro de docente (Usuarios) -> eventos -> perfil (Docentes) y solicitud (Verificación) -> aprobación
# -> evento -> catálogo (Docentes) y docentes habilitados (Mensajería) -> mensaje -> reserva (Reservas,
# que consulta Usuarios por SOAP, Docentes por REST y cobra en Pagos).
source "$(dirname "$0")/lib.sh"
titulo "Microservicios: un caso de uso de punta a punta"

paso "1. Topología: un contenedor por servicio y una base por servicio"
docker compose ps --format '   {{.Service}}\t{{.Status}}' | sort | uniq
check "6 microservicios corriendo" "6" "$(docker compose ps --services --status running | grep -cE '^(usuarios|docentes|mensajeria|verificacion|reservas|pagos)$')"
check "6 bases de datos (Database per Service)" "6" "$(docker compose ps --services --status running | grep -c '^db-')"

paso "2. Registro de un docente en Usuarios: responde sin esperar a Docentes ni a Verificación"
registrar "doc_$SUFIJO@demo.uy" "Docente Demo" DOCENTE
check "registro (Usuarios)" "201" "$CODIGO"
DOC_ID="$USUARIO_ID"
info "docente.registrado quedó en la outbox de Usuarios; el relay lo publica en RabbitMQ"

paso "3. Docentes y Verificación reaccionan al evento (consistencia eventual)"
login "doc_$SUFIJO@demo.uy" >/dev/null; DOC_TOKEN="$TOKEN"
_perfil() { [ "$(curl -s -k -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $DOC_TOKEN" "$BASE/api/docentes/me")" = "200" ]; }
esperar_hasta 15 _perfil; check "perfil creado en Docentes" "0" "$?"
aprobar_docente "$DOC_ID"
check "solicitud aprobada en Verificación" "200" "$CODIGO"

paso "4. El docente carga materia y horario (Docentes)"
req PUT /api/docentes/me/materias '{"materias":["Fisica"]}' "$DOC_TOKEN"
req POST /api/docentes/me/horarios "$(jq -nc --arg i "$(fecha_futura 3 10)" --arg f "$(fecha_futura 3 11)" '{inicio:$i,fin:$f,precio:500}')" "$DOC_TOKEN"
HORARIO=$(echo "$CUERPO" | jq -r .id)
check "horario creado" "201" "$CODIGO"

paso "5. Un estudiante busca (Docentes), escribe (Mensajería) y reserva (Reservas)"
estudiante_demo
_en_catalogo() { curl -s -k -H "Authorization: Bearer $EST_TOKEN" "$BASE/api/docentes?materia=Fisica" | jq -e --argjson d "$DOC_ID" '[.[]|select(.id==$d)]|length>0'; }
esperar_hasta 20 _en_catalogo
req GET '/api/docentes?materia=Fisica' "" "$EST_TOKEN"
check "docente aprobado visible en el catálogo" "true" "$(echo "$CUERPO" | jq --argjson d "$DOC_ID" '[.[]|select(.id==$d)]|length>0')"
_mensaje() { [ "$(curl -s -k -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer $EST_TOKEN" -d "{\"docenteId\":$DOC_ID,\"texto\":\"Hola, ¿das clases de física?\"}" "$BASE/api/mensajes")" = "201" ]; }
esperar_hasta 15 _mensaje
req GET /api/conversaciones "" "$EST_TOKEN"
check "mensaje enviado (Mensajería usa su copia local de docentes habilitados)" "1" "$(echo "$CUERPO" | jq 'length')"
req POST /api/reservas "{\"docenteId\":$DOC_ID,\"horarioId\":$HORARIO,\"tokenPago\":\"tok_ok\"}" "$EST_TOKEN"
check "reserva confirmada (saga: SOAP a Usuarios + REST a Docentes y Pagos)" "201" "$CODIGO"
check "estado de la reserva" "CONFIRMADA" "$(echo "$CUERPO" | jq -r .reserva.estado)"

paso "6. Colas de RabbitMQ (una por servicio suscriptor, sin mensajes atrasados)"
colas_rabbit
resumen
