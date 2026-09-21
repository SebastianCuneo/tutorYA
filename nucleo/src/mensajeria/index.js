// Interfaz pública del componente Mensajería.
const servicio = require('./servicio');

module.exports = {
  // Interfaz: EnviarMensaje (HU4)
  enviarMensaje: servicio.enviarMensaje,
  // Interfaz: ResponderMensaje (HU9)
  responderMensaje: servicio.responderMensaje,
  listarConversaciones: servicio.listarConversaciones,
  listarMensajes: servicio.listarMensajes,
  router: require('./rutas'),
};
