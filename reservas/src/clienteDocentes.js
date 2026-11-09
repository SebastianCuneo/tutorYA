// Llamada REST (JSON) a Docentes: ConsultarDisponibilidad, con su propio Circuit Breaker.
const { getJson, CircuitBreaker } = require('../../comun');

const DOCENTES_URL = process.env.DOCENTES_URL || 'http://docentes:3000';
const circuito = new CircuitBreaker('docentes');

const consultarDisponibilidad = (docenteId, horarioId) =>
  circuito.ejecutar(() => getJson(`${DOCENTES_URL}/internal/docentes/${docenteId}/horarios/${horarioId}`));

module.exports = { consultarDisponibilidad };
