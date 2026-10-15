-- TutorYa — base del servicio Núcleo (db-nucleo): un esquema por componente. Las referencias
-- entre esquemas son ids sueltos (sin foreign key cruzada) a propósito: cada componente es dueño de
-- sus datos. El esquema reservas vive en otra base (db-reservas, init_reservas.sql).

CREATE SCHEMA usuarios;
CREATE SCHEMA docentes;
CREATE SCHEMA mensajeria;
CREATE SCHEMA verificacion;

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

-- ---------- UT4 Materialized View: catálogo de docentes APROBADOS precalculado ----------
-- Una fila por docente con sus materias y horarios futuros ya agregados: la búsqueda pasa de
-- 1 + 2N consultas a una sola. Subconsultas correlacionadas (en vez de JOIN materias × horarios)
-- para no generar el producto cartesiano; horarios ordenados por inicio.
-- materias: en minúsculas, para el filtro con el índice GIN. materias_nombres: texto original
-- (la respuesta de la API no cambia).
CREATE MATERIALIZED VIEW IF NOT EXISTS docentes.catalogo AS
SELECT p.usuario_id AS docente_id,
       p.nombre,
       COALESCE((SELECT array_agg(DISTINCT lower(m.materia)) FROM docentes.materias m
                 WHERE m.docente_id = p.usuario_id), '{}') AS materias,
       COALESCE((SELECT array_agg(m.materia ORDER BY m.materia) FROM docentes.materias m
                 WHERE m.docente_id = p.usuario_id), '{}') AS materias_nombres,
       COALESCE((SELECT jsonb_agg(jsonb_build_object('id', h.id, 'inicio', h.inicio, 'fin', h.fin, 'precio', h.precio)
                                  ORDER BY h.inicio, h.id)
                 FROM docentes.horarios h
                 WHERE h.docente_id = p.usuario_id AND h.inicio > now()), '[]') AS horarios
FROM docentes.perfiles p
WHERE p.estado = 'APROBADO';

-- El índice único es requisito de REFRESH ... CONCURRENTLY (no bloquea las lecturas).
CREATE UNIQUE INDEX IF NOT EXISTS catalogo_docente_id ON docentes.catalogo (docente_id);
-- GIN: filtro materias @> ARRAY['matematica'].
CREATE INDEX IF NOT EXISTS catalogo_materias_gin ON docentes.catalogo USING GIN (materias);

-- ---------- Seed ----------
INSERT INTO usuarios.usuarios (email, password_hash, nombre, rol, estado)
VALUES ('verificador@tutorya.uy', '$2a$10$R/DCwQC/P9qOhnuwThaeiuGaLT5G4e1ZeJbVjHgC3nE1Pr20CBiqS',
        'Verificador TutorYa', 'VERIFICADOR', 'AUTORIZADO');

-- UT4: administrador (config, circuitos, métricas). Password: admin123
INSERT INTO usuarios.usuarios (email, password_hash, nombre, rol, estado)
VALUES ('admin@tutorya.uy', '$2a$10$1LqXWgckjGXCeAS0nUzEbudgkkiEv9N8nDwOgdUmX3t311eqtuVEa',
        'Admin TutorYa', 'ADMIN', 'AUTORIZADO');
