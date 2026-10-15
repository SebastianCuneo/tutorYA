#!/usr/bin/env bash
# Demo UT4 — Cache-Aside: catálogo de docentes en Redis. Latencia sin caché vs con caché,
# tasa de aciertos e invalidación al cambiar el catálogo.
source "$(dirname "$0")/lib.sh"

titulo "UT4 — CACHE-ASIDE (catálogo de docentes en Redis)"
RUTA='/api/docentes?materia=Matematica'
trap 'restaurar_config >/dev/null 2>&1' EXIT
esperar_sano 120

paso "1. Datos de carga: 300 docentes APROBADOS × 20 horarios"
"$RAIZ/scripts/cargar_datos.sh"
login_admin >/dev/null
restaurar_config >/dev/null
estudiante_demo

paso "2. Caché DESHABILITADA (cache.habilitado=false): 100 búsquedas"
set_config '{"cache.habilitado":false}' >/dev/null
medir 100 GET "$RUTA" "" "$EST_TOKEN"
SIN_P50="$P50"; SIN_P95="$P95"
check "100 respuestas BYPASS" "100×BYPASS" "$XCACHE"

paso "3. Caché HABILITADA: 1 búsqueda (MISS) y 100 búsquedas (HIT)"
set_config '{"cache.habilitado":true}' >/dev/null
medir 1 GET "$RUTA" "" "$EST_TOKEN"
check "primera búsqueda" "1×MISS" "$XCACHE"
medir 100 GET "$RUTA" "" "$EST_TOKEN"
CON_P50="$P50"; CON_P95="$P95"
check "100 respuestas HIT" "100×HIT" "$XCACHE"
check "todas 200" "100×200" "$CODIGOS"

paso "4. Comparación"
MEJORA=$(awk -v a="$SIN_P50" -v b="$CON_P50" 'BEGIN{printf "%.1f", (b>0? a/b : 0)}')
MEJORA95=$(awk -v a="$SIN_P95" -v b="$CON_P95" 'BEGIN{printf "%.1f", (b>0? a/b : 0)}')
printf '   %-22s %10s %10s\n' "serie (100 requests)" "p50 (ms)" "p95 (ms)"
printf '   %-22s %10s %10s\n' "sin caché (BYPASS)" "$SIN_P50" "$SIN_P95"
printf '   %-22s %10s %10s\n' "con caché (HIT)" "$CON_P50" "$CON_P95"
info "mejora: ${MEJORA}× en p50, ${MEJORA95}× en p95"
check "la caché mejora el p50" true "$(awk -v m="$MEJORA" 'BEGIN{print (m>1?"true":"false")}')"

paso "5. Tasa de aciertos (GET /api/metricas en cada réplica del núcleo)"
HITS=0; MISSES=0
for i in $(instancias_de nucleo); do
  interno nucleo "$i" GET /api/metricas "$ADMIN_TOKEN"
  info "nucleo #$i: $(echo "$CUERPO" | jq -c '.cache')"
  HITS=$((HITS + $(echo "$CUERPO" | jq '.cache.hits')))
  MISSES=$((MISSES + $(echo "$CUERPO" | jq '.cache.misses')))
done
TASA=$(awk -v h="$HITS" -v m="$MISSES" 'BEGIN{printf "%.1f", (h+m)? 100*h/(h+m) : 0}')
info "total: hits=$HITS misses=$MISSES → tasa de aciertos ${TASA}% (acumulada desde el arranque)"
check "tasa de aciertos ≥ 90%" true "$(awk -v t="$TASA" 'BEGIN{print (t>=90?"true":"false")}')"

paso "6. Invalidación: un docente agrega un horario"
login carga_001@tutorya.uy >/dev/null; DOC_TOKEN="$TOKEN"
req GET /api/docentes/me "" "$DOC_TOKEN" >/dev/null
DOC_ID=$(echo "$CUERPO" | jq -r '.id'); MATERIA=$(echo "$CUERPO" | jq -r '.materias[0]')
RUTA_DOC="/api/docentes?materia=$MATERIA"
medir 2 GET "$RUTA_DOC" "" "$EST_TOKEN"
check "búsqueda de $MATERIA cacheada (la segunda es HIT)" HIT "$(echo "$MEDICIONES" | tail -1 | awk '{print $3}')"
req POST /api/docentes/me/horarios "$(jq -nc --arg i "$(fecha_futura 40 7)" --arg f "$(fecha_futura 40 8)" '{inicio:$i,fin:$f,precio:999}')" "$DOC_TOKEN"
check "horario agregado" 201 "$CODIGO"
H_NUEVO=$(echo "$CUERPO" | jq -r '.id')
curl -s -k -D /tmp/tutorya_h.$$ -o /tmp/tutorya_b.$$ -H "Authorization: Bearer $EST_TOKEN" "$BASE$RUTA_DOC"
XC=$(grep -i '^x-cache:' /tmp/tutorya_h.$$ | tr -d '\r' | awk '{print $2}')
APARECE=$(jq --argjson d "$DOC_ID" --argjson h "$H_NUEVO" '[.[]|select(.id==$d)|.horarios[]|select(.id==$h)]|length' /tmp/tutorya_b.$$)
rm -f /tmp/tutorya_h.$$ /tmp/tutorya_b.$$
info "búsqueda siguiente → X-Cache: $XC, horario $H_NUEVO presente: $APARECE"
check "la búsqueda siguiente es MISS" MISS "$XC"
check "el horario nuevo aparece" 1 "$APARECE"

paso "Restaurando la config por defecto"
restaurar_config >/dev/null
trap - EXIT

info "MÉTRICAS: sin caché p50=${SIN_P50}ms p95=${SIN_P95}ms | con caché p50=${CON_P50}ms p95=${CON_P95}ms | mejora ${MEJORA}× (p50) | aciertos ${TASA}%"
resumen
