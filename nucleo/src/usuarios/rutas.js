const express = require('express');
const { asyncH, E } = require('../../../comun');
const servicio = require('./servicio');

const router = express.Router();

router.post('/api/usuarios/registro', asyncH(async (req, res) => {
  res.status(201).json(await servicio.registrarUsuario(req.body));
}));

router.post('/api/usuarios/login', asyncH(async (req, res) => {
  res.json(await servicio.login(req.body));
}));

router.post('/api/autorizaciones/:token', asyncH(async (req, res) => {
  res.json(await servicio.autorizarMenor(req.params.token));
}));

router.get('/internal/usuarios/:id/estado', asyncH(async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) throw E.validacion('id inválido');
  res.json(await servicio.consultarEstadoEstudiante(id));
}));

module.exports = router;
