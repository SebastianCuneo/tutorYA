-- TutorYa (UT5) — base del microservicio Pagos (db-pagos). Solo Pagos la lee y escribe.
-- reserva_id es la clave de idempotencia: un reintento del mismo cobro no cobra dos veces.

CREATE SCHEMA pagos;

CREATE TABLE pagos.pagos (
  id         serial PRIMARY KEY,
  reserva_id integer NOT NULL UNIQUE,
  monto      numeric(10,2) NOT NULL,
  estado     text NOT NULL CHECK (estado IN ('APROBADO','RECHAZADO','REEMBOLSADO')),
  referencia text,
  motivo     text,
  creado_en  timestamptz NOT NULL DEFAULT now()
);
