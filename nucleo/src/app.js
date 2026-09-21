const express = require('express');
const { middlewareInstancia, instancia, rutaNoEncontrada, manejadorErrores, db, logger } = require('../../comun');

// Cada require registra las suscripciones a eventos del módulo.
const usuarios = require('./usuarios');
const docentes = require('./docentes');
const mensajeria = require('./mensajeria');
const verificacion = require('./verificacion');

const app = express();
app.use(middlewareInstancia);
app.use(logger.middlewareLog);
app.use(express.json());

app.get('/api/salud', (req, res) => res.json({ servicio: 'nucleo', instancia }));

// Un solo proceso (Núcleo) hospeda 4 componentes lógicos, cada uno con su router.
app.use(usuarios.router);
app.use(docentes.router);
app.use(mensajeria.router);
app.use(verificacion.router);

app.use(rutaNoEncontrada);
app.use(manejadorErrores);

// Espera a la base antes de aceptar tráfico (docker compose puede arrancar todo a la vez).
async function main() {
  await db.esperarDb();
  const puerto = Number(process.env.PORT || 3000);
  app.listen(puerto, () => logger.info(`nucleo escuchando en :${puerto}`));
}

main().catch((e) => {
  logger.error('fallo al arrancar', { error: e.message });
  process.exit(1);
});
