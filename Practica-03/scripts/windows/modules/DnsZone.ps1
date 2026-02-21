# windows/modules/DnsZone.ps1

. "$PSScriptRoot\Common.ps1"

function Configure-DnsZone {
    Write-Host "== Configurar Zona DNS (Windows Server) =="
    $domain = Read-Host "Dominio: "
    $clientIp = Read-Host "IP del CLIENTE a la que apuntara el dominio"
    $ttl = Read-Host "TTL (segundos)"
    

    # Configura la zona
    Add-DnsServerPrimaryZone -Name $domain -ZoneFile "$domain.dns" -DynamicUpdate NonsecureAndSecure | Out-Null

    # Agregar registros A (IP)
    Add-DnsServerResourceRecordA -ZoneName $domain -Name "@" -IPv4Address $clientIp -TimeToLive ([TimeSpan]::FromSeconds($ttl)) | Out-Null

    # Agregar registros CNAME (www)
    Add-DnsServerResourceRecordCName -ZoneName $domain -Name "www" -HostNameAlias "$domain." -TimeToLive ([TimeSpan]::FromSeconds($ttl)) | Out-Null

    Write-Host "[OK] Zona y registros configurados: $domain"
}