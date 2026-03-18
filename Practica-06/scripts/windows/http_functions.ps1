# ============================================================================
# http_functions.ps1
# Practica 6 - Windows Server 2022 - Aprovisionamiento HTTP
# Libreria de funciones para menu_windows.ps1
# ============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# CONFIG GLOBAL
# ---------------------------------------------------------------------------

$script:APACHE_SVC_NAMES = @('Apache24','Apache2.4','apache-httpd')
$script:NGINX_SVC        = 'Nginx'
$script:IIS_SITE         = 'Default Web Site'
$script:IIS_APPPOOL      = 'DefaultAppPool'
$script:IIS_WEBROOT      = 'C:\inetpub\wwwroot'
$script:NGINX_ROOT       = 'C:\nginx'
$script:NGINX_CONF       = 'C:\nginx\conf\nginx.conf'
$script:NGINX_HTML       = 'C:\nginx\html'
$script:NSSM_PATHS       = @(
    'C:\nssm\win64\nssm.exe',
    'C:\nssm\nssm.exe',
    'C:\Windows\System32\nssm.exe',
    'C:\ProgramData\chocolatey\bin\nssm.exe'
)
$script:RESERVED_PORTS   = @(20,21,22,23,25,53,67,68,69,110,123,135,137,138,139,143,161,162,389,443,445,465,514,587,636,993,995,1433,1434,1521,2049,3306,3389,5432,5900,5985,5986)
$script:PKG_MANAGER      = $null

# ---------------------------------------------------------------------------
# SALIDA / UI
# ---------------------------------------------------------------------------

function Write-Section {
    param([string]$Text)
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Blue
    Write-Host " $Text" -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Blue
}

function Write-Info {
    param([string]$Text)
    Write-Host "[INFO] $Text" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Text)
    Write-Host "[OK]   $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host "[WARN] $Text" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Text)
    Write-Host "[ERR]  $Text" -ForegroundColor Red
}

function Assert-Admin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        throw 'Este script debe ejecutarse como Administrador.'
    }
}

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

function Wait-ForPortListener {
    param(
        [int]$Puerto,
        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $listener = Get-NetTCPConnection -State Listen -LocalPort $Puerto -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($listener) { return $listener }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)

    return $null
}

function Test-HttpEndpoint {
    param(
        [int]$Puerto,
        [int]$TimeoutSeconds = 20,
        [string]$Path = '/'
    )

    $url = "http://127.0.0.1:$Puerto$Path"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    do {
        try {
            try {
                $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
            } catch {
                $resp = Invoke-WebRequest -Uri $url -TimeoutSec 5
            }
            return [pscustomobject]@{
                Success    = $true
                Url        = $url
                StatusCode = [int]$resp.StatusCode
                Error      = $null
            }
        } catch {
            Start-Sleep -Milliseconds 750
        }
    } while ((Get-Date) -lt $deadline)

    return [pscustomobject]@{
        Success    = $false
        Url        = $url
        StatusCode = $null
        Error      = 'Sin respuesta HTTP valida en localhost.'
    }
}

function Get-LocalIPv4List {
    try {
        return @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -notlike '127.*' -and
                $_.IPAddress -notlike '169.254.*' -and
                $_.PrefixOrigin -ne 'WellKnown'
            } |
            Select-Object -ExpandProperty IPAddress -Unique)
    } catch {
        return @()
    }
}

function Show-AccessInfo {
    param(
        [string]$Servicio,
        [int]$Puerto,
        [string]$Webroot
    )

    Write-Section "$Servicio listo"
    Write-Host "URL local : http://localhost:$Puerto" -ForegroundColor Green

    $ips = Get-LocalIPv4List
    foreach ($ip in $ips) {
        Write-Host "URL red   : http://$ip`:$Puerto" -ForegroundColor Green
    }

    Write-Host "Webroot   : $Webroot" -ForegroundColor Green
    Write-Host 'Nota: en IIS es normal que el listener aparezca como PID 4 (System/HTTP.sys).' -ForegroundColor DarkYellow
    Write-Host 'Si la VM esta en NAT, para acceder desde el host puede requerirse modo puente o port forwarding.' -ForegroundColor DarkYellow
}

function Import-IISModules {
    Import-Module ServerManager -ErrorAction SilentlyContinue
    Import-Module WebAdministration -ErrorAction Stop
}

function Get-IISBindingObject {
    Import-IISModules
    return Get-WebBinding -Name $script:IIS_SITE -Protocol 'http' -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Remove-IISHttpBindings {
    Import-IISModules
    $bindings = @(Get-WebBinding -Name $script:IIS_SITE -Protocol 'http' -ErrorAction SilentlyContinue)
    foreach ($binding in $bindings) {
        Remove-WebBinding -Name $script:IIS_SITE -Protocol 'http' -BindingInformation $binding.bindingInformation -ErrorAction SilentlyContinue
    }
}

function Ensure-ApacheService {
    $defaultApacheSvc = $script:APACHE_SVC_NAMES[0]
    $svcName = Get-ApacheServiceName
    if (Get-Service -Name $svcName -ErrorAction SilentlyContinue) {
        return $svcName
    }

    $exe = Get-ApacheExePath
    if (-not (Test-Path $exe)) {
        throw "No se encontro httpd.exe en $exe"
    }

    Write-Info 'Registrando servicio de Apache...'
    & $exe -k install -n $defaultApacheSvc | Out-Null
    Start-Sleep -Seconds 2

    $svcName = Get-ApacheServiceName
    if (-not (Get-Service -Name $svcName -ErrorAction SilentlyContinue)) {
        throw 'No se pudo registrar el servicio de Apache.'
    }

    return $svcName
}

function Test-ServiceReady {
    param(
        [ValidateSet('IIS','Apache','Nginx')][string]$Servicio,
        [int]$Puerto,
        [int]$TimeoutSeconds = 20
    )

    $listener = Wait-ForPortListener -Puerto $Puerto -TimeoutSeconds $TimeoutSeconds
    $http = Test-HttpEndpoint -Puerto $Puerto -TimeoutSeconds $TimeoutSeconds

    return [pscustomobject]@{
        Servicio = $Servicio
        Puerto   = $Puerto
        Listener = $listener
        Http     = $http
        Ready    = [bool]($listener -and $http.Success)
    }
}

# ---------------------------------------------------------------------------
# VALIDACION / PUERTOS
# ---------------------------------------------------------------------------

function Test-ReservedPort {
    param(
        [int]$Puerto,
        [string]$Servicio = ''
    )

    if ($Puerto -notin $script:RESERVED_PORTS) { return $false }

    switch ($Servicio) {
        'IIS'    { if ($Puerto -eq 80) { return $false } }
        'Apache' { if ($Puerto -eq 80) { return $false } }
        'Nginx'  { if ($Puerto -eq 80) { return $false } }
    }

    return $true
}

function Test-Port {
    param(
        [int]$Puerto,
        [string]$Servicio = '',
        [int]$AllowCurrent = 0
    )

    if ($Puerto -lt 1 -or $Puerto -gt 65535) {
        Write-Warn 'El puerto debe estar entre 1 y 65535.'
        return $false
    }

    if (Test-ReservedPort -Puerto $Puerto -Servicio $Servicio) {
        Write-Warn "El puerto $Puerto esta reservado para otros servicios del sistema."
        return $false
    }

    $existing = @(Get-NetTCPConnection -State Listen -LocalPort $Puerto -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique)

    if ($existing.Count -gt 0) {
        if ($AllowCurrent -and $existing.Count -eq 1 -and $existing[0] -eq $AllowCurrent) {
            return $true
        }
        Write-Warn "El puerto $Puerto ya esta en uso por PID(s): $($existing -join ', ')."
        return $false
    }

    return $true
}

function Get-PortFromUser {
    param(
        [string]$Servicio,
        [int]$Default
    )

    do {
        $raw = Read-Host "Puerto para $Servicio [$Default]"
        if ([string]::IsNullOrWhiteSpace($raw)) { $raw = "$Default" }

        if ($raw -notmatch '^\d+$') {
            Write-Warn 'Ingresa solo numeros.'
            $ok = $false
        } else {
            $ok = Test-Port -Puerto ([int]$raw) -Servicio $Servicio
        }
    } until ($ok)

    return [int]$raw
}

# ---------------------------------------------------------------------------
# GESTOR DE PAQUETES / VERSIONES
# ---------------------------------------------------------------------------

function Initialize-PackageManager {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $script:PKG_MANAGER = 'winget'
        return
    }

    if (Get-Command choco -ErrorAction SilentlyContinue) {
        $script:PKG_MANAGER = 'choco'
        return
    }

    $script:PKG_MANAGER = $null
}

function Get-AvailableVersions {
    param([ValidateSet('Apache','Nginx')][string]$Paquete)

    Initialize-PackageManager
    $versions = @()

    if ($Paquete -eq 'Apache') {
        if ($script:PKG_MANAGER -eq 'winget') {
            try {
                $versions += @(winget show Apache.Httpd --versions 2>$null | Where-Object { $_ -match '^\d' })
            } catch {}
        }
        if ($script:PKG_MANAGER -eq 'choco' -or $versions.Count -eq 0) {
            try {
                $versions += @(choco list apache-httpd --all --exact 2>$null |
                    Where-Object { $_ -match '^apache-httpd\s+\d' } |
                    ForEach-Object { ($_ -split '\s+')[1] })
            } catch {}
        }
    }

    if ($Paquete -eq 'Nginx') {
        if ($script:PKG_MANAGER -eq 'winget') {
            try {
                $versions += @(winget show Nginx.Nginx --versions 2>$null | Where-Object { $_ -match '^\d' })
            } catch {}
        }
        if ($script:PKG_MANAGER -eq 'choco' -or $versions.Count -eq 0) {
            try {
                $versions += @(choco list nginx --all --exact 2>$null |
                    Where-Object { $_ -match '^nginx\s+\d' } |
                    ForEach-Object { ($_ -split '\s+')[1] })
            } catch {}
        }
    }

    $versions = @($versions | Where-Object { $_ } | Select-Object -Unique)
    if ($versions.Count -eq 0) {
        return @('latest','stable')
    }

    return $versions
}

function Select-Version {
    param([ValidateSet('Apache','Nginx')][string]$Paquete)

    $versions = Get-AvailableVersions -Paquete $Paquete
    Write-Host ''
    Write-Host "Versiones disponibles para $Paquete:" -ForegroundColor White

    for ($i = 0; $i -lt $versions.Count; $i++) {
        $tag = ''
        if ($i -eq 0) {
            $tag = ' [Latest/Desarrollo]'
        } elseif ($i -eq ($versions.Count - 1) -and $versions.Count -gt 1) {
            $tag = ' [LTS/Estable]'
        }
        Write-Host ("  {0}) {1}{2}" -f ($i + 1), $versions[$i], $tag)
    }

    do {
        $sel = Read-Host "Selecciona version [1-$($versions.Count)]"
        $ok = ($sel -match '^\d+$') -and ([int]$sel -ge 1) -and ([int]$sel -le $versions.Count)
        if (-not $ok) { Write-Warn 'Seleccion invalida.' }
    } until ($ok)

    return $versions[[int]$sel - 1]
}

# ---------------------------------------------------------------------------
# DETECCION DE RUTAS / ESTADOS
# ---------------------------------------------------------------------------

function Get-ApacheServiceName {
    foreach ($name in $script:APACHE_SVC_NAMES) {
        if (Get-Service -Name $name -ErrorAction SilentlyContinue) {
            return $name
        }
    }

    try {
        $svc = Get-CimInstance Win32_Service -ErrorAction Stop |
            Where-Object { $_.PathName -match 'httpd\.exe' } |
            Select-Object -First 1
        if ($svc) { return $svc.Name }
    } catch {}

    return $script:APACHE_SVC_NAMES[0]
}

function Get-ApacheInstallRoot {
    $svcName = Get-ApacheServiceName

    try {
        $svc = Get-CimInstance Win32_Service -Filter "Name='$svcName'" -ErrorAction Stop
        if ($svc -and $svc.PathName -match '"?([^" ]+httpd\.exe)') {
            return Split-Path (Split-Path $matches[1] -Parent) -Parent
        }
    } catch {}

    $candidates = @(
        'C:\Apache24',
        'C:\tools\Apache24',
        'C:\Program Files\Apache24',
        'C:\Program Files (x86)\Apache24',
        'C:\Program Files\Apache Software Foundation\Apache2.4',
        'C:\Program Files (x86)\Apache Software Foundation\Apache2.4'
    )

    foreach ($root in $candidates) {
        if (Test-Path (Join-Path $root 'bin\httpd.exe')) {
            return $root
        }
    }

    return 'C:\Apache24'
}

function Get-ApacheConfPath {
    return (Join-Path (Get-ApacheInstallRoot) 'conf\httpd.conf')
}

function Get-ApacheWebRoot {
    return (Join-Path (Get-ApacheInstallRoot) 'htdocs')
}

function Get-ApacheExePath {
    return (Join-Path (Get-ApacheInstallRoot) 'bin\httpd.exe')
}

function Get-ServiceConfiguredPort {
    param([ValidateSet('IIS','Apache','Nginx')][string]$Servicio)

    switch ($Servicio) {
        'IIS' {
            try {
                $binding = Get-IISBindingObject
                if ($binding) {
                    return [int](($binding.bindingInformation -split ':')[1])
                }
            } catch {}
        }

        'Apache' {
            $conf = Get-ApacheConfPath
            if (Test-Path $conf) {
                $line = Get-Content $conf | Where-Object { $_ -match '^Listen\s+' } | Select-Object -First 1
                if ($line -match ':(\d+)$') { return [int]$matches[1] }
                if ($line -match '^Listen\s+(\d+)$') { return [int]$matches[1] }
            }
        }

        'Nginx' {
            if (Test-Path $script:NGINX_CONF) {
                $line = Get-Content $script:NGINX_CONF | Where-Object { $_ -match '^\s*listen\s+\d+' } | Select-Object -First 1
                if ($line -match 'listen\s+(\d+)') { return [int]$matches[1] }
            }
        }
    }

    return $null
}

function Get-IISRealStatus {
    $result = [ordered]@{
        ConfiguredPort = $null
        SiteState      = 'Unknown'
        Listening      = $false
        ListenerPID    = $null
        ProcessName    = $null
        IsActive       = $false
    }

    try {
        Import-IISModules
        $site = Get-Website -Name $script:IIS_SITE -ErrorAction Stop
        $result.SiteState = [string]$site.State

        $binding = Get-IISBindingObject
        if ($binding) {
            $result.ConfiguredPort = [int](($binding.bindingInformation -split ':')[1])
            $listen = Get-NetTCPConnection -State Listen -LocalPort $result.ConfiguredPort -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($listen) {
                $result.Listening = $true
                $result.ListenerPID = $listen.OwningProcess
                if ($listen.OwningProcess -eq 4) {
                    $result.ProcessName = 'System/HTTP.sys'
                } else {
                    try {
                        $result.ProcessName = (Get-Process -Id $listen.OwningProcess -ErrorAction Stop).ProcessName
                    } catch {
                        $result.ProcessName = 'Desconocido'
                    }
                }
            }
        }

        if ($result.SiteState -eq 'Started' -and $result.Listening) {
            $result.IsActive = $true
        }
    } catch {}

    return [pscustomobject]$result
}

function Get-ServiceStateSummary {
    param([ValidateSet('IIS','Apache','Nginx')][string]$Servicio)

    switch ($Servicio) {
        'IIS' {
            $iis = Get-IISRealStatus
            return [pscustomobject]@{
                Name           = 'IIS'
                ConfiguredPort = $iis.ConfiguredPort
                RealPort       = $(if ($iis.Listening) { $iis.ConfiguredPort } else { $null })
                Running        = $iis.IsActive
                Detail         = $(if ($iis.ConfiguredPort -and -not $iis.IsActive) { 'Configurado sin escucha real' } else { '' })
            }
        }

        'Apache' {
            $svcName = Get-ApacheServiceName
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            $port = Get-ServiceConfiguredPort -Servicio 'Apache'
            $listen = $null
            if ($port) {
                $listen = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1
            }
            return [pscustomobject]@{
                Name           = 'Apache'
                ConfiguredPort = $port
                RealPort       = $(if ($listen) { $port } else { $null })
                Running        = [bool]($svc -and $svc.Status -eq 'Running' -and $listen)
                Detail         = $(if ($svc -and $svc.Status -eq 'Running' -and -not $listen -and $port) { 'Servicio arriba sin listener real' } else { '' })
            }
        }

        'Nginx' {
            $svc = Get-Service -Name $script:NGINX_SVC -ErrorAction SilentlyContinue
            $port = Get-ServiceConfiguredPort -Servicio 'Nginx'
            $listen = $null
            if ($port) {
                $listen = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1
            }
            return [pscustomobject]@{
                Name           = 'Nginx'
                ConfiguredPort = $port
                RealPort       = $(if ($listen) { $port } else { $null })
                Running        = [bool]($svc -and $svc.Status -eq 'Running' -and $listen)
                Detail         = $(if ($svc -and $svc.Status -eq 'Running' -and -not $listen -and $port) { 'Servicio arriba sin listener real' } else { '' })
            }
        }
    }
}

function Get-ListeningTable {
    $rows = @()

    foreach ($svc in @('IIS','Apache','Nginx')) {
        $port = Get-ServiceConfiguredPort -Servicio $svc
        if (-not $port) { continue }

        $listen = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $listen) { continue }

        $procName = 'Desconocido'
        if ($listen.OwningProcess -eq 4) {
            $procName = 'System/HTTP.sys'
        } else {
            try {
                $procName = (Get-Process -Id $listen.OwningProcess -ErrorAction Stop).ProcessName
            } catch {}
        }

        $rows += [pscustomobject]@{
            Servicio = $svc
            Puerto   = $port
            PID      = $listen.OwningProcess
            Proceso  = $procName
        }
    }

    return $rows
}

# ---------------------------------------------------------------------------
# FIREWALL / INDEX / PERMISOS
# ---------------------------------------------------------------------------

function Set-FirewallRule {
    param(
        [int]$Puerto,
        [string]$Servicio,
        [int]$PuertoAnterior = 0
    )

    if ($PuertoAnterior -gt 0 -and $PuertoAnterior -ne $Puerto) {
        $oldNames = @(
            "$Servicio-Puerto-$PuertoAnterior",
            "HTTP-Custom-$PuertoAnterior",
            "$Servicio-$PuertoAnterior"
        )
        foreach ($n in $oldNames) {
            Get-NetFirewallRule -DisplayName $n -ErrorAction SilentlyContinue |
                Remove-NetFirewallRule -ErrorAction SilentlyContinue
        }
    }

    $name = "$Servicio-Puerto-$Puerto"
    if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $name -Direction Inbound -Protocol TCP -LocalPort $Puerto -Action Allow -Profile Any | Out-Null
        Write-Ok "Regla de firewall creada para $Servicio en puerto $Puerto."
    }
}

function New-IndexPage {
    param(
        [string]$Servicio,
        [string]$Version,
        [int]$Puerto,
        [string]$Webroot
    )

    if (-not (Test-Path $Webroot)) {
        New-Item -ItemType Directory -Path $Webroot -Force | Out-Null
    }

    $html = @"
<!doctype html>
<html lang="es">
<head>
    <meta charset="utf-8">
    <title>$Servicio</title>
</head>
<body style="font-family:Segoe UI;background:#111827;color:#f9fafb;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;">
    <div style="background:#1f2937;padding:32px 44px;border-radius:16px;box-shadow:0 12px 30px rgba(0,0,0,.35);text-align:center;">
        <h1 style="margin:0 0 12px 0;color:#60a5fa;">$Servicio</h1>
        <p>Servidor: <b>$Servicio</b></p>
        <p>Version: <b>$Version</b></p>
        <p>Puerto: <b>$Puerto</b></p>
        <p>Practica 6 - Windows Server 2022</p>
    </div>
</body>
</html>
"@

    Set-Content -Path (Join-Path $Webroot 'index.html') -Value $html -Encoding UTF8
    Write-Ok "index.html creado en $Webroot"
}

function Set-WebRootPermissions {
    param(
        [string]$Webroot,
        [string]$Identity = 'Users'
    )

    if (-not (Test-Path $Webroot)) {
        New-Item -ItemType Directory -Path $Webroot -Force | Out-Null
    }

    try {
        & icacls $Webroot /inheritance:e | Out-Null
        & icacls $Webroot /grant:r "$Identity:(OI)(CI)(RX)" | Out-Null
        Write-Ok "Permisos NTFS aplicados: $Identity lectura/ejecucion en $Webroot"
    } catch {
        Write-Warn "No se pudieron ajustar permisos NTFS: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# IIS
# ---------------------------------------------------------------------------

function Ensure-IISInstalled {
    Import-Module ServerManager -ErrorAction SilentlyContinue
    Write-Section 'Instalando / habilitando IIS'

    $features = @(
        'Web-Server',
        'Web-WebServer',
        'Web-Common-Http',
        'Web-Default-Doc',
        'Web-Static-Content',
        'Web-Http-Errors',
        'Web-Http-Logging',
        'Web-Performance',
        'Web-Stat-Compression',
        'Web-Security',
        'Web-Filtering',
        'Web-Mgmt-Console'
    )

    foreach ($f in $features) {
        $feature = Get-WindowsFeature -Name $f -ErrorAction SilentlyContinue
        if ($feature -and -not $feature.Installed) {
            Install-WindowsFeature -Name $f -IncludeManagementTools | Out-Null
            Write-Ok "Rol habilitado: $f"
        }
    }
}

function Configure-IISSecurity {
    Import-IISModules
    Write-Info 'Aplicando seguridad en IIS...'

    try {
        Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/requestFiltering' -Name 'removeServerHeader' -Value $true -ErrorAction SilentlyContinue
    } catch {}

    $headers = @(
        @{ name = 'X-Frame-Options'; value = 'SAMEORIGIN' },
        @{ name = 'X-Content-Type-Options'; value = 'nosniff' },
        @{ name = 'X-XSS-Protection'; value = '1; mode=block' }
    )

    foreach ($header in $headers) {
        try {
            Remove-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/httpProtocol/customHeaders' -Name '.' -AtElement @{ name = $header.name } -ErrorAction SilentlyContinue
        } catch {}
        try {
            Add-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/httpProtocol/customHeaders' -Name '.' -Value $header -ErrorAction SilentlyContinue
        } catch {}
    }

    foreach ($verb in @('TRACE','TRACK','DELETE')) {
        try {
            Add-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/security/requestFiltering/verbs' -Name '.' -Value @{ verb = $verb; allowed = 'false' } -ErrorAction SilentlyContinue
        } catch {}
    }

    Write-Ok 'Cabeceras de seguridad y filtros HTTP aplicados en IIS.'
}

function Restart-IISStack {
    foreach ($svc in @('WAS','W3SVC')) {
        try {
            Set-Service -Name $svc -StartupType Automatic -ErrorAction SilentlyContinue
        } catch {}
        try {
            Start-Service -Name $svc -ErrorAction SilentlyContinue
        } catch {}
    }
    Start-Sleep -Seconds 2
}

function Set-IISPort {
    param([int]$Puerto)

    Import-IISModules
    $prev = Get-ServiceConfiguredPort -Servicio 'IIS'

    if (-not (Test-Path $script:IIS_WEBROOT)) {
        New-Item -ItemType Directory -Path $script:IIS_WEBROOT -Force | Out-Null
    }

    if (-not (Test-Path "IIS:\AppPools\$($script:IIS_APPPOOL)")) {
        New-WebAppPool -Name $script:IIS_APPPOOL | Out-Null
    }

    if (-not (Get-Website -Name $script:IIS_SITE -ErrorAction SilentlyContinue)) {
        New-Website -Name $script:IIS_SITE -PhysicalPath $script:IIS_WEBROOT -Port $Puerto -ApplicationPool $script:IIS_APPPOOL | Out-Null
    } else {
        Set-ItemProperty "IIS:\Sites\$($script:IIS_SITE)" -Name physicalPath -Value $script:IIS_WEBROOT
        try {
            Set-ItemProperty "IIS:\Sites\$($script:IIS_SITE)" -Name applicationPool -Value $script:IIS_APPPOOL
        } catch {}
    }

    Stop-Website -Name $script:IIS_SITE -ErrorAction SilentlyContinue
    Remove-IISHttpBindings
    New-WebBinding -Name $script:IIS_SITE -Protocol 'http' -IPAddress '*' -Port $Puerto | Out-Null

    Restart-IISStack
    try {
        Start-WebAppPool -Name $script:IIS_APPPOOL -ErrorAction SilentlyContinue
    } catch {}
    Start-Website -Name $script:IIS_SITE -ErrorAction SilentlyContinue

    Set-FirewallRule -Puerto $Puerto -Servicio 'IIS' -PuertoAnterior $(if ($prev) { $prev } else { 0 })

    $ready = Test-ServiceReady -Servicio 'IIS' -Puerto $Puerto -TimeoutSeconds 25
    if (-not $ready.Ready) {
        Write-Warn 'IIS no quedo completamente operativo al primer intento. Se intentara iisreset.'
        try {
            & iisreset /restart | Out-Null
        } catch {}
        $ready = Test-ServiceReady -Servicio 'IIS' -Puerto $Puerto -TimeoutSeconds 25
    }

    if (-not $ready.Listener) {
        throw "IIS no quedo escuchando en el puerto $Puerto."
    }

    if ($ready.Listener.OwningProcess -eq 4) {
        Write-Info 'IIS esta escuchando a traves de HTTP.sys (PID 4). Esto es normal en Windows.'
    } else {
        Write-Info "IIS listener detectado con PID $($ready.Listener.OwningProcess)."
    }

    if (-not $ready.Http.Success) {
        throw "IIS abrio el puerto $Puerto, pero no respondio HTTP correctamente en localhost."
    }

    Write-Ok "IIS escuchando y respondiendo en puerto $Puerto."
}

function Install-IIS {
    param([int]$Puerto)

    Ensure-IISInstalled
    Configure-IISSecurity
    Set-WebRootPermissions -Webroot $script:IIS_WEBROOT -Identity 'IIS_IUSRS'
    New-IndexPage -Servicio 'IIS' -Version '10.0' -Puerto $Puerto -Webroot $script:IIS_WEBROOT
    Set-IISPort -Puerto $Puerto
    Show-AccessInfo -Servicio 'IIS' -Puerto $Puerto -Webroot $script:IIS_WEBROOT
}

# ---------------------------------------------------------------------------
# APACHE
# ---------------------------------------------------------------------------

function Install-ApacheWindows {
    param(
        [string]$Version = 'latest',
        [int]$Puerto
    )

    Write-Section 'Instalando Apache HTTP Server'
    Initialize-PackageManager

    if ($script:PKG_MANAGER -eq 'winget') {
        if ($Version -and $Version -ne 'latest' -and $Version -ne 'stable') {
            winget install --id Apache.Httpd --version $Version --silent --accept-package-agreements --accept-source-agreements
        } else {
            winget install --id Apache.Httpd --silent --accept-package-agreements --accept-source-agreements
        }
    } elseif ($script:PKG_MANAGER -eq 'choco') {
        if ($Version -and $Version -ne 'latest' -and $Version -ne 'stable') {
            choco install apache-httpd --version $Version -y --no-progress --allow-downgrade
        } else {
            choco install apache-httpd -y --no-progress
        }
    } else {
        throw 'No se detecto winget ni chocolatey para instalar Apache.'
    }

    Start-Sleep -Seconds 5
    Configure-Apache -Puerto $Puerto -Version $Version
}

function Configure-Apache {
    param(
        [int]$Puerto,
        [string]$Version = 'installed'
    )

    $conf = Get-ApacheConfPath
    $root = Get-ApacheInstallRoot
    $prev = Get-ServiceConfiguredPort -Servicio 'Apache'

    if (-not (Test-Path $conf)) {
        throw "No se encontro httpd.conf en $conf"
    }

    $content = Get-Content $conf -Raw
    $content = [regex]::Replace($content, '(?m)^Listen\s+\S+', "Listen $Puerto")

    if ($content -match '(?m)^#?ServerName\s+.*') {
        $content = [regex]::Replace($content, '(?m)^#?ServerName\s+.*', "ServerName localhost:$Puerto")
    } else {
        $content += "`r`nServerName localhost:$Puerto`r`n"
    }

    if ($content -notmatch '(?m)^LoadModule headers_module') {
        $content = $content -replace '(?m)^#\s*LoadModule headers_module modules/mod_headers\.so', 'LoadModule headers_module modules/mod_headers.so'
        if ($content -notmatch '(?m)^LoadModule headers_module') {
            $content += "`r`nLoadModule headers_module modules/mod_headers.so`r`n"
        }
    }

    if ($content -notmatch '(?m)^ServerTokens\s+Prod') {
        $content += "`r`nServerTokens Prod`r`nServerSignature Off`r`nTraceEnable Off`r`n"
    }

    if ($content -notmatch 'Header always set X-Frame-Options') {
        $content += @"

<IfModule headers_module>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
</IfModule>
<LimitExcept GET POST HEAD>
    Require all denied
</LimitExcept>
"@
    }

    Set-Content -Path $conf -Value $content -Encoding UTF8

    $webroot = Get-ApacheWebRoot
    Set-WebRootPermissions -Webroot $webroot -Identity 'Users'
    New-IndexPage -Servicio 'Apache' -Version $Version -Puerto $Puerto -Webroot $webroot

    $svcName = Ensure-ApacheService
    $exe = Get-ApacheExePath

    if (Test-Path $exe) {
        & $exe -t | Out-Null
    }

    try {
        Restart-Service -Name $svcName -Force -ErrorAction Stop
    } catch {
        Start-Service -Name $svcName -ErrorAction SilentlyContinue
    }

    Set-FirewallRule -Puerto $Puerto -Servicio 'Apache' -PuertoAnterior $(if ($prev) { $prev } else { 0 })

    $ready = Test-ServiceReady -Servicio 'Apache' -Puerto $Puerto -TimeoutSeconds 25
    if (-not $ready.Listener) {
        throw "Apache no quedo escuchando en el puerto $Puerto."
    }
    if (-not $ready.Http.Success) {
        throw "Apache abrio el puerto $Puerto, pero no respondio HTTP correctamente en localhost."
    }

    Write-Ok "Apache escuchando y respondiendo en puerto $Puerto."
    Show-AccessInfo -Servicio 'Apache' -Puerto $Puerto -Webroot $webroot
}

# ---------------------------------------------------------------------------
# NGINX
# ---------------------------------------------------------------------------

function Get-NssmPath {
    foreach ($p in $script:NSSM_PATHS) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Ensure-NginxInstalled {
    param([string]$Version = 'latest')

    if (Test-Path "$($script:NGINX_ROOT)\nginx.exe") {
        return
    }

    Write-Section 'Instalando Nginx'

    if (Get-Command choco -ErrorAction SilentlyContinue) {
        if ($Version -and $Version -ne 'latest' -and $Version -ne 'stable') {
            choco install nginx --version $Version -y --no-progress --allow-downgrade
        } else {
            choco install nginx -y --no-progress
        }
        Start-Sleep -Seconds 3

        if (Test-Path 'C:\tools\nginx\nginx.exe' -and -not (Test-Path "$($script:NGINX_ROOT)\nginx.exe")) {
            if (Test-Path $script:NGINX_ROOT) {
                Remove-Item $script:NGINX_ROOT -Recurse -Force -ErrorAction SilentlyContinue
            }
            Copy-Item 'C:\tools\nginx' $script:NGINX_ROOT -Recurse -Force
        }
    }

    if (-not (Test-Path "$($script:NGINX_ROOT)\nginx.exe")) {
        $zip = 'C:\nginx.zip'
        $url = 'https://nginx.org/download/nginx-1.26.3.zip'
        if (-not (Test-Path $zip)) {
            Invoke-WebRequest -Uri $url -OutFile $zip
        }
        Expand-Archive -Path $zip -DestinationPath 'C:\' -Force
        $src = Get-ChildItem 'C:\' -Directory | Where-Object { $_.Name -like 'nginx-*' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($src) {
            if (Test-Path $script:NGINX_ROOT) {
                Remove-Item $script:NGINX_ROOT -Recurse -Force -ErrorAction SilentlyContinue
            }
            Move-Item $src.FullName $script:NGINX_ROOT -Force
        }
    }

    if (-not (Test-Path "$($script:NGINX_ROOT)\nginx.exe")) {
        throw 'No se pudo instalar Nginx.'
    }
}

function Ensure-NginxService {
    $svc = Get-Service -Name $script:NGINX_SVC -ErrorAction SilentlyContinue
    if ($svc) {
        return
    }

    $nssm = Get-NssmPath
    if (-not $nssm -and (Get-Command choco -ErrorAction SilentlyContinue)) {
        choco install nssm -y --no-progress
        $nssm = Get-NssmPath
    }

    if (-not $nssm) {
        throw 'No se encontro NSSM para registrar el servicio de Nginx.'
    }

    & $nssm install $script:NGINX_SVC "$($script:NGINX_ROOT)\nginx.exe" | Out-Null
    & $nssm set $script:NGINX_SVC AppDirectory $script:NGINX_ROOT | Out-Null
    & $nssm set $script:NGINX_SVC AppParameters '-p C:\nginx -c conf\nginx.conf' | Out-Null
    & $nssm set $script:NGINX_SVC Start SERVICE_AUTO_START | Out-Null
    Write-Ok 'Servicio Nginx registrado con NSSM.'
}

function Set-NginxConfig {
    param([int]$Puerto)

    if (-not (Test-Path (Join-Path $script:NGINX_ROOT 'conf'))) {
        New-Item -ItemType Directory -Path (Join-Path $script:NGINX_ROOT 'conf') -Force | Out-Null
    }

    if (-not (Test-Path $script:NGINX_HTML)) {
        New-Item -ItemType Directory -Path $script:NGINX_HTML -Force | Out-Null
    }

    $template = @'
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    server_tokens off;
    sendfile      on;
    keepalive_timeout  65;

    server {
        listen       __PORT__;
        server_name  localhost;
        root         C:/nginx/html;
        index        index.html;

        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;

        if ($request_method ~* "^(TRACE|TRACK|DELETE)$") {
            return 405;
        }

        location / {
            try_files $uri $uri/ =404;
        }
    }
}
'@

    $conf = $template.Replace('__PORT__', [string]$Puerto)
    Set-Content -Path $script:NGINX_CONF -Value $conf -Encoding UTF8
}

function Restart-NginxManaged {
    param(
        [int]$Puerto,
        [int]$PuertoAnterior = 0
    )

    $exe = Join-Path $script:NGINX_ROOT 'nginx.exe'
    if (-not (Test-Path $exe)) {
        throw "No se encontro nginx.exe en $exe"
    }

    & $exe -t -p $script:NGINX_ROOT -c 'conf\nginx.conf' | Out-Null

    Get-Process nginx -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Ensure-NginxService

    try {
        Restart-Service -Name $script:NGINX_SVC -Force -ErrorAction Stop
    } catch {
        Start-Service -Name $script:NGINX_SVC -ErrorAction SilentlyContinue
    }

    $ready = Test-ServiceReady -Servicio 'Nginx' -Puerto $Puerto -TimeoutSeconds 20
    if (-not $ready.Listener) {
        & $exe -p $script:NGINX_ROOT -c 'conf\nginx.conf' | Out-Null
        $ready = Test-ServiceReady -Servicio 'Nginx' -Puerto $Puerto -TimeoutSeconds 20
    }

    Set-FirewallRule -Puerto $Puerto -Servicio 'Nginx' -PuertoAnterior $PuertoAnterior

    if (-not $ready.Listener) {
        throw "Nginx no quedo escuchando en el puerto $Puerto."
    }
    if (-not $ready.Http.Success) {
        throw "Nginx abrio el puerto $Puerto, pero no respondio HTTP correctamente en localhost."
    }

    Write-Ok "Nginx escuchando y respondiendo en puerto $Puerto."
}

function Install-NginxWindows {
    param(
        [string]$Version = 'latest',
        [int]$Puerto
    )

    $prev = Get-ServiceConfiguredPort -Servicio 'Nginx'
    Ensure-NginxInstalled -Version $Version
    Set-NginxConfig -Puerto $Puerto
    Set-WebRootPermissions -Webroot $script:NGINX_HTML -Identity 'Users'
    New-IndexPage -Servicio 'Nginx' -Version $Version -Puerto $Puerto -Webroot $script:NGINX_HTML
    Restart-NginxManaged -Puerto $Puerto -PuertoAnterior $(if ($prev) { $prev } else { 0 })
    Show-AccessInfo -Servicio 'Nginx' -Puerto $Puerto -Webroot $script:NGINX_HTML
}

# ---------------------------------------------------------------------------
# GESTION / LOGS / HEADERS
# ---------------------------------------------------------------------------

function Invoke-ServiceAction {
    param(
        [ValidateSet('IIS','Apache','Nginx')][string]$Servicio,
        [ValidateSet('Start','Stop','Restart')][string]$Action
    )

    switch ($Servicio) {
        'IIS' {
            Import-IISModules
            switch ($Action) {
                'Start' {
                    Restart-IISStack
                    try { Start-WebAppPool -Name $script:IIS_APPPOOL -ErrorAction SilentlyContinue } catch {}
                    Start-Website -Name $script:IIS_SITE -ErrorAction SilentlyContinue
                }
                'Stop' {
                    Stop-Website -Name $script:IIS_SITE -ErrorAction SilentlyContinue
                    Stop-Service W3SVC -ErrorAction SilentlyContinue
                }
                'Restart' {
                    try { & iisreset /restart | Out-Null } catch {}
                }
            }
        }

        'Apache' {
            $svcName = Ensure-ApacheService
            switch ($Action) {
                'Start'   { Start-Service -Name $svcName -ErrorAction SilentlyContinue }
                'Stop'    { Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue }
                'Restart' { Restart-Service -Name $svcName -Force -ErrorAction SilentlyContinue }
            }
        }

        'Nginx' {
            Ensure-NginxService
            switch ($Action) {
                'Start' {
                    Start-Service -Name $script:NGINX_SVC -ErrorAction SilentlyContinue
                }
                'Stop' {
                    Stop-Service -Name $script:NGINX_SVC -Force -ErrorAction SilentlyContinue
                    Get-Process nginx -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                }
                'Restart' {
                    Stop-Service -Name $script:NGINX_SVC -Force -ErrorAction SilentlyContinue
                    Get-Process nginx -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                    Start-Service -Name $script:NGINX_SVC -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

function Show-ServiceLogs {
    param([ValidateSet('IIS','Apache','Nginx')][string]$Servicio)

    Write-Section "Logs recientes: $Servicio"

    switch ($Servicio) {
        'IIS' {
            $file = Get-ChildItem 'C:\inetpub\logs\LogFiles' -Recurse -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($file) {
                Get-Content $file.FullName -Tail 20
            } else {
                Write-Warn 'No se encontraron logs IIS.'
            }
        }

        'Apache' {
            $root = Get-ApacheInstallRoot
            $file = Get-ChildItem (Join-Path $root 'logs') -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($file) {
                Get-Content $file.FullName -Tail 20
            } else {
                Write-Warn 'No se encontraron logs Apache.'
            }
        }

        'Nginx' {
            $file = Get-ChildItem (Join-Path $script:NGINX_ROOT 'logs') -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($file) {
                Get-Content $file.FullName -Tail 20
            } else {
                Write-Warn 'No se encontraron logs Nginx.'
            }
        }
    }
}

function Test-HttpHeaders {
    param([ValidateSet('IIS','Apache','Nginx')][string]$Servicio)

    $port = Get-ServiceConfiguredPort -Servicio $Servicio
    if (-not $port) {
        Write-Warn "No se detecto puerto configurado para $Servicio."
        return
    }

    Write-Section "curl -I para $Servicio"
    & curl.exe -I "http://127.0.0.1:$port"
}

function Stop-ListeningServiceByPort {
    param([int]$Puerto)

    $conn = Get-NetTCPConnection -State Listen -LocalPort $Puerto -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $conn) {
        Write-Warn "No hay listener en puerto $Puerto."
        return
    }

    $pid = $conn.OwningProcess
    if ($pid -eq 4) {
        $iisPort = (Get-IISRealStatus).ConfiguredPort
        if ($iisPort -eq $Puerto) {
            try {
                Stop-Website -Name $script:IIS_SITE -ErrorAction SilentlyContinue
            } catch {}
            try {
                Stop-Service W3SVC -ErrorAction SilentlyContinue
            } catch {}
            Write-Ok "IIS detenido para liberar puerto $Puerto."
            return
        }

        Write-Warn 'El PID 4 corresponde a System/HTTP.sys. No se liberara a la fuerza.'
        return
    }

    try {
        $proc = Get-Process -Id $pid -ErrorAction Stop
        Stop-Process -Id $pid -Force
        Write-Ok "Proceso $($proc.ProcessName) detenido para liberar puerto $Puerto."
    } catch {
        Write-Warn "No se pudo detener el PID $pid."
    }
}
