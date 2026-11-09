// Microservicio Verificación (UT5): solicitudes de verificación de docentes (HU10).
// Base propia: db-verificacion. Consume docente.registrado y publica docente.verificado (outbox).
const { arrancar, eventos } = require('../../comun');
const rutas = require('./rutas');
const servicio = require('./servicio');

eventos.suscribir('verificacion.eventos', ['docente.registrado'], servicio.alRegistrarseDocente);

arrancar({ nombre: 'verificacion', routers: [rutas], usaEventos: true, publicaEventos: true });
