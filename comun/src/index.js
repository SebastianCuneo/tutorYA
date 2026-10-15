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
};
