const { db } = require('../../../comun');

// ON CONFLICT DO NOTHING: hace idempotente el manejo del evento.
async function crearPerfil(usuarioId, nombre) {
  await db.query(
    `INSERT INTO docentes.perfiles (usuario_id, nombre, estado)
     VALUES ($1, $2, 'PENDIENTE_VERIFICACION') ON CONFLICT (usuario_id) DO NOTHING`,
    [usuarioId, nombre]
  );
}

async function actualizarEstado(usuarioId, estado) {
  const { rowCount } = await db.query('UPDATE docentes.perfiles SET estado = $2 WHERE usuario_id = $1', [
    usuarioId,
    estado,
  ]);
  return rowCount;
}

async function obtenerPerfil(usuarioId) {
  const { rows } = await db.query('SELECT usuario_id, nombre, estado FROM docentes.perfiles WHERE usuario_id = $1', [
    usuarioId,
  ]);
  return rows[0] || null;
}

async function listarAprobados(materia) {
  const { rows } = await db.query(
    `SELECT p.usuario_id, p.nombre FROM docentes.perfiles p
     WHERE p.estado = 'APROBADO'
       AND ($1::text IS NULL OR EXISTS (
             SELECT 1 FROM docentes.materias m
             WHERE m.docente_id = p.usuario_id AND lower(m.materia) = lower($1)))
     ORDER BY p.usuario_id`,
    [materia]
  );
  return rows;
}

async function materiasDe(docenteId) {
  const { rows } = await db.query('SELECT materia FROM docentes.materias WHERE docente_id = $1 ORDER BY materia', [
    docenteId,
  ]);
  return rows.map((r) => r.materia);
}

async function reemplazarMaterias(docenteId, materias) {
  const cliente = await db.pool.connect();
  try {
    await cliente.query('BEGIN');
    await cliente.query('DELETE FROM docentes.materias WHERE docente_id = $1', [docenteId]);
    for (const m of materias) {
      await cliente.query('INSERT INTO docentes.materias (docente_id, materia) VALUES ($1, $2)', [docenteId, m]);
    }
    await cliente.query('COMMIT');
  } catch (e) {
    await cliente.query('ROLLBACK');
    throw e;
  } finally {
    cliente.release();
  }
}

async function insertarHorario(docenteId, { inicio, fin, precio }) {
  const { rows } = await db.query(
    `INSERT INTO docentes.horarios (docente_id, inicio, fin, precio) VALUES ($1,$2,$3,$4)
     RETURNING id, inicio, fin, precio`,
    [docenteId, inicio, fin, precio]
  );
  return rows[0];
}

// soloFuturos: para la búsqueda no se ofrecen horarios que ya pasaron.
async function horariosDe(docenteId, soloFuturos) {
  const { rows } = await db.query(
    `SELECT id, inicio, fin, precio FROM docentes.horarios
     WHERE docente_id = $1 AND ($2::boolean = false OR inicio > now()) ORDER BY inicio`,
    [docenteId, soloFuturos]
  );
  return rows;
}

async function obtenerHorario(docenteId, horarioId) {
  const { rows } = await db.query(
    'SELECT id, inicio, fin, precio FROM docentes.horarios WHERE docente_id = $1 AND id = $2',
    [docenteId, horarioId]
  );
  return rows[0] || null;
}

// Materialized View: una consulta trae docentes APROBADOS con materias y horarios ya agregados.
// El filtro usa el índice GIN sobre materias (guardadas en minúsculas).
async function buscarEnCatalogo(materia) {
  const { rows } = await db.query(
    `SELECT docente_id, nombre, materias_nombres, horarios FROM docentes.catalogo
     WHERE $1::text IS NULL OR materias @> ARRAY[lower($1)]
     ORDER BY docente_id`,
    [materia]
  );
  return rows;
}

// Clave del advisory lock: una sola réplica refresca a la vez.
const LOCK_CATALOGO = 4242001;

// REFRESH ... CONCURRENTLY no bloquea las lecturas (requiere el índice único).
// esperar=true: espera el lock (refresco por evento: no se puede perder el cambio recién commiteado).
// esperar=false: pg_try_advisory_lock; si otra réplica refresca, devuelve false sin hacer nada.
async function refrescarCatalogo({ esperar }) {
  const cliente = await db.pool.connect();
  let roto = null;
  try {
    if (esperar) {
      await cliente.query('SELECT pg_advisory_lock($1)', [LOCK_CATALOGO]);
    } else {
      const { rows } = await cliente.query('SELECT pg_try_advisory_lock($1) AS ok', [LOCK_CATALOGO]);
      if (!rows[0].ok) return false;
    }
    try {
      await cliente.query('REFRESH MATERIALIZED VIEW CONCURRENTLY docentes.catalogo');
    } finally {
      await cliente.query('SELECT pg_advisory_unlock($1)', [LOCK_CATALOGO]);
    }
    return true;
  } catch (e) {
    roto = e; // la conexión se descarta: no vuelve al pool con un lock tomado
    throw e;
  } finally {
    cliente.release(roto || undefined);
  }
}

module.exports = {
  buscarEnCatalogo, refrescarCatalogo,
  crearPerfil, actualizarEstado, obtenerPerfil, listarAprobados, materiasDe,
  reemplazarMaterias, insertarHorario, horariosDe, obtenerHorario,
};
