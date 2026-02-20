# windows/modules/DnsRemove.ps1

. "$PSScriptRoot\Common.ps1"

function Remove-DnsZoneByName {
    Write-Host "== Eliminar Zona DNS (dominio) =="

    $zoneName = (Read-Host "Nombre de la zona a eliminar (ej: reprobados.com)").Trim().ToLower()
    if ([string]::IsNullOrWhiteSpace($zoneName)) { throw "Zona vacía." }

    $z = Get-DnsServerZone -Name $zoneName -ErrorAction SilentlyContinue
    if (-not $z) {
        Write-Host "[INFO] La zona '$zoneName' no existe. No hay nada que eliminar."
        return
    }

    Write-Host ""
    Write-Host "Zona encontrada:"
    Write-Host " - Nombre: $($z.ZoneName)"
    Write-Host " - Tipo  : $($z.ZoneType)"
    Write-Host " - Almacen: $($z.IsDsIntegrated)"
    Write-Host ""

    if (-not (Prompt-YesNo "Confirmas ELIMINAR la zona '$zoneName'? (esto borra todos los registros)" $false)) {
        Write-Host "[INFO] Cancelado."
        return
    }

    # Eliminar zona
    Remove-DnsServerZone -Name $zoneName -Force -ErrorAction Stop
    Write-Host "[OK] Zona eliminada: $zoneName"
}