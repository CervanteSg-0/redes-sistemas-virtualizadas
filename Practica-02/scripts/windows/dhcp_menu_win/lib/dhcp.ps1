function DHCP-EstaInstalado {
    $f = Get-WindowsFeature -Name DHCP -ErrorAction Stop
    return $f.Installed
}

function DHCP-Instalar {
    Asegurar-Admin

    if (DHCP-EstaInstalado) {
        $r = Read-Host "DHCP ya esta instalado. Reinstalar? (s/n)"
        if ($r -ne "s" -and $r -ne "S") { Write-Host "No se reinstalo."; return }
        Uninstall-WindowsFeature -Name DHCP -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
    }

    $res = Install-WindowsFeature -Name DHCP -IncludeManagementTools
    if ($res.RestartNeeded -and $res.RestartNeeded -ne "No") {
        Aviso "Se requiere reiniciar el servidor para completar la instalacion del rol DHCP."
        Aviso "Reinicia y vuelve a ejecutar el menu."
        return
    }

    $m = Get-Module -ListAvailable DhcpServer -ErrorAction SilentlyContinue
    if (-not $m) { Aviso "Modulo DhcpServer no disponible. Reinicia el servidor."; return }

    Import-Module DhcpServer -ErrorAction Stop
    Write-Host "DHCP instalado y modulo disponible."
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
    $scopes = @()
    try {
        $scopes = Get-DhcpServerv4Scope -ComputerName localhost -ErrorAction Stop
        $scopes | Format-Table ScopeId, Name, StartRange, EndRange, SubnetMask, State -AutoSize
    } catch {
        Write-Host "No pude leer scopes: $($_.Exception.Message)"
        return
    }

    foreach ($s in $scopes) {
        Write-Host ""
        Write-Host "== Leases (PowerShell) del ScopeId $($s.ScopeId) =="
        try {
            $leases = Get-DhcpServerv4Lease -ComputerName localhost -ScopeId $s.ScopeId -AllLeases -ErrorAction Stop
            if ($leases) {
                $leases | Sort-Object IPAddress |
                  Select-Object IPAddress, ClientId, HostName, AddressState, LeaseExpiryTime |
                  Format-Table -AutoSize
            } else {
                Write-Host "PowerShell no devolvio leases. Probando netsh..."
                cmd /c "netsh dhcp server scope $($s.ScopeId) show clients 1"
            }
        } catch {
            Write-Host "PowerShell fallo: $($_.Exception.Message)"
            Write-Host "Probando netsh..."
            cmd /c "netsh dhcp server scope $($s.ScopeId) show clients 1"
        }
    }
}

function DHCP-ConfigurarAmbitoInteractivo {
    Asegurar-Admin
    Import-Module DhcpServer -ErrorAction Stop

    $nombre = Read-Host "Nombre descriptivo del ambito [Scope-1]"
    if ([string]::IsNullOrWhiteSpace($nombre)) { $nombre = "Scope-1" }
    $nombre = $nombre.Trim()

    Write-Host ""
    Write-Host "Interfaces disponibles (Up):"
    (Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -ExpandProperty Name) | ForEach-Object { " - $_" }

    $iface = Read-Host "Interfaz de red interna [Ethernet]"
    if ([string]::IsNullOrWhiteSpace($iface)) { $iface = "Ethernet" }
    $iface = $iface.Trim()

    $ipInicio = Leer-IPv4 "Rango inicial (IP fija del servidor)"
    $ipFinal  = Leer-FinalConShorthand "Rango final" $ipInicio

    $si = Convertir-IPaEntero $ipInicio
    $ei = Convertir-IPaEntero $ipFinal
    if ($si -ge $ei) { Error-Salir "El rango inicial debe ser menor que el rango final." }

    # FIX: prefijo para DHCP: calcula por IPs pero fuerza /24 si el rango es corto
    $pref = Prefijo-ParaDHCPDesdeRango $ipInicio $ipFinal
    $mask = Mascara-DesdePrefijo $pref
    if (-not $mask) { Error-Salir "No pude calcular mascara desde prefijo /$pref." }

    $scopeIdStr = Red-DeIP $ipInicio $mask
    $scopeId    = [System.Net.IPAddress]$scopeIdStr

    Write-Host "Mascara usada para DHCP: $mask (/$pref)"
    Write-Host "ScopeId: $scopeIdStr"

    $ipServidor   = $ipInicio
    $ipPoolInicio = Incrementar-IP $ipInicio
    $psi = Convertir-IPaEntero $ipPoolInicio
    if ($psi -gt $ei) { Error-Salir "Pool invalido: (inicio+1) es mayor que final." }

    $gateway = Leer-IPv4Opcional "Puerta de enlace (opcional)"
    $dns1 = Leer-IPv4Opcional "DNS primario (opcional)"
    $dns2 = ""
    if ($dns1) { $dns2 = Leer-IPv4Opcional "DNS secundario (opcional)" }

    $leaseSec = Leer-Entero "Lease time en segundos" 86400
    if ($leaseSec -lt 60 -or $leaseSec -gt 100000000) { Error-Salir "Lease fuera de rango (60..100000000)." }
    $lease = [TimeSpan]::FromSeconds($leaseSec)

    # IP estatica server
    try {
        $exist = Get-NetIPAddress -InterfaceAlias $iface -AddressFamily IPv4 -ErrorAction Stop |
                 Where-Object { $_.IPAddress -ne "127.0.0.1" }
        foreach ($e in $exist) {
            try { Remove-NetIPAddress -InterfaceAlias $iface -IPAddress $e.IPAddress -Confirm:$false -ErrorAction SilentlyContinue } catch {}
        }
    } catch { }

    New-NetIPAddress -InterfaceAlias $iface -IPAddress $ipServidor -PrefixLength $pref -ErrorAction Stop | Out-Null

    if ($gateway) {
        try { Set-NetIPConfiguration -InterfaceAlias $iface -IPv4DefaultGateway ([System.Net.IPAddress]$gateway) -ErrorAction SilentlyContinue | Out-Null } catch {}
    }

    if ($dns1 -and $dns2) {
        try { Set-DnsClientServerAddress -InterfaceAlias $iface -ServerAddresses @([System.Net.IPAddress]$dns1,[System.Net.IPAddress]$dns2) -ErrorAction SilentlyContinue | Out-Null } catch {}
    } elseif ($dns1) {
        try { Set-DnsClientServerAddress -InterfaceAlias $iface -ServerAddresses @([System.Net.IPAddress]$dns1) -ErrorAction SilentlyContinue | Out-Null } catch {}
    }

    # Binding DHCP
    try { Set-DhcpServerv4Binding -InterfaceAlias $iface -BindingState $true -ErrorAction SilentlyContinue | Out-Null } catch {}

    # Crear/Actualizar scope idempotente
    $existe = $null
    try { $existe = Get-DhcpServerv4Scope -ComputerName localhost -ScopeId $scopeId -ErrorAction Stop } catch { $existe = $null }

    if (-not $existe) {
    Add-DhcpServerv4Scope -ComputerName localhost `
        -Name $nombre `
        -StartRange $ipPoolInicio `
        -EndRange $ipFinal `
        -SubnetMask $mask `
        -State Active | Out-Null
} else {
    if ($existe.SubnetMask -ne $mask) {
        Aviso "El scope ya existe y su mascara es $($existe.SubnetMask). No se puede cambiar con Set-DhcpServerv4Scope."
        Aviso "Se eliminara y se recreara el scope con la nueva mascara."

        Remove-DhcpServerv4Scope -ComputerName localhost -ScopeId $scopeId -Force | Out-Null

        Add-DhcpServerv4Scope -ComputerName localhost `
            -Name $nombre `
            -StartRange $ipPoolInicio `
            -EndRange $ipFinal `
            -SubnetMask $mask `
            -State Active | Out-Null
    } else {
        Set-DhcpServerv4Scope -ComputerName localhost -ScopeId $scopeId `
            -Name $nombre `
            -StartRange $ipPoolInicio `
            -EndRange $ipFinal `
            -State Active | Out-Null
    }
}


    Set-DhcpServerv4Scope -ComputerName localhost -ScopeId $scopeId -LeaseDuration $lease | Out-Null

    # Opciones DNS/GW (casteadas)
    try {
        if ($gateway) {
            Set-DhcpServerv4OptionValue -ComputerName localhost -ScopeId $scopeId -Router @([System.Net.IPAddress]$gateway) | Out-Null
        }
        if ($dns1 -and $dns2) {
            Set-DhcpServerv4OptionValue -ComputerName localhost -ScopeId $scopeId -DnsServer @([System.Net.IPAddress]$dns1,[System.Net.IPAddress]$dns2) | Out-Null
        } elseif ($dns1) {
            Set-DhcpServerv4OptionValue -ComputerName localhost -ScopeId $scopeId -DnsServer @([System.Net.IPAddress]$dns1) | Out-Null
        }
    } catch {
        Aviso "No pude aplicar opciones DNS/GW: $($_.Exception.Message)"
    }

    Restart-Service DHCPServer

    Write-Host ""
    Write-Host "Listo."
    Write-Host "IP fija servidor ($iface): $ipServidor/$pref"
    Write-Host "ScopeId: $scopeIdStr"
    Write-Host "Pool DHCP: $ipPoolInicio - $ipFinal"
}
