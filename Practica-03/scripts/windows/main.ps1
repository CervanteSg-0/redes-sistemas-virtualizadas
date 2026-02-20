$base = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$base\modules\Common.ps1"
. "$base\modules\NetStatic.ps1"
. "$base\modules\DnsRole.ps1"
. "$base\modules\DnsZone.ps1"
. "$base\modules\DnsRemove.ps1"

Assert-Admin

while ($true) {
  Clear-Host
  Write-Host "===== DNS Windows Server 2022 ====="
  Write-Host "1) Verificar/Instalar rol DNS"
  Write-Host "2) Verificar/Configurar IP fija"
  Write-Host "3) Configurar zona + registros"
  Write-Host "4) Eliminar zona + registros"
  Write-Host "0) Salir"
  Write-Host "==================================="
  $op = (Read-Host "Opcion").Trim()
  switch ($op) {
    "1" { Ensure-DnsRole; Pause-Enter }
    "2" { Ensure-StaticIP; Pause-Enter }
    "3" { Ensure-ZoneAndRecords; Pause-Enter }
    "4" { Remove-ZoneAndRecords; Pause-Enter }
    "0" { break }
    default { Write-Host "Opcion invalida"; Pause-Enter }
  }
}
