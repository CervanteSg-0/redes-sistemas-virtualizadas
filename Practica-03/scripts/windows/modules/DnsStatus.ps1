# windows/modules/DnsStatus.ps1

function Get-DnsStatus {
    Write-Host "== Verificar Estado del Servicio DNS =="
    $service = Get-Service -Name DNS
    $service | Format-Table -Property Status, Name, DisplayName, StartType

    Write-Host "== Puertos escuchando 53 (DNS) =="
    Get-NetTCPConnection -LocalPort 53
}