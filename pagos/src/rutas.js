const express = require('express');
const { asyncH, E } = require('../../comun');
const servicio = require('./servicio');

// Solo rutas internas: el gateway no expone Pagos (lo usa Reservas dentro de la red interna).
const router = express.Router();

function idParam(req) {
  const id = Number(req.params.reservaId);
  if (!Number.isInteger(id)) throw E.validacion('reservaId inválido');
  return id;
}

router.post('/internal/pagos', asyncH(async (req, res) => {
  res.json(await servicio.cobrar(req.body));
}));

router.get('/internal/pagos/:reservaId', asyncH(async (req, res) => {
  res.json(await servicio.obtener(idParam(req)));
}));

router.post('/internal/pagos/:reservaId/reembolso', asyncH(async (req, res) => {
  res.json(await servicio.reembolsar(idParam(req)));
}));

// Fence de la saga: el reconciliador anula el cobro antes de cancelar una reserva sin pago.
router.post('/internal/pagos/:reservaId/anulacion', asyncH(async (req, res) => {
  res.json(await servicio.anular(idParam(req)));
}));

module.exports = router;
