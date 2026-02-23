# windows/modules/DnsStatus.ps1

function Get-DnsStatus {
    Write-Host "== Verificar Estado del Servicio DNS =="
    $service = Get-Service -Name DNS
    $service | Format-Table -Property Status, Name, DisplayName, StartType

    Write-Host "== Puertos escuchando 53 (DNS) =="
    Get-NetTCPConnection -LocalPort 53 -ErrorAction SilentlyContinue | Format-Table LocalAddress, LocalPort, State

    Get-ActiveZones
}

function Get-ActiveZones {
    Write-Host "== Dominios/Zonas Activas =="
    # Filtrar zonas que no sean las por defecto de Windows
    Get-DnsServerZone | Where-Object { $_.ZoneName -notmatch "TrustAnchors|0\.in-addr\.arpa|127\.in-addr\.arpa|255\.in-addr\.arpa" } | Format-Table ZoneName, ZoneType, IsDsIntegrated
}