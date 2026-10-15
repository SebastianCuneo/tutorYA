#!/usr/bin/env bash
# Demo UT4 — Materialized View: catálogo precalculado (docentes.catalogo) vs armado por tablas.
source "$(dirname "$0")/lib.sh"

titulo "UT4 — MATERIALIZED VIEW (docentes.catalogo)"
RUTA='/api/docentes?materia=Matematica'
trap 'restaurar_config >/dev/null 2>&1' EXIT
esperar_sano 120

paso "1. Datos de carga y caché DESHABILITADA (se mide la base, no Redis)"
"$RAIZ/scripts/cargar_datos.sh"
login_admin >/dev/null
restaurar_config >/dev/null
set_config '{"cache.habilitado":false}' >/dev/null
check "caché deshabilitada" 200 "$CODIGO"
estudiante_demo

# explicar TITULO SQL : EXPLAIN ANALYZE mostrando solo el nodo principal y el Execution Time. Deja EXP_MS.
explicar() {
  local plan
  plan=$(docker compose exec -T db-nucleo psql -U tutorya -d tutorya -tAc "EXPLAIN ANALYZE $2")
  EXP_MS=$(echo "$plan" | grep 'Execution Time' | awk '{print $3}')
  info "$1"
  info "   nodo principal: $(echo "$plan" | head -1 | sed -E 's/  \(cost=[^)]*\)//')"
  info "   Execution Time: ${EXP_MS} ms"
}

paso "2. EXPLAIN ANALYZE"
SQL_TABLAS="SELECT p.usuario_id, p.nombre,
  (SELECT array_agg(m.materia ORDER BY m.materia) FROM docentes.materias m WHERE m.docente_id = p.usuario_id),
  (SELECT jsonb_agg(jsonb_build_object('id',h.id,'inicio',h.inicio,'fin',h.fin,'precio',h.precio) ORDER BY h.inicio)
     FROM docentes.horarios h WHERE h.docente_id = p.usuario_id AND h.inicio > now())
 FROM docentes.perfiles p
 WHERE p.estado = 'APROBADO' AND EXISTS (SELECT 1 FROM docentes.materias m
       WHERE m.docente_id = p.usuario_id AND lower(m.materia) = lower('Matematica'))
 ORDER BY p.usuario_id"
SQL_VISTA="SELECT docente_id, nombre, materias_nombres, horarios FROM docentes.catalogo
 WHERE materias @> ARRAY[lower('Matematica')] ORDER BY docente_id"
explicar "Por tablas (agregación en cada consulta, equivalente a lo que arma la API):" "$SQL_TABLAS"; EXP_TABLAS="$EXP_MS"
explicar "Vista materializada (filtro GIN materias @> ARRAY[...]):" "$SQL_VISTA"; EXP_VISTA="$EXP_MS"
check "la vista se ejecuta más rápido que la agregación por tablas" true \
  "$(awk -v a="$EXP_TABLAS" -v b="$EXP_VISTA" 'BEGIN{print (b<a?"true":"false")}')"

paso "3. 100 búsquedas con catalogo.fuente=tablas (camino UT3: 1 + 2N consultas)"
set_config '{"catalogo.fuente":"tablas"}' >/dev/null
medir 100 GET "$RUTA" "" "$EST_TOKEN"
T_P50="$P50"; T_P95="$P95"
check "100 respuestas 200 (tablas)" "100×200" "$CODIGOS"
curl -s -k -H "Authorization: Bearer $EST_TOKEN" "$BASE$RUTA" | jq -S . > /tmp/tutorya_tablas.$$

paso "4. 100 búsquedas con catalogo.fuente=vista (1 consulta)"
set_config '{"catalogo.fuente":"vista"}' >/dev/null
medir 100 GET "$RUTA" "" "$EST_TOKEN"
V_P50="$P50"; V_P95="$P95"
check "100 respuestas 200 (vista)" "100×200" "$CODIGOS"
curl -s -k -H "Authorization: Bearer $EST_TOKEN" "$BASE$RUTA" | jq -S . > /tmp/tutorya_vista.$$
check "la respuesta es idéntica con ambas fuentes" true "$(cmp -s /tmp/tutorya_tablas.$$ /tmp/tutorya_vista.$$ && echo true || echo false)"
info "docentes en la respuesta: $(jq length /tmp/tutorya_vista.$$)"
rm -f /tmp/tutorya_tablas.$$ /tmp/tutorya_vista.$$

MEJORA=$(awk -v a="$T_P50" -v b="$V_P50" 'BEGIN{printf "%.1f", (b>0? a/b : 0)}')
printf '\n   %-28s %10s %10s\n' "serie (100 requests)" "p50 (ms)" "p95 (ms)"
printf '   %-28s %10s %10s\n' "tablas" "$T_P50" "$T_P95"
printf '   %-28s %10s %10s\n' "vista materializada" "$V_P50" "$V_P95"
info "EXPLAIN: tablas ${EXP_TABLAS} ms vs vista ${EXP_VISTA} ms | API: mejora ${MEJORA}× en p50"
check "la vista mejora el p50" true "$(awk -v m="$MEJORA" 'BEGIN{print (m>1?"true":"false")}')"

paso "5. Frescura: se aprueba un docente nuevo y aparece en la búsqueda (refresco al aprobar)"
registrar "docente_$SUFIJO@demo.uy" "Docente Vista" DOCENTE >/dev/null; DOC_ID="$USUARIO_ID"
login "docente_$SUFIJO@demo.uy" >/dev/null; DOC_TOKEN="$TOKEN"
req PUT /api/docentes/me/materias '{"materias":["Matematica"]}' "$DOC_TOKEN" >/dev/null
req POST /api/docentes/me/horarios "$(jq -nc --arg i "$(fecha_futura 9 10)" --arg f "$(fecha_futura 9 11)" '{inicio:$i,fin:$f,precio:450}')" "$DOC_TOKEN" >/dev/null
login verificador@tutorya.uy verificador123 >/dev/null; VER_TOKEN="$TOKEN"
req GET '/api/verificaciones?estado=PENDIENTE' "" "$VER_TOKEN" >/dev/null
SOL=$(echo "$CUERPO" | jq -r --argjson d "$DOC_ID" '.[]|select(.docente_id==$d)|.id')
req POST "/api/verificaciones/$SOL/llamada" "$(jq -nc --arg f "$(fecha_futura 1)" '{fecha:$f}')" "$VER_TOKEN" >/dev/null
req POST "/api/verificaciones/$SOL/resolucion" '{"resultado":"APROBADO"}' "$VER_TOKEN"
check "docente aprobado" 200 "$CODIGO"
T0=$(ahora_ms); APARECE=0
while [ $(( $(ahora_ms) - T0 )) -lt 5000 ]; do
  APARECE=$(curl -s -k -H "Authorization: Bearer $EST_TOKEN" "$BASE$RUTA" | jq --argjson d "$DOC_ID" '[.[]|select(.id==$d)]|length')
  [ "$APARECE" = 1 ] && break
done
T_APARECE=$(( $(ahora_ms) - T0 ))
info "el docente $DOC_ID aparece en la búsqueda a los ${T_APARECE} ms de la aprobación"
check "aparece" 1 "$APARECE"
check "en ≤ 1 s" true "$([ "$T_APARECE" -le 1000 ] && echo true || echo false)"

paso "Restaurando la config por defecto"
restaurar_config >/dev/null
trap - EXIT

info "MÉTRICAS: tablas p50=${T_P50}ms p95=${T_P95}ms | vista p50=${V_P50}ms p95=${V_P95}ms | mejora ${MEJORA}× | EXPLAIN ${EXP_TABLAS} vs ${EXP_VISTA} ms | docente nuevo visible en ${T_APARECE} ms"
resumen
