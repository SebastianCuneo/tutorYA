const { E, getJson, logger, CircuitBreaker, CircuitoAbiertoError } = require('../../../comun');
const repo = require('./repositorio');
const cache = require('./cache');

const RESERVAS_URL = process.env.RESERVAS_URL || 'http://reservas:3000';
const circuitoReservas = new CircuitBreaker('reservas');

// Pide a Reservas (por HTTP, a través del circuito) los horarios ocupados de un docente.
// null si Reservas no responde o el circuito está abierto => degradación elegante.
async function horariosOcupados(docenteId) {
  try {
    const { status, body } = await circuitoReservas.ejecutar(() =>
      getJson(`${RESERVAS_URL}/internal/reservas/horarios-ocupados?docenteId=${docenteId}`)
    );
    if (status !== 200) return null;
    return new Set(body.horarioIds);
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

async function armarCatalogo(filtro) {
  const docentes = await repo.listarAprobados(filtro);
  return Promise.all(
    docentes.map(async (d) => {
      const [materias, horarios, ocupados] = await Promise.all([
        repo.materiasDe(d.usuario_id),
        repo.horariosDe(d.usuario_id, true),
        horariosOcupados(d.usuario_id),
      ]);
      return {
        id: d.usuario_id,
        nombre: d.nombre,
        materias,
        horarios: ocupados ? horarios.filter((h) => !ocupados.has(h.id)) : horarios,
        disponibilidadVerificada: ocupados !== null,
      };
    })
  );
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
async function alVerificarse({ docenteId, resultado }) {
  if (!['APROBADO', 'RECHAZADO'].includes(resultado)) return;
  await repo.actualizarEstado(docenteId, resultado);
  await alCambiarCatalogo('verificacion');
}

// Cualquier cambio del catálogo invalida la caché (no se lanza: la escritura ya se hizo).
async function alCambiarCatalogo(motivo) {
  await cache.invalidar(motivo);
}

// Reservas publica reserva.creada (después del COMMIT): cambian los horarios libres => invalidar.
async function alEventoReservas(mensaje) {
  const evento = JSON.parse(mensaje);
  if (evento.tipo === 'reserva.creada') await cache.invalidar(`reserva.creada docente=${evento.docenteId}`);
}

async function alRegistrarse({ docenteId, nombre }) {
  await repo.crearPerfil(docenteId, nombre);
}

module.exports = {
  buscarDocentes, obtenerPerfilCompleto, actualizarMaterias, agregarHorario,
  consultarDisponibilidad, obtenerEstadoDocente, alVerificarse, alRegistrarse, alEventoReservas,
  metricasCache: cache.metricas,
};
