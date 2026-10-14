const { createClient } = require('redis');
const logger = require('./logger');

const URL = process.env.REDIS_URL || 'redis://redis:6379';
// Tope por operación: si Redis no responde, la caché se saltea en vez de colgar el request.
const TIMEOUT_OP_MS = Number(process.env.REDIS_TIMEOUT_MS || 500);

// disableOfflineQueue: sin conexión, los comandos fallan al instante (no se encolan).
function crear(nombre) {
  const c = createClient({
    url: URL,
    disableOfflineQueue: true,
    socket: { connectTimeout: 2000, reconnectStrategy: (n) => Math.min(n * 200, 3000) },
  });
  let caido = false;
  // Solo se loguea la transición, no cada reintento.
  c.on('error', (e) => {
    if (!caido) logger.warn(`redis (${nombre}) no disponible`, { error: e.message });
    caido = true;
  });
  c.on('ready', () => {
    if (caido) logger.info(`redis (${nombre}) reconectado`);
    caido = false;
  });
  c.connect().catch(() => {});
  return c;
}

let principal = null;
const cliente = () => principal || (principal = crear('principal'));

const disponible = () => cliente().isReady;

function conTimeout(promesa, ms = TIMEOUT_OP_MS) {
  let t;
  return Promise.race([
    promesa,
    new Promise((_, rej) => {
      t = setTimeout(() => rej(new Error(`timeout de redis (${ms}ms)`)), ms);
    }),
  ]).finally(() => clearTimeout(t));
}

// Ejecuta fn(cliente) con timeout. Lanza si Redis no está disponible.
async function ejecutar(fn, ms) {
  if (!disponible()) throw new Error('redis no disponible');
  return conTimeout(fn(cliente()), ms);
}

// Versión tolerante: devuelve null en vez de lanzar (para la caché).
async function intentar(fn) {
  try {
    return await ejecutar(fn);
  } catch (e) {
    logger.debug('operación de redis omitida', { error: e.message });
    return null;
  }
}

// Borra las claves que matchean el patrón con SCAN (nunca KEYS, que bloquea Redis).
async function borrarPorPatron(patron) {
  return intentar(async (c) => {
    let borradas = 0;
    for await (const clave of c.scanIterator({ MATCH: patron, COUNT: 200 })) {
      borradas += await c.del(clave);
    }
    return borradas;
  });
}

// Suscripción en una conexión aparte (una conexión en modo subscriber no admite otros comandos).
// node-redis re-suscribe solo al reconectar.
function suscribir(canal, fn) {
  const sub = cliente().duplicate();
  sub.on('error', () => {});
  sub
    .connect()
    .then(() => sub.subscribe(canal, (msg) => Promise.resolve(fn(msg)).catch((e) => logger.warn(`error procesando ${canal}`, { error: e.message }))))
    .then(() => logger.info(`suscripto a ${canal}`))
    .catch((e) => logger.warn(`no se pudo suscribir a ${canal}`, { error: e.message }));
  return sub;
}

module.exports = { cliente, disponible, ejecutar, intentar, borrarPorPatron, suscribir, conTimeout };
