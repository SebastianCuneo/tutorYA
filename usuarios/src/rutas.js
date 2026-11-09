const express = require('express');
const { asyncH } = require('../../comun');
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

// UT5: GET /internal/usuarios/:id/estado (REST/JSON) se migró a SOAP: soap/servidor.js.

module.exports = router;
