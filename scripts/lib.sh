#!/usr/bin/env bash
# Helpers compartidos por los scripts de demo. Requiere: bash, curl, jq, docker compose.

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ" || exit 1
# Si existe .env (mismo que usa docker compose) se toma GATEWAY_PORT de ahí.
[ -f .env ] && { set -a; . ./.env; set +a; }
BASE="${BASE_URL:-http://localhost:${GATEWAY_PORT:-8080}}"

# Sufijo único para poder re-ejecutar los scripts sin chocar con emails ya registrados.
SUFIJO="$(date +%s)$RANDOM"

TOTAL=0
FALLAS=0

titulo()  { printf '\n\033[1m════════ %s ════════\033[0m\n' "$*"; }
paso()    { printf '\n\033[1m▶ %s\033[0m\n' "$*"; }
info()    { printf '   %s\n' "$*"; }

# req METODO RUTA [BODY_JSON] [TOKEN]
# Imprime el request y la respuesta. Deja en variables globales: CODIGO, CUERPO, INSTANCIA.
req() {
  local metodo="$1" ruta="$2" body="${3:-}" token="${4:-}"
  local args=(-s -X "$metodo" -D /tmp/tutorya_headers.$$ -o /tmp/tutorya_body.$$ -w '%{http_code}' -H 'Content-Type: application/json')
  [ -n "$token" ] && args+=(-H "Authorization: Bearer $token")
  [ -n "$body" ] && args+=(-d "$body")
  printf '   → %s %s' "$metodo" "$ruta"
  [ -n "$body" ] && printf '  %s' "$body"
  printf '\n'
  CODIGO=$(curl "${args[@]}" "$BASE$ruta")
  CUERPO=$(cat /tmp/tutorya_body.$$)
  INSTANCIA=$(grep -i '^x-instancia:' /tmp/tutorya_headers.$$ | tr -d '\r' | awk '{print $2}')
  rm -f /tmp/tutorya_headers.$$ /tmp/tutorya_body.$$
  printf '   ← HTTP %s  [X-Instancia: %s]\n' "$CODIGO" "${INSTANCIA:--}"
  [ -n "$CUERPO" ] && printf '     %s\n' "$(echo "$CUERPO" | jq -c . 2>/dev/null || echo "$CUERPO")"
}

# check DESCRIPCION ESPERADO OBTENIDO
check() {
  TOTAL=$((TOTAL + 1))
  if [ "$2" = "$3" ]; then
    printf '   ✅ %s (esperado: %s)\n' "$1" "$2"
  else
    printf '   ❌ %s (esperado: %s, obtenido: %s)\n' "$1" "$2" "$3"
    FALLAS=$((FALLAS + 1))
  fi
}

# resumen: veredicto final y código de salida
resumen() {
  echo
  if [ "$FALLAS" -eq 0 ]; then
    printf '\033[1m✅ TODO OK: %s/%s verificaciones\033[0m\n' "$TOTAL" "$TOTAL"
  else
    printf '\033[1m❌ %s de %s verificaciones fallaron\033[0m\n' "$FALLAS" "$TOTAL"
    exit 1
  fi
}

# registrar EMAIL NOMBRE ROL [ESMENOR(true|false)] [EMAIL_ADULTO]  -> deja USUARIO_ID en global
registrar() {
  local email="$1" nombre="$2" rol="$3" menor="${4:-false}" adulto="${5:-}"
  local body
  body=$(jq -nc --arg e "$email" --arg n "$nombre" --arg r "$rol" --argjson m "$menor" --arg a "$adulto" \
    '{email:$e,password:"clave123",nombre:$n,rol:$r} + (if $m then {esMenor:true,emailAdulto:$a} else {} end)')
  req POST /api/usuarios/registro "$body"
  USUARIO_ID=$(echo "$CUERPO" | jq -r '.id')
  LINK_AUTORIZACION=$(echo "$CUERPO" | jq -r '.linkAutorizacion // empty')
}

# login EMAIL [PASSWORD]  -> deja TOKEN en global
login() {
  req POST /api/usuarios/login "$(jq -nc --arg e "$1" --arg p "${2:-clave123}" '{email:$e,password:$p}')"
  TOKEN=$(echo "$CUERPO" | jq -r '.token')
}

# aprobar_docente DOCENTE_ID : el verificador agenda la llamada y aprueba
aprobar_docente() {
  local docente="$1" ver_token sol
  login verificador@tutorya.uy verificador123
  ver_token="$TOKEN"
  req GET '/api/verificaciones?estado=PENDIENTE' "" "$ver_token"
  sol=$(echo "$CUERPO" | jq -r --argjson d "$docente" '.[] | select(.docente_id==$d) | .id')
  req POST "/api/verificaciones/$sol/llamada" "$(jq -nc --arg f "$(fecha_futura 1)" '{fecha:$f}')" "$ver_token"
  req POST "/api/verificaciones/$sol/resolucion" '{"resultado":"APROBADO"}' "$ver_token"
}

# fecha_futura DIAS [HORA] -> ISO 8601 UTC (compatible con macOS y Linux)
fecha_futura() {
  local dias="$1" hora="${2:-15}"
  local d
  d=$(date -u -d "+${dias} days" +%Y-%m-%d 2>/dev/null || date -u -v+"${dias}"d +%Y-%m-%d)
  printf '%sT%02d:00:00Z' "$d" "$hora"
}

# esperar_sano [TIMEOUT_SEG]: espera a que el gateway responda a ambos endpoints de salud
# y a que todos los contenedores con healthcheck estén healthy.
esperar_sano() {
  local limite="${1:-120}" t=0
  printf '   esperando servicios sanos'
  while [ "$t" -lt "$limite" ]; do
    local malos
    malos=$(docker compose ps --format '{{.Name}} {{.Health}}' 2>/dev/null | awk '$2!="" && $2!="healthy"' | wc -l | tr -d ' ')
    if [ "$malos" = "0" ] \
      && [ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/salud")" = "200" ] \
      && [ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/reservas/salud")" = "200" ]; then
      printf ' OK (%ss)\n' "$t"
      return 0
    fi
    printf '.'
    sleep 2
    t=$((t + 2))
  done
  printf ' TIMEOUT\n'
  return 1
}

# psql_escalar SQL : ejecuta una consulta que devuelve un valor
psql_escalar() {
  docker compose exec -T db psql -U tutorya -d tutorya -tAc "$1" | tr -d '[:space:]'
}
