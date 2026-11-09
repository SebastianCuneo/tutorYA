#!/usr/bin/env bash
# Demo UT4 — External Configuration Store: config compartida en Redis, cambiada en caliente
# sin reiniciar ninguna réplica.
source "$(dirname "$0")/lib.sh"

titulo "UT4 — EXTERNAL CONFIGURATION STORE"
esperar_sano 120

paso "1. Login admin y lectura de la config actual"
login_admin
req GET /api/admin/config "" "$ADMIN_TOKEN"
check "GET /api/admin/config" 200 "$CODIGO"
V0=$(echo "$CUERPO" | jq -r '.version')
info "versión actual: $V0"

paso "2. StartedAt de los contenedores de aplicación (antes)"
ARRANQUE_ANTES=$(docker inspect -f '{{.Name}} {{.State.StartedAt}}' $(docker compose ps -q nucleo reservas) | sort)
echo "$ARRANQUE_ANTES" | sed 's/^/   /'

paso "3. PUT cache.habilitado=false y propagación a TODAS las réplicas"
T0=$(ahora_ms)
set_config '{"cache.habilitado":false}'
check "PUT de config" 200 "$CODIGO"
V1="$CONFIG_VERSION"
info "versión nueva: $V1"
REPLICAS=""
for svc in nucleo reservas; do
  for i in $(instancias_de $svc); do REPLICAS="$REPLICAS $svc:$i"; done
done
PENDIENTES="$REPLICAS"
APLICADAS=""
while [ -n "$PENDIENTES" ] && [ $(( $(ahora_ms) - T0 )) -lt 15000 ]; do
  SIGUEN=""
  for r in $PENDIENTES; do
    svc="${r%%:*}"; i="${r##*:}"
    ruta=/api/salud; [ "$svc" = reservas ] && ruta=/api/reservas/salud
    interno "$svc" "$i" GET "$ruta"
    v=$(echo "$CUERPO" | jq -r '.configVersion' 2>/dev/null)
    if [ "$v" = "$V1" ]; then
      info "$svc #$i → configVersion=$v  (aplicada en $(echo "$CUERPO" | jq -r '.configAplicadaEn'))  visto a los $(( $(ahora_ms) - T0 )) ms"
      APLICADAS="$APLICADAS $(echo "$CUERPO" | jq -r '.configAplicadaEn')"
    else
      SIGUEN="$SIGUEN $r"
    fi
  done
  PENDIENTES="$SIGUEN"
done
T_TOTAL=$(( $(ahora_ms) - T0 ))
DISPERSION=$(for a in $APLICADAS; do echo "$a"; done | perl -MTime::Local -ne '
  /(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)\.(\d+)Z/ and push @t, timegm($6,$5,$4,$3,$2-1,$1)*1000+$7;
  END { @t = sort { $a <=> $b } @t; print $t[-1]-$t[0] }')
info "todas las réplicas con la versión $V1 a los ${T_TOTAL} ms (cota superior: incluye los docker exec)"
info "diferencia entre la primera y la última réplica en aplicarla (relojes de contenedor): ${DISPERSION} ms"
check "todas las réplicas ($(echo $REPLICAS | wc -w | tr -d ' ')) informan la versión nueva" "" "$PENDIENTES"
# El criterio es la propagación real entre réplicas (configAplicadaEn): T_TOTAL suma un docker exec
# por réplica, que en Docker Desktop para Windows tarda ~1 s cada uno.
check "propagación a todas las réplicas en menos de 1 s" true "$([ -n "$DISPERSION" ] && [ "$DISPERSION" -lt 1000 ] && echo true || echo false)"

paso "4. La búsqueda siguiente ya no usa la caché"
estudiante_demo
req GET '/api/docentes?materia=Matematica' "" "$EST_TOKEN"
XC=$(curl -s -k -o /dev/null -D - -H "Authorization: Bearer $EST_TOKEN" "$BASE/api/docentes?materia=Matematica" | tr -d '\r' | awk 'tolower($1)=="x-cache:"{print $2}')
info "X-Cache: $XC"
check "X-Cache con la caché deshabilitada" BYPASS "$XC"

paso "5. PUT inválido (cache.catalogoTtlSeg=-1) → 400 y la versión no cambia"
set_config '{"cache.catalogoTtlSeg":-1}'
check "valor fuera de rango" 400 "$CODIGO"
req GET /api/admin/config "" "$ADMIN_TOKEN"
check "versión sin cambios" "$V1" "$(echo "$CUERPO" | jq -r '.version')"

paso "6. PUT con token de estudiante → 403"
req PUT /api/admin/config '{"cache.habilitado":true}' "$EST_TOKEN"
check "estudiante no puede cambiar la config" 403 "$CODIGO"

paso "7. Ningún contenedor se reinició"
ARRANQUE_DESPUES=$(docker inspect -f '{{.Name}} {{.State.StartedAt}}' $(docker compose ps -q nucleo reservas) | sort)
echo "$ARRANQUE_DESPUES" | sed 's/^/   /'
check "StartedAt sin cambios" true "$([ "$ARRANQUE_ANTES" = "$ARRANQUE_DESPUES" ] && echo true || echo false)"

paso "Restaurando la config por defecto"
restaurar_config

info "MÉTRICA: propagación de la config = ${T_TOTAL} ms (observada) / ${DISPERSION} ms (entre réplicas)"
resumen
