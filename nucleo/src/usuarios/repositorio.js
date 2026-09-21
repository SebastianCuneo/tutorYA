const { db } = require('../../../comun');

const COLS = 'id, email, password_hash, nombre, rol, es_menor, email_adulto, estado';

// Crea el usuario y, si viene, su token de autorización en la misma transacción.
async function crearUsuario(u, token) {
  const cliente = await db.pool.connect();
  try {
    await cliente.query('BEGIN');
    const { rows } = await cliente.query(
      `INSERT INTO usuarios.usuarios (email, password_hash, nombre, rol, es_menor, email_adulto, estado)
       VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING ${COLS}`,
      [u.email, u.passwordHash, u.nombre, u.rol, u.esMenor, u.emailAdulto, u.estado]
    );
    if (token) {
      await cliente.query('INSERT INTO usuarios.tokens_autorizacion (token, usuario_id) VALUES ($1,$2)', [
        token,
        rows[0].id,
      ]);
    }
    await cliente.query('COMMIT');
    return rows[0];
  } catch (e) {
    await cliente.query('ROLLBACK');
    throw e;
  } finally {
    cliente.release();
  }
}

async function buscarPorEmail(email) {
  const { rows } = await db.query(`SELECT ${COLS} FROM usuarios.usuarios WHERE email = $1`, [email]);
  return rows[0] || null;
}

async function buscarPorId(id) {
  const { rows } = await db.query(`SELECT ${COLS} FROM usuarios.usuarios WHERE id = $1`, [id]);
  return rows[0] || null;
}

// Consume el token (un solo uso) y autoriza al estudiante, todo en una transacción.
// Devuelve { resultado: 'OK'|'USADO'|'NO_EXISTE', usuarioId }.
async function autorizarConToken(token) {
  const cliente = await db.pool.connect();
  try {
    await cliente.query('BEGIN');
    const { rows } = await cliente.query(
      'SELECT usuario_id, usado_en FROM usuarios.tokens_autorizacion WHERE token = $1 FOR UPDATE',
      [token]
    );
    if (!rows[0]) {
      await cliente.query('ROLLBACK');
      return { resultado: 'NO_EXISTE' };
    }
    if (rows[0].usado_en) {
      await cliente.query('ROLLBACK');
      return { resultado: 'USADO' };
    }
    await cliente.query('UPDATE usuarios.tokens_autorizacion SET usado_en = now() WHERE token = $1', [token]);
    await cliente.query("UPDATE usuarios.usuarios SET estado = 'AUTORIZADO' WHERE id = $1", [rows[0].usuario_id]);
    await cliente.query('COMMIT');
    return { resultado: 'OK', usuarioId: rows[0].usuario_id };
  } catch (e) {
    await cliente.query('ROLLBACK');
    throw e;
  } finally {
    cliente.release();
  }
}

module.exports = { crearUsuario, buscarPorEmail, buscarPorId, autorizarConToken };
