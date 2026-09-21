# TutorYa — API REST (TFU UT3, ANDIS II, UCU)

Plataforma que conecta estudiantes con docentes particulares. Implementación de la arquitectura
del grupo: 5 componentes lógicos, 2 servicios desplegables, gateway Nginx y PostgreSQL 16.

## Requisitos

Docker con Compose v2, `bash`, `curl` y `jq` (estos tres últimos, para los scripts de demo).

## Cómo levantar

```bash
docker compose up -d --build     # 2 réplicas de nucleo, 2 de reservas, db y nginx
curl localhost:8080/api/salud
```

El gateway publica el puerto `8080`. Si está ocupado en tu máquina, copiá `.env.example` a `.env`
y definí `GATEWAY_PORT=8090` (los scripts lo leen de ahí). Para borrar todo, incluida la base:
`docker compose down -v`.

## Arquitectura

```
cliente → nginx :8080 ─┬─ /api/reservas → reservas ×N ──HTTP──▶ nucleo /internal/...
                       └─ /api/*        → nucleo ×N  ──HTTP──▶ reservas /internal/...
                                            └── PostgreSQL (esquemas usuarios, docentes,
                                                mensajeria, verificacion, reservas)
```

| Carpeta | Componente del UML |
|---|---|
| `nucleo/src/usuarios/` | Usuarios |
| `nucleo/src/docentes/` | Docentes |
| `nucleo/src/mensajeria/` | Mensajería |
| `nucleo/src/verificacion/` | Verificación |
| `nucleo/src/eventos.js` | Bus de eventos en proceso del Núcleo |
| `reservas/src/` | Reservas (`pagos/simulador.js` = pasarela simulada) |
| `comun/` | Biblioteca compartida: JWT + rol, errores JSON, logger, `X-Instancia`, pool de PostgreSQL |
| `db/init.sql` | Esquemas y seed |
| `nginx/nginx.conf` | Gateway |

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
400, 401, 402, 403, 404, 409, 410. Usuario semilla: `verificador@tutorya.uy` / `verificador123`.
Colección Postman en `postman/` (variables `{{baseUrl}}` y `{{token}}`).

## Demos

Cada script imprime requests, códigos HTTP y un veredicto ✅/❌; se pueden re-ejecutar.

```bash
./scripts/demo_componentes.sh    # flujo completo por las interfaces
./scripts/demo_escalabilidad.sh  # --scale reservas=3 nucleo=2 y reparto por X-Instancia
./scripts/demo_sin_estado.sh     # cae la réplica que atendió; el mismo token sigue valiendo
./scripts/demo_acid.sh           # doble reserva concurrente, pago rechazado, durabilidad
```

## Decisiones de implementación

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
