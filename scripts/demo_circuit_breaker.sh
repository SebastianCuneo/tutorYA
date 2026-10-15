#!/usr/bin/env bash
# Demo UT4 — Circuit Breaker: Reservas → Núcleo. Con el Núcleo congelado, sin circuito cada reserva
# espera el timeout; con circuito, tras `umbral` fallas se responde 503 al instante con Retry-After.
source "$(dirname "$0")/lib.sh"

titulo "UT4 — CIRCUIT BREAKER (reservas → núcleo)"
TMP=$(mktemp -d)
N=0
TABLA=""

# intentar_reserva FASE HORARIO : POST /api/reservas midiendo el tiempo. Deja CODIGO, MS, RA, COD_ERR.
intentar_reserva() {
  local fase="$1" horario="$2" salida
  salida=$(curl -s -k -o "$TMP/b" -D "$TMP/h" -w '%{http_code} %{time_total}' -X POST "$BASE/api/reservas" \
    -H 'Content-Type: application/json' -H "Authorization: Bearer $EST_TOKEN" \
    -d "$(jq -nc --argjson d "$DOC_ID" --argjson h "$horario" '{docenteId:$d,horarioId:$h,tokenPago:"tok"}')")
  CODIGO="${salida%% *}"
  MS=$(echo "${salida##* }" | awk '{printf "%d", $1*1000}')
  RA=$(grep -i '^retry-after:' "$TMP/h" | tr -d '\r' | awk '{print $2}')
  COD_ERR=$(jq -r '.error.codigo // "-"' "$TMP/b" 2>/dev/null)
  N=$((N + 1))
  local fila
  fila=$(printf '   %3d  %-22s  %4s  %-17s  %6s ms  %s' "$N" "$fase" "$CODIGO" "$COD_ERR" "$MS" "${RA:--}")
  echo "$fila"
  TABLA="$TABLA$fila"$'\n'
}

restaurar() {
  docker compose unpause nucleo >/dev/null 2>&1
  docker compose up -d --scale reservas=2 --scale nucleo=2 >/dev/null 2>&1
  rm -rf "$TMP"
}
trap restaurar EXIT

paso "Preparación"
info "El estado del circuito es por réplica: para una lectura determinística se usa 1 réplica de reservas."
docker compose up -d --scale reservas=1 --scale nucleo=2 2>&1 | tail -1
esperar_sano 120; sleep 6
restaurar_config >/dev/null
registrar "docente_$SUFIJO@demo.uy" "Docente Circuito" DOCENTE >/dev/null; DOC_ID="$USUARIO_ID"
login "docente_$SUFIJO@demo.uy" >/dev/null; DOC_TOKEN="$TOKEN"
req POST /api/docentes/me/horarios "$(jq -nc --arg i "$(fecha_futura 6 10)" --arg f "$(fecha_futura 6 11)" '{inicio:$i,fin:$f,precio:500}')" "$DOC_TOKEN" >/dev/null
H1=$(echo "$CUERPO" | jq -r '.id')
req POST /api/docentes/me/horarios "$(jq -nc --arg i "$(fecha_futura 6 12)" --arg f "$(fecha_futura 6 13)" '{inicio:$i,fin:$f,precio:500}')" "$DOC_TOKEN" >/dev/null
H2=$(echo "$CUERPO" | jq -r '.id')
aprobar_docente "$DOC_ID" >/dev/null
estudiante_demo
TIMEOUT_MS=$(jq -r '."http.timeoutMs"' config/default.json)
ESPERA_MS=$(jq -r '."circuitBreaker.esperaMs"' config/default.json)
UMBRAL=$(jq -r '."circuitBreaker.umbral"' config/default.json)
info "docente=$DOC_ID horarios=$H1,$H2  http.timeoutMs=$TIMEOUT_MS  umbral=$UMBRAL  esperaMs=$ESPERA_MS"
printf '\n     #  fase                    HTTP  código              tiempo    Retry-After\n'

paso "1. Con el núcleo sano: reserva OK"
intentar_reserva "núcleo OK" "$H1"
check "reserva con el núcleo sano" 201 "$CODIGO"

paso "2. SIN circuito: circuitBreaker.habilitado=false + docker compose pause nucleo"
set_config '{"circuitBreaker.habilitado":false}' >/dev/null
check "circuito deshabilitado" 200 "$CODIGO"
docker compose pause nucleo 2>&1 | tail -1
LENTAS=0
for _ in 1 2 3 4 5 6; do
  intentar_reserva "sin circuito" "$H2"
  [ "$CODIGO" = 503 ] && [ "$MS" -ge $((TIMEOUT_MS * 9 / 10)) ] && LENTAS=$((LENTAS + 1))
done
check "6 reservas con 503 tras esperar ≈ timeout (${TIMEOUT_MS} ms)" 6 "$LENTAS"

paso "3. CON circuito: se rehabilita (el PUT va al núcleo, así que se descongela un momento)"
docker compose unpause nucleo 2>&1 | tail -1
# Cada intento tarda ≈ timeout + lo que cueste lanzar curl/jq (en Git Bash de Windows, cientos de ms):
# con la ventana por defecto (10 s) las 5 fallas pueden no caer juntas. Se amplía solo durante la prueba.
VENTANA_MS=$(( (UMBRAL + 1) * TIMEOUT_MS * 3 ))
set_config "$(jq -nc --argjson v "$VENTANA_MS" '{"circuitBreaker.habilitado":true,"circuitBreaker.ventanaMs":$v}')" >/dev/null
check "circuito habilitado (ventanaMs=$VENTANA_MS)" 200 "$CODIGO"
docker compose pause nucleo 2>&1 | tail -1
for i in $(seq 1 12); do
  intentar_reserva "con circuito" "$H2"
  if [ "$i" -gt "$UMBRAL" ]; then
    RAPIDA=$([ "$CODIGO" = 503 ] && [ "$COD_ERR" = CIRCUITO_ABIERTO ] && [ -n "$RA" ] && [ "$MS" -lt 200 ] && echo si || echo no)
    ULTIMAS="${ULTIMAS:-}$RAPIDA "
  fi
done
check "intentos $((UMBRAL + 1))..12: 503 CIRCUITO_ABIERTO + Retry-After en < 200 ms" \
  "$(for _ in $(seq $((UMBRAL + 1)) 12); do printf 'si '; done)" "$ULTIMAS"

req GET /api/reservas/circuitos "" "$ADMIN_TOKEN"
check "GET /api/reservas/circuitos: circuito nucleo" ABIERTO "$(echo "$CUERPO" | jq -r '.circuitos[]|select(.nombre=="nucleo")|.estado')"

paso "4. Recuperación: unpause, esperar esperaMs + 1 s y la llamada de prueba (SEMIABIERTO) cierra el circuito"
docker compose unpause nucleo 2>&1 | tail -1
info "esperando $((ESPERA_MS / 1000 + 1)) s..."
sleep $((ESPERA_MS / 1000 + 1))
intentar_reserva "recuperado" "$H2"
check "reserva tras la recuperación" 201 "$CODIGO"
req GET /api/reservas/circuitos "" "$ADMIN_TOKEN"
check "circuito nucleo" CERRADO "$(echo "$CUERPO" | jq -r '.circuitos[]|select(.nombre=="nucleo")|.estado')"

paso "Latencia de cada intento"
printf '     #  fase                    HTTP  código              tiempo    Retry-After\n%s' "$TABLA"
SIN=$(echo "$TABLA" | awk '/sin circuito/{s+=$6;n++} END{printf "%d", n?s/n:0}')
CON=$(echo "$TABLA" | awk '/CIRCUITO_ABIERTO/{s+=$6;n++} END{printf "%d", n?s/n:0}')
info "MÉTRICA: promedio sin circuito = ${SIN} ms | promedio con circuito abierto = ${CON} ms"

paso "Restaurando (config por defecto, unpause, 2 réplicas)"
restaurar_config >/dev/null
restaurar
trap - EXIT
esperar_sano 120

resumen
