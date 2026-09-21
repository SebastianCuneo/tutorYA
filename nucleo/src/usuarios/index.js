// Interfaz pública del componente Usuarios. Otros módulos solo pueden usar lo exportado aquí.
const servicio = require('./servicio');

module.exports = {
  // Interfaz: AutenticarUsuario (HU1, HU7)
  autenticarUsuario: servicio.login,
  registrarUsuario: servicio.registrarUsuario,
  // Interfaz: AutorizarMenor (HU2)
  autorizarMenor: servicio.autorizarMenor,
  // Interfaz: ConsultarEstadoEstudiante
  consultarEstadoEstudiante: servicio.consultarEstadoEstudiante,
  router: require('./rutas'),
};
