-- TutorYa (UT5) — base del microservicio Verificación (db-verificacion). Solo Verificación la lee y escribe.
-- Los ids de otros servicios son ids sueltos, sin foreign key: cada servicio es dueño de sus datos.

CREATE SCHEMA verificacion;

-- ---------- Verificación ----------
CREATE TABLE verificacion.solicitudes (
  id             serial PRIMARY KEY,
  docente_id     integer UNIQUE NOT NULL,
  estado         text NOT NULL CHECK (estado IN ('PENDIENTE','LLAMADA_AGENDADA','APROBADO','RECHAZADO')),
  llamada_en     timestamptz,
  verificador_id integer,
  resuelta_en    timestamptz
);


-- UT5 Transactional Outbox: los eventos se guardan en la misma transacción que el cambio de negocio
-- y un relay los publica en RabbitMQ (exchange tutorya.eventos). publicado_en NULL = pendiente.
CREATE TABLE verificacion.outbox (
  id           bigserial PRIMARY KEY,
  tipo         text NOT NULL,
  datos        jsonb NOT NULL,
  creado_en    timestamptz NOT NULL DEFAULT now(),
  publicado_en timestamptz
);
CREATE INDEX outbox_pendientes ON verificacion.outbox (id) WHERE publicado_en IS NULL;
