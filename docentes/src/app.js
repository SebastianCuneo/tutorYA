// Microservicio Docentes (UT5): perfil docente, búsqueda del catálogo (Cache-Aside + Materialized View)
// y ConsultarDisponibilidad. Base propia: db-docentes. Consume eventos de Usuarios, Verificación y Reservas.
const { arrancar, eventos } = require('../../comun');
const rutas = require('./rutas');
const admin = require('./admin');
const servicio = require('./servicio');

// Cola durable propia: si Docentes está caído, los eventos esperan acá y se procesan al volver.
eventos.suscribir('docentes.eventos', ['docente.registrado'], servicio.alRegistrarse);
eventos.suscribir('docentes.verificaciones', ['docente.verificado'], servicio.alVerificarse);
eventos.suscribir('docentes.reservas', ['reserva.confirmada', 'reserva.cancelada'], servicio.alEventoReservas);

arrancar({
  nombre: 'docentes',
  routers: [rutas, admin],
  usaEventos: true,
  alArrancar: async () => servicio.iniciarRefrescoPeriodico(),
});
