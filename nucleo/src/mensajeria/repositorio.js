const { db } = require('../../../comun');

async function buscarOCrearConversacion(estudianteId, docenteId) {
  const { rows } = await db.query(
    `INSERT INTO mensajeria.conversaciones (estudiante_id, docente_id) VALUES ($1,$2)
     ON CONFLICT (estudiante_id, docente_id) DO UPDATE SET estudiante_id = EXCLUDED.estudiante_id
     RETURNING id, estudiante_id, docente_id`,
    [estudianteId, docenteId]
  );
  return rows[0];
}

async function obtenerConversacion(id) {
  const { rows } = await db.query(
    'SELECT id, estudiante_id, docente_id FROM mensajeria.conversaciones WHERE id = $1',
    [id]
  );
  return rows[0] || null;
}

async function insertarMensaje(conversacionId, autorId, texto) {
  const { rows } = await db.query(
    `INSERT INTO mensajeria.mensajes (conversacion_id, autor_id, texto) VALUES ($1,$2,$3)
     RETURNING id, conversacion_id, autor_id, texto, enviado_en`,
    [conversacionId, autorId, texto]
  );
  return rows[0];
}

async function listarConversaciones(usuarioId, rol) {
  const columna = rol === 'DOCENTE' ? 'docente_id' : 'estudiante_id';
  const { rows } = await db.query(
    `SELECT id, estudiante_id, docente_id FROM mensajeria.conversaciones WHERE ${columna} = $1 ORDER BY id`,
    [usuarioId]
  );
  return rows;
}

async function listarMensajes(conversacionId) {
  const { rows } = await db.query(
    `SELECT id, conversacion_id, autor_id, texto, enviado_en FROM mensajeria.mensajes
     WHERE conversacion_id = $1 ORDER BY id`,
    [conversacionId]
  );
  return rows;
}

module.exports = { buscarOCrearConversacion, obtenerConversacion, insertarMensaje, listarConversaciones, listarMensajes };
