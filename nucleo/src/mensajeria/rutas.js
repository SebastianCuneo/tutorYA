const express = require('express');
const { asyncH, E, auth } = require('../../../comun');
const servicio = require('./servicio');

const router = express.Router();
const ambos = [auth.autenticar, auth.requerirRol('ESTUDIANTE', 'DOCENTE')];

function idParam(req) {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) throw E.validacion('id inválido');
  return id;
}

router.post('/api/mensajes', auth.autenticar, auth.requerirRol('ESTUDIANTE'), asyncH(async (req, res) => {
  res.status(201).json(await servicio.enviarMensaje(req.usuario.id, req.body));
}));

router.get('/api/conversaciones', ambos, asyncH(async (req, res) => {
  res.json(await servicio.listarConversaciones(req.usuario));
}));

router.get('/api/conversaciones/:id/mensajes', ambos, asyncH(async (req, res) => {
  res.json(await servicio.listarMensajes(req.usuario.id, idParam(req)));
}));

router.post('/api/conversaciones/:id/mensajes', auth.autenticar, auth.requerirRol('DOCENTE'), asyncH(async (req, res) => {
  res.status(201).json(await servicio.responderMensaje(req.usuario.id, idParam(req), req.body));
}));

module.exports = router;
