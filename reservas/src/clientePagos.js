// Llamadas REST a Pagos, con su propio Circuit Breaker. La clave de idempotencia es la reserva.
const { getJson, postJson, CircuitBreaker } = require('../../comun');

const PAGOS_URL = process.env.PAGOS_URL || 'http://pagos:3000';
const circuito = new CircuitBreaker('pagos');

const cobrar = ({ reservaId, monto, tokenPago }) =>
  circuito.ejecutar(() => postJson(`${PAGOS_URL}/internal/pagos`, { reservaId, monto, tokenPago }));

const consultar = (reservaId) => circuito.ejecutar(() => getJson(`${PAGOS_URL}/internal/pagos/${reservaId}`));

module.exports = { cobrar, consultar };
