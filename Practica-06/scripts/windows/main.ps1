# ==============================================================================
# Practica-06: main.ps1 - VERSION PROFESIONAL Y ROBUSTA
# ==============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8

function New-IndexPage {
    param([string]$Service, [string]$Version, [int]$Port, [string]$Path)
    $html = "<html><body style='font-family:Arial;text-align:center;'><h1>Servidor $Service Listo</h1><h2>Puerto: $Port</h2></body></html>"
    if (-not (Test-Path $Path)) { New-Item -Path $Path -ItemType Directory -Force | Out-Null }
    Set-Content -Path (Join-Path $Path "index.html") -Value $html -Force
}

function Install-IIS {
    param([int]$Port)
    Write-Host "`n[*] Configurando IIS en puerto universal ${Port}..." -ForegroundColor Blue
    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        Enable-WindowsOptionalFeature -Online -FeatureName "IIS-WebServerRole", "IIS-WebServer" -NoRestart | Out-Null
        
        # 1. Identificar sitio
        $site = Get-Website | Select-Object -First 1
        $sn = if ($site) { $site.Name } else { "Default Web Site" }

        # 2. Configurar el puerto de forma agresiva (Binding Universal)
        Write-Host "[*] Aplicando enlace http://*:${Port}..." -ForegroundColor Cyan
        Get-WebBinding -Name "$sn" | Remove-WebBinding -ErrorAction SilentlyContinue
        New-WebBinding -Name "$sn" -Port $Port -Protocol http -IPAddress "*" | Out-Null
        
        # 3. Asegurar que el sitio y el servicio esten activos
        Start-Website -Name "$sn" -ErrorAction SilentlyContinue
        iisreset /start | Out-Null
        
        New-IndexPage -Service "IIS" -Version "LTS" -Port $Port -Path "C:\inetpub\wwwroot"
        
        # 4. Firewall (Regla Maestra)
        Write-Host "[*] Abriendo paso en Firewall de Windows..." -ForegroundColor Yellow
        Remove-NetFirewallRule -DisplayName "HTTP-Practice-*" -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -Name "HTTP-P-$Port" -DisplayName "HTTP-Practice-$Port" -LocalPort $Port -Protocol TCP -Action Allow -Direction Inbound -Profile Any -Enabled True | Out-Null
        
        # 5. Verificacion de escucha real
        Start-Sleep -Seconds 2
        if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
            Write-Host "[OK] IIS ahora escucha en el puerto $Port y es accesible externamente." -ForegroundColor Green
        } else {
            Write-Host "[!] Windows aun no reporta escucha en $Port. Intentando Reinicio Final..." -ForegroundColor Red
            iisreset /restart | Out-Null
        }
    } catch {
        Write-Host "[!] Error critico: $_" -ForegroundColor Red
    }
}

function Install-ApacheWindows {
    param([string]$Version, [int]$Port)
    Write-Host "`n[*] Instalando Apache..." -ForegroundColor Blue
    choco install apache-httpd --version $Version -y | Out-Null
    $conf = "C:\tools\apache24\conf\httpd.conf"
    if (Test-Path $conf) { (Get-Content $conf) -replace "^Listen\s+\d+", "Listen $Port" | Set-Content $conf }
    New-IndexPage -Service "Apache" -Version $Version -Port $Port -Path "C:\tools\apache24\htdocs"
    Remove-NetFirewallRule -DisplayName "Apache-Practice-*" -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "Apache-Practice-$Port" -LocalPort $Port -Protocol TCP -Action Allow -Profile Any | Out-Null
    Restart-Service Apache2.4 -ErrorAction SilentlyContinue
    Write-Host "[OK] Apache listo." -ForegroundColor Green
}

function Install-NginxWindows {
    param([string]$Version, [int]$Port)
    Write-Host "`n[*] Instalando Nginx..." -ForegroundColor Blue
    choco install nginx --version $Version -y | Out-Null
    $conf = "C:\tools\nginx\conf\nginx.conf"
    if (Test-Path $conf) { (Get-Content $conf) -replace "listen\s+\d+;", "listen $Port;" | Set-Content $conf }
    New-IndexPage -Service "Nginx" -Version $Version -Port $Port -Path "C:\tools\nginx\html"
    Remove-NetFirewallRule -DisplayName "Nginx-Practice-*" -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "Nginx-Practice-$Port" -LocalPort $Port -Protocol TCP -Action Allow -Profile Any | Out-Null
    Stop-Process -Name nginx -ErrorAction SilentlyContinue
    Start-Process -FilePath "C:\tools\nginx\nginx.exe" -WorkingDirectory "C:\tools\nginx"
    Write-Host "[OK] Nginx listo." -ForegroundColor Green
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
            # Busqueda de puerto real por red
            $foundPorts = (Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { 
                $p = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
                $p.Name -match $srv.Binary -or $p.Name -match $srv.Name
            }).LocalPort | Select-Object -Unique
            $ports = if ($foundPorts) { $foundPorts -join "," } else { "Activo" }
        }
        Write-Host ("{0,-15} | " -f $srv.Name) -NoNewline
        Write-Host ("{0,-12}" -f $status) -ForegroundColor $color -NoNewline
        Write-Host (" | {0,-10}" -f $ports)
    }
}

while ($true) {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "   GESTOR DE SERVIDORES WEB (P6)          " -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "1. Configurar IIS"
    Write-Host "2. Instalar Apache"
    Write-Host "3. Instalar Nginx"
    Write-Host "4. Estado"
    Write-Host "5. Salir"
    
    $op = Read-Host "`nOpcion"
    switch ($op) {
        "1" { $p = Read-Host "Puerto?"; Install-IIS $p; Read-Host "Enter..." }
        "2" { $p = Read-Host "Puerto?"; Install-ApacheWindows "2.4.58" $p; Read-Host "Enter..." }
        "3" { $p = Read-Host "Puerto?"; Install-NginxWindows "1.24.0" $p; Read-Host "Enter..." }
        "4" { Get-ServicesStatus; Read-Host "`nEnter..." }
        "5" { exit }
    }
}
