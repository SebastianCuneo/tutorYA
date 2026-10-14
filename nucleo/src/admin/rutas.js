const express = require('express');
const { asyncH, auth, config } = require('../../../comun');

// Endpoints operativos (rol ADMIN). No es un componente de negocio: no tiene esquema propio.
const router = express.Router();
const admin = [auth.autenticar, auth.requerirRol('ADMIN')];

// External Configuration Store: lectura y escritura de la config compartida.
router.get('/api/admin/config', admin, (req, res) => {
  res.json({ version: config.version(), valores: config.snapshot() });
});

router.put('/api/admin/config', admin, asyncH(async (req, res) => {
  res.json({ version: await config.actualizar(req.body) });
}));

module.exports = router;
