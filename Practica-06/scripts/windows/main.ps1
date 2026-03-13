# ==============================================================================
# Practica-06: main.ps1 - VERSION FINAL CORREGIDA (SYNTAX FIX)
# ==============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
$TargetIP = "192.168.222.197"

# --- SEGURIDAD DE ARCHIVOS ---

function Set-FolderSecurity {
    param([string]$Path, [string]$User)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -ItemType Directory -Force | Out-Null }
    if (-not (Get-LocalUser -Name $User -ErrorAction SilentlyContinue)) {
        $p = ConvertTo-SecureString "P@ssw0rd2026!" -AsPlainText -Force
        New-LocalUser -Name $User -Password $p -Description "Usuario Web" | Out-Null
    }
    $acl = Get-Acl $Path
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow")))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($User,"ReadAndExecute","ContainerInherit,ObjectInherit","None","Allow")))
    Set-Acl $Path $acl
}

# --- PROCESO IIS ---

function Install-IIS {
    param([int]$Port)
    global:TargetIP
    Write-Host "`n[*] Configurando IIS en IP ${TargetIP} Puerto ${Port}..." -ForegroundColor Blue
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "IIS-WebServerRole", "IIS-WebServer", "IIS-RequestFiltering" -NoRestart | Out-Null
        Import-Module WebAdministration
        
        # 1. Limpieza Total
        iisreset /stop | Out-Null
        Get-WebBinding -Name "Default Web Site" | Remove-WebBinding -ErrorAction SilentlyContinue
        
        # 2. Binding con sintaxis blindada
        New-WebBinding -Name "Default Web Site" -IPAddress $TargetIP -Port $Port -Protocol http | Out-Null
        Write-Host "[*] Enlace creado: http://${TargetIP}:${Port}" -ForegroundColor Cyan

        # 3. Hardening
        iisreset /start | Out-Null
        $sitePath = "IIS:\Sites\Default Web Site"
        try { Add-WebConfigurationProperty -filter "system.webServer/httpProtocol/customHeaders" -name "." -value @{name='X-Frame-Options';value='SAMEORIGIN'} -PSPath $sitePath -ErrorAction SilentlyContinue } catch {}
        try { Add-WebConfigurationProperty -filter "system.webServer/httpProtocol/customHeaders" -name "." -value @{name='X-Content-Type-Options';value='nosniff'} -PSPath $sitePath -ErrorAction SilentlyContinue } catch {}
        
        foreach($v in @("TRACE","DELETE","TRACK")){
            try { Add-WebConfigurationProperty -filter "system.webServer/security/requestFiltering/verbs" -name "." -value @{verb=$v;allowed=$false} -PSPath $sitePath -ErrorAction SilentlyContinue } catch {}
        }

        # 4. Carpeta e Index
        Set-FolderSecurity -Path "C:\inetpub\wwwroot" -User "web_service_user"
        $html = "<html><body style='font-family:Arial;text-align:center;'><h1>IIS SEGURO</h1><h3>Puerto: ${Port}</h3><p>IP: ${TargetIP}</p></body></html>"
        Set-Content -Path "C:\inetpub\wwwroot\index.html" -Value $html -Force

        # 5. Firewall y Arranque
        Remove-NetFirewallRule -DisplayName "HTTP-P6-*" -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -Name "HTTP-P6-${Port}" -DisplayName "HTTP-P6-${Port}" -LocalPort $Port -Protocol TCP -Action Allow -Profile Any | Out-Null
        Start-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
        
        Write-Host "[*] Verificando en ${TargetIP}:${Port}..." -ForegroundColor Gray
        Start-Sleep -Seconds 2
        if ((Test-NetConnection -ComputerName $TargetIP -Port $Port).TcpTestSucceeded) {
            Write-Host "[OK] IIS Activo en http://${TargetIP}:${Port}" -ForegroundColor Green
        }
    } catch {
        Write-Host "[!] Error: $_" -ForegroundColor Red
    }
}

# --- APACHE Y NGINX ---

function Install-ApacheWindows {
    param([int]$Port)
    global:TargetIP
    Write-Host "`n[*] Instalando Apache..." -ForegroundColor Blue
    choco install apache-httpd --version 2.4.58 -y | Out-Null
    $conf = "C:\tools\apache24\conf\httpd.conf"
    if (Test-Path $conf) {
        (Get-Content $conf) -replace "^Listen\s+\d+", "Listen ${TargetIP}:${Port}" | Set-Content $conf
    }
    Restart-Service Apache2.4 -ErrorAction SilentlyContinue
    Write-Host "[OK] Apache configurado en ${TargetIP}:${Port}" -ForegroundColor Green
}

function Install-NginxWindows {
    param([int]$Port)
    global:TargetIP
    Write-Host "`n[*] Instalando Nginx..." -ForegroundColor Blue
    choco install nginx --version 1.24.0 -y | Out-Null
    $conf = "C:\tools\nginx\conf\nginx.conf"
    if (Test-Path $conf) {
        (Get-Content $conf) -replace "listen\s+\d+;", "listen ${TargetIP}:${Port};" | Set-Content $conf
    }
    Stop-Process -Name nginx -ErrorAction SilentlyContinue
    Start-Process -FilePath "C:\tools\nginx\nginx.exe" -WorkingDirectory "C:\tools\nginx"
    Write-Host "[OK] Nginx configurado en ${TargetIP}:${Port}" -ForegroundColor Green
}

# --- MENU ---

while ($true) {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   GESTOR DE SERVIDORES (FIX SYNTAX)      " -ForegroundColor Cyan
    Write-Host "   IP: $TargetIP" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "1. Instalar IIS"
    Write-Host "2. Instalar Apache"
    Write-Host "3. Instalar Nginx"
    Write-Host "4. Salir"
    
    $op = Read-Host "`nOpcion"
    switch ($op) {
        "1" { $p = Read-Host "Puerto?"; Install-IIS $p; Read-Host "Enter..." }
        "2" { $p = Read-Host "Puerto?"; Install-ApacheWindows $p; Read-Host "Enter..." }
        "3" { $p = Read-Host "Puerto?"; Install-NginxWindows $p; Read-Host "Enter..." }
        "4" { exit }
    }
}
