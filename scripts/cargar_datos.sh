#!/usr/bin/env bash
# Carga 300 docentes APROBADOS (5 materias, 20 horarios futuros c/u) directo en la base.
# Idempotente. Al terminar refresca la vista materializada y vacía la caché del catálogo.
source "$(dirname "$0")/lib.sh"

paso "Cargando datos de prueba (scripts/seed_carga.sql)"
T0=$(ahora_ms)
docker compose exec -T db psql -q -U tutorya -d tutorya < scripts/seed_carga.sql | sed 's/^/   /'
# La caché quedó con datos viejos: se vacía (SCAN, nunca KEYS).
BORRADAS=$(docker compose exec -T redis sh -c "redis-cli --scan --pattern 'catalogo:*' | xargs -r redis-cli del" | tr -d '[:space:]')
info "caché del catálogo vaciada (${BORRADAS:-0} claves) — carga en $(( $(ahora_ms) - T0 )) ms"
