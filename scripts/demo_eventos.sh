#!/usr/bin/env bash
# UT5 — Eventos sin pérdida: colas durables (un servicio caído no pierde eventos) y Transactional
# Outbox (RabbitMQ caído no rompe el registro ni pierde el evento).
source "$(dirname "$0")/lib.sh"
titulo "Eventos durables y outbox"
login verificador@tutorya.uy verificador123 >/dev/null; VER="$TOKEN"
solicitudes() { psql_en db-verificacion "SELECT count(*) FROM verificacion.solicitudes WHERE docente_id=$1"; }

paso "1. Verificación caída: el registro igual responde y el evento espera en su cola"
docker compose stop verificacion >/dev/null 2>&1
registrar "doc1_$SUFIJO@demo.uy" "Docente Uno" DOCENTE
check "registro con Verificación caída" "201" "$CODIGO"
D1="$USUARIO_ID"
sleep 2
colas_rabbit
check "evento esperando en verificacion.eventos" "1" "$(docker compose exec -T rabbitmq rabbitmqctl -q list_queues name messages | awk '$1=="verificacion.eventos"{print $2}')"
check "todavía no hay solicitud" "0" "$(solicitudes "$D1")"
docker compose start verificacion >/dev/null 2>&1
_hay() { [ "$(solicitudes "$D1")" = "1" ]; }
esperar_hasta 60 _hay
check "al volver, Verificación procesó el evento" "1" "$(solicitudes "$D1")"

paso "2. RabbitMQ caído: el evento queda en la outbox de Usuarios y se publica al volver"
docker compose stop rabbitmq >/dev/null 2>&1
registrar "doc2_$SUFIJO@demo.uy" "Docente Dos" DOCENTE
check "registro con el broker caído" "201" "$CODIGO"
D2="$USUARIO_ID"
check "evento pendiente en usuarios.outbox" "1" "$(psql_en db-usuarios "SELECT count(*) FROM usuarios.outbox WHERE publicado_en IS NULL AND datos->>'docenteId'='$D2'")"
docker compose start rabbitmq >/dev/null 2>&1
_publicado() { [ "$(psql_en db-usuarios "SELECT count(*) FROM usuarios.outbox WHERE publicado_en IS NULL")" = "0" ]; }
esperar_hasta 90 _publicado
_hay2() { [ "$(solicitudes "$D2")" = "1" ]; }
esperar_hasta 30 _hay2
check "outbox vacía y solicitud creada" "0 1" "$(psql_en db-usuarios "SELECT count(*) FROM usuarios.outbox WHERE publicado_en IS NULL") $(solicitudes "$D2")"
esperar_healthy 90
resumen
