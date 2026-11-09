# UT5 — Microservicios: un caso de uso que cruza los seis servicios (PowerShell).
. "$PSScriptRoot\lib.ps1"
Titulo 'Microservicios: un caso de uso de punta a punta'

Paso '1. Topología: un contenedor por servicio y una base por servicio'
$corriendo = @(docker compose ps --services --status running 2>$null)
$corriendo | Sort-Object | ForEach-Object { Info $_ }
Check '6 microservicios corriendo' 6 @($corriendo | Where-Object { $_ -match '^(usuarios|docentes|mensajeria|verificacion|reservas|pagos)$' }).Count
Check '6 bases de datos (una por servicio)' 6 @($corriendo | Where-Object { $_ -like 'db-*' }).Count

Paso '2. Registro de un docente en Usuarios: responde sin esperar a Docentes ni a Verificación'
$emailDoc = "doc_$($script:Sufijo)@demo.uy"
$docId = Registrar $emailDoc 'Docente Demo' DOCENTE
Check 'registro (Usuarios)' 201 $script:Codigo
Info 'docente.registrado quedó en la outbox de Usuarios; el relay lo publica en RabbitMQ'

Paso '3. Docentes y Verificación reaccionan al evento (consistencia eventual)'
$docTok = Login $emailDoc
$hayPerfil = Esperar-Hasta 20 { (Codigo-De GET /api/docentes/me $null $docTok) -eq '200' }
Check 'perfil creado en Docentes' True $hayPerfil
Aprobar-Docente $docId
Check 'solicitud aprobada en Verificación' 200 $script:Codigo

Paso '4. El docente carga materia y horario (Docentes)'
[void](Req PUT /api/docentes/me/materias @{ materias = @('Fisica') } $docTok)
$h = Req POST /api/docentes/me/horarios @{ inicio = (Fecha-Futura 3 10); fin = (Fecha-Futura 3 11); precio = 500 } $docTok
Check 'horario creado' 201 $script:Codigo

Paso '5. Un estudiante busca (Docentes), escribe (Mensajería) y reserva (Reservas)'
$estTok = Estudiante-Demo
$enCatalogo = Esperar-Hasta 30 { @(Req GET '/api/docentes?materia=Fisica' $null $estTok -Silencioso | Where-Object { $_.id -eq $docId }).Count -gt 0 }
Check 'docente aprobado visible en el catálogo' True $enCatalogo
$msj = Esperar-Hasta 20 { (Codigo-De POST /api/mensajes @{ docenteId = $docId; texto = 'Hola, ¿das clases de física?' } $estTok) -eq '201' }
Check 'mensaje enviado (Mensajería usa su copia de docentes habilitados)' True $msj
$r = Req POST /api/reservas @{ docenteId = $docId; horarioId = $h.id; tokenPago = 'tok_ok' } $estTok
Check 'reserva confirmada (SOAP a Usuarios + REST a Docentes y Pagos)' 201 $script:Codigo
Check 'estado de la reserva' CONFIRMADA $r.reserva.estado

Paso '6. Colas de RabbitMQ (una por servicio suscriptor)'
Colas-Rabbit
Resumen
