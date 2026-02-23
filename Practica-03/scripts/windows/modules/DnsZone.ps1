# windows/modules/DnsZone.ps1

. "$PSScriptRoot\Common.ps1"

function Configure-DnsZone {
    Write-Host "== Configurar Zona DNS (Windows Server) =="
    $domain = (Read-Host "Dominio").Trim().ToLower()
    $clientIp = Read-Host "IP del CLIENTE a la que apuntara el dominio"
    $ttlSeconds = 3600 # Valor por defecto fijo
    
    if ([string]::IsNullOrWhiteSpace($domain)) { die "Dominio no puede estar vacio." }
    if (-not (valid_ipv4 $clientIp)) { die "IP de cliente invalida." }

    # Configura la zona
    Add-DnsServerPrimaryZone -Name $domain -ZoneFile "$domain.dns" -DynamicUpdate NonsecureAndSecure -ErrorAction Stop | Out-Null

    # Agregar registros A (IP)
    Add-DnsServerResourceRecordA -ZoneName $domain -Name "@" -IPv4Address $clientIp -TimeToLive ([TimeSpan]::FromSeconds($ttlSeconds)) -ErrorAction Stop | Out-Null

    # Agregar registros CNAME (www)
    Add-DnsServerResourceRecordCName -ZoneName $domain -Name "www" -HostNameAlias "$domain." -TimeToLive ([TimeSpan]::FromSeconds($ttlSeconds)) -ErrorAction Stop | Out-Null

    Write-Host "[OK] Zona y registros configurados: $domain"
}