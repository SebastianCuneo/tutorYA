const crypto = require('crypto');
const { E } = require('../../comun');
const repo = require('./repositorio');

// Pasarela de pago simulada (antes vivía dentro de Reservas). tokenPago:
//   'RECHAZAR' -> rechazado · 'LENTO' -> tarda 5 s (para provocar el timeout de Reservas) · otro -> aprobado.
const espera = (ms) => new Promise((r) => setTimeout(r, ms));

async function cobrar(body = {}) {
  const reservaId = Number(body.reservaId);
  const monto = Number(body.monto);
  if (!Number.isInteger(reservaId) || !(monto >= 0)) throw E.validacion('reservaId y monto son obligatorios');
  if (typeof body.tokenPago !== 'string' || !body.tokenPago) throw E.validacion('tokenPago es obligatorio');

  // Reintento del mismo cobro (misma reserva): no se cobra dos veces.
  const previo = await repo.obtenerPorReserva(reservaId);
  if (previo) return { ...previo, repetido: true };

  await espera(body.tokenPago === 'LENTO' ? 5000 : 300); // latencia del procesador
  const aprobado = body.tokenPago !== 'RECHAZAR';
  const nuevo = await repo.insertarSiNoExiste({
    reservaId,
    monto,
    estado: aprobado ? 'APROBADO' : 'RECHAZADO',
    referencia: aprobado ? `SIM-${crypto.randomUUID()}` : null,
    motivo: aprobado ? null : 'Pago rechazado por el procesador',
  });
  return nuevo || { ...(await repo.obtenerPorReserva(reservaId)), repetido: true };
}

async function obtener(reservaId) {
  const p = await repo.obtenerPorReserva(reservaId);
  if (!p) throw E.noEncontrado('No hay pago para esa reserva');
  return p;
}

async function reembolsar(reservaId) {
  const p = await repo.reembolsar(reservaId);
  return p || obtener(reservaId);
}

// La usa el reconciliador de Reservas ANTES de cancelar una reserva sin registro de pago.
// Devuelve ANULADO (desde ahora ningún cobro de esa reserva se aprueba) o el pago que ya existía
// (el cobro llegó antes que la anulación: Reservas resuelve según ese resultado).
async function anular(reservaId) {
  return (await repo.anular(reservaId)) || { ...(await repo.obtenerPorReserva(reservaId)), repetido: true };
}

module.exports = { cobrar, obtener, reembolsar, anular };
