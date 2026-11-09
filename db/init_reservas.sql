-- TutorYa (UT5) — base del microservicio Reservas (db-reservas). Solo Reservas la lee y escribe.
-- Los ids de estudiante, docente y horario son de otros servicios: sin foreign key, se consultan
-- por SOAP (Usuarios) y REST (Docentes). El pago vive en el servicio Pagos (db-pagos).

CREATE SCHEMA reservas;

-- ---------- Reservas ----------
-- Estados de la saga: PENDIENTE (esperando el pago) -> CONFIRMADA | CANCELADA; CONFIRMADA -> DICTADA.
CREATE TABLE reservas.reservas (
  id              serial PRIMARY KEY,
  estudiante_id   integer NOT NULL,
  docente_id      integer NOT NULL,
  horario_id      integer NOT NULL,
  estado          text NOT NULL CHECK (estado IN ('PENDIENTE','CONFIRMADA','CANCELADA','DICTADA')),
  monto           numeric(10,2) NOT NULL,
  referencia_pago text,
  motivo          text,
  creada_en       timestamptz NOT NULL DEFAULT now()
);

-- Impide la doble reserva del mismo horario, incluso con requests concurrentes. Una reserva
-- CANCELADA (compensación de la saga) libera el horario.
CREATE UNIQUE INDEX reservas_horario_unico ON reservas.reservas (horario_id) WHERE estado <> 'CANCELADA';
CREATE INDEX reservas_pendientes ON reservas.reservas (creada_en) WHERE estado = 'PENDIENTE';

-- UT5 Transactional Outbox: los eventos se guardan en la misma transacción que el cambio de negocio
-- y un relay los publica en RabbitMQ (exchange tutorya.eventos). publicado_en NULL = pendiente.
CREATE TABLE reservas.outbox (
  id           bigserial PRIMARY KEY,
  tipo         text NOT NULL,
  datos        jsonb NOT NULL,
  creado_en    timestamptz NOT NULL DEFAULT now(),
  publicado_en timestamptz
);
CREATE INDEX outbox_pendientes ON reservas.outbox (id) WHERE publicado_en IS NULL;
