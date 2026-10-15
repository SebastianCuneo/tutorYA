# TutorYa — API REST (TFU UT3 + UT4, ANDIS II, UCU)

Plataforma que conecta estudiantes con docentes particulares. Implementación de la arquitectura
del grupo: 5 componentes lógicos, 2 servicios desplegables, gateway Nginx y PostgreSQL 16.

## Requisitos

Docker con Compose v2, y para los scripts de demo: `bash`, `curl` (>= 7.84), `jq`, `perl` y `openssl`.

## Cómo levantar

```bash
docker compose up -d --build     # certs (one-shot), redis, db, 2 réplicas de nucleo, 2 de reservas y nginx
curl -k https://localhost:8443/api/salud
```

El gateway publica `8443` (HTTPS) y `8080` (HTTP, redirige a HTTPS). Si están ocupados, copiá
`.env.example` a `.env` y cambiá `GATEWAY_TLS_PORT` / `GATEWAY_PORT` (los scripts los leen de ahí).
El certificado es autofirmado (lo genera el servicio `certs` en `nginx/certs/`, que no se commitea):
usá `curl -k` y, en Postman, la colección ya trae la verificación SSL desactivada.
Para borrar todo, incluidas la base y Redis: `docker compose down -v`.

**Base creada con la UT3** (volumen `pgdata` previo): `init.sql` solo corre en una base vacía. Para
agregar el rol ADMIN y la vista materializada sin perder datos (idempotente):

```bash
docker compose exec -T db psql -U tutorya -d tutorya -v ON_ERROR_STOP=1 < db/migraciones/ut4.sql
```

## Arquitectura

```
                 red "borde"            │ red "interna" (internal: true, sin puertos publicados)
cliente ─HTTPS─▶ nginx :443 (TLS) ──────┼─┬─ /api/reservas → reservas ×N ──HTTP+circuito──▶ nucleo /internal/...
        ─HTTP──▶ nginx :80 → 301 HTTPS  │ └─ /api/*        → nucleo ×N  ──HTTP+circuito──▶ reservas /internal/...
                                        │        │  │
                                        │        │  └── Redis: config:tutorya (config), catalogo:* (caché),
                                        │        │      canales config:cambios y reservas:eventos
                                        │        └───── PostgreSQL (esquemas usuarios, docentes, mensajeria,
                                        │               verificacion, reservas; vista docentes.catalogo)
```

| Carpeta | Componente del UML |
|---|---|
| `nucleo/src/usuarios/` | Usuarios |
| `nucleo/src/docentes/` | Docentes |
| `nucleo/src/mensajeria/` | Mensajería |
| `nucleo/src/verificacion/` | Verificación |
| `nucleo/src/eventos.js` | Bus de eventos en proceso del Núcleo |
| `reservas/src/` | Reservas (`pagos/simulador.js` = pasarela simulada) |
| `comun/` | Biblioteca compartida: JWT + rol, errores JSON, logger, `X-Instancia`, pool de PostgreSQL, y en la UT4: config, Redis, circuit breaker, salud y `X-Request-Id` |
| `nucleo/src/admin/` | Endpoints operativos (rol ADMIN): config, circuitos, métricas |
| `config/default.json` | Valores por defecto de la config externa |
| `db/init.sql` | Esquemas, vista materializada y seed |
| `db/migraciones/ut4.sql` | Migración UT4 para bases ya creadas |
| `nginx/templates/nginx.conf.template` | Gateway (plantilla procesada con envsubst) |

Cada módulo tiene `index.js` (interfaz pública, comentada con `// Interfaz: <Nombre> (HUx)`),
`rutas.js`, `servicio.js` y `repositorio.js`. Un módulo solo consulta su propio esquema y usa a
otro únicamente a través de su `index.js`. Reservas ↔ Núcleo solo por HTTP interno.

## Endpoints

| Método | Ruta | Interfaz (HU) | Rol |
|---|---|---|---|
| POST | `/api/usuarios/registro` | AutenticarUsuario (HU1, HU7) | público |
| POST | `/api/usuarios/login` | AutenticarUsuario | público |
| POST | `/api/autorizaciones/:token` | AutorizarMenor (HU2) | público |
| GET | `/api/docentes?materia=` | BuscarDocentes (HU3) | ESTUDIANTE |
| GET | `/api/docentes/me` | GestionarPerfilDocente (HU8) | DOCENTE |
| PUT | `/api/docentes/me/materias` | GestionarPerfilDocente (HU8) | DOCENTE |
| POST | `/api/docentes/me/horarios` | GestionarPerfilDocente (HU8) | DOCENTE |
| POST | `/api/mensajes` | EnviarMensaje (HU4) | ESTUDIANTE |
| GET | `/api/conversaciones` | — | ESTUDIANTE, DOCENTE |
| GET | `/api/conversaciones/:id/mensajes` | — | participantes |
| POST | `/api/conversaciones/:id/mensajes` | ResponderMensaje (HU9) | DOCENTE |
| GET | `/api/verificaciones?estado=` | VerificarDocente (HU10) | VERIFICADOR |
| POST | `/api/verificaciones/:id/llamada` | VerificarDocente | VERIFICADOR |
| POST | `/api/verificaciones/:id/resolucion` | VerificarDocente | VERIFICADOR |
| POST | `/api/reservas` | ReservarClase (HU5, HU6) | ESTUDIANTE |
| GET | `/api/reservas`, `/api/reservas/:id` | — | participantes |
| PATCH | `/api/reservas/:id/dictada` | ConfirmarClaseDictada (HU11) | DOCENTE dueño |
| GET | `/api/salud`, `/api/reservas/salud` | — | público |
| GET | `/internal/usuarios/:id/estado` | ConsultarEstadoEstudiante | interno |
| GET | `/internal/docentes/:docenteId/horarios/:horarioId` | ConsultarDisponibilidad | interno |
| GET | `/internal/reservas/horarios-ocupados?docenteId=` | (uso interno) | interno |

Los `/internal/*` no se exponen por Nginx (404). Errores: `{ "error": { "codigo", "mensaje" } }` con
400, 401, 402, 403, 404, 409, 410 (y 503 en la UT4). Usuarios semilla: `verificador@tutorya.uy` /
`verificador123` y `admin@tutorya.uy` / `admin123`. Colección Postman en `postman/` (variables
`{{baseUrl}}` y `{{token}}`; los endpoints nuevos están en la carpeta "UT4").

## Demos

Cada script imprime requests, códigos HTTP y un veredicto ✅/❌; se pueden re-ejecutar.

Todas las demos (UT3 y UT4) van por HTTPS: `BASE=https://localhost:${GATEWAY_TLS_PORT:-8443}`.

```bash
./scripts/demo_componentes.sh    # flujo completo por las interfaces
./scripts/demo_escalabilidad.sh  # --scale reservas=3 nucleo=2 y reparto por X-Instancia
./scripts/demo_sin_estado.sh     # cae la réplica que atendió; el mismo token sigue valiendo
./scripts/demo_acid.sh           # doble reserva concurrente, pago rechazado, durabilidad
```

## Decisiones de implementación (UT3)

- **Nombres de interfaz** en camelCase (`consultarDisponibilidad`, `autorizarMenor`, ...).
- **Reparto de carga**: Nginx resuelve `reservas`/`nucleo` con el DNS de Docker en cada pedido
  (`resolver 127.0.0.11 valid=5s` + `proxy_pass` con variable), así que ve las réplicas nuevas
  ~5 s después de un `--scale` sin reiniciarlo. El orden de IPs lo rota Docker, por lo que el
  reparto es aleatorio-parejo y no round-robin estricto (este último requiere `upstream ... resolve`,
  exclusivo de Nginx Plus).
- **Eventos**: `eventos.emitir` espera a todos los suscriptores antes de responder. No hay
  transacción entre esquemas: si falla la creación del perfil, el usuario ya quedó creado.
- **`linkAutorizacion`** apunta a `POST /api/autorizaciones/:token` (es un POST, no un link de navegador).
- **Menor pendiente** puede loguearse y mensajear; solo se le bloquea la reserva (403).
- **Búsqueda** ofrece solo horarios futuros y no ocupados; si Reservas no responde, devuelve todos con
  `disponibilidadVerificada: false` (por docente).
- **Mensajería** a un docente inexistente o no aprobado responde 404.
- **Rutas `/internal`** sin autenticación: solo son alcanzables dentro de la red de Docker.
- **Reservas**: si el núcleo no responde, 503 (nunca se permite reservar). Los campos de las
  reservas se devuelven tal cual las columnas (`estudiante_id`, ...).
- **Dependencias**: cada imagen instala `comun/` (npm ci) y el servicio; hay un `package-lock.json` por carpeta.
- **Puerto del host** configurable con `GATEWAY_PORT` (por defecto 8080).

---

## UT4 — Patrones

Siete patrones sobre la misma arquitectura de la UT3. La única infraestructura nueva es un
contenedor `redis:7-alpine`, que se usa como caché y como almacén de configuración.

### Patrones → archivos

| Grupo | Patrón | Archivos principales |
|---|---|---|
| Modificabilidad | **External Configuration Store** | `comun/src/config.js`, `comun/src/redis.js`, `config/default.json`, `nucleo/src/admin/rutas.js` |
| Disponibilidad | **Circuit Breaker** | `comun/src/circuitBreaker.js`, `reservas/src/clienteNucleo.js`, `reservas/src/servicio.js`, `nucleo/src/docentes/servicio.js` |
| Disponibilidad | **Health Endpoint Monitoring** | `comun/src/salud.js`, `nucleo/src/app.js`, `reservas/src/app.js`, `*/Dockerfile` (HEALTHCHECK), Nginx (`proxy_next_upstream`) |
| Rendimiento | **Cache-Aside** | `nucleo/src/docentes/cache.js`, `nucleo/src/docentes/servicio.js` y `rutas.js` (`X-Cache`), `reservas/src/servicio.js` (evento `reserva.creada`) |
| Rendimiento | **Materialized View** | `db/init.sql`, `db/migraciones/ut4.sql`, `nucleo/src/docentes/repositorio.js` (`buscarEnCatalogo`, `refrescarCatalogo`), `reservas/src/rutas.js` (`?docenteIds=`) |
| Seguridad | **Gatekeeper** | `docker-compose.yaml` (redes `borde`/`interna`), `nginx/templates/nginx.conf.template` |
| Seguridad | **Gateway Offloading** | `nginx/templates/nginx.conf.template` (TLS, cabeceras, gzip, log JSON), servicio `certs`, `comun/src/contexto.js` (`X-Request-Id`) |

### Endpoints nuevos

| Método | Ruta | Servicio | Rol | Patrón |
|---|---|---|---|---|
| GET | `/api/admin/config` → `{ version, valores }` | núcleo | ADMIN | External Configuration Store |
| PUT | `/api/admin/config` body `{ "cache.habilitado": false, ... }` → `{ version }` (400 si es inválido) | núcleo | ADMIN | External Configuration Store |
| GET | `/api/circuitos` | núcleo | ADMIN | Circuit Breaker |
| GET | `/api/reservas/circuitos` | reservas | ADMIN | Circuit Breaker |
| GET | `/api/salud/listo`, `/api/reservas/salud/listo` → 200 OK / 503 DEGRADADO | ambos | público | Health Endpoint Monitoring |
| GET | `/api/metricas` → `{ cache: {hits, misses, bypass, tasaAciertos}, circuitos }` | núcleo | ADMIN | Cache-Aside |
| POST | `/internal/fallas/degradar`, `/internal/fallas/restaurar` | ambos | interno | Health (inyección de fallas) |
| GET | `/internal/reservas/horarios-ocupados?docenteIds=1,2,3` → `{ ocupados: { "1": [ids] } }` | reservas | interno | Materialized View |

Cambios en los existentes:
- `/api/salud` y `/api/reservas/salud` agregan `version` (`APP_VERSION`), `configVersion` y `configAplicadaEn`.
- `GET /api/docentes` agrega la cabecera `X-Cache: HIT | MISS | BYPASS`; el cuerpo no cambia.
- Todas las respuestas del gateway traen `X-Request-Id` y las cabeceras de seguridad.

Claves de configuración (`config/default.json`, sobrescribibles con `CFG_<CLAVE>`, p. ej.
`CFG_CACHE_HABILITADO=false`): `circuitBreaker.{habilitado,umbral,ventanaMs,esperaMs}`,
`http.timeoutMs`, `cache.{habilitado,catalogoTtlSeg}`, `catalogo.{fuente,refrescoSeg}`,
`salud.timeoutChequeoMs`, `log.nivel`.

### Demos UT4

Cada script imprime los pasos, cada request con su código, las métricas y un veredicto ✅/❌, y al
final deja todo como estaba (config por defecto, contenedores reanudados, réplicas restauradas).

```bash
./scripts/demo_config.sh                # PUT de config y propagación a todas las réplicas sin reiniciar
./scripts/demo_circuit_breaker.sh       # núcleo congelado: timeout sin circuito vs 503 inmediato con circuito
./scripts/demo_health.sh                # réplica degradada fuera de rotación; base congelada => readiness 503
./scripts/demo_cache.sh                 # p50/p95 sin y con caché, tasa de aciertos, invalidación
./scripts/demo_materialized_view.sh     # EXPLAIN ANALYZE y p50/p95 tablas vs vista, frescura al aprobar
./scripts/demo_gatekeeper.sh            # solo Nginx expone puertos; 404/405/413 en JSON
./scripts/demo_gateway_offloading.sh    # HTTPS, 301, cabeceras, X-Request-Id en los logs, gzip, TLS
./scripts/demo_todo.sh                  # las 11 demos (UT3 + UT4) en orden; salidas en scripts/salidas/
./scripts/cargar_datos.sh               # (lo usan cache y materialized_view) 300 docentes de carga por SQL
```

### Decisiones de implementación UT4

**External Configuration Store**
- Hash `config:tutorya`: un campo por clave (valor JSON) y un campo `version`. Se siembra con
  `HSETNX` campo por campo, así no hay carrera entre réplicas y las claves nuevas del default se
  agregan solas. `PUT` valida todo antes de escribir (todo o nada) y hace `HSET` + `HINCRBY` en un
  `MULTI`, y después el `PUBLISH`.
- Redis corre con AOF y un volumen (`redisdata`), así la config sobrevive a un reinicio de Redis.
- Los endpoints de salud informan también `configAplicadaEn`: `demo_config.sh` mide con eso la
  propagación real entre réplicas, además del tiempo observado desde afuera (que incluye los `docker exec`).
- El nivel de log lo aplica `config.js` sobre el logger (`logger.setNivel`), sin dependencia circular.

**Circuit Breaker**
- Un circuito por réplica y por dependencia: `nucleo` en Reservas y `reservas` en el Núcleo. Con
  `circuitBreaker.habilitado=false` es un passthrough que no cuenta fallas.
- Las respuestas 5xx se devuelven al llamador (que decide), pero cuentan como falla del circuito.
- En la demo se usa **1 réplica de reservas** durante la prueba. El estado del circuito es por
  réplica y Nginx reparte casi al azar (ver decisiones de la UT3), así que con 2 réplicas el momento
  en que cada una abre no es determinístico. Al final se vuelve a 2.
- La demo descongela el núcleo un momento para rehabilitar el circuito: el `PUT /api/admin/config`
  vive en el Núcleo.

**Health Endpoint Monitoring**
- El endpoint de readiness siempre evalúa en el momento. El middleware que bloquea `/api/*`
  reutiliza la última evaluación durante 2 s. Nunca hay más de una evaluación en curso por réplica,
  y un chequeo colgado (base congelada) no se vuelve a disparar hasta que termina, así que no agota el pool.
- Los endpoints de salud **no** se reintentan en Nginx (`proxy_next_upstream off`): informan el
  estado de la réplica que respondió y no esperan el timeout de cada réplica.
- Nginx no reintenta un `POST` que recibió 503 (`non_idempotent` está apagado a propósito). Con
  una réplica degradada, los `GET` se desvían solos y los `POST` pueden recibir 503
  `REPLICA_DEGRADADA` (el cliente reintenta).
- El demo consulta la readiness de una réplica con `node -e fetch(...)` dentro del contenedor (helper
  `interno` de `lib.sh`). `wget` de busybox no muestra el código ni el cuerpo de una respuesta 503.

**Cache-Aside**
- La clave es `catalogo:<materia en minúsculas | _todas>` y guarda la respuesta ya filtrada por
  horarios ocupados. Cualquier cambio de docentes o una reserva nueva borra `catalogo:*` con `SCAN`.
- Reservas publica `reserva.creada` en `reservas:eventos` después del COMMIT; si Redis no está, la
  reserva igual queda hecha (la caché vence por TTL). Solo el Núcleo borra claves del catálogo.
- El cliente Redis usa `disableOfflineQueue` y un timeout de 500 ms por operación: con Redis caído o
  lento la búsqueda responde `BYPASS` en vez de colgarse.
- Las métricas son en memoria por réplica. La tasa de aciertos es `hits / (hits + misses)` (el
  bypass no cuenta) y la demo suma las de todas las réplicas.

**Materialized View**
- SQL ajustado: subconsultas correlacionadas en vez de `LEFT JOIN` materias × horarios (evita el
  producto cartesiano), horarios ordenados por `inicio`, y una columna extra `materias_nombres` con
  el texto original para que la respuesta no cambie. `materias` (en minúsculas) queda para el filtro
  GIN. Se mantienen el índice único (requisito de `CONCURRENTLY`) y el GIN.
- Al leer de la vista se descartan los horarios que pasaron desde el último refresco y las fechas se
  normalizan al mismo formato que el camino por tablas. La demo verifica que ambas respuestas son idénticas.
- Refresco: **primero refrescar, después invalidar** la caché. El refresco por evento usa
  `pg_advisory_lock` (espera): con `pg_try_advisory_lock` se perdería el cambio recién commiteado si
  otra réplica justo estaba refrescando. El refresco periódico (`catalogo.refrescoSeg`) usa
  `pg_try_advisory_lock` y, si está ocupado, saltea la vuelta. En ambos casos, dos réplicas nunca
  refrescan a la vez. El refresco por evento se hace dentro del request: el cambio se ve de inmediato.
- `reserva.creada` solo invalida la caché, sin refrescar la vista: la vista no contiene reservas
  (los ocupados los sigue informando Reservas).
- Horarios ocupados: una sola llamada por búsqueda (`?docenteIds=`), también en el camino por tablas.

**Gatekeeper**
- La red `interna` es `internal: true`: los servicios no tienen salida a internet. `certs` va en
  `borde` porque necesita instalar `openssl`.
- Además de lo pedido, los errores 400 (cabeceras demasiado grandes), 408, 414 y 502/504 generados
  por Nginx también salen en JSON. Los errores de los servicios pasan tal cual (`proxy_intercept_errors off`).
- En el demo, la verificación de puertos chequea que ningún contenedor de TutorYa los publique y que
  lo que responda ahí no sea TutorYa: en una máquina de desarrollo el 3000/5432/6379 pueden estar
  ocupados por otros proyectos.

**Gateway Offloading**
- `nginx.conf` pasó a `nginx/templates/nginx.conf.template`, procesado por el envsubst de la imagen
  oficial con `NGINX_ENVSUBST_OUTPUT_DIR=/etc/nginx` y `NGINX_ENVSUBST_FILTER=^GATEWAY_`, así que
  solo se reemplaza `${GATEWAY_TLS_PORT}`. Se monta la carpeta y no un archivo suelto: un bind mount
  de archivo deja de ver los cambios cuando el editor reemplaza el archivo.
- `X-Request-Id` también se agrega a todas las respuestas, igual que las cabeceras de seguridad. Si
  el cliente manda uno, Nginx lo reemplaza por `$request_id`.
- El demo prueba las versiones de TLS con `curlimages/curl` en la red `borde`: el `curl` de macOS
  (SecureTransport) no permite elegir TLS 1.3.
