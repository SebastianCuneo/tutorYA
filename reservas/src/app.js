const express = require('express');
const { middlewareInstancia, rutaNoEncontrada, manejadorErrores, db, logger, config, salud, circuitos } = require('../../comun');
const reservas = require('./index');

const app = express();
app.use(middlewareInstancia);
app.use(logger.middlewareLog);
app.use(express.json());
// Readiness: base (crítica) y Redis (no crítico). Los circuitos se informan pero no la hacen fallar.
app.get('/api/reservas/salud/listo', salud.rutaListo(() => ({ circuitos: circuitos() })));
app.use(salud.middlewareListo(['/api/reservas/salud', '/api/reservas/salud/listo']));
app.use(salud.routerFallas());
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
