# ==============================================================================
# Practica-06: main.ps1 - SOLUCION DEFINITIVA (IP: 192.168.222.197)
# ==============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
$TargetIP = "192.168.222.197"

# --- SEGURIDAD NTFS ---

function Set-FolderSecurity {
    param([string]$Path, [string]$User)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -ItemType Directory -Force | Out-Null }
    if (-not (Get-LocalUser -Name $User -ErrorAction SilentlyContinue)) {
        $p = ConvertTo-SecureString "P@ssw0rd2026!" -AsPlainText -Force
        New-LocalUser -Name $User -Password $p -Description "Usuario Web P6" | Out-Null
    }
    $acl = Get-Acl $Path
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow")))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($User,"ReadAndExecute","ContainerInherit,ObjectInherit","None","Allow")))
    Set-Acl $Path $acl
}

# --- PROCESO IIS (ESTABLE Y SEGURO) ---

function Install-IIS {
    param([int]$Port)
    $ip = $TargetIP
    Write-Host "`n[*] Configurando IIS para escuchar en http://${ip}:${Port}..." -ForegroundColor Blue
    
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "IIS-WebServerRole", "IIS-WebServer", "IIS-RequestFiltering" -NoRestart | Out-Null
        Import-Module WebAdministration
        $appcmd = "$env:SystemRoot\system32\inetsrv\appcmd.exe"
        
        # 1. Limpieza de procesos y servicios
        Write-Host "[*] Reiniciando servicios de red..." -ForegroundColor Yellow
        iisreset /stop | Out-Null
        Stop-Service AppHostSvc, WAS, W3SVC -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # 2. Configuración de Binding (IP Universal para asegurar conexion)
        Start-Service AppHostSvc, WAS -ErrorAction SilentlyContinue
        $sn = "Default Web Site"
        
        # Recreamos el sitio para que no haya basura de configuraciones anteriores
        if (Get-Website -Name "$sn" -ErrorAction SilentlyContinue) { Remove-Website -Name "$sn" | Out-Null }
        New-Website -Name "$sn" -Port $Port -PhysicalPath "C:\inetpub\wwwroot" -IPAddress "*" -Force | Out-Null
        Write-Host "[*] Binding aplicado en puerto $Port (Todas las IPs)" -ForegroundColor Cyan

        # 3. HARDENING (Headers y Seguridad con comillas para evitar Malformed Indexer)
        Write-Host "[*] Aplicando Hardening de Seguridad..." -ForegroundColor Yellow
        
        # Quitar X-Powered-By
        & $appcmd set config /section:httpProtocol /-"customHeaders.[name='X-Powered-By']" /commit:apphost 2>$null
        
        # Agregar Headers P6 (Usando comillas dobles para que AppCmd no se confunda)
        & $appcmd set config /section:httpProtocol /+"customHeaders.[name='X-Frame-Options',value='SAMEORIGIN']" /commit:apphost 2>$null
        & $appcmd set config /section:httpProtocol /+"customHeaders.[name='X-Content-Type-Options',value='nosniff']" /commit:apphost 2>$null
        
        # Bloquear Verbos (DELETE, TRACE)
        & $appcmd set config /section:requestFiltering /+"verbs.[verb='TRACE',allowed='false']" /commit:apphost 2>$null
        & $appcmd set config /section:requestFiltering /+"verbs.[verb='DELETE',allowed='false']" /commit:apphost 2>$null

        # 4. Seguridad de Carpeta e Index
        Set-FolderSecurity -Path "C:\inetpub\wwwroot" -User "web_service_user"
        $html = "<html><body style='font-family:Arial;text-align:center;'><h1>Servidor: [IIS]</h1><h3>Version: [LTS] - Puerto: [${Port}]</h3><p>IP: ${ip}</p></body></html>"
        Set-Content -Path "C:\inetpub\wwwroot\index.html" -Value $html -Force

        # 5. REINICIO FINAL Y FIREWALL
        iisreset /start | Out-Null
        Start-Website -Name "$sn" -ErrorAction SilentlyContinue
        
        Remove-NetFirewallRule -DisplayName "HTTP-P6-*" -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -Name "HTTP-P6-${Port}" -DisplayName "HTTP-P6-${Port}" -LocalPort $Port -Protocol TCP -Action Allow -Profile Any | Out-Null

        # 6. VALIDACION REAL
        Write-Host "[*] Verificando conectividad en http://${ip}:${Port}..." -ForegroundColor Gray
        Start-Sleep -Seconds 3
        if ((Test-NetConnection -ComputerName $ip -Port $Port).TcpTestSucceeded) {
            Write-Host "[OK] IIS Corriendo perfectamente en http://${ip}:${Port}" -ForegroundColor Green
        } else {
            Write-Host "[!] El puerto sigue cerrado. Revisa si la IP $ip esta activa en este equipo." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[!] Error: $_" -ForegroundColor Red
    }
}

# --- APACHE Y NGINX ---

function Install-ApacheWindows {
    param([int]$Port)
    $ip = $TargetIP
    Write-Host "`n[*] Instalando Apache en puerto $Port..." -ForegroundColor Blue
    choco install apache-httpd --version 2.4.58 -y | Out-Null
    $conf = "C:\tools\apache24\conf\httpd.conf"
    if (Test-Path $conf) {
        (Get-Content $conf) -replace "^Listen\s+\d+", "Listen ${Port}" | Set-Content $conf
    }
    Restart-Service Apache2.4 -ErrorAction SilentlyContinue
    Write-Host "[OK] Apache listo en puerto $Port." -ForegroundColor Green
}

function Install-NginxWindows {
    param([int]$Port)
    $ip = $TargetIP
    Write-Host "`n[*] Instalando Nginx en puerto $Port..." -ForegroundColor Blue
    choco install nginx --version 1.24.0 -y | Out-Null
    $conf = "C:\tools\nginx\conf\nginx.conf"
    if (Test-Path $conf) {
        (Get-Content $conf) -replace "listen\s+\d+;", "listen ${Port};" | Set-Content $conf
    }
    Stop-Process -Name nginx -ErrorAction SilentlyContinue
    Start-Process -FilePath "C:\tools\nginx\nginx.exe" -WorkingDirectory "C:\tools\nginx"
    Write-Host "[OK] Nginx listo en puerto $Port." -ForegroundColor Green
}

# --- MENU ---

while ($true) {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   SISTEMA DE SERVIDORES (IP: $TargetIP)  " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "1. Configurar IIS"
    Write-Host "2. Configurar Apache"
    Write-Host "3. Configurar Nginx"
    Write-Host "4. Salir"
    
    $op = Read-Host "`nOpcion"
    switch ($op) {
        "1" { $p = Read-Host "Puerto?"; Install-IIS $p; Read-Host "Enter..." }
        "2" { $p = Read-Host "Puerto?"; Install-ApacheWindows $p; Read-Host "Enter..." }
        "3" { $p = Read-Host "Puerto?"; Install-NginxWindows $p; Read-Host "Enter..." }
        "4" { exit }
    }
}
