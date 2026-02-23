# windows/modules/DnsRemove.ps1

. "$PSScriptRoot\Common.ps1"

function Remove-DnsZoneByName {
    Write-Host "== Eliminar Zona DNS (Windows) ==" -ForegroundColor White

    $zoneName = (Read-Host "Nombre de la zona a eliminar").Trim().ToLower()
    if ([string]::IsNullOrWhiteSpace($zoneName)) { return }

    $z = Get-DnsServerZone -Name $zoneName -ErrorAction SilentlyContinue
    if (-not $z) {
        info "La zona '$zoneName' no existe. Nada que eliminar."
        return
    }

    Write-Host "`nZona encontrada:"
    Write-Host " - Nombre: $($z.ZoneName)"
    Write-Host " - Tipo  : $($z.ZoneType)"
    Write-Host ""

    if (-not (prompt_yesno "Confirmas ELIMINAR la zona '$zoneName'?" $false)) {
        info "Operacion cancelada por el usuario."
        return
    }

    info "Eliminando zona..."
    try {
        Remove-DnsServerZone -Name $zoneName -Force -ErrorAction Stop
        # Sincronizar lista para el cliente
        Update-SharedDomainsList
        ok "Zona '$zoneName' eliminada exitosamente."
    } catch {
        die "Error al eliminar la zona: $_"
    }
}