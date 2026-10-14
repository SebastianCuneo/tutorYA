// External Configuration Store: la config operativa vive en Redis (hash config:tutorya),
// compartida por todas las réplicas y modificable en caliente sin reiniciar.
// Precedencia: variable de entorno CFG_* > Redis > config/default.json.
// Los secretos (JWT_SECRET, DB_PASSWORD) NO pasan por acá: solo variables de entorno.
const fs = require('fs');
const path = require('path');
const logger = require('./logger');
const redis = require('./redis');
const { E } = require('./errores');

const HASH = 'config:tutorya';
const CANAL = 'config:cambios';
const SONDEO_MS = 10000;
const RUTA_DEFAULTS = process.env.CONFIG_DEFAULTS || path.join(__dirname, '../../config/default.json');

const entero = (min, max) => ({ tipo: 'entero', min, max });
const booleano = { tipo: 'booleano' };
const opciones = (...valores) => ({ tipo: 'opcion', valores });

// Tipo y rango de cada clave. Una clave que no está acá no se puede escribir (400).
const ESQUEMA = {
  'circuitBreaker.habilitado': booleano,
  'circuitBreaker.umbral': entero(1, 100),
  'circuitBreaker.ventanaMs': entero(1000, 600000),
  'circuitBreaker.esperaMs': entero(1000, 600000),
  'http.timeoutMs': entero(100, 30000),
  'cache.habilitado': booleano,
  'cache.catalogoTtlSeg': entero(1, 86400),
  'catalogo.fuente': opciones('vista', 'tablas'),
  'catalogo.refrescoSeg': entero(5, 3600),
  'salud.timeoutChequeoMs': entero(100, 10000),
  'log.nivel': opciones('debug', 'info', 'warn', 'error'),
};

// Devuelve el motivo si el valor no cumple el esquema, o null si es válido.
function invalido(clave, valor) {
  const r = ESQUEMA[clave];
  if (!r) return `clave desconocida: ${clave}`;
  if (r.tipo === 'booleano' && typeof valor !== 'boolean') return `${clave} debe ser booleano`;
  if (r.tipo === 'entero' && (!Number.isInteger(valor) || valor < r.min || valor > r.max)) {
    return `${clave} debe ser un entero entre ${r.min} y ${r.max}`;
  }
  if (r.tipo === 'opcion' && !r.valores.includes(valor)) return `${clave} debe ser uno de: ${r.valores.join(', ')}`;
  return null;
}

const defaults = JSON.parse(fs.readFileSync(RUTA_DEFAULTS, 'utf8'));
let remotos = {}; // última config conocida de Redis (se conserva si Redis se cae)
let ver = 0;
let aplicadaEn = null;

const nombreEnv = (clave) => `CFG_${clave.replace(/\./g, '_').toUpperCase()}`;

function desdeEnv(clave) {
  const crudo = process.env[nombreEnv(clave)];
  if (crudo === undefined) return undefined;
  try {
    return JSON.parse(crudo);
  } catch {
    return crudo;
  }
}

function get(clave) {
  const env = desdeEnv(clave);
  if (env !== undefined) return env;
  if (clave in remotos) return remotos[clave];
  return defaults[clave];
}

const version = () => ver;
const snapshot = () => Object.fromEntries(Object.keys(ESQUEMA).map((k) => [k, get(k)]));

function aplicar(hash) {
  const nuevos = {};
  for (const [campo, crudo] of Object.entries(hash)) {
    if (campo === 'version') continue;
    let valor;
    try {
      valor = JSON.parse(crudo);
    } catch {
      valor = crudo;
    }
    const motivo = invalido(campo, valor);
    if (motivo) logger.warn('valor de config ignorado', { motivo });
    else nuevos[campo] = valor;
  }
  remotos = nuevos;
  const anterior = ver;
  ver = Number(hash.version) || 0;
  aplicadaEn = new Date().toISOString();
  logger.setNivel(get('log.nivel'));
  if (ver !== anterior) logger.info('config cargada', { version: ver });
}

async function cargar() {
  try {
    aplicar(await redis.ejecutar((c) => c.hGetAll(HASH), 2000));
  } catch (e) {
    logger.warn('no se pudo leer la config de Redis; se mantiene la última conocida', { error: e.message, version: ver });
  }
}

// Siembra con HSETNX campo por campo: no hay carrera entre réplicas y las claves nuevas del default se agregan solas.
async function sembrar() {
  await redis.ejecutar(async (c) => {
    const m = c.multi();
    for (const [k, v] of Object.entries(defaults)) m.hSetNX(HASH, k, JSON.stringify(v));
    m.hSetNX(HASH, 'version', '1');
    await m.exec();
  }, 2000);
}

async function esperarRedis(ms) {
  const limite = Date.now() + ms;
  while (!redis.disponible() && Date.now() < limite) await new Promise((r) => setTimeout(r, 200));
  return redis.disponible();
}

// Arranque: nunca tira el proceso. Sin Redis se usa el default hasta que vuelva.
async function iniciar() {
  logger.setNivel(get('log.nivel'));
  if (await esperarRedis(5000)) {
    try {
      await sembrar();
    } catch (e) {
      logger.warn('no se pudo sembrar la config', { error: e.message });
    }
    await cargar();
  } else {
    logger.warn('Redis no disponible al arrancar; se usa config/default.json');
  }
  // Aviso inmediato por pub/sub...
  redis.suscribir(CANAL, (msg) => {
    if (Number(msg) !== ver) return cargar();
  });
  // ...y sondeo de la versión como respaldo (mensaje perdido, Redis reiniciado, etc.).
  setInterval(async () => {
    try {
      const v = await redis.ejecutar((c) => c.hGet(HASH, 'version'), 2000);
      if (v === null) await sembrar();
      if (Number(v) !== ver) await cargar();
    } catch {
      /* se mantiene la última config conocida */
    }
  }, SONDEO_MS).unref();
}

// Valida todo antes de escribir (todo o nada) y devuelve la versión nueva.
async function actualizar(cambios) {
  if (!cambios || typeof cambios !== 'object' || Array.isArray(cambios) || !Object.keys(cambios).length) {
    throw E.validacion('el body debe ser un objeto con al menos una clave');
  }
  for (const [k, v] of Object.entries(cambios)) {
    const motivo = invalido(k, v);
    if (motivo) throw E.validacion(motivo);
  }
  let nueva;
  try {
    const campos = Object.fromEntries(Object.entries(cambios).map(([k, v]) => [k, JSON.stringify(v)]));
    const res = await redis.ejecutar((c) => c.multi().hSet(HASH, campos).hIncrBy(HASH, 'version', 1).exec(), 2000);
    nueva = Number(res[1]);
    await redis.ejecutar((c) => c.publish(CANAL, String(nueva)), 2000);
  } catch (e) {
    logger.warn('no se pudo actualizar la config', { error: e.message });
    throw E.noDisponible('El almacén de configuración no está disponible');
  }
  await cargar();
  logger.info('config actualizada', { version: nueva, cambios });
  return nueva;
}

const info = () => ({ configVersion: ver, configAplicadaEn: aplicadaEn });

module.exports = { get, version, snapshot, actualizar, iniciar, info, ESQUEMA };
