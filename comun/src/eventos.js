// Eventos entre microservicios (UT5) sobre RabbitMQ.
//
// Publicar (Transactional Outbox): el servicio guarda el evento en su tabla <esquema>.outbox DENTRO de
// la misma transacción que el cambio de negocio. Un relay lo publica después en el exchange y lo marca
// como publicado. Si RabbitMQ está caído, el evento espera en la base: no se pierde ni bloquea el request.
//
// Consumir (Publisher/Subscriber + Competing Consumers): cada servicio interesado tiene SU cola durable,
// atada al exchange con las claves que le interesan. Las réplicas de un mismo servicio comparten la cola
// (se reparten los mensajes). El ack es manual y se envía recién cuando el handler terminó: si el
// servicio está caído o falla, el mensaje queda en la cola y se procesa cuando vuelve.
// Los handlers son idempotentes (un mensaje puede llegar más de una vez).
const amqp = require('amqplib');
const db = require('./db');
const logger = require('./logger');

const URL = process.env.RABBITMQ_URL || 'amqp://tutorya:tutorya@rabbitmq:5672';
const EXCHANGE = 'tutorya.eventos';
const ORIGEN = process.env.SERVICIO || 'desconocido';
const TABLA = process.env.OUTBOX_TABLA || `${ORIGEN}.outbox`;
const RELAY_MS = 500;
const REINTENTO_HANDLER_MS = 2000;

let conexion = null;
let canalPub = null; // confirm channel: el broker confirma que persistió el mensaje
let conectando = null;
const suscripciones = []; // { cola, claves, handler }

const conectado = () => !!canalPub;

async function prepararSuscripcion({ cola, claves, handler }) {
  const ch = await conexion.createChannel();
  await ch.assertExchange(EXCHANGE, 'topic', { durable: true });
  await ch.assertQueue(cola, { durable: true });
  for (const clave of claves) await ch.bindQueue(cola, EXCHANGE, clave);
  await ch.prefetch(10);
  await ch.consume(cola, async (msg) => {
    if (!msg) return;
    let evento;
    try {
      evento = JSON.parse(msg.content.toString());
    } catch {
      logger.warn('evento ilegible descartado', { cola });
      return ch.ack(msg);
    }
    try {
      await handler(evento);
      ch.ack(msg);
      logger.info('evento procesado', { cola, tipo: evento.tipo, id: evento.id });
    } catch (e) {
      // Se devuelve a la cola después de una pausa (p. ej. la base del servicio está caída).
      logger.warn('falló el handler; el evento vuelve a la cola', { cola, tipo: evento.tipo, error: e.message });
      setTimeout(() => {
        try {
          ch.nack(msg, false, true);
        } catch {
          /* canal cerrado: RabbitMQ lo reentrega solo */
        }
      }, REINTENTO_HANDLER_MS);
    }
  }, { noAck: false });
  logger.info('suscripto a eventos', { cola, claves });
}

// Conexión con reintento infinito (backoff hasta 5 s). Al reconectar, rearma las suscripciones.
async function conectar() {
  if (conectando) return conectando;
  conectando = (async () => {
    for (let i = 1; ; i++) {
      try {
        conexion = await amqp.connect(URL);
        conexion.on('error', (e) => logger.warn('rabbitmq: error de conexión', { error: e.message }));
        conexion.on('close', () => {
          logger.warn('rabbitmq: conexión cerrada; reconectando');
          conexion = null;
          canalPub = null;
          setTimeout(conectar, 1000);
        });
        const ch = await conexion.createConfirmChannel();
        await ch.assertExchange(EXCHANGE, 'topic', { durable: true });
        canalPub = ch;
        for (const s of suscripciones) await prepararSuscripcion(s);
        logger.info('rabbitmq conectado');
        return;
      } catch (e) {
        const espera = Math.min(500 * i, 5000);
        if (i === 1 || i % 10 === 0) logger.warn('rabbitmq no disponible; reintento', { intento: i, error: e.message });
        await new Promise((r) => setTimeout(r, espera));
      }
    }
  })().finally(() => {
    conectando = null;
  });
  return conectando;
}

// Guarda el evento en la outbox usando el cliente de la transacción en curso.
async function guardar(cliente, tipo, datos) {
  await cliente.query(`INSERT INTO ${TABLA} (tipo, datos) VALUES ($1, $2)`, [tipo, JSON.stringify(datos)]);
}

// Publica los eventos pendientes. FOR UPDATE SKIP LOCKED: si hay varias réplicas, no publican lo mismo.
async function publicarPendientes() {
  if (!conectado()) return 0;
  const cliente = await db.pool.connect();
  try {
    await cliente.query('BEGIN');
    const { rows } = await cliente.query(
      `SELECT id, tipo, datos, creado_en FROM ${TABLA} WHERE publicado_en IS NULL
       ORDER BY id LIMIT 50 FOR UPDATE SKIP LOCKED`
    );
    for (const ev of rows) {
      const cuerpo = { id: `${ORIGEN}-${ev.id}`, tipo: ev.tipo, origen: ORIGEN, ocurridoEn: ev.creado_en, datos: ev.datos };
      canalPub.publish(EXCHANGE, ev.tipo, Buffer.from(JSON.stringify(cuerpo)), {
        persistent: true,
        contentType: 'application/json',
        messageId: cuerpo.id,
        type: ev.tipo,
      });
    }
    if (rows.length) {
      await canalPub.waitForConfirms(); // el broker ya lo guardó: recién ahora se marca
      await cliente.query(`UPDATE ${TABLA} SET publicado_en = now() WHERE id = ANY($1::bigint[])`, [rows.map((r) => r.id)]);
      logger.info('eventos publicados', { cantidad: rows.length, tipos: [...new Set(rows.map((r) => r.tipo))] });
    }
    await cliente.query('COMMIT');
    return rows.length;
  } catch (e) {
    await cliente.query('ROLLBACK').catch(() => {});
    logger.warn('relay de outbox: no se pudo publicar; se reintenta', { error: e.message });
    return 0;
  } finally {
    cliente.release();
  }
}

function iniciarRelay() {
  const vuelta = async () => {
    await publicarPendientes().catch(() => {});
    setTimeout(vuelta, RELAY_MS).unref();
  };
  setTimeout(vuelta, RELAY_MS).unref();
}

// Registra una suscripción. Se arma al conectar (y se rearma al reconectar).
function suscribir(cola, claves, handler) {
  const s = { cola, claves, handler };
  suscripciones.push(s);
  if (conexion) prepararSuscripcion(s).catch((e) => logger.warn('no se pudo suscribir', { cola, error: e.message }));
}

// Pendientes en la outbox (para la readiness y las demos).
async function pendientes() {
  const { rows } = await db.query(`SELECT count(*)::int AS n FROM ${TABLA} WHERE publicado_en IS NULL`);
  return rows[0].n;
}

module.exports = { conectar, conectado, guardar, iniciarRelay, suscribir, pendientes, EXCHANGE };
