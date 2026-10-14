const express = require('express');
const { asyncH, E, auth, instancia, config } = require('../../comun');
const servicio = require('./servicio');

const router = express.Router();

function idParam(req) {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) throw E.validacion('id inválido');
  return id;
}

const VERSION = process.env.APP_VERSION || 'ut4';

// Liveness: no toca dependencias.
router.get('/api/reservas/salud', (req, res) =>
  res.json({ servicio: 'reservas', instancia, version: VERSION, ...config.info() }));

router.post('/api/reservas', auth.autenticar, auth.requerirRol('ESTUDIANTE'), asyncH(async (req, res) => {
  res.status(201).json(await servicio.reservarClase(req.usuario, req.body));
}));

router.get('/api/reservas', auth.autenticar, auth.requerirRol('ESTUDIANTE', 'DOCENTE'), asyncH(async (req, res) => {
  res.json(await servicio.listarReservas(req.usuario));
}));

router.get('/api/reservas/:id', auth.autenticar, asyncH(async (req, res) => {
  res.json(await servicio.obtenerReserva(req.usuario, idParam(req)));
}));

router.patch('/api/reservas/:id/dictada', auth.autenticar, auth.requerirRol('DOCENTE'), asyncH(async (req, res) => {
  res.json(await servicio.confirmarClaseDictada(req.usuario, idParam(req)));
}));

// Ruta interna: Nginx no la expone; solo la usa el Núcleo dentro de la red de Docker.
router.get('/internal/reservas/horarios-ocupados', asyncH(async (req, res) => {
  const docenteId = Number(req.query.docenteId);
  if (!Number.isInteger(docenteId)) throw E.validacion('docenteId inválido');
  res.json(await servicio.horariosOcupados(docenteId));
}));

module.exports = router;
