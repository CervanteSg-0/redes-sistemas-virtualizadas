. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\DnsRole.ps1"

function Remove-DnsZoneByName {
  Write-Host "== Eliminar Zona DNS (dominio) =="

  Ensure-DnsRole

  $zoneName = (Read-Host "Nombre de la zona a eliminar (ej: reprobados.com)").Trim().ToLower()
  if (-not (Is-ValidZoneName $zoneName)) { throw "Nombre de zona invalido. Ej: reprobados.com" }

  $z = Get-DnsServerZone -Name $zoneName -ErrorAction SilentlyContinue
  if (-not $z) {
    Write-Host "[INFO] La zona '$zoneName' no existe. No hay nada que eliminar."
    return
  }

  Write-Host ""
  Write-Host "Zona encontrada:"
  Write-Host " - Nombre: $($z.ZoneName)"
  Write-Host " - Tipo  : $($z.ZoneType)"
  Write-Host " - Integrada AD: $($z.IsDsIntegrated)"
  Write-Host ""

  if (-not (Prompt-YesNo "Confirmas ELIMINAR la zona '$zoneName'? (borra todos los registros)" $false)) {
    Write-Host "[INFO] Cancelado."
    return
  }

  Remove-DnsServerZone -Name $zoneName -Force -ErrorAction Stop
  Write-Host "[OK] Zona eliminada: $zoneName"

  if (Prompt-YesNo "¿Intentar eliminar tambien una zona inversa asociada (si existe)?" $false) {
    $revZones = Get-DnsServerZone -ErrorAction SilentlyContinue |
      Where-Object { $_.ZoneName -match 'in-addr\.arpa$|ip6\.arpa$' }

    if (-not $revZones) {
      Write-Host "[INFO] No se encontraron zonas inversas."
      return
    }

    Write-Host ""
    Write-Host "Zonas inversas detectadas:"
    $revZones | Select-Object ZoneName,ZoneType,IsDsIntegrated | Format-Table -AutoSize

    $revName = (Read-Host "Escribe el nombre EXACTO de la zona inversa a eliminar (ENTER para omitir)").Trim()
    if ([string]::IsNullOrWhiteSpace($revName)) {
      Write-Host "[INFO] Omitido."
      return
    }

    $rz = Get-DnsServerZone -Name $revName -ErrorAction SilentlyContinue
    if (-not $rz) {
      Write-Host "[INFO] La zona inversa '$revName' no existe."
      return
    }

    if (Prompt-YesNo "Confirmas ELIMINAR la zona inversa '$revName'?" $false) {
      Remove-DnsServerZone -Name $revName -Force -ErrorAction Stop
      Write-Host "[OK] Zona inversa eliminada: $revName"
    } else {
      Write-Host "[INFO] Cancelado."
    }
  }
}