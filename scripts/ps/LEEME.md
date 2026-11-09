# Demos de la UT5 para Windows PowerShell

Versiones en PowerShell de las demos de `scripts/`. No necesitan Git Bash, `jq` ni `perl`: usan
`curl.exe` (incluido en Windows 10/11), `ConvertFrom-Json` y `docker`. Funcionan en Windows
PowerShell 5.1 y en PowerShell 7.

```powershell
cd "C:\Users\<usuario>\...\tutorYA"
Set-ExecutionPolicy -Scope Process Bypass     # solo para esta ventana
docker compose up -d --build
.\scripts\ps\demo_microservicios.ps1
.\scripts\ps\demo_soap.ps1
.\scripts\ps\demo_eventos.ps1
.\scripts\ps\demo_disponibilidad.ps1                       # falla de Mensajería
.\scripts\ps\demo_disponibilidad.ps1 -Componente docentes  # otras fallas
.\scripts\ps\demo_todo.ps1                                 # las cuatro en orden
```

La saga (`demo_saga.sh`) solo está en bash.
