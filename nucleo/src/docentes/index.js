// Interfaz pública del componente Docentes.
const servicio = require('./servicio');
const eventos = require('../eventos');

// Eventos que consume este módulo
eventos.on('docente.registrado', servicio.alRegistrarse);
eventos.on('docente.verificado', servicio.alVerificarse);

module.exports = {
  // Interfaz: BuscarDocentes (HU3)
  buscarDocentes: servicio.buscarDocentes,
  // Interfaz: GestionarPerfilDocente (HU8)
  obtenerPerfil: servicio.obtenerPerfilCompleto,
  actualizarMaterias: servicio.actualizarMaterias,
  agregarHorario: servicio.agregarHorario,
  // Interfaz: GestionarPerfilDocente (HU8) — consulta del estado del perfil, usada por Mensajería
  obtenerEstadoDocente: servicio.obtenerEstadoDocente,
  // Interfaz: ConsultarDisponibilidad
  consultarDisponibilidad: servicio.consultarDisponibilidad,
  router: require('./rutas'),
};
