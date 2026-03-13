# ==============================================================================
# Practica-06: main.ps1 - VERSION FINAL CORREGIDA (SIN ERRORES DE BLOQUEO)
# ==============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8

# --- FUNCIONES DE APOYO ---

function New-IndexPage {
    param([string]$Service, [string]$Version, [int]$Port, [string]$Path)
    $html = "<html><body style='font-family:sans-serif; text-align:center; padding-top:50px;'><h1>Servicio: $Service</h1><h3>Version: $Version</h3><h3>Puerto actual: $Port</h3><p>Estado: Activo y Funcionando</p></body></html>"
    if (-not (Test-Path $Path)) { New-Item -Path $Path -ItemType Directory -Force | Out-Null }
    Set-Content -Path (Join-Path $Path "index.html") -Value $html -Force
}

function Install-IIS {
    param([int]$Port)
    Write-Host "`n[*] Iniciando configuracion profesional de IIS..." -ForegroundColor Blue
    try {
        # 1. Asegurar caracteristicas de Windows
        Enable-WindowsOptionalFeature -Online -FeatureName "IIS-WebServerRole", "IIS-WebServer", "IIS-CommonHttpFeatures" -NoRestart -ErrorAction SilentlyContinue | Out-Null
        
        # 2. Reset previo para liberar archivos bloqueados (Vital)
        Write-Host "[*] Liberando bloqueos de configuracion..." -ForegroundColor Yellow
        iisreset /restart | Out-Null
        Start-Sleep -Seconds 2

        Import-Module WebAdministration -ErrorAction SilentlyContinue
        
        # 3. Detectar sitio principal
        $site = Get-Website | Select-Object -First 1
        $siteName = if ($site) { $site.Name } else { "Default Web Site" }

        # 4. Usar APPCMD para configuracion de bajo nivel (mas robusto que PowerShell)
        Write-Host "[*] Aplicando puerto $Port via APPCMD..." -ForegroundColor Cyan
        $appcmd = "$env:SystemRoot\system32\inetsrv\appcmd.exe"
        
        if (-not $site) {
            & $appcmd add site /name:"Default Web Site" /bindings:http/*:${Port}: /physicalPath:"C:\inetpub\wwwroot" | Out-Null
        } else {
            & $appcmd set site /site.name:"$siteName" /bindings:http/*:${Port}: | Out-Null
        }

        # 5. Crear la pagina de inicio
        New-IndexPage -Service "IIS" -Version "Windows Server" -Port $Port -Path "C:\inetpub\wwwroot"

        # 6. Reinicio final y encendido
        iisreset /start | Out-Null
        Start-Website -Name "$siteName" -ErrorAction SilentlyContinue
        
        # 7. Firewall Total
        $ruleName = "HTTP-Practice-$Port"
        Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "HTTP-Practice-*" } | Remove-NetFirewallRule -ErrorAction SilentlyContinue
        New-NetFirewallRule -Name $ruleName -DisplayName $ruleName -LocalPort $Port -Protocol TCP -Action Allow -Direction Inbound -Profile Any | Out-Null
        
        Write-Host "[OK] IIS configurado perfectamente en puerto $Port" -ForegroundColor Green
    } catch {
        Write-Host "[!] Error en IIS: $_" -ForegroundColor Red
        Write-Host "[CONSEJO] Si el error persiste, reinicia la VM una vez." -ForegroundColor Yellow
    }
}

function Install-ApacheWindows {
    param([string]$Version, [int]$Port)
    Write-Host "`n[*] Instalando Apache $Version..." -ForegroundColor Blue
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) { Write-Host "[!] Falta Chocolatey"; return }
    
    choco install apache-httpd --version $Version -y | Out-Null
    $confPath = "C:\tools\apache24\conf\httpd.conf"
    if (Test-Path $confPath) {
        $content = Get-Content $confPath
        $content = $content -replace "^Listen\s+\d+", "Listen $Port"
        $content | Set-Content $confPath
    }
    New-IndexPage -Service "Apache" -Version $Version -Port $Port -Path "C:\tools\apache24\htdocs"
    
    # Firewall
    Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "Apache-Practice-*" } | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "Apache-Practice-$Port" -LocalPort $Port -Protocol TCP -Action Allow -Direction Inbound -Profile Any | Out-Null
    
    Restart-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
    Write-Host "[OK] Apache listo en puerto $Port" -ForegroundColor Green
}

function Install-NginxWindows {
    param([string]$Version, [int]$Port)
    Write-Host "`n[*] Instalando Nginx $Version..." -ForegroundColor Blue
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) { Write-Host "[!] Falta Chocolatey"; return }
    
    choco install nginx --version $Version -y | Out-Null
    $confPath = "C:\tools\nginx\conf\nginx.conf"
    if (Test-Path $confPath) {
        $content = Get-Content $confPath
        $content = $content -replace "listen\s+\d+;", "listen $Port;"
        $content | Set-Content $confPath
    }
    New-IndexPage -Service "Nginx" -Version $Version -Port $Port -Path "C:\tools\nginx\html"
    
    # Firewall
    Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "Nginx-Practice-*" } | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "Nginx-Practice-$Port" -LocalPort $Port -Protocol TCP -Action Allow -Direction Inbound -Profile Any | Out-Null
    
    # Iniciar Nginx
    Stop-Process -Name nginx -ErrorAction SilentlyContinue
    Start-Process -FilePath "C:\tools\nginx\nginx.exe" -WorkingDirectory "C:\tools\nginx"
    Write-Host "[OK] Nginx listo en puerto $Port" -ForegroundColor Green
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
            $conns = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { 
                $p = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
                $p.Name -match $srv.Binary -or $p.Name -match $srv.Name
            }
            $ports = ($conns.LocalPort | Select-Object -Unique) -join ","
            if (-not $ports) { $ports = "?" }
        }
        Write-Host ("{0,-15} | " -f $srv.Name) -NoNewline
        Write-Host ("{0,-12}" -f $status) -ForegroundColor $color -NoNewline
        Write-Host (" | {0,-10}" -f $ports)
    }
}

# --- MENU ---

while ($true) {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "   GESTOR DE SERVIDORES WEB (P6)          " -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "1. Instalar/Configurar IIS"
    Write-Host "2. Instalar Apache"
    Write-Host "3. Instalar Nginx"
    Write-Host "4. Ver estado de servicios"
    Write-Host "5. Parar un servicio"
    Write-Host "6. Salir"
    
    $op = Read-Host "`nElige una opcion"
    
    switch ($op) {
        "1" { $p = Read-Host "Puerto?"; Install-IIS $p; Read-Host "Enter..." }
        "2" { $p = Read-Host "Puerto?"; Install-ApacheWindows "2.4.58" $p; Read-Host "Enter..." }
        "3" { $p = Read-Host "Puerto?"; Install-NginxWindows "1.24.0" $p; Read-Host "Enter..." }
        "4" { Get-ServicesStatus; Read-Host "`nEnter..." }
        "5" {
            Write-Host "1.IIS 2.Apache 3.Nginx"
            $s = Read-Host "Cual?"; 
            if($s -eq "1"){ Stop-Service W3SVC -ErrorAction SilentlyContinue; iisreset /stop }
            elseif($s -eq "2"){ Stop-Service Apache2.4 -ErrorAction SilentlyContinue }
            elseif($s -eq "3"){ Stop-Process -Name nginx -ErrorAction SilentlyContinue }
            Read-Host "Enter..."
        }
        "6" { exit }
    }
}
