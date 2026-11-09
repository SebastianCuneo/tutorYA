// Arranque común de cada microservicio (UT5). Cada servicio es un proceso y un contenedor propio,
// con su base; esto solo evita repetir el "esqueleto" operativo en los seis servicios:
// request id, X-Instancia, log, liveness/readiness, inyección de fallas, errores y conexión a RabbitMQ.
const express = require('express');
const { middlewareRequestId } = require('./contexto');
const { middlewareInstancia, instancia } = require('./instancia');
const { rutaNoEncontrada, manejadorErrores } = require('./errores');
const { circuitos } = require('./circuitBreaker');
const db = require('./db');
const logger = require('./logger');
const config = require('./config');
const salud = require('./salud');
const eventos = require('./eventos');

const VERSION = process.env.APP_VERSION || 'ut5';

// opciones: { nombre, routers: [router], extender: fn(app) (p. ej. SOAP), usaEventos, publicaEventos, alArrancar }
function crearServicio({ nombre, routers = [], extender, usaEventos = false, publicaEventos = false, alArrancar }) {
  const app = express();
  app.use(middlewareRequestId);
  app.use(middlewareInstancia);
  app.use(logger.middlewareLog);

  const base = `/api/salud/${nombre}`;
  // Liveness: no toca dependencias.
  app.get(base, (req, res) => res.json({ servicio: nombre, instancia, version: VERSION, ...config.info() }));
  // Readiness: base propia (crítica); Redis y RabbitMQ se informan pero no la degradan.
  app.get(`${base}/listo`, salud.rutaListo(() => ({ servicio: nombre, circuitos: circuitos() })));
  app.use(salud.middlewareListo([base, `${base}/listo`]));
  app.use(salud.routerFallas());

  if (usaEventos || publicaEventos) {
    salud.registrarChequeo('broker', async () => {
      if (!eventos.conectado()) throw new Error('sin conexión a RabbitMQ');
    });
  }

  app.use(express.json());
  for (const r of routers) app.use(r);
  if (extender) extender(app);
  app.use(rutaNoEncontrada);
  app.use(manejadorErrores);

  async function iniciar() {
    await db.esperarDb();
    await config.iniciar();
    if (usaEventos || publicaEventos) eventos.conectar(); // no se espera: sin broker el servicio igual atiende
    if (publicaEventos) eventos.iniciarRelay();
    if (alArrancar) await alArrancar();
    const puerto = Number(process.env.PORT || 3000);
    app.listen(puerto, () => logger.info(`${nombre} escuchando en :${puerto}`));
  }

  return { app, iniciar };
}

// Atajo para el app.js de cada servicio.
function arrancar(opciones) {
  const s = crearServicio(opciones);
  s.iniciar().catch((e) => {
    logger.error('fallo al arrancar', { error: e.message });
    process.exit(1);
  });
  return s.app;
}

module.exports = { crearServicio, arrancar };
