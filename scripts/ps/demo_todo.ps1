# UT5: corre las demos de PowerShell en orden.
$fallidas = @()
foreach ($d in 'demo_microservicios', 'demo_soap', 'demo_eventos', 'demo_disponibilidad') {
  $exe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
  & $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "$d.ps1")
  if ($LASTEXITCODE -ne 0) { $fallidas += $d }
}
Write-Host ''
if ($fallidas.Count -eq 0) { Write-Host 'Todas las demos pasaron' -ForegroundColor Green }
else { Write-Host "Fallaron: $($fallidas -join ', ')" -ForegroundColor Red; exit 1 }
