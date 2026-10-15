// Cache-Aside del catálogo de docentes (HU3) en Redis.
// Lectura: se busca en la caché; si no está, se arma desde la base y se guarda con TTL.
// Escritura: los cambios del catálogo borran catalogo:* (la próxima lectura repuebla).
const { redis, config, logger } = require('../../../comun');

const PREFIJO = 'catalogo:';
// Métricas en memoria, por réplica (estado operativo, no de negocio).
const contadores = { hits: 0, misses: 0, bypass: 0 };

const clave = (materia) => PREFIJO + (materia ? materia.toLowerCase() : '_todas');

// Devuelve { datos, cache: 'HIT'|'MISS'|'BYPASS' }. Sin caché (deshabilitada o Redis caído) => BYPASS.
async function obtener(materia, construir) {
  const bypass = async () => {
    contadores.bypass++;
    return { datos: await construir(), cache: 'BYPASS' };
  };
  if (!config.get('cache.habilitado') || !redis.disponible()) return bypass();

  const k = clave(materia);
  let crudo;
  try {
    crudo = await redis.ejecutar((c) => c.get(k));
  } catch (e) {
    logger.debug('caché no disponible, bypass', { error: e.message });
    return bypass();
  }
  if (crudo !== null) {
    contadores.hits++;
    return { datos: JSON.parse(crudo), cache: 'HIT' };
  }
  const datos = await construir();
  await redis.intentar((c) => c.set(k, JSON.stringify(datos), { EX: config.get('cache.catalogoTtlSeg') }));
  contadores.misses++;
  return { datos, cache: 'MISS' };
}

async function invalidar(motivo) {
  const borradas = await redis.borrarPorPatron(`${PREFIJO}*`);
  logger.info('caché del catálogo invalidada', { motivo, borradas });
}

function metricas() {
  const { hits, misses, bypass } = contadores;
  const consultas = hits + misses;
  return { hits, misses, bypass, tasaAciertos: consultas ? Number((hits / consultas).toFixed(4)) : null };
}

module.exports = { obtener, invalidar, metricas };
