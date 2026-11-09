-- TutorYa (UT5) — base del microservicio Mensajería (db-mensajeria). Solo Mensajería la lee y escribe.
-- Los ids de otros servicios son ids sueltos, sin foreign key: cada servicio es dueño de sus datos.

CREATE SCHEMA mensajeria;

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

-- UT5: copia local de los docentes APROBADOS, alimentada por el evento docente.verificado.
-- Mensajería la usa para validar a quién se puede escribir sin llamar a Docentes.
CREATE TABLE mensajeria.docentes_habilitados (
  docente_id    integer PRIMARY KEY,
  actualizado_en timestamptz NOT NULL DEFAULT now()
);
