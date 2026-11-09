const { E, logger, CircuitoAbiertoError } = require('../../comun');
const repo = require('./repositorio');
const usuarios = require('./clienteUsuarios'); // SOAP
const docentes = require('./clienteDocentes'); // REST
const pagos = require('./clientePagos'); // REST

// Si una dependencia no responde (red/timeout) o su circuito está abierto => 503: ante la duda no se reserva.
async function llamar(nombre, fn) {
  try {
    return await fn();
  } catch (e) {
    if (e instanceof CircuitoAbiertoError) {
      throw E.circuitoAbierto(`${nombre} no está disponible (circuito abierto); reintentá más tarde`, e.retryAfterSeg);
    }
    logger.warn(`${nombre} no responde`, { error: e.message });
    throw E.noDisponible(`No se pudo consultar ${nombre}; reintentá más tarde`);
  }
}

// Errores en los que el pedido nunca llegó a Pagos (conexión rechazada o nombre inexistente).
const SIN_CONEXION = ['ECONNREFUSED', 'ENOTFOUND', 'EAI_AGAIN', 'EHOSTUNREACH'];
const sinConexion = (e) => SIN_CONEXION.includes(e && e.cause && e.cause.code);

// HU5/HU6 (UT5): Saga orquestada por Reservas. Ya no hay una transacción ACID que abarque reserva y
// pago, porque el pago vive en otro servicio con otra base. Pasos:
//   1. Validar estudiante (SOAP a Usuarios) y disponibilidad (REST a Docentes): consultas fail-safe.
//   2. Insertar la reserva PENDIENTE (transacción local; el índice único bloquea el horario).
//   3. Cobrar en Pagos (clave de idempotencia = id de la reserva).
//   4a. Aprobado  -> CONFIRMADA + evento reserva.confirmada (misma transacción local, outbox).
//   4b. Rechazado -> CANCELADA (compensación: libera el horario) + evento reserva.cancelada.
//   4c. Sin respuesta (timeout) -> queda PENDIENTE (202); el reconciliador consulta a Pagos y la resuelve.
async function reservarClase(estudiante, body = {}) {
  const docenteId = Number(body.docenteId);
  const horarioId = Number(body.horarioId);
  if (!Number.isInteger(docenteId) || !Number.isInteger(horarioId)) throw E.validacion('docenteId y horarioId deben ser enteros');
  if (typeof body.tokenPago !== 'string' || !body.tokenPago) throw E.validacion('tokenPago es obligatorio');

  // 1a. Estado del estudiante (SOAP). Fail-safe: ante cualquier duda, no se reserva.
  const est = await llamar('Usuarios', () => usuarios.consultarEstadoEstudiante(estudiante.id));
  if (est.status !== 200) {
    if (est.status === 404) throw E.prohibido('Estudiante no encontrado');
    throw E.noDisponible('No se pudo verificar la autorización del estudiante');
  }
  if (est.body.esMenor && est.body.estado !== 'AUTORIZADO') {
    throw E.prohibido('El estudiante menor no tiene autorización del adulto responsable');
  }

  // 1b. Disponibilidad del docente y del horario (REST).
  const disp = await llamar('Docentes', () => docentes.consultarDisponibilidad(docenteId, horarioId));
  if (disp.status === 404) throw E.noEncontrado('Docente u horario no encontrado');
  if (disp.status !== 200) throw E.noDisponible('No se pudo consultar la disponibilidad');
  if (!disp.body.docenteAprobado) throw E.conflicto('El docente no está aprobado');
  const monto = disp.body.horario.precio;

  // 2. Reserva PENDIENTE (transacción local).
  let reserva;
  try {
    reserva = await repo.insertarPendiente({ estudianteId: estudiante.id, docenteId, horarioId, monto });
  } catch (e) {
    if (e.code === '23505') throw E.conflicto('Horario ya reservado');
    throw e;
  }

  // 3. Cobro en Pagos.
  let cobro;
  try {
    cobro = await pagos.cobrar({ reservaId: reserva.id, monto, tokenPago: body.tokenPago });
  } catch (e) {
    if (e instanceof CircuitoAbiertoError) {
      // Seguro que no se cobró (no se llamó): se compensa ya y se libera el horario.
      await repo.resolver(reserva.id, 'CANCELADA', { motivo: 'Pagos no disponible' });
      throw E.circuitoAbierto('Pagos no está disponible (circuito abierto); reintentá más tarde', e.retryAfterSeg);
    }
    if (sinConexion(e)) {
      // No se pudo ni conectar (servicio caído): seguro que no se cobró => compensar ya.
      await repo.resolver(reserva.id, 'CANCELADA', { motivo: 'Pagos no disponible' });
      logger.warn('Pagos no disponible; reserva compensada', { reservaId: reserva.id, error: e.message });
      throw E.noDisponible('No se pudo contactar a Pagos; reintentá más tarde');
    }
    // Timeout u otro error a mitad de camino: NO se sabe si se cobró. No se cancela a ciegas: queda PENDIENTE.
    logger.warn('pago sin respuesta; la reserva queda PENDIENTE para el reconciliador', { reservaId: reserva.id, error: e.message });
    return { reserva, pago: null, mensaje: 'Pago en verificación: la reserva se confirma o se cancela en unos segundos' };
  }

  // 4. Resultado del cobro.
  if (cobro.status === 200 && cobro.body.estado === 'APROBADO') {
    const r = await repo.resolver(reserva.id, 'CONFIRMADA', { referencia: cobro.body.referencia });
    return { reserva: r || (await repo.obtener(reserva.id)), pago: cobro.body };
  }
  if (cobro.status === 200 && cobro.body.estado === 'RECHAZADO') {
    await repo.resolver(reserva.id, 'CANCELADA', { motivo: cobro.body.motivo });
    throw E.pagoRechazado(cobro.body.motivo || 'Pago rechazado');
  }
  // Respuesta inesperada (5xx): no se sabe el resultado => PENDIENTE.
  logger.warn('respuesta inesperada de Pagos; la reserva queda PENDIENTE', { reservaId: reserva.id, status: cobro.status });
  return { reserva, pago: null, mensaje: 'Pago en verificación: la reserva se confirma o se cancela en unos segundos' };
}

// Reconciliador de la saga: resuelve las reservas PENDIENTES preguntando a Pagos (idempotente).
// Si Pagos no tiene registro después de PLAZO_SIN_PAGO_SEG, el cobro nunca ocurrió: se cancela.
const PLAZO_SIN_PAGO_SEG = 30;

async function reconciliar() {
  const pendientes = await repo.pendientesDesde(3);
  for (const r of pendientes) {
    try {
      const p = await pagos.consultar(r.id);
      if (p.status === 200 && p.body.estado === 'APROBADO') {
        await repo.resolver(r.id, 'CONFIRMADA', { referencia: p.body.referencia });
        logger.info('saga: reserva confirmada por el reconciliador', { reservaId: r.id });
      } else if (p.status === 200 && p.body.estado === 'RECHAZADO') {
        await repo.resolver(r.id, 'CANCELADA', { motivo: p.body.motivo });
        logger.info('saga: reserva cancelada por el reconciliador (pago rechazado)', { reservaId: r.id });
      } else if (p.status === 404 && Date.now() - new Date(r.creada_en).getTime() > PLAZO_SIN_PAGO_SEG * 1000) {
        await repo.resolver(r.id, 'CANCELADA', { motivo: 'Sin registro de pago' });
        logger.info('saga: reserva cancelada por el reconciliador (sin pago)', { reservaId: r.id });
      }
    } catch (e) {
      logger.debug('reconciliador: Pagos no responde; se reintenta', { reservaId: r.id, error: e.message });
    }
  }
}

function iniciarReconciliador(ms = 5000) {
  const vuelta = async () => {
    await reconciliar().catch((e) => logger.warn('reconciliador falló', { error: e.message }));
    setTimeout(vuelta, ms).unref();
  };
  setTimeout(vuelta, ms).unref();
}

const listarReservas = (usuario) => repo.listarPorUsuario(usuario.id, usuario.rol);

async function obtenerReserva(usuario, id) {
  const r = await repo.obtener(id);
  if (!r) throw E.noEncontrado('Reserva no encontrada');
  if (![r.estudiante_id, r.docente_id].includes(usuario.id)) throw E.prohibido('No participás de esta reserva');
  // El pago vive en el servicio Pagos; acá queda la referencia.
  return { reserva: r, pago: r.referencia_pago ? { referencia: r.referencia_pago, monto: r.monto } : null };
}

// HU11: solo el docente dueño; CONFIRMADA -> DICTADA (UPDATE condicional, evita doble transición).
async function confirmarClaseDictada(docente, id) {
  const r = await repo.obtener(id);
  if (!r) throw E.noEncontrado('Reserva no encontrada');
  if (r.docente_id !== docente.id) throw E.prohibido('La reserva no es tuya');
  const actualizada = await repo.marcarDictada(id);
  if (!actualizada) throw E.conflicto('Solo se puede marcar como dictada una reserva CONFIRMADA');
  return actualizada;
}

const horariosOcupados = async (docenteId) => ({ docenteId, horarioIds: await repo.horariosOcupados(docenteId) });

// Varios docentes en una consulta; todos los pedidos aparecen en la respuesta (con [] si no tienen).
async function horariosOcupadosDe(docenteIds) {
  const ocupados = Object.fromEntries(docenteIds.map((id) => [id, []]));
  for (const { docente_id: d, horario_id: h } of await repo.horariosOcupadosDe(docenteIds)) ocupados[d].push(h);
  return { ocupados };
}

module.exports = { reservarClase, reconciliar, iniciarReconciliador, listarReservas, obtenerReserva, confirmarClaseDictada, horariosOcupados, horariosOcupadosDe };
