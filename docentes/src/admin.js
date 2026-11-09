const express = require('express');
const { auth, circuitos, instancia } = require('../../comun');
const servicio = require('./servicio');

// Endpoints operativos de Docentes (rol ADMIN): circuito hacia Reservas y métricas de la caché.
// La config compartida se administra por /api/admin/config (servicio Usuarios).
const router = express.Router();
const admin = [auth.autenticar, auth.requerirRol('ADMIN')];

// Circuit Breaker: estado de los circuitos de esta réplica.
router.get('/api/circuitos', admin, (req, res) => {
  res.json({ instancia, circuitos: circuitos() });
});

// Métricas en memoria de esta réplica: caché del catálogo y circuitos.
router.get('/api/metricas', admin, (req, res) => {
  res.json({ instancia, cache: servicio.metricasCache(), circuitos: circuitos() });
});

module.exports = router;
