# ==============================================================================
# Practica-06: main.ps1 - VERSION IP ESPECIFICA (192.168.222.197)
# ==============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
$TargetIP = "192.168.222.197"

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

# --- PROCESO IIS ---

function Install-IIS {
    param([int]$Port)
    global:TargetIP
    Write-Host "`n[*] Configurando IIS en IP $TargetIP Puerto $Port..." -ForegroundColor Blue
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "IIS-WebServerRole", "IIS-WebServer", "IIS-RequestFiltering" -NoRestart | Out-Null
        Import-Module WebAdministration
        
        # 1. Limpieza de Bindings previos para evitar conflictos
        Write-Host "[*] Limpiando enlaces antiguos..." -ForegroundColor Yellow
        Get-WebBinding -Name "Default Web Site" | Remove-WebBinding -ErrorAction SilentlyContinue
        
        # 2. Aplicar Binding especifico a la IP del usuario
        # Segun especificacion: Set-WebBinding -Name "Default Web Site" -BindingInformation "IP:PORT:"
        New-WebBinding -Name "Default Web Site" -IPAddress "$TargetIP" -Port $Port -Protocol http | Out-Null
        Write-Host "[*] Enlace creado: http://$TargetIP:$Port" -ForegroundColor Cyan

        # 3. Hardening (Headers y Verbos)
        # Reinicio preventivo para cargar modulos
        iisreset /restart | Out-Null
        Start-Sleep -Seconds 1
        
        $sitePath = "IIS:\Sites\Default Web Site"
        # Quitar X-Powered-By
        try { Remove-WebConfigurationProperty -filter "system.webServer/httpProtocol/customHeaders" -name "X-Powered-By" -PSPath "IIS:\" -ErrorAction SilentlyContinue } catch {}
        
        # Agregar Headers P6
        try { Add-WebConfigurationProperty -filter "system.webServer/httpProtocol/customHeaders" -name "." -value @{name='X-Frame-Options';value='SAMEORIGIN'} -PSPath $sitePath -ErrorAction SilentlyContinue } catch {}
        try { Add-WebConfigurationProperty -filter "system.webServer/httpProtocol/customHeaders" -name "." -value @{name='X-Content-Type-Options';value='nosniff'} -PSPath $sitePath -ErrorAction SilentlyContinue } catch {}
        
        # Bloquear verbos
        foreach($v in @("TRACE","DELETE","TRACK")){
            try { Add-WebConfigurationProperty -filter "system.webServer/security/requestFiltering/verbs" -name "." -value @{verb=$v;allowed=$false} -PSPath $sitePath -ErrorAction SilentlyContinue } catch {}
        }

        # 4. Seguridad de Carpeta e Index
        Set-FolderSecurity -Path "C:\inetpub\wwwroot" -User "web_service_user"
        $html = "<html><body style='font-family:Arial;text-align:center;'><h1>Servidor: [IIS]</h1><h3>Version: [LTS] - Puerto: [$Port]</h3><p>IP: $TargetIP</p></body></html>"
        Set-Content -Path "C:\inetpub\wwwroot\index.html" -Value $html -Force

        # 5. FIREWALL Y ARRANQUE FINAL
        Remove-NetFirewallRule -DisplayName "HTTP-P6-*" -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -Name "HTTP-P6-$Port" -DisplayName "HTTP-P6-$Port" -LocalPort $Port -Protocol TCP -Action Allow -Profile Any | Out-Null
        
        Start-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
        
        # 6. Validacion a la IP Real
        Write-Host "[*] Verificando conectividad en $TargetIP : $Port..." -ForegroundColor Gray
        Start-Sleep -Seconds 2
        $check = Test-NetConnection -ComputerName "$TargetIP" -Port $Port -ErrorAction SilentlyContinue
        if ($check.TcpTestSucceeded) {
            Write-Host "[OK] IIS Corriendo perfectamente en http://$TargetIP:$Port" -ForegroundColor Green
        } else {
            Write-Host "[!] El servicio esta configurado pero Windows aun no permite el trafico en $TargetIP. Revisa el Firewall manualmente." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[!] Error: $_" -ForegroundColor Red
    }
}

function Install-ApacheWindows {
    param([int]$Port)
    global:TargetIP
    Write-Host "`n[*] Instalando Apache..." -ForegroundColor Blue
    choco install apache-httpd --version 2.4.58 -y | Out-Null
    $conf = "C:\tools\apache24\conf\httpd.conf"
    if (Test-Path $conf) {
        (Get-Content $conf) -replace "^Listen\s+\d+", "Listen $TargetIP:$Port" | Set-Content $conf
    }
    Restart-Service Apache2.4 -ErrorAction SilentlyContinue
    Write-Host "[OK] Apache configurado en $TargetIP:$Port" -ForegroundColor Green
}

function Install-NginxWindows {
    param([int]$Port)
    global:TargetIP
    Write-Host "`n[*] Instalando Nginx..." -ForegroundColor Blue
    choco install nginx --version 1.24.0 -y | Out-Null
    $conf = "C:\tools\nginx\conf\nginx.conf"
    if (Test-Path $conf) {
        (Get-Content $conf) -replace "listen\s+\d+;", "listen $TargetIP:$Port;" | Set-Content $conf
    }
    Stop-Process -Name nginx -ErrorAction SilentlyContinue
    Start-Process -FilePath "C:\tools\nginx\nginx.exe" -WorkingDirectory "C:\tools\nginx"
    Write-Host "[OK] Nginx configurado en $TargetIP:$Port" -ForegroundColor Green
}

# --- MENU ---

while ($true) {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "   GESTOR DE SERVIDORES (IP DEFINIDA)     " -ForegroundColor Cyan
    Write-Host "   IP OBJETIVO: $TargetIP" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "1. Configurar IIS"
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
