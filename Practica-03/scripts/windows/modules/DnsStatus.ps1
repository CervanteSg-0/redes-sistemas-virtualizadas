# windows/modules/DnsStatus.ps1

. "$PSScriptRoot\Common.ps1"

function Get-DnsStatus {
    Write-Host "== Verificar Estado del Servicio DNS ==" -ForegroundColor White
    $service = Get-Service -Name DNS -ErrorAction SilentlyContinue
    if (-not $service) {
        warn "El servicio DNS no parece estar instalado."
        return
    }
    
    $service | Format-Table -Property Status, Name, DisplayName, StartType

    Write-Host "== Puertos escuchando 53 (DNS) ==" -ForegroundColor White
    $conns = Get-NetTCPConnection -LocalPort 53 -ErrorAction SilentlyContinue 
    if ($conns) {
        $conns | Format-Table LocalAddress, LocalPort, State
    } else {
        warn "Nada escuchando en el puerto 53 TCP."
    }

    Get-ActiveZones
}

function Get-ActiveZones {
    Write-Host "== Dominios/Zonas DNS Activas (Windows) ==" -ForegroundColor White
    $zones = Get-DnsServerZone | Where-Object { $_.ZoneName -notmatch "TrustAnchors|0\.in-addr\.arpa|127\.in-addr\.arpa|255\.in-addr\.arpa" }
    if ($zones) {
        $zones | Format-Table ZoneName, ZoneType, IsDsIntegrated
    } else {
        info "No hay zonas configuradas manualmente."
    }
}