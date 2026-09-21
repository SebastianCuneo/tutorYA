// Único punto de contacto con el Núcleo: solo HTTP a endpoints internos.
const { getJson } = require('../../comun');

const NUCLEO_URL = process.env.NUCLEO_URL || 'http://nucleo:3000';

const consultarEstadoEstudiante = (id) => getJson(`${NUCLEO_URL}/internal/usuarios/${id}/estado`);
const consultarDisponibilidad = (docenteId, horarioId) =>
  getJson(`${NUCLEO_URL}/internal/docentes/${docenteId}/horarios/${horarioId}`);

module.exports = { consultarEstadoEstudiante, consultarDisponibilidad };
