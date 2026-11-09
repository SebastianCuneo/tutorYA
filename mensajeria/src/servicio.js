const { E } = require('../../comun');
const repo = require('./repositorio');

function validarTexto(texto) {
  if (typeof texto !== 'string' || !texto.trim() || texto.length > 2000) {
    throw E.validacion('texto es obligatorio (máx. 2000 caracteres)');
  }
  return texto.trim();
}

// HU4: el estudiante escribe a un docente APROBADO; la conversación se crea al primer mensaje.
async function enviarMensaje(estudianteId, body = {}) {
  const docenteId = Number(body.docenteId);
  if (!Number.isInteger(docenteId)) throw E.validacion('docenteId inválido');
  const texto = validarTexto(body.texto);
  // UT5: ya no se llama a Docentes. Mensajería tiene su propia copia de los docentes habilitados,
  // alimentada por el evento docente.verificado: si Docentes está caído, se puede seguir escribiendo.
  if (!(await repo.docenteHabilitado(docenteId))) throw E.noEncontrado('Docente no encontrado');
  const conv = await repo.buscarOCrearConversacion(estudianteId, docenteId);
  const mensaje = await repo.insertarMensaje(conv.id, estudianteId, texto);
  return { conversacionId: conv.id, mensaje };
}

// Solo el estudiante o el docente de la conversación pueden verla (403 si no).
async function conversacionDelParticipante(id, usuarioId) {
  const conv = await repo.obtenerConversacion(id);
  if (!conv) throw E.noEncontrado('Conversación no encontrada');
  if (![conv.estudiante_id, conv.docente_id].includes(usuarioId)) throw E.prohibido('No participás de esta conversación');
  return conv;
}

// HU9: el docente responde dentro de una conversación propia.
async function responderMensaje(docenteId, conversacionId, body = {}) {
  const texto = validarTexto(body.texto);
  const conv = await conversacionDelParticipante(conversacionId, docenteId);
  if (conv.docente_id !== docenteId) throw E.prohibido('No participás de esta conversación');
  return repo.insertarMensaje(conv.id, docenteId, texto);
}

const listarConversaciones = (usuario) => repo.listarConversaciones(usuario.id, usuario.rol);

async function listarMensajes(usuarioId, conversacionId) {
  await conversacionDelParticipante(conversacionId, usuarioId);
  return repo.listarMensajes(conversacionId);
}

// Handler del evento docente.verificado (idempotente: upsert / delete).
async function alVerificarseDocente({ datos: { docenteId, resultado } }) {
  if (resultado === 'APROBADO') await repo.habilitarDocente(docenteId);
  else if (resultado === 'RECHAZADO') await repo.deshabilitarDocente(docenteId);
}

module.exports = {
  alVerificarseDocente, enviarMensaje, responderMensaje, listarConversaciones, listarMensajes };
