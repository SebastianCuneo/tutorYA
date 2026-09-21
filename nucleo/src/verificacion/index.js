// Interfaz pública del componente Verificación.
const servicio = require('./servicio');
const eventos = require('../eventos');

// Evento que consume este módulo
eventos.on('docente.registrado', servicio.alRegistrarseDocente);

module.exports = {
  // Interfaz: VerificarDocente (HU10)
  listarSolicitudes: servicio.listarSolicitudes,
  agendarLlamada: servicio.agendarLlamada,
  resolverSolicitud: servicio.resolverSolicitud,
  router: require('./rutas'),
};
