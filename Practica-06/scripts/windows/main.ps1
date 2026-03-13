# ==============================================================================
# Practica-06: main.ps1 - VERSION ESTABILIDAD TOTAL (APPCMD NATIVO)
# ==============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8

# --- FUNCIONES DE SEGURIDAD ---

function Set-FolderSecurity {
    param([string]$Path, [string]$User)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -ItemType Directory -Force | Out-Null }
    if (-not (Get-LocalUser -Name $User -ErrorAction SilentlyContinue)) {
        $pass = ConvertTo-SecureString "P@ssw0rd2026!" -AsPlainText -Force
        New-LocalUser -Name $User -Password $pass -Description "Usuario Web" | Out-Null
    }
    $acl = Get-Acl $Path
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow")))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($User,"ReadAndExecute","ContainerInherit,ObjectInherit","None","Allow")))
    Set-Acl $Path $acl
}

# --- PROCESO IIS (MODO BAJO NIVEL) ---

function Install-IIS {
    param([int]$Port)
    Write-Host "`n[*] Aprovisionando IIS con herramientas nativas (AppCmd)..." -ForegroundColor Blue
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "IIS-WebServerRole", "IIS-WebServer", "IIS-RequestFiltering" -NoRestart | Out-Null
        $appcmd = "$env:SystemRoot\system32\inetsrv\appcmd.exe"
        
        # 1. Limpieza de procesos y reseteo
        Write-Host "[*] Preparando el sistema..." -ForegroundColor Yellow
        Stop-Process -Name "inetmgr", "w3wp" -ErrorAction SilentlyContinue
        iisreset /stop | Out-Null
        Start-Sleep -Seconds 1
        iisreset /start | Out-Null

        $sn = "Default Web Site"

        # 2. Configuración de Binding (Cero Errores)
        Write-Host "[*] Configurando puerto $Port..." -ForegroundColor Cyan
        & $appcmd set site /site.name:"$sn" /bindings:http/*:${Port}: | Out-Null

        # 3. HARDENING (Seguridad de Encabezados)
        Write-Host "[*] Aplicando Hardening de Seguridad..." -ForegroundColor Yellow
        # Quitar X-Powered-By
        & $appcmd set config /section:httpProtocol /-customHeaders.[name='X-Powered-By'] /commit:apphost | Out-Null
        # Agregar Headers P6
        & $appcmd set config /section:httpProtocol /+customHeaders.[name='X-Frame-Options',value='SAMEORIGIN'] /commit:apphost | Out-Null
        & $appcmd set config /section:httpProtocol /+customHeaders.[name='X-Content-Type-Options',value='nosniff'] /commit:apphost | Out-Null
        
        # Bloquear Verbos (DELETE, TRACE)
        & $appcmd set config /section:requestFiltering /+verbs.[verb='TRACE',allowed='false'] /commit:apphost | Out-Null
        & $appcmd set config /section:requestFiltering /+verbs.[verb='DELETE',allowed='false'] /commit:apphost | Out-Null

        # 4. Seguridad NTFS e Index
        Set-FolderSecurity -Path "C:\inetpub\wwwroot" -User "web_service_user"
        $html = "<html><body style='font-family:Arial;text-align:center;'><h1>IIS Seguro: Puerto $Port</h1><p>Hardening y NTFS Activos (P6)</p></body></html>"
        Set-Content -Path "C:\inetpub\wwwroot\index.html" -Value $html -Force

        # 5. Reinicio Final y Firewall
        iisreset /restart | Out-Null
        Remove-NetFirewallRule -DisplayName "HTTP-P-*" -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -Name "HTTP-P-$Port" -DisplayName "HTTP-P-$Port" -LocalPort $Port -Protocol TCP -Action Allow -Profile Any | Out-Null

        if ((Test-NetConnection -ComputerName localhost -Port $Port).TcpTestSucceeded) {
            Write-Host "[OK] IIS funcionando perfectamente en puerto $Port." -ForegroundColor Green
        }
    } catch {
        Write-Host "[!] Error inesperado: $_" -ForegroundColor Red
    }
}

# --- APACHE Y NGINX ---

function Install-ApacheWindows {
    param([int]$Port)
    Write-Host "`n[*] Instalando Apache..." -ForegroundColor Blue
    choco install apache-httpd --version 2.4.58 -y | Out-Null
    $conf = "C:\tools\apache24\conf\httpd.conf"
    if (Test-Path $conf) {
        (Get-Content $conf) -replace "^Listen\s+\d+", "Listen $Port" | Set-Content $conf
        Add-Content $conf "`nServerTokens Prod`nServerSignature Off"
    }
    Restart-Service Apache2.4 -ErrorAction SilentlyContinue
    Write-Host "[OK] Apache listo." -ForegroundColor Green
}

function Install-NginxWindows {
    param([int]$Port)
    Write-Host "`n[*] Instalando Nginx..." -ForegroundColor Blue
    choco install nginx --version 1.24.0 -y | Out-Null
    $conf = "C:\tools\nginx\conf\nginx.conf"
    if (Test-Path $conf) {
        (Get-Content $conf) -replace "listen\s+\d+;", "listen $Port;" | Set-Content $conf
    }
    Stop-Process -Name nginx -ErrorAction SilentlyContinue
    Start-Process -FilePath "C:\tools\nginx\nginx.exe" -WorkingDirectory "C:\tools\nginx"
    Write-Host "[OK] Nginx listo." -ForegroundColor Green
}

# --- MENU ---

while ($true) {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   GESTOR DE SERVIDORES (MODO ESTABLE)    " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "1. Configurar IIS (AppCmd + Hardening)"
    Write-Host "2. Instalar Apache (Secured)"
    Write-Host "3. Instalar Nginx (Secured)"
    Write-Host "4. Salir"
    
    $op = Read-Host "`nElige tu opcion"
    switch ($op) {
        "1" { $p = Read-Host "Puerto?"; Install-IIS $p; Read-Host "Enter..." }
        "2" { $p = Read-Host "Puerto?"; Install-ApacheWindows $p; Read-Host "Enter..." }
        "3" { $p = Read-Host "Puerto?"; Install-NginxWindows $p; Read-Host "Enter..." }
        "4" { exit }
    }
}
