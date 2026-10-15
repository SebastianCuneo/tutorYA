// Interfaz pública del componente Docentes.
const servicio = require('./servicio');
const eventos = require('../eventos');
const { redis } = require('../../../comun');

// Eventos que consume este módulo
eventos.on('docente.registrado', servicio.alRegistrarse);
eventos.on('docente.verificado', servicio.alVerificarse);
// Evento entre servicios (Redis pub/sub): Reservas avisa; Docentes invalida su propia caché.
redis.suscribir('reservas:eventos', servicio.alEventoReservas);
// Materialized View: refresco periódico del catálogo.
servicio.iniciarRefrescoPeriodico();

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
  // Métricas de la caché del catálogo (Cache-Aside)
  metricasCache: servicio.metricasCache,
  router: require('./rutas'),
};
