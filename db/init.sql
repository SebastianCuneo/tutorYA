-- TutorYa: un esquema por componente. Las referencias entre esquemas son ids sueltos
-- (sin foreign key cruzada) a propósito: cada componente es dueño de sus datos.

CREATE SCHEMA usuarios;
CREATE SCHEMA docentes;
CREATE SCHEMA mensajeria;
CREATE SCHEMA verificacion;
CREATE SCHEMA reservas;

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

-- ---------- Docentes ----------
CREATE TABLE docentes.perfiles (
  usuario_id integer PRIMARY KEY,
  nombre     text NOT NULL,
  estado     text NOT NULL CHECK (estado IN ('PENDIENTE_VERIFICACION','APROBADO','RECHAZADO'))
);

CREATE TABLE docentes.materias (
  docente_id integer NOT NULL REFERENCES docentes.perfiles(usuario_id),
  materia    text NOT NULL,
  PRIMARY KEY (docente_id, materia)
);

CREATE TABLE docentes.horarios (
  id         serial PRIMARY KEY,
  docente_id integer NOT NULL REFERENCES docentes.perfiles(usuario_id),
  inicio     timestamptz NOT NULL,
  fin        timestamptz NOT NULL,
  precio     numeric(10,2) NOT NULL CHECK (precio >= 0),
  CHECK (fin > inicio)
);

-- ---------- Mensajería ----------
CREATE TABLE mensajeria.conversaciones (
  id            serial PRIMARY KEY,
  estudiante_id integer NOT NULL,
  docente_id    integer NOT NULL,
  UNIQUE (estudiante_id, docente_id)
);

CREATE TABLE mensajeria.mensajes (
  id              serial PRIMARY KEY,
  conversacion_id integer NOT NULL REFERENCES mensajeria.conversaciones(id),
  autor_id        integer NOT NULL,
  texto           text NOT NULL,
  enviado_en      timestamptz NOT NULL DEFAULT now()
);

-- ---------- Verificación ----------
CREATE TABLE verificacion.solicitudes (
  id             serial PRIMARY KEY,
  docente_id     integer UNIQUE NOT NULL,
  estado         text NOT NULL CHECK (estado IN ('PENDIENTE','LLAMADA_AGENDADA','APROBADO','RECHAZADO')),
  llamada_en     timestamptz,
  verificador_id integer,
  resuelta_en    timestamptz
);

-- ---------- Reservas ----------
CREATE TABLE reservas.reservas (
  id            serial PRIMARY KEY,
  estudiante_id integer NOT NULL,
  docente_id    integer NOT NULL,
  horario_id    integer NOT NULL,
  estado        text NOT NULL CHECK (estado IN ('CONFIRMADA','DICTADA')),
  monto         numeric(10,2) NOT NULL,
  creada_en     timestamptz NOT NULL DEFAULT now(),
  -- Impide la doble reserva del mismo horario, incluso con requests concurrentes.
  CONSTRAINT reservas_horario_unico UNIQUE (horario_id)
);

CREATE TABLE reservas.pagos (
  id         serial PRIMARY KEY,
  reserva_id integer NOT NULL UNIQUE REFERENCES reservas.reservas(id),
  monto      numeric(10,2) NOT NULL,
  referencia text NOT NULL,
  pagado_en  timestamptz NOT NULL DEFAULT now()
);

-- ---------- Seed ----------
INSERT INTO usuarios.usuarios (email, password_hash, nombre, rol, estado)
VALUES ('verificador@tutorya.uy', '$2a$10$R/DCwQC/P9qOhnuwThaeiuGaLT5G4e1ZeJbVjHgC3nE1Pr20CBiqS',
        'Verificador TutorYa', 'VERIFICADOR', 'AUTORIZADO');

-- UT4: administrador (config, circuitos, métricas). Password: admin123
INSERT INTO usuarios.usuarios (email, password_hash, nombre, rol, estado)
VALUES ('admin@tutorya.uy', '$2a$10$1LqXWgckjGXCeAS0nUzEbudgkkiEv9N8nDwOgdUmX3t311eqtuVEa',
        'Admin TutorYa', 'ADMIN', 'AUTORIZADO');
