# ==============================================================================
# Practica-06: main.ps1
# ==============================================================================

# Forzar codificacion UTF8 para evitar simbolos extraños
$OutputEncoding = [System.Text.Encoding]::UTF8

# --- LIBRERIA DE FUNCIONES INTEGRADAS ---

function Test-PortAvailability {
    param([int]$Port)
    $connection = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    if ($connection) { return $false }
    return $true
}

function Test-IsReservedPort {
    param([int]$Port)
    if ($Port -lt 1 -or $Port -gt 65535) { return $true }
    return $false
}

function New-IndexPage {
    param([string]$Service, [string]$Version, [int]$Port, [string]$Path)
    $html = "Servidor: $Service`nVersion: $Version`nPuerto: $Port"
    if (-not (Test-Path $Path)) { New-Item -Path $Path -ItemType Directory -Force | Out-Null }
    Set-Content -Path (Join-Path $Path "index.html") -Value $html -Force
    Write-Host "[*] Pagina de index creada en $Path" -ForegroundColor Gray
}

function Install-IIS {
    param([int]$Port)
    Write-Host "`n[*] Habilitando IIS (Internet Information Services)..." -ForegroundColor Blue
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "IIS-WebServerRole", "IIS-WebServer", "IIS-CommonHttpFeatures" -NoRestart -ErrorAction SilentlyContinue | Out-Null
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        
        # Detectar sitio existe
        $site = Get-Website | Select-Object -First 1
        if ($site) {
            Write-Host "[*] Aplicando puerto $Port a $($site.Name)..." -ForegroundColor Cyan
            Set-ItemProperty "IIS:\Sites\$($site.Name)" -Name bindings -Value @{protocol="http";bindingInformation="*:${Port}:"}
            Set-ItemProperty "IIS:\Sites\$($site.Name)" -Name serverAutoStart -Value $true
        } else {
            Write-Host "[*] Creando nuevo sitio Default Web Site..." -ForegroundColor Cyan
            New-Website -Name "Default Web Site" -Port $Port -PhysicalPath "C:\inetpub\wwwroot" -Force | Out-Null
        }
        
        # Reiniciar IIS
        Write-Host "[*] Reiniciando servicios de IIS (iisreset)..." -ForegroundColor Yellow
        iisreset /restart | Out-Null
        Start-Sleep -Seconds 2
        
        # Asegurar encendido
        Start-Website -Name "*" -ErrorAction SilentlyContinue
        
        New-IndexPage -Service "IIS" -Version "LTS" -Port $Port -Path "C:\inetpub\wwwroot"
        
        # Firewall Extremo
        Write-Host "[*] Abriendo Firewall para puerto $Port (Perfiles: Any)..." -ForegroundColor Cyan
        Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "HTTP-Practice-*" } | Remove-NetFirewallRule -ErrorAction SilentlyContinue
        New-NetFirewallRule -Name "HTTP-Practice-$Port" -DisplayName "HTTP-Practice-$Port" -LocalPort $Port -Protocol TCP -Action Allow -Direction Inbound -Profile Any -Enabled True | Out-Null
        
        Write-Host "[OK] IIS configurado y accesible en el puerto $Port" -ForegroundColor Green
    } catch {
        Write-Host "[!] Error critico al configurar IIS: $_" -ForegroundColor Red
    }
}

function Install-ApacheWindows {
    param([string]$Version, [int]$Port)
    Write-Host "`n[*] Instalando Apache version $Version..." -ForegroundColor Blue
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "[!] Chocolatey no detectado. Instala choco primero." -ForegroundColor Red; return
    }
    choco install apache-httpd --version $Version -y | Out-Null
    $confPath = "C:\tools\apache24\conf\httpd.conf"
    if (Test-Path $confPath) {
        (Get-Content $confPath) -replace "^Listen\s+\d+", "Listen $Port" | Set-Content $confPath
        Add-Content $confPath "`nServerTokens Prod`nServerSignature Off"
    }
    New-IndexPage -Service "Apache" -Version $Version -Port $Port -Path "C:\tools\apache24\htdocs"
    
    Remove-NetFirewallRule -DisplayName "Apache-Practice-*" -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "Apache-Practice-${Port}" -LocalPort $Port -Protocol TCP -Action Allow -Direction Inbound -Profile Any | Out-Null
    
    Restart-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
    Write-Host "[OK] Apache configurado en el puerto $Port" -ForegroundColor Green
}

function Install-NginxWindows {
    param([string]$Version, [int]$Port)
    Write-Host "`n[*] Instalando Nginx version $Version..." -ForegroundColor Blue
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "[!] Chocolatey no detectado." -ForegroundColor Red; return
    }
    choco install nginx --version $Version -y | Out-Null
    $confPath = "C:\tools\nginx\conf\nginx.conf"
    if (Test-Path $confPath) {
        $content = Get-Content $confPath
        $content = $content -replace "listen\s+\d+;", "listen $Port;"
        $content | Set-Content $confPath
    }
    New-IndexPage -Service "Nginx" -Version $Version -Port $Port -Path "C:\tools\nginx\html"
    
    Remove-NetFirewallRule -DisplayName "Nginx-Practice-*" -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "Nginx-Practice-${Port}" -LocalPort $Port -Protocol TCP -Action Allow -Direction Inbound -Profile Any | Out-Null
    
    Write-Host "[OK] Nginx instalado en puerto $Port. (Ejecuta el binario para iniciar)" -ForegroundColor Green
}

function Get-ServicesStatus {
    Write-Host "`n==========================================" -ForegroundColor Blue
    Write-Host "       ESTADO DE LOS SERVICIOS WEB        " -ForegroundColor Blue
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host ("{0,-15} | {1,-12} | {2,-10}" -f "SERVICIO", "ESTADO", "PUERTO(S)")
    
    $services = @(
        @{Name="IIS"; Binary="w3wp"; SrvName="W3SVC"},
        @{Name="Apache"; Binary="httpd"; SrvName="Apache2.4"},
        @{Name="Nginx"; Binary="nginx"; SrvName=""}
    )
    
    foreach ($srv in $services) {
        $status = "Detenido"; $color = "Red"; $ports = "-"
        $isRunning = $false
        if ($srv.SrvName -ne "") {
            $s = Get-Service -Name $srv.SrvName -ErrorAction SilentlyContinue
            if ($s -and $s.Status -eq "Running") { $isRunning = $true }
        } else {
            if (Get-Process -Name $srv.Binary -ErrorAction SilentlyContinue) { $isRunning = $true }
        }
        
        if ($isRunning) {
            $status = "Corriendo"; $color = "Green"
            if ($srv.Name -eq "IIS") {
                try {
                    Import-Module WebAdministration -ErrorAction SilentlyContinue
                    $ports = (Get-WebBinding -Protocol "http").bindingInformation.Split(":")[1] -join ","
                } catch { $ports = "?" }
            } else {
                $conns = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { 
                    $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
                    $proc.Name -like "*$($srv.Binary)*"
                }
                $ports = ($conns.LocalPort | Select-Object -Unique) -join ","
            }
        }
        Write-Host ("{0,-15} | " -f $srv.Name) -NoNewline
        Write-Host ("{0,-12}" -f $status) -ForegroundColor $color -NoNewline
        Write-Host (" | {0,-10}" -f $ports)
    }
}

function Stop-WindowsService {
    param([string]$ServiceName)
    switch ($ServiceName) {
        "IIS" { Stop-Service -Name "W3SVC" -ErrorAction SilentlyContinue; iisreset /stop | Out-Null }
        "Apache" { Stop-Service -Name "Apache2.4" -ErrorAction SilentlyContinue }
        "Nginx" { Stop-Process -Name "nginx" -ErrorAction SilentlyContinue }
    }
    Write-Host "[OK] Servicio $ServiceName detenido." -ForegroundColor Green
}

function Clear-WindowsService {
    param([string]$ServiceName)
    Write-Host "[!] Eliminando por completo $ServiceName..." -ForegroundColor Red
    switch ($ServiceName) {
        "IIS" { 
            Disable-WindowsOptionalFeature -Online -FeatureName "IIS-WebServerRole" -NoRestart | Out-Null
        }
        "Apache" { 
            Stop-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
            choco uninstall apache-httpd -y | Out-Null
            if (Test-Path "C:\tools\apache24") { Remove-Item "C:\tools\apache24" -Recurse -Force -ErrorAction SilentlyContinue }
        }
        "Nginx" { 
            Stop-Process -Name "nginx" -ErrorAction SilentlyContinue
            choco uninstall nginx -y | Out-Null
            if (Test-Path "C:\tools\nginx") { Remove-Item "C:\tools\nginx" -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    Write-Host "[OK] Purga de $ServiceName completada." -ForegroundColor Green
}

# --- LOGICA DEL MENU ---

while ($true) {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "   SISTEMA DE APROVISIONAMIENTO WEB (WIN)   " -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "1. Instalar IIS"
    Write-Host "2. Instalar Apache"
    Write-Host "3. Instalar Nginx"
    Write-Host "4. Mostrar estado de los servicios"
    Write-Host "5. Bajar un servicio"
    Write-Host "6. Eliminar por completo un servicio (Purge)"
    Write-Host "7. Salir"
    Write-Host "==========================================" -ForegroundColor Green
    
    $opt = Read-Host "Cual es tu opcion?"
    
    switch ($opt) {
        "1" {
            $port = Read-Host "Puerto para IIS?"
            if (Test-IsReservedPort $port) { Write-Host "Puerto invalido"; Start-Sleep 2; continue }
            Install-IIS $port
            Read-Host "Presiona Enter..."
        }
        "2" {
            $port = Read-Host "Puerto para Apache?"
            if (Test-IsReservedPort $port) { Write-Host "Puerto invalido"; Start-Sleep 2; continue }
            Install-ApacheWindows "2.4.58" $port
            Read-Host "Presiona Enter..."
        }
        "3" {
            $port = Read-Host "Puerto para Nginx?"
            if (Test-IsReservedPort $port) { Write-Host "Puerto invalido"; Start-Sleep 2; continue }
            Install-NginxWindows "1.24.0" $port
            Read-Host "Presiona Enter..."
        }
        "4" {
            Get-ServicesStatus
            Read-Host "`nPresiona Enter..."
        }
        "5" {
            Write-Host "1.IIS 2.Apache 3.Nginx"
            $s = Read-Host "Cual bajas?"
            if($s -eq "1"){ Stop-WindowsService "IIS" }
            elseif($s -eq "2"){ Stop-WindowsService "Apache" }
            elseif($s -eq "3"){ Stop-WindowsService "Nginx" }
            Read-Host "Presiona Enter..."
        }
        "6" {
            Write-Host "1.IIS 2.Apache 3.Nginx"
            $p = Read-Host "Cual eliminas (PURGE)?"
            if($p -eq "1"){ Clear-WindowsService "IIS" }
            elseif($p -eq "2"){ Clear-WindowsService "Apache" }
            elseif($p -eq "3"){ Clear-WindowsService "Nginx" }
            Read-Host "Presiona Enter..."
        }
        "7" { exit }
        Default { Write-Host "Opcion invalida"; Start-Sleep 1 }
    }
}
