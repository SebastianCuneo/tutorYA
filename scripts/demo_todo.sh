#!/usr/bin/env bash
# UT5: corre todas las demos de la unidad en orden. Las de la UT3/UT4 están en scripts/ut4/ y se
# corren en la rama ut4-patrones (usan la topología Núcleo + Reservas).
source "$(dirname "$0")/lib.sh"
titulo "TutorYa UT5 — todas las demos"
esperar_sano 240 || exit 1
FALLIDAS=()
for d in demo_microservicios demo_soap demo_saga demo_eventos demo_disponibilidad; do
  bash "scripts/$d.sh" || FALLIDAS+=("$d")
done
echo
if [ ${#FALLIDAS[@]} -eq 0 ]; then
  printf '\033[1m✅ Todas las demos pasaron\033[0m\n'
else
  printf '\033[1m❌ Fallaron: %s\033[0m\n' "${FALLIDAS[*]}"
  exit 1
fi
