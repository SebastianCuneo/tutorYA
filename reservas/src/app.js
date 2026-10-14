const express = require('express');
const { middlewareInstancia, rutaNoEncontrada, manejadorErrores, db, logger, config } = require('../../comun');
const reservas = require('./index');

const app = express();
app.use(middlewareInstancia);
app.use(logger.middlewareLog);
app.use(express.json());
// Servicio independiente: solo expone el router de Reservas.
app.use(reservas.router);
app.use(rutaNoEncontrada);
app.use(manejadorErrores);

async function main() {
  await db.esperarDb();
  await config.iniciar();
  const puerto = Number(process.env.PORT || 3000);
  app.listen(puerto, () => logger.info(`reservas escuchando en :${puerto}`));
}

main().catch((e) => {
  logger.error('fallo al arrancar', { error: e.message });
  process.exit(1);
});
