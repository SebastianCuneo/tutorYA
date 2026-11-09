const { E, getJson, logger, config, CircuitBreaker, CircuitoAbiertoError } = require('../../comun');
const repo = require('./repositorio');
const cache = require('./cache');

const RESERVAS_URL = process.env.RESERVAS_URL || 'http://reservas:3000';
const circuitoReservas = new CircuitBreaker('reservas');

// Pide a Reservas (por HTTP, a través del circuito) los horarios ocupados de TODOS los docentes
// de la búsqueda en una sola llamada. Devuelve { docenteId: Set(horarioIds) }, o null si Reservas
// no responde o el circuito está abierto => degradación elegante.
async function horariosOcupados(docenteIds) {
  if (!docenteIds.length) return {};
  try {
    const { status, body } = await circuitoReservas.ejecutar(() =>
      getJson(`${RESERVAS_URL}/internal/reservas/horarios-ocupados?docenteIds=${docenteIds.join(',')}`)
    );
    if (status !== 200) return null;
    return Object.fromEntries(Object.entries(body.ocupados).map(([id, hs]) => [id, new Set(hs)]));
  } catch (e) {
    if (e instanceof CircuitoAbiertoError) logger.debug('circuito reservas abierto, degradación elegante');
    else logger.warn('Reservas no responde, degradación elegante', { error: e.message });
    return null;
  }
}

// HU3: docentes APROBADOS con sus horarios futuros libres (los ocupados los informa Reservas).
// Cache-Aside: devuelve { datos, cache } con cache = HIT | MISS | BYPASS.
async function buscarDocentes(materia) {
  const filtro = typeof materia === 'string' && materia.trim() ? materia.trim() : null;
  return cache.obtener(filtro, () => armarCatalogo(filtro));
}

// catalogo.fuente = "vista": una consulta a la vista materializada docentes.catalogo.
// catalogo.fuente = "tablas": camino de la UT3 (1 consulta + 2 por docente), para comparar.
async function armarCatalogo(filtro) {
  const docentes = config.get('catalogo.fuente') === 'tablas' ? await desdeTablas(filtro) : await desdeVista(filtro);
  const ocupados = await horariosOcupados(docentes.map((d) => d.id));
  return docentes.map((d) => {
    const suyos = ocupados && ocupados[d.id];
    return {
      id: d.id,
      nombre: d.nombre,
      materias: d.materias,
      horarios: suyos ? d.horarios.filter((h) => !suyos.has(h.id)) : d.horarios,
      disponibilidadVerificada: ocupados !== null,
    };
  });
}

async function desdeTablas(filtro) {
  const docentes = await repo.listarAprobados(filtro);
  return Promise.all(
    docentes.map(async (d) => {
      const [materias, horarios] = await Promise.all([repo.materiasDe(d.usuario_id), repo.horariosDe(d.usuario_id, true)]);
      return { id: d.usuario_id, nombre: d.nombre, materias, horarios };
    })
  );
}

// La vista guarda los horarios como jsonb: se normalizan las fechas al mismo formato que el camino
// por tablas y se descartan los que pasaron desde el último refresco.
async function desdeVista(filtro) {
  const ahora = Date.now();
  const filas = await repo.buscarEnCatalogo(filtro);
  return filas.map((f) => ({
    id: f.docente_id,
    nombre: f.nombre,
    materias: f.materias_nombres,
    horarios: f.horarios
      .map((h) => ({ id: h.id, inicio: new Date(h.inicio), fin: new Date(h.fin), precio: Number(h.precio) }))
      .filter((h) => h.inicio.getTime() > ahora),
  }));
}

async function obtenerPerfilCompleto(docenteId) {
  const perfil = await repo.obtenerPerfil(docenteId);
  if (!perfil) throw E.noEncontrado('Perfil de docente no encontrado');
  return {
    id: perfil.usuario_id,
    nombre: perfil.nombre,
    estado: perfil.estado,
    materias: await repo.materiasDe(docenteId),
    horarios: await repo.horariosDe(docenteId, false),
  };
}

// HU8: reemplaza la lista de materias del docente (sin duplicados).
async function actualizarMaterias(docenteId, body = {}) {
  const { materias } = body;
  if (!Array.isArray(materias) || materias.length > 30 || materias.some((m) => typeof m !== 'string' || !m.trim())) {
    throw E.validacion('materias debe ser un arreglo de textos no vacíos');
  }
  const limpias = [...new Set(materias.map((m) => m.trim()))];
  await obtenerPerfilCompleto(docenteId);
  await repo.reemplazarMaterias(docenteId, limpias);
  await alCambiarCatalogo('materias');
  return { materias: limpias };
}

// HU8: alta de un horario con precio; valida fechas ISO y fin > inicio.
async function agregarHorario(docenteId, body = {}) {
  const inicio = new Date(body.inicio);
  const fin = new Date(body.fin);
  const precio = Number(body.precio);
  if (typeof body.inicio !== 'string' || Number.isNaN(inicio.getTime())) throw E.validacion('inicio inválido (ISO 8601)');
  if (typeof body.fin !== 'string' || Number.isNaN(fin.getTime())) throw E.validacion('fin inválido (ISO 8601)');
  if (fin <= inicio) throw E.validacion('fin debe ser posterior a inicio');
  if (typeof body.precio === 'boolean' || !Number.isFinite(precio) || precio < 0) throw E.validacion('precio inválido');
  await obtenerPerfilCompleto(docenteId);
  const horario = await repo.insertarHorario(docenteId, { inicio: inicio.toISOString(), fin: fin.toISOString(), precio });
  await alCambiarCatalogo('horario');
  return horario;
}

// Usada por Reservas (HTTP interno): ¿el docente está aprobado y el horario existe y es suyo? Devuelve el precio.
async function consultarDisponibilidad(docenteId, horarioId) {
  const perfil = await repo.obtenerPerfil(docenteId);
  const horario = perfil && (await repo.obtenerHorario(docenteId, horarioId));
  if (!horario) return null;
  return { docenteAprobado: perfil.estado === 'APROBADO', horario };
}

// Usada por Mensajería (a través de la interfaz pública de Docentes).
async function obtenerEstadoDocente(docenteId) {
  const perfil = await repo.obtenerPerfil(docenteId);
  return perfil ? perfil.estado : null;
}

// Docentes es la fuente de verdad del estado del perfil.
async function alVerificarse({ datos: { docenteId, resultado } }) {
  if (!['APROBADO', 'RECHAZADO'].includes(resultado)) return;
  // docente.registrado y docente.verificado llegan por colas distintas, sin orden entre sí (p. ej. si
  // Docentes estuvo caído, al volver consume las dos a la vez). Si el perfil todavía no existe, el
  // UPDATE no tocaba ninguna fila, el evento se confirmaba igual y el docente quedaba
  // PENDIENTE_VERIFICACION para siempre. Se lanza: el evento vuelve a la cola y se reintenta.
  const n = await repo.actualizarEstado(docenteId, resultado);
  if (n === 0) throw new Error(`el perfil ${docenteId} todavía no existe (docente.registrado sin procesar)`);
  await alCambiarCatalogo('verificacion');
}

// Cualquier cambio del catálogo: PRIMERO refresca la vista, DESPUÉS invalida la caché
// (al revés, una lectura entre medio volvería a cachear la vista vieja).
// No se lanza: la escritura ya se hizo; la vista se pone al día en el próximo refresco periódico.
async function alCambiarCatalogo(motivo) {
  try {
    await repo.refrescarCatalogo({ esperar: true });
  } catch (e) {
    logger.warn('no se pudo refrescar el catálogo', { motivo, error: e.message });
  }
  await cache.invalidar(motivo);
}

// Refresco periódico (catalogo.refrescoSeg, leído en cada vuelta): si otra réplica ya está
// refrescando (pg_try_advisory_lock ocupado), se saltea esta vuelta.
function iniciarRefrescoPeriodico() {
  const vuelta = async () => {
    try {
      const hecho = await repo.refrescarCatalogo({ esperar: false });
      logger.debug(hecho ? 'catálogo refrescado (periódico)' : 'refresco periódico salteado: otra réplica refresca');
    } catch (e) {
      logger.warn('refresco periódico del catálogo falló', { error: e.message });
    }
    setTimeout(vuelta, config.get('catalogo.refrescoSeg') * 1000).unref();
  };
  setTimeout(vuelta, config.get('catalogo.refrescoSeg') * 1000).unref();
}

// UT5: Reservas publica reserva.confirmada / reserva.cancelada (RabbitMQ): cambian los horarios
// libres => invalidar la caché. Idempotente: invalidar dos veces no rompe nada.
async function alEventoReservas(evento) {
  await cache.invalidar(`${evento.tipo} docente=${evento.datos.docenteId}`);
}

async function alRegistrarse({ datos: { docenteId, nombre } }) {
  await repo.crearPerfil(docenteId, nombre);
}

module.exports = {
  buscarDocentes, obtenerPerfilCompleto, actualizarMaterias, agregarHorario,
  consultarDisponibilidad, obtenerEstadoDocente, alVerificarse, alRegistrarse, alEventoReservas,
  metricasCache: cache.metricas,
  iniciarRefrescoPeriodico,
};
