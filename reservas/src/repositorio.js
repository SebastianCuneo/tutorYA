const { db, eventos } = require('../../comun');

const RESERVA = 'id, estudiante_id, docente_id, horario_id, estado, monto, referencia_pago, motivo, creada_en';

// Paso 1 de la saga: la reserva nace PENDIENTE. El índice único parcial (horario_id, salvo CANCELADA)
// ya bloquea el horario: de dos pedidos concurrentes, el segundo falla con 409.
async function insertarPendiente({ estudianteId, docenteId, horarioId, monto }) {
  const { rows } = await db.query(
    `INSERT INTO reservas.reservas (estudiante_id, docente_id, horario_id, estado, monto)
     VALUES ($1,$2,$3,'PENDIENTE',$4) RETURNING ${RESERVA}`,
    [estudianteId, docenteId, horarioId, monto]
  );
  return rows[0];
}

// Transición PENDIENTE -> estadoNuevo + evento en la outbox, en una sola transacción local.
// Condicional: si otra réplica (o el reconciliador) ya la resolvió, no hace nada y devuelve null.
async function resolver(id, estadoNuevo, { referencia = null, motivo = null } = {}) {
  const cliente = await db.pool.connect();
  try {
    await cliente.query('BEGIN');
    const { rows } = await cliente.query(
      `UPDATE reservas.reservas SET estado = $2, referencia_pago = $3, motivo = $4
       WHERE id = $1 AND estado = 'PENDIENTE' RETURNING ${RESERVA}`,
      [id, estadoNuevo, referencia, motivo]
    );
    const r = rows[0];
    if (r) {
      const tipo = estadoNuevo === 'CONFIRMADA' ? 'reserva.confirmada' : 'reserva.cancelada';
      await eventos.guardar(cliente, tipo, { reservaId: r.id, docenteId: r.docente_id, horarioId: r.horario_id, estudianteId: r.estudiante_id });
    }
    await cliente.query('COMMIT');
    return r || null;
  } catch (e) {
    await cliente.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    cliente.release();
  }
}

// Reservas que quedaron PENDIENTES (pago sin respuesta) hace más de `segundos`.
async function pendientesDesde(segundos) {
  const { rows } = await db.query(
    `SELECT ${RESERVA} FROM reservas.reservas
     WHERE estado = 'PENDIENTE' AND creada_en < now() - make_interval(secs => $1) ORDER BY id LIMIT 50`,
    [segundos]
  );
  return rows;
}

async function listarPorUsuario(usuarioId, rol) {
  const columna = rol === 'DOCENTE' ? 'docente_id' : 'estudiante_id';
  const { rows } = await db.query(`SELECT ${RESERVA} FROM reservas.reservas WHERE ${columna} = $1 ORDER BY id`, [usuarioId]);
  return rows;
}

async function obtener(id) {
  const { rows } = await db.query(`SELECT ${RESERVA} FROM reservas.reservas WHERE id = $1`, [id]);
  return rows[0] || null;
}

// UPDATE condicional: solo cambia si sigue CONFIRMADA.
async function marcarDictada(id) {
  const { rows } = await db.query(
    `UPDATE reservas.reservas SET estado = 'DICTADA' WHERE id = $1 AND estado = 'CONFIRMADA' RETURNING ${RESERVA}`,
    [id]
  );
  return rows[0] || null;
}

// Alimenta la búsqueda de docentes. Una reserva PENDIENTE también ocupa el horario.
async function horariosOcupados(docenteId) {
  const { rows } = await db.query(
    "SELECT horario_id FROM reservas.reservas WHERE docente_id = $1 AND estado <> 'CANCELADA'",
    [docenteId]
  );
  return rows.map((r) => r.horario_id);
}

async function horariosOcupadosDe(docenteIds) {
  const { rows } = await db.query(
    "SELECT docente_id, horario_id FROM reservas.reservas WHERE docente_id = ANY($1::int[]) AND estado <> 'CANCELADA'",
    [docenteIds]
  );
  return rows;
}

module.exports = { insertarPendiente, resolver, pendientesDesde, listarPorUsuario, obtener, marcarDictada, horariosOcupados, horariosOcupadosDe };
