const { instancia } = require('./instancia');

function log(nivel, mensaje, extra = {}) {
  console.log(JSON.stringify({ ts: new Date().toISOString(), nivel, instancia, mensaje, ...extra }));
}

function middlewareLog(req, res, next) {
  const inicio = Date.now();
  res.on('finish', () => {
    log('info', 'request', {
      metodo: req.method,
      ruta: req.originalUrl,
      status: res.statusCode,
      ms: Date.now() - inicio,
    });
  });
  next();
}

module.exports = {
  info: (m, e) => log('info', m, e),
  warn: (m, e) => log('warn', m, e),
  error: (m, e) => log('error', m, e),
  middlewareLog,
};
