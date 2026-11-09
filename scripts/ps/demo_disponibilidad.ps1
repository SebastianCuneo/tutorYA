# UT5 — Validación del atributo de calidad: DISPONIBILIDAD (PowerShell).
# Escenario: falla el proceso que ejecuta un componente de dominio (por defecto, Mensajería).
#   UT5: se detiene ese contenedor.  UT4: Mensajería vive dentro de "nucleo", así que se detiene "nucleo".
# Se mide el % de pedidos exitosos (2xx) de seis operaciones ANTES y DURANTE la falla.
# Uso: .\scripts\ps\demo_disponibilidad.ps1 [-Componente mensajeria|docentes|verificacion|usuarios] [-N 10]
param([string]$Componente = 'mensajeria', [int]$N = 10)
. "$PSScriptRoot\lib.ps1"

$servicios = @(docker compose config --services 2>$null)
if ($servicios -contains 'nucleo') { $Arq = 'ut4'; $Contenedor = if ($Componente -eq 'reservas') { 'reservas' } else { 'nucleo' } }
else { $Arq = 'ut5'; $Contenedor = $Componente }
Titulo "Disponibilidad ($Arq): falla de $Componente => se detiene '$Contenedor'"

Paso "Preparación: docente aprobado con $(2 * $N + 2) horarios, estudiante y verificador"
$doc = Preparar-Docente (2 * $N + 2)
$estTok = Estudiante-Demo
$verTok = Login 'verificador@tutorya.uy' 'verificador123'
[void](Esperar-Hasta 30 { @(Req GET '/api/docentes?materia=Fisica' $null $estTok -Silencioso | Where-Object { $_.id -eq $doc.Id }).Count -gt 0 })
[void](Esperar-Hasta 20 { (Codigo-De POST /api/mensajes @{ docenteId = $doc.Id; texto = 'hola' } $estTok) -eq '201' })
Info "docente $($doc.Id), $($doc.Horarios.Count) horarios"

$script:H = 0
$Operaciones = 'login', 'buscar', 'mensaje', 'verificacion', 'reservar', 'mis_reservas'
$Dueno = @{ login = 'Usuarios'; buscar = 'Docentes'; mensaje = 'Mensajería'; verificacion = 'Verificación'; reservar = 'Reservas'; mis_reservas = 'Reservas' }
function Operacion([string]$Op) {
  switch ($Op) {
    'login' { return Codigo-De POST /api/usuarios/login @{ email = "est_$($script:Sufijo)@demo.uy"; password = 'clave123' } }
    'buscar' { return Codigo-De GET '/api/docentes?materia=Fisica' $null $estTok }
    'mensaje' { return Codigo-De POST /api/mensajes @{ docenteId = $doc.Id; texto = 'consulta' } $estTok }
    'verificacion' { return Codigo-De GET /api/verificaciones $null $verTok }
    'reservar' {
      $c = Codigo-De POST /api/reservas @{ docenteId = $doc.Id; horarioId = $doc.Horarios[$script:H]; tokenPago = 'tok_ok' } $estTok
      if ($c -like '2*') { $script:H++ }
      return $c
    }
    'mis_reservas' { return Codigo-De GET /api/reservas $null $estTok }
  }
}
function Fase {
  $oks = @{}; foreach ($op in $Operaciones) { $oks[$op] = 0 }
  for ($r = 1; $r -le $N; $r++) {
    foreach ($op in $Operaciones) { if ((Operacion $op) -like '2*') { $oks[$op]++ } }
  }
  $pct = @{}; foreach ($op in $Operaciones) { $pct[$op] = [int]($oks[$op] * 100 / $N) }
  return $pct
}

Paso "Fase 1: todo sano ($N pedidos por operación)"
$Antes = Fase

Paso "Fase 2: docker compose stop $Contenedor"
docker compose stop $Contenedor 2>$null | Out-Null
Start-Sleep -Seconds 6   # el DNS del gateway (valid=5s) deja de devolver el contenedor detenido
$Durante = Fase

Paso "Restaurando $Contenedor"
docker compose start $Contenedor 2>$null | Out-Null
Esperar-Healthy 120
Start-Sleep -Seconds 16  # DNS del gateway y circuitos (15 s) vuelven a la normalidad

$lineas = @('| Operación | Servicio dueño | Éxito antes | Éxito durante la falla |', '|---|---|---|---|')
$disp = 0
foreach ($op in $Operaciones) {
  $lineas += "| $op | $($Dueno[$op]) | $($Antes[$op]) % | $($Durante[$op]) % |"
  if ($Durante[$op] -ge 90) { $disp++ }
}
$lineas += ''
$lineas += "Arquitectura: $Arq · componente que falla: $Componente (contenedor detenido: $Contenedor) · N=$N"
$lineas += "Operaciones disponibles durante la falla (>= 90 % de éxito): $disp de 6"
New-Item -ItemType Directory -Force -Path scripts\salidas | Out-Null
$salida = Join-Path 'scripts' (Join-Path 'salidas' "disponibilidad_${Arq}_$Componente.md")
[IO.File]::WriteAllLines((Join-Path $script:Raiz $salida), [string[]]$lineas)
Write-Host ''
$lineas | ForEach-Object { Write-Host "   $_" }
Info "resultado guardado en $salida"

Paso 'Verificaciones'
foreach ($op in $Operaciones) { Check "antes de la falla: $op" 100 $Antes[$op] }
if ($Arq -eq 'ut5') {
  $nombre = @{ mensajeria = 'Mensajería'; verificacion = 'Verificación'; usuarios = 'Usuarios'; docentes = 'Docentes' }[$Componente]
  foreach ($op in $Operaciones) {
    $esperado = 100
    if ($Dueno[$op] -eq $nombre) { $esperado = 0 }
    if ($op -eq 'reservar' -and ($Componente -eq 'usuarios' -or $Componente -eq 'docentes')) { $esperado = 0 }
    Check "durante la falla: $op" $esperado $Durante[$op]
  }
}
Resumen
