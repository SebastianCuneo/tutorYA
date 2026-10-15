-- TutorYa — base del servicio Reservas (db-reservas). Los ids de estudiante, docente y horario
-- son de Núcleo (db-nucleo): sin foreign key cruzada, Reservas los consulta por HTTP.

CREATE SCHEMA reservas;

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

