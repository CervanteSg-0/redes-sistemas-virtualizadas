# windows/modules/DnsZone.ps1

. "$PSScriptRoot\Common.ps1"

function Configure-DnsZone {
    Write-Host "== Configurar Zona DNS + Registros (Windows) ==" -ForegroundColor White
    
    $domain = (Read-Host "Dominio").Trim().ToLower()
    if ([string]::IsNullOrWhiteSpace($domain)) { die "Dominio no puede estar vacio." }

    $clientIp = prompt_ip "IP del CLIENTE a la que apuntara el dominio"
    $ttlSeconds = 3600 # Valor por defecto fijo (1 hora)
    
    info "Configurando zona primaria: $domain"
    try {
        # Configura la zona (idempotente: si ya existe lanza error, lo manejamos)
        Add-DnsServerPrimaryZone -Name $domain -ZoneFile "$domain.dns" -DynamicUpdate NonsecureAndSecure -ErrorAction Stop | Out-Null
        
        info "Agregando registros base..."
        # Agregar registros A (IP)
        Add-DnsServerResourceRecordA -ZoneName $domain -Name "@" -IPv4Address $clientIp -TimeToLive ([TimeSpan]::FromSeconds($ttlSeconds)) -ErrorAction Stop | Out-Null

        # Agregar registros CNAME (www)
        Add-DnsServerResourceRecordCName -ZoneName $domain -Name "www" -HostNameAlias "$domain." -TimeToLive ([TimeSpan]::FromSeconds($ttlSeconds)) -ErrorAction Stop | Out-Null

        # Sincronizar lista para el cliente
        Update-SharedDomainsList

        ok "Zona y registros configurados exitosamente: $domain (-> $clientIp)"
    } catch {
        warn "La zona '$domain' ya existe o hubo un error. Revisa con la opcion 5."
    }
}