-- Migración UT4 para bases creadas con el init.sql de la UT3. Idempotente: se puede correr varias veces.
--   docker compose exec -T db psql -U tutorya -d tutorya -v ON_ERROR_STOP=1 < db/migraciones/ut4.sql

-- ---------- External Configuration Store: rol ADMIN + usuario semilla (password: admin123) ----------
ALTER TABLE usuarios.usuarios DROP CONSTRAINT IF EXISTS usuarios_rol_check;
ALTER TABLE usuarios.usuarios ADD CONSTRAINT usuarios_rol_check
  CHECK (rol IN ('ESTUDIANTE','DOCENTE','VERIFICADOR','ADMIN'));

INSERT INTO usuarios.usuarios (email, password_hash, nombre, rol, estado)
VALUES ('admin@tutorya.uy', '$2a$10$1LqXWgckjGXCeAS0nUzEbudgkkiEv9N8nDwOgdUmX3t311eqtuVEa',
        'Admin TutorYa', 'ADMIN', 'AUTORIZADO')
ON CONFLICT (email) DO NOTHING;
