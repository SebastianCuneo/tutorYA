const { instancia } = require('./instancia');
const contexto = require('./contexto');

// Nivel mínimo a emitir; lo ajusta config.js en caliente (clave log.nivel).
const NIVELES = { debug: 10, info: 20, warn: 30, error: 40 };
let minimo = NIVELES.info;

function setNivel(nivel) {
  if (NIVELES[nivel]) minimo = NIVELES[nivel];
}

// Log estructurado en JSON, con la instancia que lo emitió y el X-Request-Id del request en curso.
function log(nivel, mensaje, extra = {}) {
  if (NIVELES[nivel] < minimo) return;
  const requestId = contexto.requestId();
  console.log(JSON.stringify({ ts: new Date().toISOString(), nivel, instancia, ...(requestId ? { requestId } : {}), mensaje, ...extra }));
}

// Registra método, ruta, status y duración de cada request.
function middlewareLog(req, res, next) {
  const inicio = Date.now();
  const requestId = contexto.requestId(); // 'finish' puede emitirse fuera del contexto del request
  res.on('finish', () => {
    log('info', 'request', {
      requestId,
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
