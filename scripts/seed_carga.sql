-- Datos de carga para las demos de rendimiento (Cache-Aside y Materialized View):
-- 300 docentes APROBADOS, cada uno con 5 materias (de una lista de 10) y 20 horarios futuros.
-- Se insertan directo por SQL (no por la API). Idempotente: borra y recrea SOLO lo suyo
-- (usuarios carga_*@tutorya.uy y todo lo que cuelga de ellos). Password de todos: clave123.
-- Corre contra db-nucleo: las reservas de estos docentes viven en db-reservas y las borra
-- scripts/cargar_datos.sh antes de ejecutar este archivo.
\set ON_ERROR_STOP on
BEGIN;

CREATE TEMP TABLE carga_ids ON COMMIT DROP AS
  SELECT id FROM usuarios.usuarios WHERE email LIKE 'carga\_%@tutorya.uy';

DELETE FROM mensajeria.mensajes WHERE conversacion_id IN
  (SELECT id FROM mensajeria.conversaciones WHERE docente_id IN (SELECT id FROM carga_ids));
DELETE FROM mensajeria.conversaciones WHERE docente_id IN (SELECT id FROM carga_ids);
DELETE FROM verificacion.solicitudes WHERE docente_id IN (SELECT id FROM carga_ids);
DELETE FROM docentes.horarios WHERE docente_id IN (SELECT id FROM carga_ids);
DELETE FROM docentes.materias WHERE docente_id IN (SELECT id FROM carga_ids);
DELETE FROM docentes.perfiles WHERE usuario_id IN (SELECT id FROM carga_ids);
DELETE FROM usuarios.usuarios WHERE id IN (SELECT id FROM carga_ids);

-- Usuarios + perfiles APROBADOS
WITH nuevos AS (
  INSERT INTO usuarios.usuarios (email, password_hash, nombre, rol, estado)
  SELECT format('carga_%s@tutorya.uy', lpad(i::text, 3, '0')),
         '$2a$10$GWtSXcciviHl7skO9JPBMufY9Yv5Vs2ciwbBmOpTfpqLRa4c1.vDO',
         format('Docente Carga %s', lpad(i::text, 3, '0')), 'DOCENTE', 'AUTORIZADO'
  FROM generate_series(1, 300) AS i
  RETURNING id, nombre
)
INSERT INTO docentes.perfiles (usuario_id, nombre, estado)
SELECT id, nombre, 'APROBADO' FROM nuevos;

CREATE TEMP TABLE carga_docentes ON COMMIT DROP AS
  SELECT usuario_id AS id, row_number() OVER (ORDER BY usuario_id) AS n
  FROM docentes.perfiles p JOIN usuarios.usuarios u ON u.id = p.usuario_id
  WHERE u.email LIKE 'carga\_%@tutorya.uy';

-- La verificación también queda resuelta (datos consistentes entre componentes)
INSERT INTO verificacion.solicitudes (docente_id, estado, resuelta_en)
SELECT id, 'APROBADO', now() FROM carga_docentes;

-- 5 materias distintas por docente: posiciones n, n+2, n+4, n+6, n+8 (mod 10) => cada materia en 150 docentes
INSERT INTO docentes.materias (docente_id, materia)
SELECT d.id,
       (ARRAY['Matematica','Fisica','Quimica','Biologia','Historia',
              'Geografia','Literatura','Ingles','Programacion','Filosofia'])[((d.n + k * 2) % 10) + 1]
FROM carga_docentes d, generate_series(0, 4) AS k;

-- 20 horarios futuros de 1 hora por docente
INSERT INTO docentes.horarios (docente_id, inicio, fin, precio)
SELECT d.id,
       date_trunc('day', now()) + (k + 1) * interval '1 day' + (8 + d.n % 10) * interval '1 hour',
       date_trunc('day', now()) + (k + 1) * interval '1 day' + (9 + d.n % 10) * interval '1 hour',
       300 + (d.n * 7 + k * 13) % 700
FROM carga_docentes d, generate_series(0, 19) AS k;

COMMIT;

-- Refresca el catálogo materializado si existe (UT4, Materialized View)
DO $$
BEGIN
  IF to_regclass('docentes.catalogo') IS NOT NULL THEN
    EXECUTE 'REFRESH MATERIALIZED VIEW docentes.catalogo';
  END IF;
END $$;

SELECT count(DISTINCT p.usuario_id) AS docentes, count(h.id) AS horarios
FROM docentes.perfiles p JOIN usuarios.usuarios u ON u.id = p.usuario_id
LEFT JOIN docentes.horarios h ON h.docente_id = p.usuario_id
WHERE u.email LIKE 'carga\_%@tutorya.uy';
