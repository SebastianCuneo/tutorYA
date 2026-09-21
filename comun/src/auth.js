const jwt = require('jsonwebtoken');
const { E } = require('./errores');

function secreto() {
  if (!process.env.JWT_SECRET) throw new Error('Falta la variable de entorno JWT_SECRET');
  return process.env.JWT_SECRET;
}

// Payload: { sub, rol, esMenor }, expira en 8h.
function firmarToken({ id, rol, esMenor }) {
  return jwt.sign({ sub: String(id), rol, esMenor: !!esMenor }, secreto(), { expiresIn: '8h' });
}

function autenticar(req, res, next) {
  const cab = req.headers.authorization || '';
  const [tipo, token] = cab.split(' ');
  if (tipo !== 'Bearer' || !token) return next(E.noAutenticado());
  try {
    const p = jwt.verify(token, secreto());
    req.usuario = { id: Number(p.sub), rol: p.rol, esMenor: !!p.esMenor };
    next();
  } catch {
    next(E.noAutenticado());
  }
}

function requerirRol(...roles) {
  return (req, res, next) => {
    if (!req.usuario || !roles.includes(req.usuario.rol)) {
      return next(E.prohibido(`Requiere rol ${roles.join(' o ')}`));
    }
    next();
  };
}

module.exports = { firmarToken, autenticar, requerirRol };
