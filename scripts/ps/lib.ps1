# Funciones comunes de las demos de la UT5 para Windows PowerShell (5.1) y PowerShell 7.
# No necesitan bash, jq ni perl: usan curl.exe (viene con Windows 10/11), ConvertFrom-Json y docker.
# Uso: desde la carpeta del proyecto, .\scripts\ps\demo_soap.ps1  (ver scripts\ps\LEEME.md)

[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
$OutputEncoding = New-Object System.Text.UTF8Encoding $false

# Se ejecuta siempre desde la raíz del repo (docker compose busca ahí el docker-compose.yaml).
$script:Raiz = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $script:Raiz

$puerto = '8443'
if (Test-Path .env) {
  $m = Select-String -Path .env -Pattern '^GATEWAY_TLS_PORT=(\d+)'
  if ($m) { $puerto = $m.Matches[0].Groups[1].Value }
}
$script:Base = if ($env:BASE_URL) { $env:BASE_URL } else { "https://localhost:$puerto" }
$script:CurlExe = if ($env:OS -eq 'Windows_NT') { 'curl.exe' } else { 'curl' }
$script:Sufijo = '{0}{1}' -f (Get-Date -Format 'HHmmss'), (Get-Random -Maximum 1000)
$script:Ok = 0
$script:Fallas = 0
$script:Codigo = ''
$script:Cuerpo = ''

function Titulo([string]$t) { Write-Host ''; Write-Host "════════ $t ════════" -ForegroundColor Cyan }
function Paso([string]$t) { Write-Host ''; Write-Host "▶ $t" -ForegroundColor Yellow }
function Info([string]$t) { Write-Host "   $t" -ForegroundColor Gray }

function Check([string]$Desc, $Esperado, $Obtenido) {
  if ("$Obtenido" -eq "$Esperado") {
    Write-Host "   [OK] $Desc ($Obtenido)" -ForegroundColor Green
    $script:Ok++
  } else {
    Write-Host "   [FALLA] ${Desc}: esperado '$Esperado', obtenido '$Obtenido'" -ForegroundColor Red
    $script:Fallas++
  }
}

function Resumen {
  Write-Host ''
  if ($script:Fallas -eq 0) {
    Write-Host "TODO OK: $($script:Ok) verificaciones" -ForegroundColor Green
    exit 0
  }
  Write-Host "$($script:Fallas) verificaciones fallaron (de $($script:Ok + $script:Fallas))" -ForegroundColor Red
  exit 1
}

# Pedido HTTP al gateway. Deja $script:Codigo y $script:Cuerpo (texto) y devuelve el cuerpo parseado.
# El cuerpo JSON va por archivo temporal: así PowerShell 5.1 no rompe las comillas.
function Req([string]$Metodo, [string]$Ruta, $Datos = $null, [string]$Token = '', [switch]$Silencioso) {
  $salidaTmp = [IO.Path]::GetTempFileName()
  $a = @('-s', '-k', '-X', $Metodo, '-o', $salidaTmp, '-w', '%{http_code}', '--max-time', '30')
  if ($Token) { $a += @('-H', "Authorization: Bearer $Token") }
  $tmp = $null
  if ($null -ne $Datos) {
    $json = if ($Datos -is [string]) { $Datos } else { $Datos | ConvertTo-Json -Compress -Depth 5 }
    $tmp = [IO.Path]::GetTempFileName()
    [IO.File]::WriteAllText($tmp, $json)
    $a += @('-H', 'Content-Type: application/json', '--data-binary', "@$tmp")
  }
  $codigo = & $script:CurlExe @a "$($script:Base)$Ruta"
  $script:Codigo = if ($codigo) { "$codigo".Trim() } else { '000' }
  $script:Cuerpo = [IO.File]::ReadAllText($salidaTmp)
  Remove-Item $salidaTmp -ErrorAction SilentlyContinue
  if ($tmp) { Remove-Item $tmp -ErrorAction SilentlyContinue }
  if (-not $Silencioso) { Info "$Metodo $Ruta -> $($script:Codigo)" }
  try { return ($script:Cuerpo | ConvertFrom-Json) } catch { return $null }
}

function Codigo-De([string]$Metodo, [string]$Ruta, $Datos = $null, [string]$Token = '') {
  [void](Req $Metodo $Ruta $Datos $Token -Silencioso)
  return $script:Codigo
}

function Registrar([string]$Email, [string]$Nombre, [string]$Rol) {
  $r = Req POST /api/usuarios/registro @{ email = $Email; password = 'clave123'; nombre = $Nombre; rol = $Rol }
  if ($r) { return $r.id }
}

function Login([string]$Email, [string]$Clave = 'clave123') {
  $r = Req POST /api/usuarios/login @{ email = $Email; password = $Clave } -Silencioso
  if ($r) { return $r.token }
}

function Fecha-Futura([int]$Dias, [int]$Hora = 15) {
  return (Get-Date).ToUniversalTime().Date.AddDays($Dias).AddHours($Hora).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
}

# Reintenta un bloque cada 0,5 s hasta que devuelva $true o pase el tiempo (los eventos son asíncronos).
function Esperar-Hasta([int]$Segundos, [scriptblock]$Condicion) {
  $fin = (Get-Date).AddSeconds($Segundos)
  while ((Get-Date) -lt $fin) {
    try { if (& $Condicion) { return $true } } catch { }
    Start-Sleep -Milliseconds 500
  }
  return $false
}

# El verificador agenda la llamada y aprueba al docente (la solicitud llega por evento: se espera).
function Aprobar-Docente([int]$DocenteId) {
  $ver = Login 'verificador@tutorya.uy' 'verificador123'
  $sol = $null
  [void](Esperar-Hasta 20 {
    $lista = Req GET '/api/verificaciones?estado=PENDIENTE' $null $ver -Silencioso
    $script:solTmp = @($lista | Where-Object { $_.docente_id -eq $DocenteId })[0]
    return [bool]$script:solTmp
  })
  $sol = $script:solTmp
  if (-not $sol) { Info 'no apareció la solicitud de verificación'; return }
  [void](Req POST "/api/verificaciones/$($sol.id)/llamada" @{ fecha = (Fecha-Futura 1) } $ver)
  [void](Req POST "/api/verificaciones/$($sol.id)/resolucion" @{ resultado = 'APROBADO' } $ver)
}

# Docente aprobado con una materia y N horarios. Devuelve @{ Id; Token; Horarios }.
function Preparar-Docente([int]$CantHorarios, [string]$Materia = 'Fisica') {
  $email = "doc_$($script:Sufijo)@demo.uy"
  $id = Registrar $email 'Docente Demo' DOCENTE
  $tok = Login $email
  [void](Esperar-Hasta 20 { (Codigo-De GET /api/docentes/me $null $tok) -eq '200' })
  Aprobar-Docente $id
  # Docentes marca el perfil APROBADO al recibir docente.verificado (asíncrono): se espera a verlo.
  [void](Esperar-Hasta 20 { (Req GET /api/docentes/me $null $tok -Silencioso).estado -eq 'APROBADO' })
  [void](Req PUT /api/docentes/me/materias @{ materias = @($Materia) } $tok -Silencioso)
  $hs = @()
  for ($i = 1; $i -le $CantHorarios; $i++) {
    $h = Req POST /api/docentes/me/horarios @{ inicio = (Fecha-Futura ($i + 1) 10); fin = (Fecha-Futura ($i + 1) 11); precio = 500 } $tok -Silencioso
    $hs += $h.id
  }
  return @{ Id = $id; Token = $tok; Horarios = $hs }
}

function Estudiante-Demo {
  $email = "est_$($script:Sufijo)@demo.uy"
  [void](Registrar $email 'Estudiante Demo' ESTUDIANTE)
  return (Login $email)
}

# Valor de una consulta en la base de un servicio (docker compose exec ... psql).
function Psql([string]$BaseDatos, [string]$Sql) {
  $r = docker compose exec -T $BaseDatos psql -U tutorya -d tutorya -tAc $Sql 2>$null
  return ("$r").Trim()
}

function Colas-Rabbit {
  docker compose exec -T rabbitmq rabbitmqctl -q list_queues name messages consumers 2>$null | ForEach-Object { Info $_ }
}

function Mensajes-En-Cola([string]$Cola) {
  $l = docker compose exec -T rabbitmq rabbitmqctl -q list_queues name messages 2>$null |
    Where-Object { ($_ -split '\s+')[0] -eq $Cola }
  if ($l) { return (($l -split '\s+')[1]) } else { return '' }
}

function Esperar-Healthy([int]$Segundos = 120) {
  Write-Host '   esperando contenedores healthy' -NoNewline
  $ok = Esperar-Hasta $Segundos {
    $malos = @(docker compose ps --format '{{.Name}} {{.Health}}' 2>$null | Where-Object {
      $p = $_ -split ' '; $p.Count -gt 1 -and $p[1] -and $p[1] -ne 'healthy'
    })
    return ($malos.Count -eq 0)
  }
  if ($ok) { Write-Host ' OK' } else { Write-Host ' TIMEOUT' }
}
