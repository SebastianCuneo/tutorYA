const os = require('os');

// Identificador de la réplica: en Docker el hostname es el id corto del contenedor.
const instancia = os.hostname();

function middlewareInstancia(req, res, next) {
  res.setHeader('X-Instancia', instancia);
  next();
}

module.exports = { instancia, middlewareInstancia };
