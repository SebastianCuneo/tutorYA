const express = require('express');
const { asyncH, auth, config } = require('../../comun');

// External Configuration Store (UT4): lectura y escritura de la config compartida por TODOS los
// microservicios. El gateway enruta /api/admin/* a Usuarios, pero cualquier réplica de cualquier
// servicio aplica el cambio (todas escuchan config:cambios en Redis).
const router = express.Router();
const admin = [auth.autenticar, auth.requerirRol('ADMIN')];

router.get('/api/admin/config', admin, (req, res) => {
  res.json({ version: config.version(), valores: config.snapshot() });
});

router.put('/api/admin/config', admin, asyncH(async (req, res) => {
  res.json({ version: await config.actualizar(req.body) });
}));

module.exports = router;
