module.exports = {
  ...require('./instancia'),
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
