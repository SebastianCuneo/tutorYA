#!/usr/bin/env bash
# Carga 300 docentes APROBADOS (5 materias, 20 horarios futuros c/u) directo en la base.
# Idempotente. Al terminar refresca la vista materializada y vacía la caché del catálogo.
source "$(dirname "$0")/lib.sh"

paso "Cargando datos de prueba (scripts/seed_carga.sql)"
T0=$(ahora_ms)
# Reservas de una carga anterior: están en db-reservas (otra base), se borran por id de docente.
IDS=$(psql_nucleo "SELECT string_agg(id::text, ',') FROM usuarios.usuarios WHERE email LIKE 'carga\_%@tutorya.uy'")
if [ -n "$IDS" ]; then
  psql_reservas "DELETE FROM reservas.pagos WHERE reserva_id IN (SELECT id FROM reservas.reservas WHERE docente_id IN ($IDS));
                 DELETE FROM reservas.reservas WHERE docente_id IN ($IDS)" >/dev/null
fi
docker compose exec -T db-nucleo psql -q -U tutorya -d tutorya < scripts/seed_carga.sql | sed 's/^/   /'
# La caché quedó con datos viejos: se vacía (SCAN, nunca KEYS).
BORRADAS=$(docker compose exec -T redis sh -c "redis-cli --scan --pattern 'catalogo:*' | xargs -r redis-cli del" | tr -d '[:space:]')
info "caché del catálogo vaciada (${BORRADAS:-0} claves) — carga en $(( $(ahora_ms) - T0 )) ms"
