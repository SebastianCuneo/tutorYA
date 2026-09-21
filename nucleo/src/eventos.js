const { EventEmitter } = require('events');

// Bus de eventos en proceso: solo vive dentro del Núcleo, entre sus módulos.
const emitter = new EventEmitter();

// Emite y espera a que todos los suscriptores terminen (para que el request
// no responda antes de que los otros módulos hayan actuado).
async function emitir(evento, payload) {
  await Promise.all(emitter.listeners(evento).map((fn) => fn(payload)));
}

module.exports = { on: (evento, fn) => emitter.on(evento, fn), emitir };
