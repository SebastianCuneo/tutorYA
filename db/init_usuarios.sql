-- TutorYa (UT5) — base del microservicio Usuarios (db-usuarios). Solo Usuarios la lee y escribe.
-- Los ids de otros servicios son ids sueltos, sin foreign key: cada servicio es dueño de sus datos.

CREATE SCHEMA usuarios;
-- ---------- Usuarios ----------
CREATE TABLE usuarios.usuarios (
  id            serial PRIMARY KEY,
  email         text UNIQUE NOT NULL,
  password_hash text NOT NULL,
  nombre        text NOT NULL,
  rol           text NOT NULL CHECK (rol IN ('ESTUDIANTE','DOCENTE','VERIFICADOR','ADMIN')),
  es_menor      boolean NOT NULL DEFAULT false,
  email_adulto  text,
  estado        text NOT NULL DEFAULT 'AUTORIZADO' CHECK (estado IN ('PENDIENTE','AUTORIZADO')),
  creado_en     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE usuarios.tokens_autorizacion (
  token      text PRIMARY KEY,
  usuario_id integer NOT NULL REFERENCES usuarios.usuarios(id),
  usado_en   timestamptz,
  creado_en  timestamptz NOT NULL DEFAULT now()
);


-- UT5 Transactional Outbox: los eventos se guardan en la misma transacción que el cambio de negocio
-- y un relay los publica en RabbitMQ (exchange tutorya.eventos). publicado_en NULL = pendiente.
CREATE TABLE usuarios.outbox (
  id           bigserial PRIMARY KEY,
  tipo         text NOT NULL,
  datos        jsonb NOT NULL,
  creado_en    timestamptz NOT NULL DEFAULT now(),
  publicado_en timestamptz
);
CREATE INDEX outbox_pendientes ON usuarios.outbox (id) WHERE publicado_en IS NULL;

-- ---------- Seed ----------
INSERT INTO usuarios.usuarios (email, password_hash, nombre, rol, estado)
VALUES ('verificador@tutorya.uy', '$2a$10$R/DCwQC/P9qOhnuwThaeiuGaLT5G4e1ZeJbVjHgC3nE1Pr20CBiqS',
        'Verificador TutorYa', 'VERIFICADOR', 'AUTORIZADO');

-- UT4: administrador (config, circuitos, métricas). Password: admin123
INSERT INTO usuarios.usuarios (email, password_hash, nombre, rol, estado)
VALUES ('admin@tutorya.uy', '$2a$10$1LqXWgckjGXCeAS0nUzEbudgkkiEv9N8nDwOgdUmX3t311eqtuVEa',
        'Admin TutorYa', 'ADMIN', 'AUTORIZADO');
