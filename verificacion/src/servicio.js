const { E } = require('../../comun');
const repo = require('./repositorio');

const ESTADOS = ['PENDIENTE', 'LLAMADA_AGENDADA', 'APROBADO', 'RECHAZADO'];

// Reacciona al evento docente.registrado: abre la solicitud de verificación (PENDIENTE).
async function alRegistrarseDocente({ datos: { docenteId } }) {
  await repo.crearSolicitud(docenteId);
}

async function listarSolicitudes(estado) {
  if (estado !== undefined && !ESTADOS.includes(estado)) throw E.validacion(`estado debe ser uno de ${ESTADOS.join(', ')}`);
  return repo.listar(estado || null);
}

// HU10, paso 1: PENDIENTE -> LLAMADA_AGENDADA.
async function agendarLlamada(id, verificadorId, body = {}) {
  const fecha = new Date(body.fecha);
  if (typeof body.fecha !== 'string' || Number.isNaN(fecha.getTime())) throw E.validacion('fecha inválida (ISO 8601)');
  const s = await repo.agendarLlamada(id, verificadorId, fecha.toISOString());
  if (s) return s;
  if (!(await repo.obtener(id))) throw E.noEncontrado('Solicitud no encontrada');
  throw E.conflicto('Solo se puede agendar la llamada de una solicitud PENDIENTE');
}

// HU10, paso 2: LLAMADA_AGENDADA -> APROBADO/RECHAZADO; avisa a Docentes por evento.
async function resolverSolicitud(id, verificadorId, body = {}) {
  const { resultado } = body;
  if (!['APROBADO', 'RECHAZADO'].includes(resultado)) throw E.validacion('resultado debe ser APROBADO o RECHAZADO');
  const s = await repo.resolver(id, verificadorId, resultado);
  if (!s) {
    if (!(await repo.obtener(id))) throw E.noEncontrado('Solicitud no encontrada');
    throw E.conflicto('Solo se puede resolver una solicitud en estado LLAMADA_AGENDADA');
  }
  // UT5: el evento docente.verificado se guardó en la outbox en la misma transacción (repositorio).
  return s;
}

module.exports = { alRegistrarseDocente, listarSolicitudes, agendarLlamada, resolverSolicitud };
