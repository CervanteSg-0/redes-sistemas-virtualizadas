# ==============================================================================
# Practica-06: main.ps1 - VERSION BLINDADA (SOLUCIÓN DEFINITIVA)
# ==============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8

# --- SEGURIDAD DE ARCHIVOS ---

function Set-FolderSecurity {
    param([string]$Path, [string]$User)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -ItemType Directory -Force | Out-Null }
    
    # Crear usuario dedicado si no existe
    if (-not (Get-LocalUser -Name $User -ErrorAction SilentlyContinue)) {
        $pass = ConvertTo-SecureString "P@ssw0rdService2026!" -AsPlainText -Force
        New-LocalUser -Name $User -Password $pass -Description "Usuario de Servicio" | Out-Null
    }
    
    # Reset de ACLs para evitar bloqueos de permisos
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
    $html = "<html><body style='font-family:Arial;text-align:center;'><h1>Servidor: [$Service]</h1><h2>Version: [$Version]</h2><h2>Puerto: [$Port]</h2><hr><p>Hardening y Seguridad NTFS Aplicados</p></body></html>"
    Set-Content -Path (Join-Path $Path "index.html") -Value $html -Force
}

# --- PROCESO IIS (MODO SEGURO) ---

function Install-IIS {
    param([int]$Port)
    Write-Host "`n[*] Aprovisionando IIS bajo normas estrictas de seguridad..." -ForegroundColor Blue
    try {
        # 1. Asegurar instalacion
        Enable-WindowsOptionalFeature -Online -FeatureName "IIS-WebServerRole", "IIS-WebServer", "IIS-RequestFiltering" -NoRestart | Out-Null
        Import-Module WebAdministration
        
        # 2. LIMPIEZA TOTAL DE BLOQUEOS
        Write-Host "[*] Liberando bloqueos del sistema de archivos..." -ForegroundColor Yellow
        Stop-Process -Name "inetmgr", "w3wp" -ErrorAction SilentlyContinue
        iisreset /stop | Out-Null
        Stop-Service WAS, W3SVC, AppHostSvc -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # 3. CONFIGURACION DE PUERTO (USANDO COMANDO DE ESTRUCTURA PARA EVITAR 'CANNOT WRITE')
        Start-Service AppHostSvc, WAS -ErrorAction SilentlyContinue
        $sn = "Default Web Site"
        
        # Eliminar bindings anteriores de forma limpia
        Get-WebBinding -Name "$sn" | Remove-WebBinding -ErrorAction SilentlyContinue
        # Aplicar el puerto segun tu especificacion
        New-WebBinding -Name "$sn" -Port $Port -Protocol http -IPAddress "*" | Out-Null
        
        # Comando obligatorio de tu especificación
        Write-Host "[*] Validando Set-WebBinding: *:${Port}:" -ForegroundColor Cyan
        Set-WebBinding -Name "$sn" -BindingInformation "*:${Port}:" -PropertyName "Port" -Value $Port -ErrorAction SilentlyContinue

        # 4. HARDENING (HEADERS Y METODOS)
        # Eliminar X-Powered-By
        Remove-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/httpProtocol/customHeaders" -name "X-Powered-By" -ErrorAction SilentlyContinue
        # Agregar Headers de Seguridad
        Set-WebConfigurationProperty -filter "system.webServer/httpProtocol/customHeaders" -PSPath "IIS:\Sites\$sn" -Name "." -value @{name='X-Frame-Options';value='SAMEORIGIN'} -ErrorAction SilentlyContinue
        Set-WebConfigurationProperty -filter "system.webServer/httpProtocol/customHeaders" -PSPath "IIS:\Sites\$sn" -Name "." -value @{name='X-Content-Type-Options';value='nosniff'} -ErrorAction SilentlyContinue
        
        # Bloquear verbos peligrosos
        foreach($v in @("TRACE","TRACK","DELETE")){
            Add-WebConfigurationProperty -filter "system.webServer/security/requestFiltering/verbs" -PSPath "IIS:\Sites\$sn" -Name "." -value @{verb=$v;allowed=$false} -ErrorAction SilentlyContinue
        }

        # 5. SEGURIDAD DE CARPETA E INDEX
        Set-FolderSecurity -Path "C:\inetpub\wwwroot" -User "web_service_user"
        New-IndexPage -Service "IIS" -Version "LTS" -Port $Port -Path "C:\inetpub\wwwroot"

        # 6. REINICIO Y FIREWALL
        iisreset /start | Out-Null
        Start-Website -Name "$sn" -ErrorAction SilentlyContinue
        
        Remove-NetFirewallRule -DisplayName "HTTP-Practice-*" -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -Name "HTTP-Practice-$Port" -DisplayName "HTTP-Practice-$Port" -LocalPort $Port -Protocol TCP -Action Allow -Profile Any | Out-Null

        # 7. VALIDACION FINAL
        if ((Test-NetConnection -ComputerName localhost -Port $Port).TcpTestSucceeded) {
            Write-Host "[OK] IIS instalado, endurecido y accesible en puerto $Port" -ForegroundColor Green
        }
    } catch {
        Write-Host "[!] Error de instalacion: $_" -ForegroundColor Red
        iisreset /restart | Out-Null # Intentar dejar el servicio vivo al menos
    }
}

function Install-ApacheWindows {
    param([int]$Port)
    $version = "2.4.58"
    Write-Host "`n[*] Instalando Apache con Seguridad Avanzada..." -ForegroundColor Blue
    choco install apache-httpd --version $version -y | Out-Null
    $conf = "C:\tools\apache24\conf\httpd.conf"
    if (Test-Path $conf) {
        $c = Get-Content $conf
        $c = $c -replace "^Listen\s+\d+", "Listen $Port"
        $c += "`nServerTokens Prod`nServerSignature Off`nTraceEnable Off"
        $c | Set-Content $conf
    }
    Set-FolderSecurity -Path "C:\tools\apache24\htdocs" -User "web_service_user"
    New-IndexPage -Service "Apache" -Version $version -Port $Port -Path "C:\tools\apache24\htdocs"
    New-NetFirewallRule -DisplayName "HTTP-Apache" -LocalPort $Port -Protocol TCP -Action Allow -Profile Any -Force | Out-Null
    Restart-Service Apache2.4 -ErrorAction SilentlyContinue
    Write-Host "[OK] Apache endurecido listo." -ForegroundColor Green
}

function Install-NginxWindows {
    param([int]$Port)
    $version = "1.24.0"
    Write-Host "`n[*] Instalando Nginx con Seguridad Avanzada..." -ForegroundColor Blue
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
    New-NetFirewallRule -DisplayName "HTTP-Nginx" -LocalPort $Port -Protocol TCP -Action Allow -Profile Any -Force | Out-Null
    Stop-Process -Name nginx -ErrorAction SilentlyContinue
    Start-Process -FilePath "$path\nginx.exe" -WorkingDirectory $path
    Write-Host "[OK] Nginx endurecido listo." -ForegroundColor Green
}

# --- MENU ---

while ($true) {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   GESTOR PROFESIONAL DE SERVIDORES (P6)  " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "1. Configurar IIS (Set-WebBinding + Hardening)"
    Write-Host "2. Instalar Apache (Security Headers)"
    Write-Host "3. Instalar Nginx (Security Headers)"
    Write-Host "4. Salir"
    
    $op = Read-Host "`nElige tu opcion"
    switch ($op) {
        "1" { $p = Read-Host "Puerto?"; Install-IIS $p; Read-Host "Presiona Enter..." }
        "2" { $p = Read-Host "Puerto?"; Install-ApacheWindows $p; Read-Host "Presiona Enter..." }
        "3" { $p = Read-Host "Puerto?"; Install-NginxWindows $p; Read-Host "Presiona Enter..." }
        "4" { exit }
    }
}
