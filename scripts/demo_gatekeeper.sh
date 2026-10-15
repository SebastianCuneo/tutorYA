#!/usr/bin/env bash
# Demo UT4 — Gatekeeper: Nginx es el único punto de entrada. Los servicios, la base y Redis
# viven en una red interna sin puertos publicados; el gateway filtra métodos, rutas y tamaños.
source "$(dirname "$0")/lib.sh"

titulo "UT4 — GATEKEEPER"
esperar_sano 120

# esperar_json DESCRIPCION CODIGO_ESPERADO : verifica código y formato { error: { codigo, mensaje } }
esperar_json() {
  check "$1" "$2" "$CODIGO"
  check "$1: error en formato JSON" true "$(echo "$CUERPO" | jq -e '.error.codigo and .error.mensaje' >/dev/null 2>&1 && echo true || echo false)"
}

paso "1. Solo Nginx publica puertos (docker compose ps --format json)"
PUBLICAN=$(docker compose ps --format json | jq -s -r 'flatten | map(select([.Publishers[]? | select(.PublishedPort > 0)] | length > 0) | .Service) | unique | join(",")')
docker compose ps --format json | jq -s -r 'flatten[] | "\(.Service)\t\([.Publishers[]? | select(.PublishedPort > 0) | "\(.PublishedPort)->\(.TargetPort)"] | unique | join(", "))"' \
  | sort -u | awk -F'\t' '{printf "   %-10s %s\n", $1, ($2==""?"(sin puertos publicados)":$2)}'
check "servicios con puertos publicados" nginx "$PUBLICAN"

paso "2. Desde el host, los puertos de los servicios no llegan a TutorYa"
for puerto in 3000 5432 6379; do
  CUERPO=$(curl -s -m 3 "http://localhost:$puerto/api/salud" 2>/dev/null); rc=$?
  PROPIOS=$(docker ps --filter "publish=$puerto" --filter "label=com.docker.compose.project=tutorya" --format '{{.Names}}')
  AJENOS=$(docker ps --filter "publish=$puerto" --format '{{.Names}}' | grep -v '^tutorya-' | tr '\n' ' ')
  ES_TUTORYA=$(echo "$CUERPO" | jq -e '.servicio == "nucleo" or .servicio == "reservas"' >/dev/null 2>&1 && echo si || echo no)
  info "curl localhost:$puerto → exit $rc${AJENOS:+  (puerto ocupado por otro contenedor del host: $AJENOS)}"
  check "localhost:$puerto no expone TutorYa" "ninguno/no" "${PROPIOS:-ninguno}/$ES_TUTORYA"
done

paso "3. Desde la red borde (fuera de la interna), 'nucleo' ni siquiera resuelve"
docker pull -q curlimages/curl:8.10.1 >/dev/null 2>&1
SALIDA=$(docker run --rm --network tutorya_borde curlimages/curl:8.10.1 -s -m 3 http://nucleo:3000/api/salud 2>&1); rc=$?
info "docker run --network tutorya_borde curl http://nucleo:3000/api/salud → exit $rc ${SALIDA:+($SALIDA)}"
check "nucleo inaccesible desde tutorya_borde" true "$([ "$rc" -ne 0 ] && echo true || echo false)"

paso "4. Filtros del gateway"
req GET /internal/usuarios/1/estado
esperar_json "/internal bloqueado" 404
req GET /otra
esperar_json "ruta fuera de /api/" 404
req TRACE /api/salud
esperar_json "método TRACE" 405
GRANDE=$(mktemp)
head -c 102400 /dev/zero | tr '\0' 'a' | awk '{printf "{\"email\":\"%s\",\"password\":\"x\"}", $0}' > "$GRANDE"
printf '   → POST /api/usuarios/login  (body de %s bytes)\n' "$(wc -c < "$GRANDE" | tr -d ' ')"
CODIGO=$(curl -s -k -o "$GRANDE.out" -w '%{http_code}' -X POST "$BASE/api/usuarios/login" -H 'Content-Type: application/json' --data-binary @"$GRANDE")
CUERPO=$(cat "$GRANDE.out"); rm -f "$GRANDE" "$GRANDE.out"
printf '   ← HTTP %s\n     %s\n' "$CODIGO" "$CUERPO"
esperar_json "body de 100 KB (límite 64 KB)" 413
CAB=$(head -c 10000 /dev/zero | tr '\0' 'a')
printf '   → GET /api/salud  (cabecera de 10 KB)\n'
CODIGO=$(curl -s -k -o /tmp/tutorya_cab.$$ -w '%{http_code}' -H "X-Relleno: $CAB" "$BASE/api/salud")
CUERPO=$(cat /tmp/tutorya_cab.$$); rm -f /tmp/tutorya_cab.$$
printf '   ← HTTP %s\n     %s\n' "$CODIGO" "$CUERPO"
esperar_json "cabecera más grande que el buffer (8 KB)" 400

paso "5. X-Instancia falsificada por el cliente"
REALES=$(for c in $(docker compose ps -q nucleo); do docker inspect -f '{{.Config.Hostname}}' "$c"; done)
info "instancias reales del núcleo: $(echo $REALES)"
RESP=$(curl -s -k -D - -o /dev/null -H 'X-Instancia: instancia-falsa' "$BASE/api/salud" | tr -d '\r' | awk 'tolower($1)=="x-instancia:"{print $2}')
info "pedido con 'X-Instancia: instancia-falsa' → la respuesta trae X-Instancia: $RESP"
check "la respuesta trae una instancia real" true "$(echo "$REALES" | grep -qx "$RESP" && echo true || echo false)"

resumen
