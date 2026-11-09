# UT5 — Eventos sin pérdida: colas durables y Transactional Outbox (PowerShell).
. "$PSScriptRoot\lib.ps1"
Titulo 'Eventos durables y outbox'
function Solicitudes([int]$DocenteId) { Psql db-verificacion "SELECT count(*) FROM verificacion.solicitudes WHERE docente_id=$DocenteId" }

Paso '1. Verificación caída: el registro igual responde y el evento espera en su cola'
docker compose stop verificacion 2>$null | Out-Null
$d1 = Registrar "doc1_$($script:Sufijo)@demo.uy" 'Docente Uno' DOCENTE
Check 'registro con Verificación caída' 201 $script:Codigo
Start-Sleep -Seconds 2
Colas-Rabbit
Check 'evento esperando en verificacion.eventos' 1 (Mensajes-En-Cola 'verificacion.eventos')
Check 'todavía no hay solicitud' 0 (Solicitudes $d1)
docker compose start verificacion 2>$null | Out-Null
[void](Esperar-Hasta 60 { (Solicitudes $d1) -eq '1' })
Check 'al volver, Verificación procesó el evento' 1 (Solicitudes $d1)

Paso '2. RabbitMQ caído: el evento queda en la outbox de Usuarios y se publica al volver'
docker compose stop rabbitmq 2>$null | Out-Null
$d2 = Registrar "doc2_$($script:Sufijo)@demo.uy" 'Docente Dos' DOCENTE
Check 'registro con el broker caído' 201 $script:Codigo
Check 'evento pendiente en usuarios.outbox' 1 (Psql db-usuarios "SELECT count(*) FROM usuarios.outbox WHERE publicado_en IS NULL AND datos->>'docenteId'='$d2'")
docker compose start rabbitmq 2>$null | Out-Null
[void](Esperar-Hasta 90 { (Psql db-usuarios 'SELECT count(*) FROM usuarios.outbox WHERE publicado_en IS NULL') -eq '0' })
[void](Esperar-Hasta 30 { (Solicitudes $d2) -eq '1' })
Check 'outbox vacía' 0 (Psql db-usuarios 'SELECT count(*) FROM usuarios.outbox WHERE publicado_en IS NULL')
Check 'solicitud creada' 1 (Solicitudes $d2)
Esperar-Healthy 90
Resumen
