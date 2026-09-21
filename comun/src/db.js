const { Pool, types } = require('pg');
const logger = require('./logger');

// numeric -> number (montos y precios)
types.setTypeParser(1700, parseFloat);

const pool = new Pool({
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT || 5432),
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  max: Number(process.env.DB_POOL_MAX || 10),
});

// Sin este handler, un corte de la base (p. ej. restart) tumba el proceso.
pool.on('error', (e) => logger.warn('error en cliente idle del pool', { error: e.message }));

const query = (texto, params) => pool.query(texto, params);

// Reintenta la conexión inicial con backoff simple (500ms, 1s, 1.5s... tope 5s).
async function esperarDb(intentos = 30) {
  for (let i = 1; i <= intentos; i++) {
    try {
      await pool.query('SELECT 1');
      logger.info('conexión a la base OK');
      return;
    } catch (e) {
      const espera = Math.min(500 * i, 5000);
      logger.warn(`base no disponible (intento ${i}/${intentos}), reintento en ${espera}ms`, { error: e.message });
      await new Promise((r) => setTimeout(r, espera));
    }
  }
  throw new Error('No se pudo conectar a la base de datos');
}

module.exports = { pool, query, esperarDb };
