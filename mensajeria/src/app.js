// Microservicio Mensajería (UT5): conversaciones entre estudiantes y docentes (HU4, HU9).
// Base propia: db-mensajeria. Consume docente.verificado para saber a qué docentes se puede escribir.
const { arrancar, eventos } = require('../../comun');
const rutas = require('./rutas');
const servicio = require('./servicio');

eventos.suscribir('mensajeria.verificaciones', ['docente.verificado'], servicio.alVerificarseDocente);

arrancar({ nombre: 'mensajeria', routers: [rutas], usaEventos: true });
