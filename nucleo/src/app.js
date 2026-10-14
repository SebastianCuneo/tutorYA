const express = require('express');
const { middlewareInstancia, instancia, rutaNoEncontrada, manejadorErrores, db, logger, config } = require('../../comun');

// Cada require registra las suscripciones a eventos del módulo.
const usuarios = require('./usuarios');
const docentes = require('./docentes');
const mensajeria = require('./mensajeria');
const verificacion = require('./verificacion');
const admin = require('./admin/rutas');

const app = express();
app.use(middlewareInstancia);
app.use(logger.middlewareLog);
app.use(express.json());

const VERSION = process.env.APP_VERSION || 'ut4';

// Liveness: no toca dependencias.
app.get('/api/salud', (req, res) => res.json({ servicio: 'nucleo', instancia, version: VERSION, ...config.info() }));

// Un solo proceso (Núcleo) hospeda 4 componentes lógicos, cada uno con su router.
app.use(usuarios.router);
app.use(docentes.router);
app.use(mensajeria.router);
app.use(verificacion.router);
app.use(admin);

app.use(rutaNoEncontrada);
app.use(manejadorErrores);

// Espera a la base antes de aceptar tráfico (docker compose puede arrancar todo a la vez).
async function main() {
  await db.esperarDb();
  await config.iniciar();
  const puerto = Number(process.env.PORT || 3000);
  app.listen(puerto, () => logger.info(`nucleo escuchando en :${puerto}`));
}

main().catch((e) => {
  logger.error('fallo al arrancar', { error: e.message });
  process.exit(1);
});
