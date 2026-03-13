# ==============================================================================
# Practica-06: main.ps1 - CORRECCION DEFINITIVA DE PUERTOS
# ==============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8

function New-IndexPage {
    param([string]$Service, [string]$Version, [int]$Port, [string]$Path)
    $html = "Servidor: $Service`nVersion: $Version`nPuerto: $Port"
    if (-not (Test-Path $Path)) { New-Item -Path $Path -ItemType Directory -Force | Out-Null }
    Set-Content -Path (Join-Path $Path "index.html") -Value $html -Force
}

function Install-IIS {
    param([int]$Port)
    Write-Host "`n[*] Forzando configuracion de IIS en puerto ${Port}..." -ForegroundColor Blue
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "IIS-WebServerRole", "IIS-WebServer", "IIS-CommonHttpFeatures" -NoRestart | Out-Null
        
        # Reset para desbloquear configs
        iisreset /restart | Out-Null
        Start-Sleep -Seconds 2

        Import-Module WebAdministration
        
        # Obtener nombre del sitio
        $site = Get-Website | Select-Object -First 1
        $sn = if ($site) { $site.Name } else { "Default Web Site" }

        # Configurar via PowerShell (mas compatible para lectura)
        if (-not (Get-Website -Name "$sn" -ErrorAction SilentlyContinue)) {
            New-Website -Name "$sn" -Port $Port -PhysicalPath "C:\inetpub\wwwroot" -Force | Out-Null
        } else {
            Set-ItemProperty "IIS:\Sites\$sn" -Name bindings -Value @{protocol="http";bindingInformation="*:${Port}:"}
        }

        # Asegurar arranque
        Start-Website -Name "$sn" -ErrorAction SilentlyContinue
        iisreset /start | Out-Null
        
        New-IndexPage -Service "IIS" -Version "LTS" -Port $Port -Path "C:\inetpub\wwwroot"
        
        # Firewall
        $rn = "HTTP-Practice-$Port"
        Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "HTTP-Practice-*" } | Remove-NetFirewallRule -ErrorAction SilentlyContinue
        New-NetFirewallRule -Name $rn -DisplayName $rn -LocalPort $Port -Protocol TCP -Action Allow -Direction Inbound -Profile Any | Out-Null
        
        Write-Host "[OK] IIS configurado y encendido en puerto $Port" -ForegroundColor Green
    } catch {
        Write-Host "[!] Error: $_" -ForegroundColor Red
    }
}

function Install-ApacheWindows {
    param([string]$Version, [int]$Port)
    Write-Host "`n[*] Instalando Apache $Version en puerto $Port..." -ForegroundColor Blue
    choco install apache-httpd --version $Version -y | Out-Null
    $conf = "C:\tools\apache24\conf\httpd.conf"
    if (Test-Path $conf) {
        (Get-Content $conf) -replace "^Listen\s+\d+", "Listen $Port" | Set-Content $conf
    }
    New-IndexPage -Service "Apache" -Version $Version -Port $Port -Path "C:\tools\apache24\htdocs"
    Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "Apache-Practice-*" } | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "Apache-Practice-$Port" -LocalPort $Port -Protocol TCP -Action Allow -Profile Any | Out-Null
    Restart-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
    Write-Host "[OK] Apache listo." -ForegroundColor Green
}

function Install-NginxWindows {
    param([string]$Version, [int]$Port)
    Write-Host "`n[*] Instalando Nginx en puerto $Port..." -ForegroundColor Blue
    choco install nginx --version $Version -y | Out-Null
    $conf = "C:\tools\nginx\conf\nginx.conf"
    if (Test-Path $conf) {
        (Get-Content $conf) -replace "listen\s+\d+;", "listen $Port;" | Set-Content $conf
    }
    New-IndexPage -Service "Nginx" -Version $Version -Port $Port -Path "C:\tools\nginx\html"
    Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "Nginx-Practice-*" } | Remove-NetFirewallRule -ErrorAction SilentlyContinue
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
            if ($s -and $srv.Name -eq "IIS" -and $s.Status -eq "Running") { $isRunning = $true }
            elseif ($s -and $s.Status -eq "Running") { $isRunning = $true }
        } else {
            if (Get-Process -Name $srv.Binary -ErrorAction SilentlyContinue) { $isRunning = $true }
        }
        
        if ($isRunning) {
            $status = "Corriendo"; $color = "Green"
            if ($srv.Name -eq "IIS") {
                Import-Module WebAdministration -ErrorAction SilentlyContinue
                $ports = (Get-WebBinding -Protocol "http").bindingInformation.Split(":")[1] -join ","
                if (-not $ports) { $ports = "?" }
            } else {
                $conns = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { 
                    $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
                    $proc.Name -match $srv.Binary
                }
                $ports = ($conns.LocalPort | Select-Object -Unique) -join ","
            }
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
