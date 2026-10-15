const logger = require('./logger');

// Error controlado: lleva el status HTTP y un código de negocio.
class ErrorApi extends Error {
  constructor(status, codigo, mensaje) {
    super(mensaje);
    this.status = status;
    this.codigo = codigo;
  }
}

// Fábricas de errores según el status HTTP.
const E = {
  validacion: (m) => new ErrorApi(400, 'VALIDACION', m),
  noAutenticado: (m = 'Token ausente o inválido') => new ErrorApi(401, 'NO_AUTENTICADO', m),
  pagoRechazado: (m) => new ErrorApi(402, 'PAGO_RECHAZADO', m),
  prohibido: (m = 'No tenés permisos para esta operación') => new ErrorApi(403, 'PROHIBIDO', m),
  noEncontrado: (m = 'Recurso no encontrado') => new ErrorApi(404, 'NO_ENCONTRADO', m),
  conflicto: (m) => new ErrorApi(409, 'CONFLICTO', m),
  gone: (m) => new ErrorApi(410, 'GONE', m),
  noDisponible: (m) => new ErrorApi(503, 'NO_DISPONIBLE', m),
  // Circuit Breaker abierto: el cliente puede reintentar pasados retryAfterSeg segundos.
  circuitoAbierto: (m, retryAfterSeg) => Object.assign(new ErrorApi(503, 'CIRCUITO_ABIERTO', m), { retryAfterSeg }),
};

// Envuelve handlers async para que los errores lleguen al manejador (Express 4).
const asyncH = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

function rutaNoEncontrada(req, res, next) {
  next(E.noEncontrado(`Ruta no encontrada: ${req.method} ${req.originalUrl}`));
}

// eslint-disable-next-line no-unused-vars
// Último middleware: todo error sale como { error: { codigo, mensaje } }; lo inesperado es 500.
function manejadorErrores(err, req, res, next) {
  if (err.type === 'entity.parse.failed') {
    err = E.validacion('JSON inválido en el body');
  }
  if (!(err instanceof ErrorApi)) {
    logger.error('error no controlado', { error: err.message, stack: err.stack });
    err = new ErrorApi(500, 'ERROR_INTERNO', 'Error interno del servidor');
  }
  if (err.retryAfterSeg) res.setHeader('Retry-After', String(err.retryAfterSeg));
  res.status(err.status).json({ error: { codigo: err.codigo, mensaje: err.message } });
}

module.exports = { ErrorApi, E, asyncH, rutaNoEncontrada, manejadorErrores };
