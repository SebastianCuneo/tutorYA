const config = require('./config');
const contexto = require('./contexto');

// Cliente HTTP mínimo para llamadas internas entre servicios.
// Lanza excepción ante error de red o timeout; devuelve { status, body } en cualquier respuesta HTTP.
// El timeout sale del config store (http.timeoutMs) salvo que se pase explícito.
// Propaga el X-Request-Id del request en curso: el mismo id aparece en los logs de ambos servicios.
async function getJson(url, { timeoutMs = config.get('http.timeoutMs') } = {}) {
  const requestId = contexto.requestId();
  const res = await fetch(url, {
    signal: AbortSignal.timeout(timeoutMs),
    headers: requestId ? { 'X-Request-Id': requestId } : {},
  });
  let body = null;
  try {
    body = await res.json();
  } catch {
    /* sin body JSON */
  }
  return { status: res.status, body };
}

module.exports = { getJson };
