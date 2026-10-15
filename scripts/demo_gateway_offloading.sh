#!/usr/bin/env bash
# Demo UT4 — Gateway Offloading: Nginx se encarga de TLS, redirección HTTP→HTTPS, cabeceras de
# seguridad, X-Request-Id, compresión y log de acceso; los servicios siguen en HTTP plano.
source "$(dirname "$0")/lib.sh"

titulo "UT4 — GATEWAY OFFLOADING"
esperar_sano 120
CURL_IMG=curlimages/curl:8.10.1
docker pull -q "$CURL_IMG" >/dev/null 2>&1

# cabecera NOMBRE ARCHIVO_DE_CABECERAS
cabecera() { grep -i "^$1:" "$2" | head -1 | cut -d' ' -f2- | tr -d '\r'; }

paso "1. HTTPS"
req GET /api/salud
check "GET $BASE/api/salud" 200 "$CODIGO"

paso "2. HTTP redirige a HTTPS"
H=$(mktemp)
CODIGO=$(curl -s -o /dev/null -D "$H" -w '%{http_code}' "$BASE_HTTP/api/salud?x=1")
LOC=$(cabecera Location "$H")
info "GET $BASE_HTTP/api/salud?x=1 → HTTP $CODIGO  Location: $LOC"
check "redirección permanente" 301 "$CODIGO"
check "Location apunta a HTTPS (mismo path y query)" "$BASE/api/salud?x=1" "$LOC"

paso "3. Cabeceras de seguridad (también en errores) y Server sin versión"
for ruta in /api/salud /no-existe; do
  curl -s -k -o /dev/null -D "$H" "$BASE$ruta"
  info "GET $ruta"
  for c in Strict-Transport-Security X-Content-Type-Options X-Frame-Options Referrer-Policy X-Request-Id Server; do
    info "   $c: $(cabecera "$c" "$H")"
  done
  check "$ruta: HSTS" "max-age=31536000" "$(cabecera Strict-Transport-Security "$H")"
  check "$ruta: X-Content-Type-Options" nosniff "$(cabecera X-Content-Type-Options "$H")"
  check "$ruta: X-Frame-Options" DENY "$(cabecera X-Frame-Options "$H")"
  check "$ruta: Referrer-Policy" no-referrer "$(cabecera Referrer-Policy "$H")"
  check "$ruta: Server sin versión" nginx "$(cabecera Server "$H")"
done

paso "4. X-Request-Id: lo asigna Nginx, lo loguean el gateway y los servicios, y se propaga en las llamadas internas"
estudiante_demo
# Reserva sobre un docente inexistente: Reservas llama 2 veces al Núcleo (/internal) con el mismo id.
curl -s -k -o /dev/null -D "$H" -X POST "$BASE/api/reservas" -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $EST_TOKEN" -H 'X-Request-Id: id-falsificado-por-el-cliente' \
  -d '{"docenteId":999999,"horarioId":999999,"tokenPago":"tok"}'
RID=$(cabecera X-Request-Id "$H")
info "POST /api/reservas (con 'X-Request-Id: id-falsificado-por-el-cliente') → X-Request-Id: $RID"
check "el gateway ignora el id del cliente" true "$([ -n "$RID" ] && [ "$RID" != id-falsificado-por-el-cliente ] && echo true || echo false)"
sleep 1
EN_NGINX=$(docker compose logs nginx 2>/dev/null | grep -c "$RID")
EN_RESERVAS=$(docker compose logs reservas 2>/dev/null | grep -c "$RID")
EN_NUCLEO=$(docker compose logs nucleo 2>/dev/null | grep -c "$RID")
docker compose logs --no-log-prefix nginx 2>/dev/null | grep "$RID" | head -1 | sed 's/^/   nginx    │ /'
docker compose logs reservas 2>/dev/null | grep "$RID" | head -1 | sed 's/^/   /'
docker compose logs nucleo 2>/dev/null | grep "$RID" | head -2 | sed 's/^/   /'
info "líneas con $RID → nginx: $EN_NGINX, reservas: $EN_RESERVAS, nucleo: $EN_NUCLEO"
check "en docker compose logs nginx" true "$([ "$EN_NGINX" -ge 1 ] && echo true || echo false)"
check "en docker compose logs reservas" true "$([ "$EN_RESERVAS" -ge 1 ] && echo true || echo false)"
check "en docker compose logs nucleo (propagado por getJson)" true "$([ "$EN_NUCLEO" -ge 1 ] && echo true || echo false)"
LINEA=$(docker compose logs --no-log-prefix nginx 2>/dev/null | grep "$RID" | tail -1)
check "log de Nginx en JSON con request_id, status, upstream_addr y request_time" true \
  "$(echo "$LINEA" | jq -e 'has("request_id") and has("status") and has("upstream_addr") and has("request_time")' >/dev/null 2>&1 && echo true || echo false)"

paso "5. Compresión gzip de las respuestas JSON"
RUTA='/api/docentes?materia=Matematica'
SIN=$(curl -s -k -o /dev/null -w '%{size_download}' -H "Authorization: Bearer $EST_TOKEN" "$BASE$RUTA")
CON=$(curl -s -k -o /dev/null -D "$H" -w '%{size_download}' -H 'Accept-Encoding: gzip' -H "Authorization: Bearer $EST_TOKEN" "$BASE$RUTA")
info "GET $RUTA → Content-Encoding: $(cabecera Content-Encoding "$H")"
info "sin comprimir: $SIN bytes | gzip: $CON bytes | $(awk -v a="$SIN" -v b="$CON" 'BEGIN{printf "%.1f%% del original (%.1f× menos)", 100*b/a, a/b}')"
check "Content-Encoding" gzip "$(cabecera Content-Encoding "$H")"
check "la respuesta comprimida es más chica" true "$([ "$CON" -lt "$SIN" ] && echo true || echo false)"

paso "6. Certificado y versiones de TLS"
CERT=$(echo | openssl s_client -connect "localhost:${GATEWAY_TLS_PORT:-8443}" -servername localhost 2>/dev/null)
echo "$CERT" | openssl x509 -noout -subject -issuer -enddate 2>/dev/null | sed 's/^/   /'
echo "$CERT" | grep -E '^\s*(Protocol|Cipher)\s*:' | head -2 | sed 's/^ */   /'
check "certificado para localhost" true "$(echo "$CERT" | openssl x509 -noout -subject 2>/dev/null | grep -q 'CN *= *localhost' && echo true || echo false)"
for v in "1.1:--tlsv1.1 --tls-max 1.1" "1.2:--tlsv1.2 --tls-max 1.2" "1.3:--tlsv1.3"; do
  ver="${v%%:*}"; flags="${v#*:}"
  c=$(docker run --rm --network tutorya_borde "$CURL_IMG" -s -k -o /dev/null -w '%{http_code}' $flags https://nginx/api/salud 2>/dev/null)
  info "TLS $ver → HTTP ${c:-000}"
  RES="${RES:-}$ver=${c:-000} "
done
check "TLS 1.1 rechazado, 1.2 y 1.3 aceptados" "1.1=000 1.2=200 1.3=200 " "$RES"
rm -f "$H"

resumen
