module.exports = {
  ...require('./instancia'),
  ...require('./errores'),
  ...require('./http'),
  auth: require('./auth'),
  db: require('./db'),
  logger: require('./logger'),
};
