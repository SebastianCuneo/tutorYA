const express = require('express');
const { middlewareInstancia, rutaNoEncontrada, manejadorErrores, db, logger } = require('../../comun');
const reservas = require('./index');

const app = express();
app.use(middlewareInstancia);
app.use(logger.middlewareLog);
app.use(express.json());
app.use(reservas.router);
app.use(rutaNoEncontrada);
app.use(manejadorErrores);

async function main() {
  await db.esperarDb();
  const puerto = Number(process.env.PORT || 3000);
  app.listen(puerto, () => logger.info(`reservas escuchando en :${puerto}`));
}

main().catch((e) => {
  logger.error('fallo al arrancar', { error: e.message });
  process.exit(1);
});
