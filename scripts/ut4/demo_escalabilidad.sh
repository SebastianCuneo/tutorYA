#!/usr/bin/env bash
# Demo 2: escalabilidad horizontal (reservas x3, núcleo x2) con reparto round-robin.
source "$(dirname "$0")/lib.sh"

titulo "DEMO 2 — Escalabilidad horizontal"

paso "Escalando: docker compose up -d --scale reservas=3 --scale nucleo=2"
docker compose up -d --scale reservas=3 --scale nucleo=2 2>&1 | tail -6
# Nginx re-resuelve el DNS cada 5s (resolver valid=5s), no hace falta reiniciarlo.
esperar_sano 120
sleep 6

repartir() { # $1 = ruta, $2 = instancias esperadas
  paso "30 GET a $1"
  local salida
  salida=$(for _ in $(seq 1 30); do
    curl -s -k -o /dev/null -D - "$BASE$1" | tr -d '\r' | awk 'tolower($1)=="x-instancia:"{print $2}'
  done)
  echo "$salida" | sort | uniq -c | awk '{printf "   %s peticiones → instancia %s\n", $1, $2}'
  local distintas minimo
  distintas=$(echo "$salida" | sort -u | wc -l | tr -d ' ')
  minimo=$(echo "$salida" | sort | uniq -c | awk 'NR==1||$1<m{m=$1} END{print m}')
  check "instancias distintas atendieron" "$2" "$distintas"
  check "reparto parejo (mínimo por instancia >= 5 de 30)" true "$([ "$minimo" -ge 5 ] && echo true || echo false)"
}

repartir /api/reservas/salud 3
repartir /api/salud 2

paso "Réplicas en ejecución"
docker compose ps --format 'table {{.Name}}\t{{.Service}}\t{{.Status}}' | grep -E 'NAME|nucleo|reservas'

resumen
