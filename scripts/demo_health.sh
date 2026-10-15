#!/usr/bin/env bash
# Demo UT4 — Health Endpoint Monitoring: liveness vs readiness, réplica degradada fuera de
# rotación (Nginx reintenta en la otra) y db-nucleo congelada => readiness del Núcleo 503 con
# liveness 200, mientras Reservas sigue lista con su propia base (Bulkhead de datos).
source "$(dirname "$0")/lib.sh"

titulo "UT4 — HEALTH ENDPOINT MONITORING"

restaurar() {
  docker compose unpause db-nucleo >/dev/null 2>&1
  for i in $(instancias_de nucleo); do interno nucleo "$i" POST /internal/fallas/restaurar >/dev/null 2>&1; done
}
trap restaurar EXIT

docker compose up -d --scale nucleo=2 --scale reservas=2 2>&1 | tail -1
esperar_sano 120; sleep 6

estudiante_demo

paso "1. Liveness y readiness por el gateway"
req GET /api/salud
check "liveness núcleo" 200 "$CODIGO"
req GET /api/salud/listo
check "readiness núcleo" 200 "$CODIGO"
req GET /api/reservas/salud
check "liveness reservas" 200 "$CODIGO"
req GET /api/reservas/salud/listo
check "readiness reservas" 200 "$CODIGO"

paso "2. Falla inyectada en la réplica 1 del núcleo (POST /internal/fallas/degradar, desde dentro del contenedor)"
NUC1=$(docker inspect -f '{{.Config.Hostname}}' tutorya-nucleo-1)
info "réplica 1 = instancia $NUC1"
interno nucleo 1 POST /internal/fallas/degradar
info "← $CODIGO $CUERPO"
T0=$(ahora_ms)
interno nucleo 1 GET /api/salud/listo
info "readiness de la réplica 1 (docker compose exec --index 1 nucleo ...): HTTP $CODIGO $(echo "$CUERPO" | jq -c '{estado,fallaInyectada}')"
check "readiness de la réplica degradada" 503 "$CODIGO"
interno nucleo 1 GET /api/salud
check "liveness de la réplica degradada (sigue viva)" 200 "$CODIGO"

printf '   esperando que Docker la marque unhealthy'
SALUD=""
while [ $(( $(ahora_ms) - T0 )) -lt 25000 ]; do
  SALUD=$(docker inspect -f '{{.State.Health.Status}}' tutorya-nucleo-1)
  [ "$SALUD" = unhealthy ] && break
  printf '.'; sleep 1
done
T_UNHEALTHY=$(( ($(ahora_ms) - T0) / 1000 ))
printf ' %s (%ss)\n' "$SALUD" "$T_UNHEALTHY"
check "docker inspect: unhealthy en ≤ 25 s" unhealthy "$SALUD"

paso "3. 30 GET /api/docentes: Nginx reintenta (503 REPLICA_DEGRADADA → otra réplica)"
medir 30 GET /api/docentes "" "$EST_TOKEN"
echo "$MEDICIONES" | awk '{print $4}' | sort | uniq -c | awk '{printf "   %s respuestas desde la instancia %s\n", $1, $2}'
check "30 respuestas 200" "30×200" "$CODIGOS"
check "ninguna desde la réplica degradada ($NUC1)" 0 "$(echo "$MEDICIONES" | awk -v d="$NUC1" '$4==d' | wc -l | tr -d ' ')"

paso "Restaurando la réplica 1"
interno nucleo 1 POST /internal/fallas/restaurar
info "← $CODIGO $CUERPO"
esperar_healthy 60

paso "4. docker compose pause db-nucleo: Núcleo degradado, Reservas sigue lista (Bulkhead de datos)"
docker compose pause db-nucleo 2>&1 | tail -1
T0=$(ahora_ms)
CODIGO=""
while [ $(( $(ahora_ms) - T0 )) -lt 10000 ]; do
  CODIGO=$(curl -s -k -o /tmp/tutorya_listo.$$ -w '%{http_code}' "$BASE/api/salud/listo")
  [ "$CODIGO" = 503 ] && break
done
T_503=$(( $(ahora_ms) - T0 ))
info "readiness → HTTP $CODIGO a los ${T_503} ms: $(jq -c '{estado,chequeos}' /tmp/tutorya_listo.$$ 2>/dev/null)"
rm -f /tmp/tutorya_listo.$$
check "readiness del Núcleo con db-nucleo congelada" 503 "$CODIGO"
check "detectado en ≤ 2 s" true "$([ "$T_503" -le 2000 ] && echo true || echo false)"
req GET /api/salud
check "liveness del Núcleo con db-nucleo congelada" 200 "$CODIGO"
info "(se esperan 2 s: el middleware reutiliza la readiness calculada durante 2 s)"
sleep 2
req GET /api/docentes "" "$EST_TOKEN"
check "resto de /api/* del Núcleo → 503 REPLICA_DEGRADADA" "503 REPLICA_DEGRADADA" "$CODIGO $(echo "$CUERPO" | jq -r '.error.codigo')"
info "Bulkhead de datos: Reservas chequea solo db-reservas, así que sigue atendiendo"
req GET /api/reservas/salud/listo
COD_RES_LISTO="$CODIGO"
check "readiness de Reservas con db-nucleo congelada" 200 "$CODIGO"
req GET /api/reservas "" "$EST_TOKEN"
COD_RES_LISTAR="$CODIGO"
check "GET /api/reservas sigue respondiendo con db-nucleo congelada" 200 "$CODIGO"

paso "Restaurando db-nucleo"
docker compose unpause db-nucleo 2>&1 | tail -1
trap - EXIT
esperar_healthy 90
esperar_sano 60
req GET /api/salud/listo
check "readiness recuperada" 200 "$CODIGO"

info "MÉTRICAS: unhealthy en ${T_UNHEALTHY} s | readiness del Núcleo 503 a los ${T_503} ms de congelar db-nucleo"
info "         Reservas con db-nucleo congelada: readiness HTTP $COD_RES_LISTO, listar reservas HTTP $COD_RES_LISTAR"
resumen
