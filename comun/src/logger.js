const { instancia } = require('./instancia');

// Nivel mínimo a emitir; lo ajusta config.js en caliente (clave log.nivel).
const NIVELES = { debug: 10, info: 20, warn: 30, error: 40 };
let minimo = NIVELES.info;

function setNivel(nivel) {
  if (NIVELES[nivel]) minimo = NIVELES[nivel];
}

// Log estructurado en JSON, con la instancia que lo emitió.
function log(nivel, mensaje, extra = {}) {
  if (NIVELES[nivel] < minimo) return;
  console.log(JSON.stringify({ ts: new Date().toISOString(), nivel, instancia, mensaje, ...extra }));
}

// Registra método, ruta, status y duración de cada request.
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
  debug: (m, e) => log('debug', m, e),
  info: (m, e) => log('info', m, e),
  warn: (m, e) => log('warn', m, e),
  error: (m, e) => log('error', m, e),
  setNivel,
  middlewareLog,
};
