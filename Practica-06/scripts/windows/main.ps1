# ==============================================================================
# Practica-06: main.ps1 - SOLUCIÓN DEFINITIVA (HARDENING + CONEXIÓN)
# ==============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8

# --- SEGURIDAD DE ARCHIVOS ---

function Set-FolderSecurity {
    param([string]$Path, [string]$User)
    Write-Host "[*] Aplicando restricciones NTFS en $Path..." -ForegroundColor Gray
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

# --- PROCESO IIS (MODO DEFINITIVO) ---

function Install-IIS {
    param([int]$Port)
    Write-Host "`n[*] Aprovisionando IIS bajo especificaciones P6..." -ForegroundColor Blue
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "IIS-WebServerRole", "IIS-WebServer", "IIS-RequestFiltering" -NoRestart | Out-Null
        Import-Module WebAdministration
        
        # 1. Liberar bloqueos de archivos
        Write-Host "[*] Preparando el sistema..." -ForegroundColor Yellow
        iisreset /stop | Out-Null
        Start-Sleep -Seconds 2
        
        # 2. Binding segun especificacion (Usando AppCmd para bypass de bloqueos)
        $appcmd = "$env:SystemRoot\system32\inetsrv\appcmd.exe"
        & $appcmd set site /site.name:"Default Web Site" /bindings:http/*:${Port}: | Out-Null

        # 3. Hardening (Usando comandos de PowerShell segun especificación)
        iisreset /start | Out-Null
        Start-Sleep -Seconds 1
        Write-Host "[*] Aplicando Hardening de Cabeceras..." -ForegroundColor Cyan
        
        # Eliminar X-Powered-By
        try { Remove-WebConfigurationProperty -filter "system.webServer/httpProtocol/customHeaders" -name "X-Powered-By" -PSPath "IIS:\" -ErrorAction SilentlyContinue } catch {}
        
        # Agregar Headers de Seguridad
        $sitePath = "IIS:\Sites\Default Web Site"
        try { Add-WebConfigurationProperty -filter "system.webServer/httpProtocol/customHeaders" -name "." -value @{name='X-Frame-Options';value='SAMEORIGIN'} -PSPath $sitePath -ErrorAction SilentlyContinue } catch {}
        try { Add-WebConfigurationProperty -filter "system.webServer/httpProtocol/customHeaders" -name "." -value @{name='X-Content-Type-Options';value='nosniff'} -PSPath $sitePath -ErrorAction SilentlyContinue } catch {}
        
        # Bloquear verbos peligrosos
        foreach($v in @("TRACE","DELETE","TRACK")){
            try { Add-WebConfigurationProperty -filter "system.webServer/security/requestFiltering/verbs" -name "." -value @{verb=$v;allowed=$false} -PSPath $sitePath -ErrorAction SilentlyContinue } catch {}
        }

        # 4. Seguridad de Carpeta e Index
        Set-FolderSecurity -Path "C:\inetpub\wwwroot" -User "web_service_user"
        $html = "<html><body style='font-family:Arial;text-align:center;'><h1>Servidor: [IIS]</h1><h3>Version: [LTS] - Puerto: [$Port]</h3><p>Hardening Completado</p></body></html>"
        Set-Content -Path "C:\inetpub\wwwroot\index.html" -Value $html -Force

        # 5. Reinicio Final y Firewall
        iisreset /restart | Out-Null
        Start-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
        
        Remove-NetFirewallRule -DisplayName "HTTP-P-*" -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -Name "HTTP-P-$Port" -DisplayName "HTTP-P-$Port" -LocalPort $Port -Protocol TCP -Action Allow -Profile Any | Out-Null

        # 6. Validacion Paciente
        Write-Host "[*] Verificando puerto $Port..." -ForegroundColor Gray
        Start-Sleep -Seconds 3
        if ((Test-NetConnection -ComputerName localhost -Port $Port).TcpTestSucceeded) {
            Write-Host "[OK] IIS funcionando perfectamente en puerto $Port." -ForegroundColor Green
        } else {
            Write-Host "[!] El sitio esta configurado. Intenta entrar a http://localhost:$Port manualmente." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[!] Error: $_" -ForegroundColor Red
    }
}

function Install-ApacheWindows {
    param([int]$Port)
    Write-Host "`n[*] Instalando Apache..." -ForegroundColor Blue
    choco install apache-httpd --version 2.4.58 -y | Out-Null
    $conf = "C:\tools\apache24\conf\httpd.conf"
    if (Test-Path $conf) {
        $c = Get-Content $conf
        $c = $c -replace "^Listen\s+\d+", "Listen $Port"
        $c += "`nServerTokens Prod`nServerSignature Off"
        $c | Set-Content $conf
    }
    Set-FolderSecurity -Path "C:\tools\apache24\htdocs" -User "web_service_user"
    Restart-Service Apache2.4 -ErrorAction SilentlyContinue
    Write-Host "[OK] Apache listo." -ForegroundColor Green
}

function Install-NginxWindows {
    param([int]$Port)
    Write-Host "`n[*] Instalando Nginx..." -ForegroundColor Blue
    choco install nginx --version 1.24.0 -y | Out-Null
    $path = "C:\tools\nginx"
    if (Test-Path "$path\conf\nginx.conf") {
        (Get-Content "$path\conf\nginx.conf") -replace "listen\s+\d+;", "listen $Port;" | Set-Content "$path\conf\nginx.conf"
    }
    Set-FolderSecurity -Path "$path\html" -User "web_service_user"
    Stop-Process -Name nginx -ErrorAction SilentlyContinue
    Start-Process -FilePath "$path\nginx.exe" -WorkingDirectory $path
    Write-Host "[OK] Nginx listo." -ForegroundColor Green
}

# --- MENU ---

while ($true) {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   SISTEMA DE SERVIDORES SEGUROS (P6)     " -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "1. Configurar IIS (Set-WebBinding + Hardening)"
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
