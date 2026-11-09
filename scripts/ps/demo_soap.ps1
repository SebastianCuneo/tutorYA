# UT5 — Migración REST -> SOAP: ConsultarEstadoEstudiante (PowerShell).
# Los pedidos a /soap y /internal se hacen desde DENTRO de la red interna (el gateway no los expone):
# se ejecuta un pequeño script de Node en el contenedor de Reservas.
. "$PSScriptRoot\lib.ps1"
Titulo 'Migración de REST a SOAP'

# Ejecuta un pedido HTTP desde el contenedor de Reservas. Devuelve "<código> <cuerpo>".
function Desde-Reservas([string]$Metodo, [string]$Url, [string]$Xml = '') {
  $js = 'fetch(process.env.U,{method:process.env.M,headers:{"Content-Type":"text/xml; charset=utf-8",' +
        'SOAPAction:"\"http://tutorya.uy/usuarios/estudiantes/ConsultarEstadoEstudiante\""},' +
        'body:process.env.B?Buffer.from(process.env.B,"base64").toString():undefined}).then(async r=>console.log(r.status+" "+(await r.text())))' +
        '.catch(e=>console.log("000 "+e.message))'
  # El XML va en base64: PowerShell 5.1 rompe las comillas de los argumentos de programas externos.
  $b64 = if ($Xml) { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Xml)) } else { '' }
  $salida = $js | docker compose exec -T --index 1 -e "U=$Url" -e "M=$Metodo" -e "B=$b64" reservas node - 2>$null
  return ($salida -join "`n")
}
function Sobre([string]$Id) {
  return '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:e="http://tutorya.uy/usuarios/estudiantes">' +
         "<soap:Body><e:ConsultarEstadoEstudianteRequest><e:estudianteId>$Id</e:estudianteId></e:ConsultarEstadoEstudianteRequest></soap:Body></soap:Envelope>"
}

Paso '1. El endpoint REST viejo ya no existe'
$r = Desde-Reservas GET 'http://usuarios:3000/internal/usuarios/1/estado'
Check 'GET /internal/usuarios/1/estado' 404 ($r -split ' ')[0]

Paso '2. Contrato WSDL publicado por Usuarios'
$w = Desde-Reservas GET 'http://usuarios:3000/soap/estudiantes?wsdl'
($w -split "`n") | Where-Object { $_ -match 'operation name|element name="(estudianteId|esMenor|estado)"|soap:address' } | ForEach-Object { Info $_.Trim() }
Check 'WSDL disponible' 200 ($w -split ' ')[0]

Paso '3. Pedido SOAP (XML) válido'
$estId = Registrar "est_$($script:Sufijo)@demo.uy" 'Estudiante Demo' ESTUDIANTE
Info 'pedido:'; Info (Sobre $estId)
$s = Desde-Reservas POST 'http://usuarios:3000/soap/estudiantes' (Sobre $estId)
Info 'respuesta:'; ($s.Substring($s.IndexOf(' ') + 1) -replace '><', ">`n<") -split "`n" | ForEach-Object { Info $_ }
Check 'HTTP del servicio SOAP' 200 ($s -split ' ')[0]
Check 'respuesta XML con <estado>AUTORIZADO</estado>' True ($s -match '<estado>AUTORIZADO</estado>')

Paso '4. Error de negocio como SOAP Fault'
$f = Desde-Reservas POST 'http://usuarios:3000/soap/estudiantes' (Sobre 999999)
if ($f -match '<soap:Fault>.*</soap:Fault>') { Info $Matches[0] }
Check 'estudiante inexistente => soap:Client' True ($f -match 'soap:Client')

Paso '5. Otro componente consume el servicio: Reservas reserva usando SOAP'
$doc = Preparar-Docente 1
$estTok = Login "est_$($script:Sufijo)@demo.uy"
[void](Req POST /api/reservas @{ docenteId = $doc.Id; horarioId = $doc.Horarios[0]; tokenPago = 'tok_ok' } $estTok)
Check 'reserva creada (el estado del estudiante vino por SOAP)' 201 $script:Codigo
Info 'log de Reservas:'
docker compose logs reservas 2>$null | Select-String 'cliente SOAP creado' | Select-Object -First 1 | ForEach-Object { Info ("$_".Substring(0, [Math]::Min(200, "$_".Length))) }
Resumen
