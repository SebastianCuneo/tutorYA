const { AsyncLocalStorage } = require('async_hooks');
const crypto = require('crypto');

// Contexto por request (AsyncLocalStorage): el X-Request-Id que asignó Nginx viaja con la
// ejecución asíncrona del request sin pasarlo a mano. Lo usan el logger y getJson.
const als = new AsyncLocalStorage();

const requestId = () => als.getStore()?.requestId;

// Toma X-Request-Id (lo pone Nginx o el servicio que llama) o genera uno si falta.
function middlewareRequestId(req, res, next) {
  const id = req.get('X-Request-Id') || crypto.randomUUID().replace(/-/g, '');
  req.requestId = id;
  als.run({ requestId: id }, next);
}

module.exports = { requestId, middlewareRequestId };
