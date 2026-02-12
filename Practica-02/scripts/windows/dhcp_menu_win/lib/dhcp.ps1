function DHCP-EstaInstalado {
    $f = Get-WindowsFeature -Name DHCP -ErrorAction Stop
    return $f.Installed
}

function DHCP-Instalar {
    Asegurar-Admin

    if (DHCP-EstaInstalado) {
        $r = Read-Host "DHCP ya esta instalado. Reinstalar? (s/n)"
        if ($r -ne "s" -and $r -ne "S") {
            Write-Host "No se reinstalo."
            return
        }
        Uninstall-WindowsFeature -Name DHCP -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
    }

    Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
    Import-Module DhcpServer -ErrorAction Stop

    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 |
               Where-Object { $_.IPAddress -ne "127.0.0.1" -and $_.PrefixOrigin -ne "WellKnown" } |
               Select-Object -First 1 -ExpandProperty IPAddress)
        if ($ip) { Add-DhcpServerInDC -DnsName $env:COMPUTERNAME -IPAddress $ip | Out-Null }
    } catch { }

    Write-Host "DHCP instalado."
}

function DHCP-ReiniciarServicio {
    Asegurar-Admin
    Restart-Service -Name "DHCPServer" -ErrorAction Stop
}

function DHCP-Monitoreo {
    Import-Module DhcpServer -ErrorAction SilentlyContinue | Out-Null

    Write-Host "== Servicio DHCPServer =="
    Get-Service DHCPServer | Format-Table -AutoSize

    Write-Host ""
    Write-Host "== Scopes =="
    try {
        Get-DhcpServerv4Scope | Format-Table ScopeId, Name, StartRange, EndRange, SubnetMask, State -AutoSize
    } catch {
        Write-Host "No hay scopes o el modulo no esta disponible."
    }

    Write-Host ""
    $scope = Read-Host "ScopeId para ver leases (ENTER=omitir, ej 103.5.153.0)"
    if (-not [string]::IsNullOrWhiteSpace($scope)) {
        try {
            Get-DhcpServerv4Lease -ScopeId $scope |
                Sort-Object IPAddress |
                Select-Object IPAddress, ClientId, HostName, AddressState, LeaseExpiryTime |
                Format-Table -AutoSize
        } catch {
            Write-Host "No pude leer leases para ese ScopeId."
        }
    }
}

function DHCP-ConfigurarAmbitoInteractivo {
    Asegurar-Admin
    Import-Module DhcpServer -ErrorAction Stop

    $nombre = Read-Host "Nombre descriptivo del ambito [Scope-1]"
    if ([string]::IsNullOrWhiteSpace($nombre)) { $nombre = "Scope-1" }

    Write-Host ""
    Write-Host "Interfaces disponibles (Up):"
    (Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -ExpandProperty Name) | ForEach-Object { " - $_" }

    $iface = Read-Host "Interfaz de red interna [Ethernet]"
    if ([string]::IsNullOrWhiteSpace($iface)) { $iface = "Ethernet" }

    $ipInicio = Leer-IPv4 "Rango inicial (IP fija del servidor)"
    $mask     = Leer-Mascara "Mascara" "255.255.255.0"
    $ipFinal  = Leer-FinalConShorthand "Rango final" $ipInicio

    if (-not (Misma-Subred $ipInicio $ipFinal $mask)) { Error-Salir "Inicio y final no estan en la misma subred." }

    $si = Convertir-IPaEntero $ipInicio
    $ei = Convertir-IPaEntero $ipFinal
    if ($si -ge $ei) { Error-Salir "El rango inicial debe ser menor que el rango final." }

    $ipServidor   = $ipInicio
    $ipPoolInicio = Incrementar-IP $ipInicio
    $psi = Convertir-IPaEntero $ipPoolInicio
    if ($psi -gt $ei) { Error-Salir "Pool invalido: (inicio+1) es mayor que final." }

    $gateway = Leer-IPv4Opcional "Puerta de enlace (opcional)"
    if ($gateway -and -not (Misma-Subred $gateway $ipInicio $mask)) { Error-Salir "Gateway fuera de la subred." }

    $dns1 = Leer-IPv4Opcional "DNS primario (opcional)"
    $dns2 = ""
    if ($dns1) { $dns2 = Leer-IPv4Opcional "DNS secundario (opcional)" }

    $leaseSec = Leer-Entero "Lease time en segundos" 86400
    if ($leaseSec -lt 60 -or $leaseSec -gt 31536000) { Error-Salir "Lease fuera de rango (60..31536000)." }
    $lease = [TimeSpan]::FromSeconds($leaseSec)

    $scopeId = Red-DeIP $ipInicio $mask
    $prefix  = Prefijo-DesdeMascara $mask

    # IP estatica en interfaz
    try {
        $exist = Get-NetIPAddress -InterfaceAlias $iface -AddressFamily IPv4 -ErrorAction Stop |
                 Where-Object { $_.IPAddress -ne "127.0.0.1" }
        foreach ($e in $exist) {
            try { Remove-NetIPAddress -InterfaceAlias $iface -IPAddress $e.IPAddress -Confirm:$false -ErrorAction SilentlyContinue } catch {}
        }
    } catch { }

    New-NetIPAddress -InterfaceAlias $iface -IPAddress $ipServidor -PrefixLength $prefix -ErrorAction Stop | Out-Null

    if ($gateway) { try { Set-NetIPConfiguration -InterfaceAlias $iface -IPv4DefaultGateway $gateway -ErrorAction SilentlyContinue | Out-Null } catch {} }

    if ($dns1 -and $dns2) {
        try { Set-DnsClientServerAddress -InterfaceAlias $iface -ServerAddresses @($dns1,$dns2) -ErrorAction SilentlyContinue | Out-Null } catch {}
    } elseif ($dns1) {
        try { Set-DnsClientServerAddress -InterfaceAlias $iface -ServerAddresses @($dns1) -ErrorAction SilentlyContinue | Out-Null } catch {}
    }

    # Binding DHCP
    try { Set-DhcpServerv4Binding -InterfaceAlias $iface -BindingState $true -ErrorAction SilentlyContinue | Out-Null } catch {}

    # Scope idempotente
    $existe = $null
    try { $existe = Get-DhcpServerv4Scope -ScopeId $scopeId -ErrorAction Stop } catch { $existe = $null }

    if (-not $existe) {
        Add-DhcpServerv4Scope -Name $nombre -StartRange $ipPoolInicio -EndRange $ipFinal -SubnetMask $mask -State Active | Out-Null
    } else {
        Set-DhcpServerv4Scope -ScopeId $scopeId -Name $nombre -StartRange $ipPoolInicio -EndRange $ipFinal -SubnetMask $mask -State Active | Out-Null
    }

    Set-DhcpServerv4Scope -ScopeId $scopeId -LeaseDuration $lease | Out-Null

    if ($gateway) { Set-DhcpServerv4OptionValue -ScopeId $scopeId -Router $gateway | Out-Null }
    if ($dns1 -and $dns2) { Set-DhcpServerv4OptionValue -ScopeId $scopeId -DnsServer @($dns1,$dns2) | Out-Null }
    elseif ($dns1) { Set-DhcpServerv4OptionValue -ScopeId $scopeId -DnsServer @($dns1) | Out-Null }

    Restart-Service DHCPServer

    Write-Host ""
    Write-Host "Listo."
    Write-Host "IP fija servidor ($iface): $ipServidor/$prefix"
    Write-Host "ScopeId: $scopeId"
    Write-Host "Pool DHCP: $ipPoolInicio - $ipFinal"
}

