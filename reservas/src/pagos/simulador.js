const crypto = require('crypto');

// Pasarela de pago simulada. tokenPago === 'RECHAZAR' -> rechazo; cualquier otro valor -> aprobado.
async function cobrar({ monto, tokenPago }) {
  // Latencia del procesador: hace demostrable la carrera concurrente.
  await new Promise((r) => setTimeout(r, 300));
  if (tokenPago === 'RECHAZAR') {
    return { aprobado: false, motivo: 'Pago rechazado por el procesador' };
  }
  return { aprobado: true, monto, referencia: `SIM-${crypto.randomUUID()}` };
}

module.exports = { cobrar };
