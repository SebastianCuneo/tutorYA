// Microservicio Pagos (UT5): cobra las reservas con una pasarela simulada. Base propia: db-pagos.
// Idempotente por reserva: Reservas puede reintentar sin cobrar dos veces.
const { arrancar } = require('../../comun');
const rutas = require('./rutas');

arrancar({ nombre: 'pagos', routers: [rutas] });
