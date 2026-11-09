// Microservicio Reservas (UT5): orquesta la saga de reserva y pago (HU5, HU6) y confirma clases
// dictadas (HU11). Base propia: db-reservas. Consume Usuarios por SOAP, Docentes y Pagos por REST,
// y publica reserva.confirmada / reserva.cancelada (outbox -> RabbitMQ).
const { arrancar } = require('../../comun');
const rutas = require('./rutas');
const servicio = require('./servicio');

arrancar({
  nombre: 'reservas',
  routers: [rutas],
  publicaEventos: true,
  alArrancar: async () => servicio.iniciarReconciliador(),
});
