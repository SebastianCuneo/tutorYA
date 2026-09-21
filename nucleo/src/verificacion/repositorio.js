const { db } = require('../../../comun');

const COLS = 'id, docente_id, estado, llamada_en, verificador_id, resuelta_en';

async function crearSolicitud(docenteId) {
  await db.query(
    `INSERT INTO verificacion.solicitudes (docente_id, estado) VALUES ($1, 'PENDIENTE')
     ON CONFLICT (docente_id) DO NOTHING`,
    [docenteId]
  );
}

async function listar(estado) {
  const { rows } = await db.query(
    `SELECT ${COLS} FROM verificacion.solicitudes WHERE ($1::text IS NULL OR estado = $1) ORDER BY id`,
    [estado]
  );
  return rows;
}

async function obtener(id) {
  const { rows } = await db.query(`SELECT ${COLS} FROM verificacion.solicitudes WHERE id = $1`, [id]);
  return rows[0] || null;
}

// Transición atómica: solo cambia si la solicitud está en el estado esperado.
async function agendarLlamada(id, verificadorId, fecha) {
  const { rows } = await db.query(
    `UPDATE verificacion.solicitudes SET estado = 'LLAMADA_AGENDADA', llamada_en = $3, verificador_id = $2
     WHERE id = $1 AND estado = 'PENDIENTE' RETURNING ${COLS}`,
    [id, verificadorId, fecha]
  );
  return rows[0] || null;
}

async function resolver(id, verificadorId, resultado) {
  const { rows } = await db.query(
    `UPDATE verificacion.solicitudes SET estado = $3, verificador_id = $2, resuelta_en = now()
     WHERE id = $1 AND estado = 'LLAMADA_AGENDADA' RETURNING ${COLS}`,
    [id, verificadorId, resultado]
  );
  return rows[0] || null;
}

module.exports = { crearSolicitud, listar, obtener, agendarLlamada, resolver };
