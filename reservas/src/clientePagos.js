// Llamadas REST a Pagos, con su propio Circuit Breaker. La clave de idempotencia es la reserva.
const dns = require('dns').promises;
const { getJson, postJson, config, CircuitBreaker } = require('../../comun');

const PAGOS_URL = process.env.PAGOS_URL || 'http://pagos:3000';
const HOST_PAGOS = new URL(PAGOS_URL).hostname;
const circuito = new CircuitBreaker('pagos');

// Antes de cobrar se resuelve el nombre de Pagos por separado. En la red interna de Docker
// (internal: true), el DNS de un contenedor detenido no responde NXDOMAIN al toque: tarda ~5 s y da
// EAI_AGAIN, y el timeout del fetch (2 s) cortaba antes. Ese corte se veía como "no se sabe si se
// cobró" y la reserva quedaba PENDIENTE bloqueando el horario. Si el nombre no resuelve, el pedido
// nunca salió: el error lleva cause.code de DNS y la saga compensa en el acto.
async function resolverPagos(ms) {
  let t;
  try {
    await Promise.race([
      dns.lookup(HOST_PAGOS),
      new Promise((_, rej) => {
        t = setTimeout(() => rej(Object.assign(new Error(`DNS sin respuesta en ${ms} ms`), { code: 'EAI_AGAIN' })), ms);
      }),
    ]);
  } catch (e) {
    throw new Error(`no se pudo resolver ${HOST_PAGOS}: ${e.message}`, { cause: { code: e.code || 'EAI_AGAIN' } });
  } finally {
    clearTimeout(t);
  }
}

const cobrar = ({ reservaId, monto, tokenPago }) =>
  circuito.ejecutar(async () => {
    await resolverPagos(config.get('http.timeoutMs'));
    return postJson(`${PAGOS_URL}/internal/pagos`, { reservaId, monto, tokenPago });
  });

const consultar = (reservaId) => circuito.ejecutar(() => getJson(`${PAGOS_URL}/internal/pagos/${reservaId}`));

// Fence: antes de cancelar una reserva sin pago, se anula el cobro en Pagos (ver reconciliar).
const anular = (reservaId) => circuito.ejecutar(() => postJson(`${PAGOS_URL}/internal/pagos/${reservaId}/anulacion`, {}));

// Compensación de un pago aprobado cuya reserva ya no se puede confirmar.
const reembolsar = (reservaId) => circuito.ejecutar(() => postJson(`${PAGOS_URL}/internal/pagos/${reservaId}/reembolso`, {}));

module.exports = { cobrar, consultar, anular, reembolsar };
