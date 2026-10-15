// Health Endpoint Monitoring.
// - Liveness (/api/salud): el proceso responde; no toca dependencias (lo define cada servicio).
// - Readiness (/salud/listo): chequea las dependencias. Solo la base es crítica; sin Redis la app
//   funciona (sin caché), así que Redis caído se informa pero no degrada la réplica.
// - Mientras la réplica está DEGRADADA, todo /api/* responde 503 y Nginx reintenta en otra réplica.
const express = require('express');
const db = require('./db');
const redis = require('./redis');
const config = require('./config');
const logger = require('./logger');
const { instancia } = require('./instancia');

const VIGENCIA_MS = 2000; // el resultado se reutiliza 2 s: no se consulta la base en cada request
let forzada = false; // falla inyectada por /internal/fallas
let ultimo = null;
let calculadoEn = 0;
let enCurso = null;
const pendientes = {}; // un chequeo colgado (p. ej. base congelada) no se re-dispara: no agota el pool

function conTimeout(promesa, ms) {
  let t;
  return Promise.race([
    promesa,
    new Promise((_, rej) => {
      t = setTimeout(() => rej(new Error(`timeout (${ms}ms)`)), ms);
    }),
  ]).finally(() => clearTimeout(t));
}

async function chequear(nombre, fn, critico) {
  const ms = config.get('salud.timeoutChequeoMs');
  const t0 = Date.now();
  if (!pendientes[nombre]) {
    pendientes[nombre] = Promise.resolve()
      .then(fn)
      .finally(() => delete pendientes[nombre]);
    pendientes[nombre].catch(() => {});
  }
  try {
    await conTimeout(pendientes[nombre], ms);
    return { ok: true, ms: Date.now() - t0, critico };
  } catch (e) {
    return { ok: false, ms: Date.now() - t0, critico, error: e.message };
  }
}

async function calcular() {
  const [dbR, redisR] = await Promise.all([
    chequear('db', () => db.query('SELECT 1'), true),
    chequear('redis', () => redis.ejecutar((c) => c.ping(), config.get('salud.timeoutChequeoMs')), false),
  ]);
  const chequeos = { db: dbR, redis: redisR };
  const estado = !forzada && Object.values(chequeos).every((c) => c.ok || !c.critico) ? 'OK' : 'DEGRADADO';
  if (ultimo && ultimo.estado !== estado) logger.warn(`readiness: ${ultimo.estado} → ${estado}`, { chequeos });
  return { estado, instancia, ...(forzada ? { fallaInyectada: true } : {}), chequeos };
}

// Readiness con una sola evaluación en curso a la vez. El middleware reutiliza el resultado
// durante 2 s (fresca=false); el endpoint /salud/listo siempre evalúa (fresca=true).
async function readiness(fresca = false) {
  if (!fresca && ultimo && Date.now() - calculadoEn < VIGENCIA_MS) return ultimo;
  if (!enCurso) {
    enCurso = calcular()
      .then((r) => {
        ultimo = r;
        calculadoEn = Date.now();
        return r;
      })
      .finally(() => {
        enCurso = null;
      });
  }
  return enCurso;
}

// GET .../salud/listo -> 200 OK | 503 DEGRADADO. extra(): campos adicionales (p. ej. circuitos).
function rutaListo(extra = () => ({})) {
  return async (req, res, next) => {
    try {
      const r = await readiness(true);
      res.status(r.estado === 'OK' ? 200 : 503).json({ ...r, ...config.info(), ...extra() });
    } catch (e) {
      next(e);
    }
  };
}

// Con la réplica DEGRADADA, /api/* (salvo los endpoints de salud) responde 503 REPLICA_DEGRADADA.
function middlewareListo(rutasSalud) {
  return async (req, res, next) => {
    if (!req.path.startsWith('/api/') || rutasSalud.includes(req.path)) return next();
    try {
      if ((await readiness()).estado === 'OK') return next();
    } catch (e) {
      return next(e);
    }
    res.status(503).json({ error: { codigo: 'REPLICA_DEGRADADA', mensaje: `La réplica ${instancia} no está lista` } });
  };
}

// Inyección de fallas (solo si FALLAS_HABILITADAS=true). Nginx bloquea /internal: solo desde el contenedor.
function routerFallas() {
  const router = express.Router();
  if (process.env.FALLAS_HABILITADAS !== 'true') return router;
  const cambiar = (valor) => (req, res) => {
    forzada = valor;
    calculadoEn = 0; // invalida la readiness cacheada
    logger.warn(`falla inyectada: réplica ${valor ? 'degradada' : 'restaurada'}`);
    res.json({ instancia, degradada: forzada });
  };
  router.post('/internal/fallas/degradar', cambiar(true));
  router.post('/internal/fallas/restaurar', cambiar(false));
  return router;
}

module.exports = { readiness, rutaListo, middlewareListo, routerFallas };
