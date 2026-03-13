# ==============================================================================
# Practica-06: main.ps1 - VERSION 100% OPERATIVA (ANTI-BLOQUEOS)
# ==============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8

# --- FUNCIONES DE SEGURIDAD ---

function Set-FolderSecurity {
    param([string]$Path, [string]$User)
    Write-Host "[*] Aplicando restricciones NTFS en $Path..." -ForegroundColor Gray
    if (-not (Test-Path $Path)) { New-Item -Path $Path -ItemType Directory -Force | Out-Null }
    if (-not (Get-LocalUser -Name $User -ErrorAction SilentlyContinue)) {
        $pass = ConvertTo-SecureString "P@ssw0rdService2026!" -AsPlainText -Force
        New-LocalUser -Name $User -Password $pass -Description "Usuario dedicado" | Out-Null
    }
    $acl = Get-Acl $Path
    $acl.SetAccessRuleProtection($true, $false)
    $rules = @(
        (New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow")),
        (New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM","FullControl","ContainerInherit,ObjectInherit","None","Allow")),
        (New-Object System.Security.AccessControl.FileSystemAccessRule($User,"ReadAndExecute","ContainerInherit,ObjectInherit","None","Allow"))
    )
    foreach($r in $rules){ $acl.AddAccessRule($r) }
    Set-Acl $Path $acl
}

function New-IndexPage {
    param([string]$Service, [string]$Version, [int]$Port, [string]$Path)
    $content = "Servidor: [$Service] - Version: [$Version] - Puerto: [$Port]"
    if (-not (Test-Path $Path)) { New-Item -Path $Path -ItemType Directory -Force | Out-Null }
    Set-Content -Path (Join-Path $Path "index.html") -Value "<html><body style='font-family:Arial;text-align:center;'><h1>$content</h1><hr><p>Hardening Aplicado Correctamente</p></body></html>" -Force
}

# --- PROCESOS DE INSTALACION ---

function Install-IIS {
    param([int]$Port)
    Write-Host "`n[*] Iniciando aprovisionamiento seguro de IIS..." -ForegroundColor Blue
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "IIS-WebServerRole", "IIS-WebServer", "IIS-RequestFiltering" -NoRestart | Out-Null
        Import-Module WebAdministration
        
        # 1. ELIMINAR BLOQUEOS DE ARCHIVOS (ESTRATEGIA RADICAL)
        Write-Host "[*] Eliminando procesos y servicios bloqueantes..." -ForegroundColor Yellow
        Stop-Process -Name "inetmgr", "w3wp" -ErrorAction SilentlyContinue
        iisreset /stop | Out-Null
        Stop-Service WAS, W3SVC, AppHostSvc, IISADMIN -Force -ErrorAction SilentlyContinue 
        Start-Sleep -Seconds 3 # Tiempo para que Windows suelte el archivo config

        # 2. Levantar solo lo necesario para configurar
        Start-Service AppHostSvc, IISADMIN -ErrorAction SilentlyContinue

        $sn = "Default Web Site"
        Write-Host "[*] Aplicando Set-WebBinding en puerto ${Port}..." -ForegroundColor Cyan
        
        # Obtener binding actual
        $binding = Get-WebBinding -Name "$sn" | Select-Object -First 1
        $currentInfo = if ($binding) { $binding.bindingInformation } else { "*:80:" }

        # Aplicar comando segun especificacion (PropertyName + Value)
        Set-WebBinding -Name "$sn" -BindingInformation "$currentInfo" -PropertyName "Port" -Value $Port -ErrorAction SilentlyContinue
        # Forzar IP Universal
        Set-WebBinding -Name "$sn" -BindingInformation "*:${Port}:" -PropertyName "IPAddress" -Value "*" -ErrorAction SilentlyContinue

        # 3. Hardening
        Remove-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/httpProtocol/customHeaders" -name "X-Powered-By" -ErrorAction SilentlyContinue
        Add-WebConfigurationProperty -filter "system.webServer/httpProtocol/customHeaders" -PSPath "IIS:\Sites\$sn" -Name "." -value @{name='X-Frame-Options';value='SAMEORIGIN'} -ErrorAction SilentlyContinue
        Add-WebConfigurationProperty -filter "system.webServer/httpProtocol/customHeaders" -PSPath "IIS:\Sites\$sn" -Name "." -value @{name='X-Content-Type-Options';value='nosniff'} -ErrorAction SilentlyContinue
        
        foreach($v in @("TRACE","TRACK","DELETE")){
            Add-WebConfigurationProperty -filter "system.webServer/security/requestFiltering/verbs" -PSPath "IIS:\Sites\$sn" -Name "." -value @{verb=$v;allowed=$false} -ErrorAction SilentlyContinue
        }

        # 4. Seguridad NTFS e Index
        Set-FolderSecurity -Path "C:\inetpub\wwwroot" -User "web_service_user"
        New-IndexPage -Service "IIS" -Version "LTS" -Port $Port -Path "C:\inetpub\wwwroot"
        
        # 5. Reinicio Final
        iisreset /start | Out-Null
        Start-Website -Name "$sn" -ErrorAction SilentlyContinue

        # 6. Firewall
        Remove-NetFirewallRule -DisplayName "HTTP-Custom" -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -Name "HTTP-Custom" -DisplayName "HTTP-Custom" -LocalPort $Port -Protocol TCP -Action Allow -Profile Any | Out-Null
        
        if ((Test-NetConnection -ComputerName localhost -Port $Port).TcpTestSucceeded) {
            Write-Host "[OK] IIS validado y seguro en puerto $Port" -ForegroundColor Green
        }
    } catch { 
        Write-Error "Error en instalacion de IIS: $_"
        Write-Host "[!] Si el error 'Cannot write' persiste, Cierra el Administrador de IIS (la ventana azul) y vuelve a intentar." -ForegroundColor Yellow
    }
}

function Install-ApacheWindows {
    param([int]$Port)
    $version = "2.4.58"
    Write-Host "`n[*] Instalando Apache con Hardening..." -ForegroundColor Blue
    choco install apache-httpd --version $version -y | Out-Null
    $conf = "C:\tools\apache24\conf\httpd.conf"
    if (Test-Path $conf) {
        $c = Get-Content $conf
        $c = $c -replace "^Listen\s+\d+", "Listen $Port"
        $c += "`nServerTokens Prod`nServerSignature Off"
        $c | Set-Content $conf
    }
    Set-FolderSecurity -Path "C:\tools\apache24\htdocs" -User "web_service_user"
    New-IndexPage -Service "Apache" -Version $version -Port $Port -Path "C:\tools\apache24\htdocs"
    New-NetFirewallRule -DisplayName "HTTP-Custom" -LocalPort $Port -Protocol TCP -Action Allow -Force -ErrorAction SilentlyContinue | Out-Null
    Restart-Service Apache2.4 -ErrorAction SilentlyContinue
    Write-Host "[OK] Apache activo en puerto $Port" -ForegroundColor Green
}

function Install-NginxWindows {
    param([int]$Port)
    $version = "1.24.0"
    Write-Host "`n[*] Instalando Nginx con Hardening..." -ForegroundColor Blue
    choco install nginx --version $version -y | Out-Null
    $path = "C:\tools\nginx"
    $conf = "$path\conf\nginx.conf"
    if (Test-Path $conf) {
        $c = Get-Content $conf
        $c = $c -replace "listen\s+\d+;", "listen $Port;"
        $c = $c -replace "http \{", "http {`n    server_tokens off;`n    add_header X-Frame-Options SAMEORIGIN;`n    add_header X-Content-Type-Options nosniff;"
        $c | Set-Content $conf
    }
    Set-FolderSecurity -Path "$path\html" -User "web_service_user"
    New-IndexPage -Service "Nginx" -Version $version -Port $Port -Path "$path\html"
    New-NetFirewallRule -DisplayName "HTTP-Custom" -LocalPort $Port -Protocol TCP -Action Allow -Force -ErrorAction SilentlyContinue | Out-Null
    Stop-Process -Name nginx -ErrorAction SilentlyContinue
    Start-Process -FilePath "$path\nginx.exe" -WorkingDirectory $path
    Write-Host "[OK] Nginx activo en puerto $Port" -ForegroundColor Green
}

# --- MENU ---

while ($true) {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "   SISTEMA DE SERVIDORES SEGUROS (P6)     " -ForegroundColor Blue
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "1. Instalar IIS (Set-WebBinding + Hardening)"
    Write-Host "2. Instalar Apache (Choco + Security)"
    Write-Host "3. Instalar Nginx (Choco + Security)"
    Write-Host "4. Salir"
    $op = Read-Host "`nOpcion"
    switch ($op) {
        "1" { $p = Read-Host "Puerto?"; Install-IIS $p; Read-Host "Enter..." }
        "2" { $p = Read-Host "Puerto?"; Install-ApacheWindows $p; Read-Host "Enter..." }
        "3" { $p = Read-Host "Puerto?"; Install-NginxWindows $p; Read-Host "Enter..." }
        "4" { exit }
    }
}
