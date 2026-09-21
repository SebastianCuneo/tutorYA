const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const { E, auth } = require('../../../comun');
const repo = require('./repositorio');
const eventos = require('../eventos');

const URL_PUBLICA = process.env.PUBLIC_URL || 'http://localhost:8080';
const REGEX_EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function texto(v) {
  return typeof v === 'string' ? v.trim() : '';
}

async function registrarUsuario(body = {}) {
  const email = texto(body.email).toLowerCase();
  const nombre = texto(body.nombre);
  const { password, rol } = body;
  if (!REGEX_EMAIL.test(email)) throw E.validacion('email inválido');
  if (typeof password !== 'string' || password.length < 6) throw E.validacion('password debe tener al menos 6 caracteres');
  if (!nombre) throw E.validacion('nombre es obligatorio');
  if (!['ESTUDIANTE', 'DOCENTE'].includes(rol)) throw E.validacion('rol debe ser ESTUDIANTE o DOCENTE');

  const esMenor = body.esMenor === true;
  const emailAdulto = texto(body.emailAdulto).toLowerCase() || null;
  if (esMenor) {
    if (rol !== 'ESTUDIANTE') throw E.validacion('solo un ESTUDIANTE puede ser menor');
    if (!emailAdulto || !REGEX_EMAIL.test(emailAdulto)) throw E.validacion('emailAdulto es obligatorio para menores');
  }

  const token = esMenor ? crypto.randomBytes(24).toString('hex') : null;
  let usuario;
  try {
    usuario = await repo.crearUsuario(
      {
        email,
        passwordHash: await bcrypt.hash(password, 10),
        nombre,
        rol,
        esMenor,
        emailAdulto: esMenor ? emailAdulto : null,
        estado: esMenor ? 'PENDIENTE' : 'AUTORIZADO',
      },
      token
    );
  } catch (e) {
    if (e.code === '23505') throw E.conflicto('El email ya está registrado');
    throw e;
  }

  const respuesta = {
    id: usuario.id,
    email: usuario.email,
    nombre: usuario.nombre,
    rol: usuario.rol,
    esMenor: usuario.es_menor,
    estado: usuario.estado,
  };
  // Simula el email al adulto responsable: no se envía nada, se devuelve el link.
  if (esMenor) respuesta.linkAutorizacion = `${URL_PUBLICA}/api/autorizaciones/${token}`;

  if (rol === 'DOCENTE') {
    await eventos.emitir('docente.registrado', { docenteId: usuario.id, nombre: usuario.nombre, email: usuario.email });
  }
  return respuesta;
}

async function login(body = {}) {
  const email = texto(body.email).toLowerCase();
  if (!email || typeof body.password !== 'string') throw E.validacion('email y password son obligatorios');
  const u = await repo.buscarPorEmail(email);
  if (!u || !(await bcrypt.compare(body.password, u.password_hash))) {
    throw E.noAutenticado('Credenciales inválidas');
  }
  return { token: auth.firmarToken({ id: u.id, rol: u.rol, esMenor: u.es_menor }) };
}

async function autorizarMenor(token) {
  const { resultado, usuarioId } = await repo.autorizarConToken(token);
  if (resultado === 'NO_EXISTE') throw E.noEncontrado('Token de autorización inexistente');
  if (resultado === 'USADO') throw E.gone('El token de autorización ya fue utilizado');
  return { usuarioId, estado: 'AUTORIZADO' };
}

async function consultarEstadoEstudiante(id) {
  const u = await repo.buscarPorId(id);
  if (!u) throw E.noEncontrado('Usuario no encontrado');
  return { id: u.id, rol: u.rol, esMenor: u.es_menor, estado: u.estado };
}

module.exports = { registrarUsuario, login, autorizarMenor, consultarEstadoEstudiante };
