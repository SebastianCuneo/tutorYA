-- TutorYa (UT5) — base del microservicio Docentes (db-docentes). Solo Docentes la lee y escribe.
-- Los ids de otros servicios son ids sueltos, sin foreign key: cada servicio es dueño de sus datos.

CREATE SCHEMA docentes;

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

