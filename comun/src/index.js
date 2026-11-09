module.exports = {
  ...require('./instancia'),
  ...require('./contexto'),
  ...require('./errores'),
  ...require('./http'),
  ...require('./circuitBreaker'),
  auth: require('./auth'),
  db: require('./db'),
  logger: require('./logger'),
  redis: require('./redis'),
  config: require('./config'),
  salud: require('./salud'),
  eventos: require('./eventos'),
  ...require('./servicio'),
  // UT5: biblioteca SOAP (servidor en Usuarios, cliente en Reservas). Se carga solo si se usa.
  get soap() {
    return require('soap');
  },
};
