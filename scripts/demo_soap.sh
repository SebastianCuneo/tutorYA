#!/usr/bin/env bash
# UT5 — Migración REST -> SOAP: ConsultarEstadoEstudiante.
# Antes: GET /internal/usuarios/:id/estado (JSON). Ahora: POST /soap/estudiantes con un sobre SOAP (XML),
# contrato en /soap/estudiantes?wsdl. La consume Reservas al reservar.
source "$(dirname "$0")/lib.sh"
titulo "Migración de REST a SOAP"

# Pedido HTTP desde dentro de la red interna (el gateway no expone /soap ni /internal).
desde_reservas() {
  docker compose exec -T --index 1 reservas node -e '
    const [m, u, b] = process.argv.slice(1);
    fetch(u, { method: m, headers: { "Content-Type": "text/xml; charset=utf-8",
      SOAPAction: "\"http://tutorya.uy/usuarios/estudiantes/ConsultarEstadoEstudiante\"" }, body: b || undefined })
      .then(async (r) => console.log(r.status + " " + (await r.text())))
      .catch((e) => console.log("000 " + e.message));' "$@"
}
sobre() {
  cat <<XML
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:e="http://tutorya.uy/usuarios/estudiantes">
  <soap:Body><e:ConsultarEstadoEstudianteRequest><e:estudianteId>$1</e:estudianteId></e:ConsultarEstadoEstudianteRequest></soap:Body>
</soap:Envelope>
XML
}

paso "1. El endpoint REST viejo ya no existe"
R=$(docker compose exec -T --index 1 reservas node -e 'fetch("http://usuarios:3000/internal/usuarios/1/estado").then(r=>console.log(r.status))')
check "GET /internal/usuarios/1/estado" "404" "$R"

paso "2. Contrato WSDL publicado por Usuarios"
W=$(desde_reservas GET "http://usuarios:3000/soap/estudiantes?wsdl")
echo "${W#* }" | grep -E 'operation name|element name="(estudianteId|esMenor|estado)"|soap:address' | sed 's/^ */     /'
check "WSDL disponible" "200" "${W%% *}"

paso "3. Pedido SOAP (XML) válido"
registrar "est_$SUFIJO@demo.uy" "Estudiante Demo" ESTUDIANTE >/dev/null
EST_ID="$USUARIO_ID"
info "pedido:"; sobre "$EST_ID" | sed 's/^/     /'
S=$(desde_reservas POST http://usuarios:3000/soap/estudiantes "$(sobre "$EST_ID")")
info "respuesta:"; echo "${S#* }" | sed 's/></>\n</g' | sed 's/^/     /'
check "HTTP del servicio SOAP" "200" "${S%% *}"
check "respuesta en XML con <estado>AUTORIZADO</estado>" "1" "$(echo "$S" | grep -c '<estado>AUTORIZADO</estado>')"

paso "4. Error de negocio como SOAP Fault"
S=$(desde_reservas POST http://usuarios:3000/soap/estudiantes "$(sobre 999999)")
echo "${S#* }" | grep -o '<soap:Fault>.*</soap:Fault>' | sed 's/^/     /'
check "estudiante inexistente => soap:Client" "1" "$(echo "$S" | grep -c 'soap:Client')"

paso "5. Otro componente consume el servicio: Reservas reserva usando SOAP"
preparar_docente 1 >/dev/null
req POST /api/reservas "{\"docenteId\":$DOC_ID,\"horarioId\":${HORARIOS// /},\"tokenPago\":\"tok_ok\"}" "$EST_TOKEN"
check "reserva creada (el estado del estudiante vino por SOAP)" "201" "$CODIGO"
info "log de Reservas:"
docker compose logs reservas 2>/dev/null | grep -m1 'cliente SOAP creado' | sed 's/^/     /' | cut -c1-220
resumen
