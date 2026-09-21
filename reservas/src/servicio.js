const { E, db, logger } = require('../../comun');
const repo = require('./repositorio');
const nucleo = require('./clienteNucleo');
const simulador = require('./pagos/simulador');

async function llamarNucleo(fn) {
  try {
    return await fn();
  } catch (e) {
    logger.warn('el núcleo no responde', { error: e.message });
    throw E.noDisponible('No se pudo consultar el núcleo; reintentá más tarde');
  }
}

async function reservarClase(estudiante, body = {}) {
  const docenteId = Number(body.docenteId);
  const horarioId = Number(body.horarioId);
  if (!Number.isInteger(docenteId) || !Number.isInteger(horarioId)) throw E.validacion('docenteId y horarioId deben ser enteros');
  if (typeof body.tokenPago !== 'string' || !body.tokenPago) throw E.validacion('tokenPago es obligatorio');

  // 1. Estado del estudiante (fail-safe: ante cualquier duda, no se permite reservar).
  const est = await llamarNucleo(() => nucleo.consultarEstadoEstudiante(estudiante.id));
  if (est.status !== 200) {
    if (est.status === 404) throw E.prohibido('Estudiante no encontrado');
    throw E.noDisponible('No se pudo verificar la autorización del estudiante');
  }
  if (est.body.esMenor && est.body.estado !== 'AUTORIZADO') {
    throw E.prohibido('El estudiante menor no tiene autorización del adulto responsable');
  }

  // 2. Disponibilidad del docente y del horario.
  const disp = await llamarNucleo(() => nucleo.consultarDisponibilidad(docenteId, horarioId));
  if (disp.status === 404) throw E.noEncontrado('Docente u horario no encontrado');
  if (disp.status !== 200) throw E.noDisponible('No se pudo consultar la disponibilidad');
  if (!disp.body.docenteAprobado) throw E.conflicto('El docente no está aprobado');
  const monto = disp.body.horario.precio;

  // 3. Transacción ACID con un cliente dedicado del pool.
  const cliente = await db.pool.connect();
  try {
    await cliente.query('BEGIN');
    let reserva;
    try {
      reserva = await repo.insertarReserva(cliente, { estudianteId: estudiante.id, docenteId, horarioId, monto });
    } catch (e) {
      if (e.code === '23505') {
        await cliente.query('ROLLBACK');
        throw E.conflicto('Horario ya reservado');
      }
      throw e;
    }
    const cobro = await simulador.cobrar({ monto, tokenPago: body.tokenPago });
    if (!cobro.aprobado) {
      await cliente.query('ROLLBACK');
      throw E.pagoRechazado(cobro.motivo);
    }
    const pago = await repo.insertarPago(cliente, { reservaId: reserva.id, monto, referencia: cobro.referencia });
    await cliente.query('COMMIT');
    return { reserva, pago };
  } catch (e) {
    // ROLLBACK ya emitido en los casos controlados; si falló otra cosa, se revierte aquí (inocuo si no hay tx).
    await cliente.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    cliente.release();
  }
}

const listarReservas = (usuario) => repo.listarPorUsuario(usuario.id, usuario.rol);

async function obtenerReserva(usuario, id) {
  const r = await repo.obtener(id);
  if (!r) throw E.noEncontrado('Reserva no encontrada');
  if (![r.estudiante_id, r.docente_id].includes(usuario.id)) throw E.prohibido('No participás de esta reserva');
  return { reserva: r, pago: await repo.obtenerPago(id) };
}

async function confirmarClaseDictada(docente, id) {
  const r = await repo.obtener(id);
  if (!r) throw E.noEncontrado('Reserva no encontrada');
  if (r.docente_id !== docente.id) throw E.prohibido('La reserva no es tuya');
  const actualizada = await repo.marcarDictada(id);
  if (!actualizada) throw E.conflicto('Solo se puede marcar como dictada una reserva CONFIRMADA');
  return actualizada;
}

const horariosOcupados = async (docenteId) => ({ docenteId, horarioIds: await repo.horariosOcupados(docenteId) });

module.exports = { reservarClase, listarReservas, obtenerReserva, confirmarClaseDictada, horariosOcupados };
