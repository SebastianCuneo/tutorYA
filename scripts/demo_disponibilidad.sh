#!/usr/bin/env bash
# UT5 — Validación del atributo de calidad: DISPONIBILIDAD (aislamiento de fallas).
#
# Escenario: falla el proceso que ejecuta un componente de dominio (por defecto, Mensajería).
#   - UT5 (microservicios): se detiene el contenedor "mensajeria".
#   - UT4 (service-based):  Mensajería vive dentro de "nucleo", así que se detiene "nucleo".
# Se mide el % de pedidos exitosos (2xx) de seis operaciones ANTES y DURANTE la falla.
#
# Uso:   ./scripts/demo_disponibilidad.sh [componente]   (usuarios|docentes|mensajeria|verificacion)
# UT4:   en la rama ut4-patrones, con su compose levantado:
#        git show ut5-microservicios:scripts/demo_disponibilidad.sh > scripts/demo_disponibilidad_ut5.sh
#        bash scripts/demo_disponibilidad_ut5.sh mensajeria
# Solo usa funciones de lib.sh que existen en ambas ramas.
source "$(dirname "$0")/lib.sh"

COMPONENTE="${1:-mensajeria}"
N="${N:-10}" # pedidos por operación y por fase
if docker compose config --services 2>/dev/null | grep -qx nucleo; then
  ARQ=ut4; CONTENEDOR=nucleo
  [ "$COMPONENTE" = "reservas" ] && CONTENEDOR=reservas
else
  ARQ=ut5; CONTENEDOR="$COMPONENTE"
fi
titulo "Disponibilidad ($ARQ): falla de $COMPONENTE => se detiene el contenedor '$CONTENEDOR'"

# Reintenta un comando hasta TIMEOUT segundos (los efectos de los eventos son asíncronos en la UT5).
d_esperar() {
  local limite="$1"; shift
  local fin=$(( $(date +%s) + limite ))
  while [ "$(date +%s)" -le "$fin" ]; do "$@" >/dev/null 2>&1 && return 0; sleep 0.5; done
  return 1
}
codigo() { curl -s -k -o /dev/null -w '%{http_code}' "$@"; }
json() { curl -s -k -H 'Content-Type: application/json' "$@"; }

paso "Preparación: docente aprobado con $((2 * N + 2)) horarios, estudiante y verificador"
registrar "doc_$SUFIJO@demo.uy" "Docente Disponibilidad" DOCENTE >/dev/null; DOC_ID="$USUARIO_ID"
login "doc_$SUFIJO@demo.uy" >/dev/null; DOC_TOKEN="$TOKEN"
_perfil() { [ "$(codigo -H "Authorization: Bearer $DOC_TOKEN" "$BASE/api/docentes/me")" = "200" ]; }
d_esperar 20 _perfil
login verificador@tutorya.uy verificador123 >/dev/null; VER_TOKEN="$TOKEN"
_sol() { json -H "Authorization: Bearer $VER_TOKEN" "$BASE/api/verificaciones?estado=PENDIENTE" | jq -e --argjson d "$DOC_ID" '.[]|select(.docente_id==$d)|.id'; }
d_esperar 20 _sol
aprobar_docente "$DOC_ID" >/dev/null
json -X PUT -H "Authorization: Bearer $DOC_TOKEN" -d '{"materias":["Fisica"]}' "$BASE/api/docentes/me/materias" >/dev/null
HORARIOS=()
for i in $(seq 1 $((2 * N + 2))); do
  HORARIOS+=("$(json -X POST -H "Authorization: Bearer $DOC_TOKEN" \
    -d "$(jq -nc --arg i "$(fecha_futura $((i + 1)) 9)" --arg f "$(fecha_futura $((i + 1)) 10)" '{inicio:$i,fin:$f,precio:300}')" \
    "$BASE/api/docentes/me/horarios" | jq -r .id)")
done
registrar "est_$SUFIJO@demo.uy" "Estudiante Disponibilidad" ESTUDIANTE >/dev/null
login "est_$SUFIJO@demo.uy" >/dev/null; EST_TOKEN="$TOKEN"
_catalogo() { json -H "Authorization: Bearer $EST_TOKEN" "$BASE/api/docentes?materia=Fisica" | jq -e --argjson d "$DOC_ID" '[.[]|select(.id==$d)]|length>0'; }
d_esperar 30 _catalogo
_msj() { [ "$(codigo -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer $EST_TOKEN" -d "{\"docenteId\":$DOC_ID,\"texto\":\"hola\"}" "$BASE/api/mensajes")" = "201" ]; }
d_esperar 20 _msj
info "docente $DOC_ID, ${#HORARIOS[@]} horarios"

H=0 # próximo horario libre para reservar
# operacion NOMBRE -> deja en RC el código HTTP de un pedido de esa operación
# (sin subshell: así el contador de horarios H se conserva entre llamadas)
operacion() {
  RC=$(operacion_http "$1")
  [ "$1" = "reservar" ] && case "$RC" in 2*) H=$((H + 1)) ;; esac
}
operacion_http() {
  case "$1" in
    login)        codigo -X POST -H 'Content-Type: application/json' -d "{\"email\":\"est_$SUFIJO@demo.uy\",\"password\":\"clave123\"}" "$BASE/api/usuarios/login" ;;
    buscar)       codigo -H "Authorization: Bearer $EST_TOKEN" "$BASE/api/docentes?materia=Fisica" ;;
    mensaje)      codigo -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer $EST_TOKEN" -d "{\"docenteId\":$DOC_ID,\"texto\":\"consulta\"}" "$BASE/api/mensajes" ;;
    verificacion) codigo -H "Authorization: Bearer $VER_TOKEN" "$BASE/api/verificaciones" ;;
    reservar)     codigo -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer $EST_TOKEN" \
                    -d "{\"docenteId\":$DOC_ID,\"horarioId\":${HORARIOS[$H]},\"tokenPago\":\"tok_ok\"}" "$BASE/api/reservas" ;;
    mis_reservas) codigo -H "Authorization: Bearer $EST_TOKEN" "$BASE/api/reservas" ;;
  esac
}
OPERACIONES="login buscar mensaje verificacion reservar mis_reservas"
declare -A SERVICIO=([login]=Usuarios [buscar]=Docentes [mensaje]=Mensajería [verificacion]=Verificación [reservar]=Reservas [mis_reservas]=Reservas)
declare -A ANTES DURANTE

# fase ARREGLO : N rondas de las seis operaciones; guarda el % de 2xx de cada una
fase() {
  local -n destino="$1"
  local op r c ok
  declare -A oks
  for op in $OPERACIONES; do oks[$op]=0; done
  for r in $(seq 1 "$N"); do
    for op in $OPERACIONES; do
      operacion "$op"; c="$RC"
      case "$c" in 2*) oks[$op]=$((oks[$op] + 1)) ;; esac
    done
  done
  for op in $OPERACIONES; do destino[$op]=$(( oks[$op] * 100 / N )); done
}

paso "Fase 1: todo sano ($N pedidos por operación)"
fase ANTES

paso "Fase 2: docker compose stop $CONTENEDOR"
docker compose stop "$CONTENEDOR" >/dev/null 2>&1
sleep 6 # el DNS de Nginx (valid=5s) deja de devolver las réplicas detenidas
T0=$(ahora_ms)
fase DURANTE
info "fase medida en $(( $(ahora_ms) - T0 )) ms"

paso "Restaurando $CONTENEDOR"
docker compose start "$CONTENEDOR" >/dev/null 2>&1
esperar_healthy 120
sleep 16 # DNS del gateway (5 s) y circuitos de las otras réplicas (esperaMs = 15 s) vuelven a la normalidad

mkdir -p scripts/salidas
SALIDA="scripts/salidas/disponibilidad_${ARQ}_${COMPONENTE}.md"
{
  echo "| Operación | Servicio dueño | Éxito antes | Éxito durante la falla |"
  echo "|---|---|---|---|"
  DISP=0
  for op in $OPERACIONES; do
    echo "| $op | ${SERVICIO[$op]} | ${ANTES[$op]} % | ${DURANTE[$op]} % |"
    [ "${DURANTE[$op]}" -ge 90 ] && DISP=$((DISP + 1))
  done
  echo
  echo "Arquitectura: $ARQ · componente que falla: $COMPONENTE (contenedor detenido: $CONTENEDOR) · N=$N"
  echo "Operaciones disponibles durante la falla (≥ 90 % de éxito): $DISP de 6"
} | tee "$SALIDA" | sed 's/^/   /'
info "resultado guardado en $SALIDA"

paso "Verificaciones"
for op in $OPERACIONES; do check "antes de la falla: $op" "100" "${ANTES[$op]}"; done
if [ "$ARQ" = "ut5" ]; then
  # Lo esperado en microservicios: solo fallan las operaciones del servicio caído (y, si cae Docentes
  # o Usuarios, también reservar, porque Reservas no confirma sin validar: elección CP).
  for op in $OPERACIONES; do
    esperado=100
    [ "${SERVICIO[$op]}" = "$(echo "$COMPONENTE" | sed 's/mensajeria/Mensajería/;s/verificacion/Verificación/;s/usuarios/Usuarios/;s/docentes/Docentes/')" ] && esperado=0
    [ "$op" = "reservar" ] && [[ "$COMPONENTE" =~ ^(usuarios|docentes)$ ]] && esperado=0
    check "durante la falla: $op" "$esperado" "${DURANTE[$op]}"
  done
fi
resumen
