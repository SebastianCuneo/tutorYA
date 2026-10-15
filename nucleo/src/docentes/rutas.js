const express = require('express');
const { asyncH, E, auth } = require('../../../comun');
const servicio = require('./servicio');

const router = express.Router();
const estudiante = [auth.autenticar, auth.requerirRol('ESTUDIANTE')];
const docente = [auth.autenticar, auth.requerirRol('DOCENTE')];

router.get('/api/docentes', estudiante, asyncH(async (req, res) => {
  const { datos, cache } = await servicio.buscarDocentes(req.query.materia);
  res.setHeader('X-Cache', cache);
  res.json(datos);
}));

router.get('/api/docentes/me', docente, asyncH(async (req, res) => {
  res.json(await servicio.obtenerPerfilCompleto(req.usuario.id));
}));

router.put('/api/docentes/me/materias', docente, asyncH(async (req, res) => {
  res.json(await servicio.actualizarMaterias(req.usuario.id, req.body));
}));

router.post('/api/docentes/me/horarios', docente, asyncH(async (req, res) => {
  res.status(201).json(await servicio.agregarHorario(req.usuario.id, req.body));
}));

router.get('/internal/docentes/:docenteId/horarios/:horarioId', asyncH(async (req, res) => {
  const docenteId = Number(req.params.docenteId);
  const horarioId = Number(req.params.horarioId);
  if (!Number.isInteger(docenteId) || !Number.isInteger(horarioId)) throw E.validacion('ids inválidos');
  const r = await servicio.consultarDisponibilidad(docenteId, horarioId);
  if (!r) throw E.noEncontrado('Horario no encontrado');
  res.json(r);
}));

module.exports = router;
