# ==============================================================================
# Practica-07: http_functions.ps1
# Librería de funciones para aprovisionamiento web automatizado en Windows
# ==============================================================================

# Validar entrada
function Validate-InputString {
    param([string]$InputStr)
    if ([string]::IsNullOrWhiteSpace($InputStr) -or $InputStr -match '[^a-zA-Z0-9._-]') {
        return $false
    }
    return $true
}

# Verificar disponibilidad de puerto
function Test-PortAvailability {
    param([int]$Port)
    $connection = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    if ($connection) {
        return $false # Ocupado
    }
    return $true # Libre
}

# Validar puerto reservado
function Test-IsReservedPort {
    param([int]$Port)
    # Incluimos 444 según requerimiento de la práctica para demostración
    $reserved = @(21, 22, 23, 25, 53, 110, 143, 443, 444, 3306, 5432)
    if ($reserved -contains $Port) {
        return $true
    }
    return $false
}

# Obtener versiones dinámicamente usando Chocolatey
function Get-ServiceVersions {
    param([string]$PackageName)
    Write-Host "Consultando versiones para $PackageName en Chocolatey..." -ForegroundColor Blue
    $versions = choco search $PackageName --all | Select-String -Pattern "$PackageName\s+([\d\.]+)" | Select-Object -First 5
    return $versions
}

# Crear página index.html personalizada
function New-IndexPage {
    param(
        [string]$Service,
        [string]$Version,
        [int]$Port,
        [string]$Path
    )
    
    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Servidor `$Service</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f0f2f5; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .card { background: white; padding: 2rem; border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,0.1); text-align: center; }
        h1 { color: #1a73e8; }
        .info { font-size: 1.2rem; margin: 10px 0; color: #5f6368; }
        .badge { background: #e8f0fe; color: #1967d2; padding: 5px 12px; border-radius: 20px; font-weight: bold; }
    </style>
</head>
<body>
    <div class="card">
        <h1>Servidor Provisionado (Windows)</h1>
        <p class="info">Servidor: <span class="badge">`$Service</span></p>
        <p class="info">Versión: <span class="badge">`$Version</span></p>
        <p class="info">Puerto: <span class="badge">`$Port</span></p>
    </div>
</body>
</html>
"@
    New-Item -Path $Path -Name "index.html" -Value $html -ItemType File -Force
    # Permisos limitados (Solo lectura para el servicio)
    $acl = Get-Acl $Path
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("IIS_IUSRS", "ReadAndExecute", "Allow")
    $acl.SetAccessRule($rule)
    Set-Acl $Path $acl
}

# Configuración de Seguridad IIS
function Set-IISSecurity {
    param([int]$Port)
    Write-Host "Configurando seguridad de IIS..." -ForegroundColor Cyan
    Import-Module WebAdministration
    
    # Ocultar X-Powered-By
    Remove-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Filter "system.webServer/httpProtocol/customHeaders" -Name "X-Powered-By" -ErrorAction SilentlyContinue
    
    # Agregar Security Headers
    Add-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Filter "system.webServer/httpProtocol/customHeaders" -Name "." -Value @{name='X-Frame-Options';value='SAMEORIGIN'}
    Add-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Filter "system.webServer/httpProtocol/customHeaders" -Name "." -Value @{name='X-Content-Type-Options';value='nosniff'}

    # Abrir Firewall
    New-NetFirewallRule -DisplayName "HTTP-Practice-$Port" -LocalPort $Port -Protocol TCP -Action Allow -Force
}

# Instalación de IIS
function Install-IIS {
    param([int]$Port)
    Write-Host "Habilitando IIS (Internet Information Services)..." -ForegroundColor Blue
    Enable-WindowsOptionalFeature -Online -FeatureName "IIS-WebServerRole", "IIS-WebServer", "IIS-CommonHttpFeatures" -NoRestart
    
    Import-Module WebAdministration
    # Cambiar puerto del sitio por defecto
    Set-WebBinding -Name "Default Web Site" -BindingInformation "*:$Port:"
    
    New-IndexPage -Service "IIS" -Version "LTS (Windows Feature)" -Port $Port -Path "C:\inetpub\wwwroot"
    Set-IISSecurity -Port $Port
}

# Instalación de Apache Win64
function Install-ApacheWindows {
    param([string]$Version, [int]$Port)
    Write-Host "Instalando Apache Win64 versión $Version..." -ForegroundColor Blue
    choco install apache-httpd --version $Version -y
    
    $confPath = "C:\tools\apache24\conf\httpd.conf"
    if (Test-Path $confPath) {
        (Get-Content $confPath) -replace "Listen 80", "Listen $Port" | Set-Content $confPath
        
        # Ocultar tokens
        Add-Content $confPath "`nServerTokens Prod`nServerSignature Off"
    }
    
    # Firewall
    New-NetFirewallRule -DisplayName "Apache-Practice-$Port" -LocalPort $Port -Protocol TCP -Action Allow -Force
    Start-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
}

# Instalación de Nginx Windows
function Install-NginxWindows {
    param([string]$Version, [int]$Port)
    Write-Host "Instalando Nginx para Windows versión $Version..." -ForegroundColor Blue
    choco install nginx --version $Version -y
    
    $confPath = "C:\tools\nginx\conf\nginx.conf"
    if (Test-Path $confPath) {
        (Get-Content $confPath) -replace "listen\s+80;", "listen $Port;" | Set-Content $confPath
        # Ocultar versión
        (Get-Content $confPath) -replace "#server_tokens off;", "server_tokens off;" | Set-Content $confPath
    }
    
    # Firewall
    New-NetFirewallRule -DisplayName "Nginx-Practice-$Port" -LocalPort $Port -Protocol TCP -Action Allow -Force
    # Nginx en windows se suele correr como proceso o servicio nssm
}
