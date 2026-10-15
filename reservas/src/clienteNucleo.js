// Único punto de contacto con el Núcleo: solo HTTP a endpoints internos.
// Ambas llamadas pasan por el mismo circuito: si el Núcleo viene fallando, se corta rápido.
const { getJson, CircuitBreaker } = require('../../comun');

const NUCLEO_URL = process.env.NUCLEO_URL || 'http://nucleo:3000';
const circuito = new CircuitBreaker('nucleo');

const consultarEstadoEstudiante = (id) => circuito.ejecutar(() => getJson(`${NUCLEO_URL}/internal/usuarios/${id}/estado`));
const consultarDisponibilidad = (docenteId, horarioId) =>
  circuito.ejecutar(() => getJson(`${NUCLEO_URL}/internal/docentes/${docenteId}/horarios/${horarioId}`));

module.exports = { consultarEstadoEstudiante, consultarDisponibilidad };
