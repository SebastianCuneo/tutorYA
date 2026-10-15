const config = require('./config');

// Cliente HTTP mínimo para llamadas internas entre servicios.
// Lanza excepción ante error de red o timeout; devuelve { status, body } en cualquier respuesta HTTP.
// El timeout sale del config store (http.timeoutMs) salvo que se pase explícito.
async function getJson(url, { timeoutMs = config.get('http.timeoutMs') } = {}) {
  const res = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) });
  let body = null;
  try {
    body = await res.json();
  } catch {
    /* sin body JSON */
  }
  return { status: res.status, body };
}

module.exports = { getJson };
