#!/usr/bin/env bash
# Corre las 4 demos de la UT3 y las 7 de la UT4 en orden y resume el resultado.
# La salida completa de cada una queda en scripts/salidas/<demo>.txt (sin colores).
source "$(dirname "$0")/lib.sh"

DEMOS=(
  demo_componentes demo_escalabilidad demo_sin_estado demo_acid
  demo_config demo_circuit_breaker demo_health demo_cache
  demo_materialized_view demo_gatekeeper demo_gateway_offloading
)
SALIDAS="$RAIZ/scripts/salidas"
mkdir -p "$SALIDAS"

titulo "TutorYa — todas las demos (UT3 + UT4)"
RESUMEN=""
OK=0
INICIO=$(date +%s)
for d in "${DEMOS[@]}"; do
  t0=$(date +%s)
  "$RAIZ/scripts/$d.sh" 2>&1 | tee "$SALIDAS/$d.raw"
  rc=${PIPESTATUS[0]}
  sed $'s/\033\\[[0-9;]*m//g' "$SALIDAS/$d.raw" > "$SALIDAS/$d.txt" && rm -f "$SALIDAS/$d.raw"
  seg=$(( $(date +%s) - t0 ))
  veredicto=$(grep -E '(TODO OK|verificaciones fallaron)' "$SALIDAS/$d.txt" | tail -1 | sed 's/^ *//')
  if [ "$rc" -eq 0 ]; then OK=$((OK + 1)); marca="✅"; else marca="❌"; fi
  RESUMEN="$RESUMEN$(printf '   %s %-26s %4ss  %s' "$marca" "$d" "$seg" "$veredicto")"$'\n'
done

titulo "RESUMEN ($OK/${#DEMOS[@]} demos OK, $(( $(date +%s) - INICIO ))s)"
printf '%s' "$RESUMEN"
info "salidas completas en scripts/salidas/"
[ "$OK" -eq "${#DEMOS[@]}" ]
