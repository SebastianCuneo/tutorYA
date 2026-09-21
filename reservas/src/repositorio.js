const { db } = require('../../comun');

const RESERVA = 'id, estudiante_id, docente_id, horario_id, estado, monto, creada_en';

// Los inserts reciben el cliente de la transacción en curso.
async function insertarReserva(cliente, { estudianteId, docenteId, horarioId, monto }) {
  const { rows } = await cliente.query(
    `INSERT INTO reservas.reservas (estudiante_id, docente_id, horario_id, estado, monto)
     VALUES ($1,$2,$3,'CONFIRMADA',$4) RETURNING ${RESERVA}`,
    [estudianteId, docenteId, horarioId, monto]
  );
  return rows[0];
}

async function insertarPago(cliente, { reservaId, monto, referencia }) {
  const { rows } = await cliente.query(
    `INSERT INTO reservas.pagos (reserva_id, monto, referencia) VALUES ($1,$2,$3)
     RETURNING id, reserva_id, monto, referencia, pagado_en`,
    [reservaId, monto, referencia]
  );
  return rows[0];
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

async function obtenerPago(reservaId) {
  const { rows } = await db.query(
    'SELECT id, reserva_id, monto, referencia, pagado_en FROM reservas.pagos WHERE reserva_id = $1',
    [reservaId]
  );
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

// Alimenta la búsqueda de docentes (Núcleo la consulta por HTTP interno).
async function horariosOcupados(docenteId) {
  const { rows } = await db.query('SELECT horario_id FROM reservas.reservas WHERE docente_id = $1', [docenteId]);
  return rows.map((r) => r.horario_id);
}

module.exports = { insertarReserva, insertarPago, listarPorUsuario, obtener, obtenerPago, marcarDictada, horariosOcupados };
