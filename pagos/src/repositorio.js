const { db } = require('../../comun');

const COLS = 'id, reserva_id, monto, estado, referencia, motivo, creado_en';

// Idempotencia: la clave es la reserva (UNIQUE). Si el pago ya existe, se devuelve el mismo resultado.
async function insertarSiNoExiste({ reservaId, monto, estado, referencia, motivo }) {
  const { rows } = await db.query(
    `INSERT INTO pagos.pagos (reserva_id, monto, estado, referencia, motivo) VALUES ($1,$2,$3,$4,$5)
     ON CONFLICT (reserva_id) DO NOTHING RETURNING ${COLS}`,
    [reservaId, monto, estado, referencia, motivo]
  );
  return rows[0] || null;
}

async function obtenerPorReserva(reservaId) {
  const { rows } = await db.query(`SELECT ${COLS} FROM pagos.pagos WHERE reserva_id = $1`, [reservaId]);
  return rows[0] || null;
}

// Compensación de la saga: solo se reembolsa lo aprobado.
async function reembolsar(reservaId) {
  const { rows } = await db.query(
    `UPDATE pagos.pagos SET estado = 'REEMBOLSADO' WHERE reserva_id = $1 AND estado = 'APROBADO' RETURNING ${COLS}`,
    [reservaId]
  );
  return rows[0] || null;
}

// Anulación (fence de la saga): ocupa la clave de idempotencia con un registro ANULADO. Si ya hay un
// pago para esa reserva no hace nada (devuelve null) y gana el pago existente.
async function anular(reservaId) {
  const { rows } = await db.query(
    `INSERT INTO pagos.pagos (reserva_id, monto, estado, motivo) VALUES ($1, 0, 'ANULADO', 'Anulado por el reconciliador')
     ON CONFLICT (reserva_id) DO NOTHING RETURNING ${COLS}`,
    [reservaId]
  );
  return rows[0] || null;
}

module.exports = { insertarSiNoExiste, obtenerPorReserva, reembolsar, anular };
