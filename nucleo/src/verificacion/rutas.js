const express = require('express');
const { asyncH, E, auth } = require('../../../comun');
const servicio = require('./servicio');

const router = express.Router();
const verificador = [auth.autenticar, auth.requerirRol('VERIFICADOR')];

function idParam(req) {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) throw E.validacion('id inválido');
  return id;
}

router.get('/api/verificaciones', verificador, asyncH(async (req, res) => {
  res.json(await servicio.listarSolicitudes(req.query.estado));
}));

router.post('/api/verificaciones/:id/llamada', verificador, asyncH(async (req, res) => {
  res.json(await servicio.agendarLlamada(idParam(req), req.usuario.id, req.body));
}));

router.post('/api/verificaciones/:id/resolucion', verificador, asyncH(async (req, res) => {
  res.json(await servicio.resolverSolicitud(idParam(req), req.usuario.id, req.body));
}));

module.exports = router;
