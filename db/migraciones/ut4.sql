-- Migración UT4 para bases creadas con el init.sql de la UT3. Idempotente: se puede correr varias veces.
-- Solo toca esquemas del Núcleo (usuarios, docentes): se ejecuta contra db-nucleo.
--   docker compose exec -T db-nucleo psql -U tutorya -d tutorya -v ON_ERROR_STOP=1 < db/migraciones/ut4.sql

-- ---------- External Configuration Store: rol ADMIN + usuario semilla (password: admin123) ----------
ALTER TABLE usuarios.usuarios DROP CONSTRAINT IF EXISTS usuarios_rol_check;
ALTER TABLE usuarios.usuarios ADD CONSTRAINT usuarios_rol_check
  CHECK (rol IN ('ESTUDIANTE','DOCENTE','VERIFICADOR','ADMIN'));

INSERT INTO usuarios.usuarios (email, password_hash, nombre, rol, estado)
VALUES ('admin@tutorya.uy', '$2a$10$1LqXWgckjGXCeAS0nUzEbudgkkiEv9N8nDwOgdUmX3t311eqtuVEa',
        'Admin TutorYa', 'ADMIN', 'AUTORIZADO')
ON CONFLICT (email) DO NOTHING;

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
