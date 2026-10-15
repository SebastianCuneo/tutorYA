// Circuit Breaker: corta las llamadas a una dependencia que viene fallando, para responder
// rápido en vez de esperar un timeout por cada request. Estado operativo, en memoria por réplica.
const config = require('./config');
const logger = require('./logger');

const registro = new Map();

class CircuitoAbiertoError extends Error {
  constructor(nombre, retryAfterSeg) {
    super(`Circuito ${nombre} abierto`);
    this.circuito = nombre;
    this.retryAfterSeg = Math.max(1, retryAfterSeg);
  }
}

// Falla = excepción (error de red, timeout) o respuesta 5xx. Un 4xx es una respuesta válida.
const esFallaPorDefecto = (r) => !!r && typeof r.status === 'number' && r.status >= 500;

class CircuitBreaker {
  constructor(nombre, { esFalla = esFallaPorDefecto } = {}) {
    this.nombre = nombre;
    this.esFalla = esFalla;
    this.estado = 'CERRADO'; // CERRADO | ABIERTO | SEMIABIERTO
    this.fallas = []; // timestamps de las fallas dentro de la ventana
    this.abiertoDesde = null;
    this.pruebaEnCurso = false;
    registro.set(nombre, this);
  }

  // Se leen en cada llamada: un cambio en el config store aplica en caliente.
  parametros() {
    return {
      habilitado: config.get('circuitBreaker.habilitado'),
      umbral: config.get('circuitBreaker.umbral'),
      ventanaMs: config.get('circuitBreaker.ventanaMs'),
      esperaMs: config.get('circuitBreaker.esperaMs'),
    };
  }

  cambiar(estado) {
    if (estado === this.estado) return;
    logger.warn(`circuito ${this.nombre}: ${this.estado} → ${estado}`);
    this.estado = estado;
    this.abiertoDesde = estado === 'ABIERTO' ? Date.now() : estado === 'CERRADO' ? null : this.abiertoDesde;
    if (estado !== 'SEMIABIERTO') this.fallas = [];
  }

  podar(ventanaMs) {
    const limite = Date.now() - ventanaMs;
    this.fallas = this.fallas.filter((t) => t > limite);
  }

  registrarFalla(p, esPrueba) {
    if (esPrueba) return this.cambiar('ABIERTO');
    this.fallas.push(Date.now());
    this.podar(p.ventanaMs);
    if (this.fallas.length >= p.umbral) this.cambiar('ABIERTO');
  }

  async ejecutar(fn) {
    const p = this.parametros();
    if (!p.habilitado) return fn(); // passthrough: ni corta ni cuenta

    if (this.estado === 'ABIERTO') {
      const transcurrido = Date.now() - this.abiertoDesde;
      if (transcurrido < p.esperaMs) {
        throw new CircuitoAbiertoError(this.nombre, Math.ceil((p.esperaMs - transcurrido) / 1000));
      }
      this.cambiar('SEMIABIERTO');
    }
    // En SEMIABIERTO pasa una sola llamada de prueba; las concurrentes se rechazan.
    let esPrueba = false;
    if (this.estado === 'SEMIABIERTO') {
      if (this.pruebaEnCurso) throw new CircuitoAbiertoError(this.nombre, 1);
      this.pruebaEnCurso = true;
      esPrueba = true;
    }

    let resultado;
    try {
      resultado = await fn();
    } catch (e) {
      this.registrarFalla(p, esPrueba);
      throw e;
    } finally {
      if (esPrueba) this.pruebaEnCurso = false;
    }
    if (this.esFalla(resultado)) this.registrarFalla(p, esPrueba);
    else if (esPrueba) this.cambiar('CERRADO');
    return resultado;
  }

  snapshot() {
    this.podar(this.parametros().ventanaMs);
    return {
      nombre: this.nombre,
      estado: this.estado,
      fallasEnVentana: this.fallas.length,
      abiertoDesde: this.abiertoDesde ? new Date(this.abiertoDesde).toISOString() : null,
    };
  }
}

const circuitos = () => [...registro.values()].map((c) => c.snapshot());

module.exports = { CircuitBreaker, CircuitoAbiertoError, circuitos };
