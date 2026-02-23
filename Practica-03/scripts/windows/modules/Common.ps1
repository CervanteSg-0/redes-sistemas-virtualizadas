# windows/modules/Common.ps1

function die {
    param([string]$msg)
    Write-Host "[ERROR] $msg" -ForegroundColor Red
    exit 1
}

function info {
    param([string]$msg)
    Write-Host "[INFO] $msg" -ForegroundColor Blue
}

function ok {
    param([string]$msg)
    Write-Host "[OK] $msg" -ForegroundColor Green
}

function warn {
    param([string]$msg)
    Write-Host "[WARN] $msg" -ForegroundColor Yellow
}

function pause {
    Write-Host ""
    Write-Host "[PAUSE] Presiona ENTER para continuar..."
    Read-Host | Out-Null
}

# Validación básica de IP v4
function valid_ipv4 {
    param([string]$ip)
    if ($ip -match "^([0-9]{1,3}\.){3}[0-9]{1,3}$") {
        $parts = $ip.Split(".")
        foreach ($part in $parts) {
            if ([int]$part -gt 255 -or [int]$part -lt 0) {
                return $false
            }
        }
        return $true
    }
    return $false
}

# Leer IP con validación
function prompt_ip {
    param([string]$label)
    while ($true) {
        $v = (Read-Host $label).Trim()
        if (valid_ipv4 $v) {
            return $v
        } else {
            Write-Host "  IP invalida. Ej: 192.168.100.50" -ForegroundColor Red
        }
    }
}

# Funcion para confirmar con S/N
function prompt_yesno {
    param([string]$label, [bool]$defaultYes=$true)
    $suffix = if ($defaultYes) { "[S/n]" } else { "[s/N]" }
    while ($true) {
        $r = (Read-Host "$label $suffix").Trim().ToLower()
        if ($r -eq "") { return $defaultYes }
        if ($r -match '^(s|si|y|yes)$') { return $true }
        if ($r -match '^(n|no)$') { return $false }
        Write-Host "  Responde S o N." -ForegroundColor Yellow
    }
}

function Update-SharedDomainsList {
    $sharedFile = Join-Path $PSScriptRoot "..\..\dominios_activos.txt"
    info "Actualizando lista de dominios compartida..."
    try {
        $zones = Get-DnsServerZone | Where-Object { $_.ZoneName -notmatch "TrustAnchors|0\.in-addr\.arpa|127\.in-addr\.arpa|255\.in-addr\.arpa" } | Select-Object -ExpandProperty ZoneName
        $zones | Out-File -FilePath $sharedFile -Encoding utf8 -Force
    } catch {
        warn "No se pudo actualizar el archivo compartido."
    }
}

function Get-ServerIP {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" -and $_.IPAddress -notmatch "^169\.254" } | Select-Object -First 1).IPAddress
    return $ip
}

function Show-ServerIPInfo {
    $ip = Get-ServerIP
    Write-Host "[TIP] IP del Servidor: $ip (Usa esta IP como DNS en el Cliente)" -ForegroundColor Yellow
}

function Manual-IPFlow {
    info "== Asignar IP Estatica Manualmente (Windows) =="
    
    $adapters = Get-NetAdapter | Where-Object Status -eq "Up"
    Write-Host "Interfaces disponibles:"
    foreach ($a in $adapters) {
        Write-Host " - $($a.Name) ($($a.InterfaceAlias))"
    }

    $ifaceName = Read-Host "Nombre de la interfaz [Ethernet]"
    if ([string]::IsNullOrWhiteSpace($ifaceName)) { $ifaceName = "Ethernet" }

    $ip = prompt_ip "IP Estatica para el servidor"
    
    warn "[!] ADVERTENCIA: Si dejas el Gateway vacio, podrias perder internet en la VM."
    $mask = Read-Host "Prefijo de red [24 para 255.255.255.0]"
    if ([string]::IsNullOrWhiteSpace($mask)) { $mask = "24" }
    
    $gw = Read-Host "Puerta de enlace (ENTER para omitir)"
    $dns = Read-Host "DNS Primario (ENTER para omitir)"

    info "Aplicando configuracion..."
    try {
        # Limpiar IPs anteriores si existen
        $currentIPs = Get-NetIPAddress -InterfaceAlias $ifaceName -AddressFamily IPv4 -ErrorAction SilentlyContinue
        foreach ($cip in $currentIPs) {
            Remove-NetIPAddress -IPAddress $cip.IPAddress -InterfaceAlias $ifaceName -Confirm:$false
        }

        New-NetIPAddress -InterfaceAlias $ifaceName -IPAddress $ip -PrefixLength $mask -DefaultGateway $gw -ErrorAction Stop | Out-Null
        if (-not [string]::IsNullOrWhiteSpace($dns)) {
            Set-DnsClientServerAddress -InterfaceAlias $ifaceName -ServerAddresses $dns -ErrorAction Stop
        }
        ok "Configuracion aplicada exitosamente."
    } catch {
        die "Error al aplicar la configuracion: $_"
    }
}