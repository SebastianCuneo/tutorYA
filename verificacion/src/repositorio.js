const { db, eventos } = require('../../comun');

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

// UT5: el cambio de estado y el evento docente.verificado (outbox) van en la misma transacción.
async function resolver(id, verificadorId, resultado) {
  const cliente = await db.pool.connect();
  try {
    await cliente.query('BEGIN');
    const { rows } = await cliente.query(
      `UPDATE verificacion.solicitudes SET estado = $3, verificador_id = $2, resuelta_en = now()
       WHERE id = $1 AND estado = 'LLAMADA_AGENDADA' RETURNING ${COLS}`,
      [id, verificadorId, resultado]
    );
    if (rows[0]) await eventos.guardar(cliente, 'docente.verificado', { docenteId: rows[0].docente_id, resultado });
    await cliente.query('COMMIT');
    return rows[0] || null;
  } catch (e) {
    await cliente.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    cliente.release();
  }
}

module.exports = { crearSolicitud, listar, obtener, agendarLlamada, resolver };
