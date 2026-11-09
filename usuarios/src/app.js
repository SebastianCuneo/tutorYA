// Microservicio Usuarios (UT5): registro, login (JWT), autorización de menores y el servicio SOAP
// ConsultarEstadoEstudiante. Base propia: db-usuarios. Publica docente.registrado (outbox -> RabbitMQ).
const { arrancar } = require('../../comun');
const rutas = require('./rutas');
const soap = require('./soap/servidor');
const admin = require('./admin');

arrancar({
  nombre: 'usuarios',
  routers: [rutas, admin],
  extender: soap.montar,
  publicaEventos: true,
});
