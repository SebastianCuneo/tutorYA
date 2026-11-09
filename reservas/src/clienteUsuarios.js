// UT5: cliente SOAP de Usuarios. Reservas ya no llama a GET /internal/usuarios/:id/estado (REST/JSON):
// lee el contrato WSDL que publica Usuarios y envía un sobre SOAP (XML) a ConsultarEstadoEstudiante.
// Pasa por su propio Circuit Breaker y devuelve { status, body } como el cliente REST, para que el
// servicio de reservas no dependa del protocolo.
const { soap, config, requestId: idDelRequest, CircuitBreaker, logger } = require('../../comun');

const USUARIOS_URL = process.env.USUARIOS_URL || 'http://usuarios:3000';
const ENDPOINT = `${USUARIOS_URL}/soap/estudiantes`;
const circuito = new CircuitBreaker('usuarios');

let cliente = null; // se crea una vez a partir del WSDL; si falla, se reintenta en la próxima llamada

async function obtenerCliente() {
  if (!cliente) {
    cliente = await soap.createClientAsync(`${ENDPOINT}?wsdl`, {
      endpoint: ENDPOINT,
      wsdl_options: { timeout: config.get('http.timeoutMs') },
    });
    logger.info('cliente SOAP creado desde el WSDL', { wsdl: `${ENDPOINT}?wsdl` });
  }
  return cliente;
}

// Fault de negocio (soap:Client) => respuesta válida 4xx. Fault del servidor => 500 (cuenta como falla).
function desdeFault(e) {
  const fault = e && e.root && e.root.Envelope && e.root.Envelope.Body && e.root.Envelope.Body.Fault;
  if (!fault) return null;
  const codigo = fault.detail && fault.detail.codigo;
  if (codigo === 'NO_ENCONTRADO') return { status: 404, body: { fault } };
  return { status: String(fault.faultcode).endsWith('Client') ? 400 : 500, body: { fault } };
}

async function llamar(estudianteId) {
  const c = await obtenerCliente();
  const requestId = idDelRequest();
  try {
    const [resultado] = await c.ConsultarEstadoEstudianteAsync(
      { estudianteId },
      { timeout: config.get('http.timeoutMs') },
      requestId ? { 'X-Request-Id': requestId } : {}
    );
    return {
      status: 200,
      body: { id: Number(resultado.id), rol: resultado.rol, esMenor: resultado.esMenor === true || resultado.esMenor === 'true', estado: resultado.estado },
    };
  } catch (e) {
    const r = desdeFault(e);
    if (r) return r;
    if (!e.response) cliente = null; // error de red: se vuelve a leer el WSDL la próxima vez
    throw e;
  }
}

const consultarEstadoEstudiante = (estudianteId) => circuito.ejecutar(() => llamar(estudianteId));

module.exports = { consultarEstadoEstudiante };
