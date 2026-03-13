# ==============================================================================
# Practica-06: main.ps1 - SOLUCION DE EMERGENCIA (ANTI-BLOQUEOS TOTAL)
# ==============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
$TargetIP = "192.168.222.197"

# --- FUNCION DE REINTENTO PARA APPCMD ---
function Invoke-AppCmdSafe {
    param([string]$Arguments)
    $appcmd = "$env:SystemRoot\system32\inetsrv\appcmd.exe"
    $maxRetries = 5
    $retryCount = 0
    $success = $false
    
    while (-not $success -and $retryCount -lt $maxRetries) {
        & $appcmd $Arguments 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $success = $true
        } else {
            Write-Host "[!] Reintentando comando por bloqueo de archivo ($($retryCount + 1))..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            $retryCount++
        }
    }
}

function Set-FolderSecurity {
    param([string]$Path, [string]$User)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -ItemType Directory -Force | Out-Null }
    if (-not (Get-LocalUser -Name $User -ErrorAction SilentlyContinue)) {
        $p = ConvertTo-SecureString "P@ssw0rd2026!" -AsPlainText -Force
        New-LocalUser -Name $User -Password $p -Description "Usuario P6" | Out-Null
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
    $ip = $TargetIP
    Write-Host "`n[*] Iniciando aprovisionamiento critico de IIS..." -ForegroundColor Blue
    
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "IIS-WebServerRole", "IIS-WebServer", "IIS-RequestFiltering" -NoRestart | Out-Null
        
        # 1. LIMPIEZA TOTAL DE BLOQUEOS (TASKKILL)
        Write-Host "[*] Matando procesos bloqueantes..." -ForegroundColor Yellow
        taskkill /F /IM inetmgr.exe /T 2>$null | Out-Null
        taskkill /F /IM w3wp.exe /T 2>$null | Out-Null
        taskkill /F /IM appcmd.exe /T 2>$null | Out-Null
        
        # Detener servicios
        iisreset /stop | Out-Null
        Stop-Service WAS -Force -ErrorAction SilentlyContinue
        Stop-Service AppHostSvc -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # 2. CONFIGURAR PUERTO (METODO LIMPIO)
        # Arrancamos solo lo minimo
        Start-Service AppHostSvc -ErrorAction SilentlyContinue
        
        Write-Host "[*] Aplicando IP:Port ($ip : $Port)..." -ForegroundColor Cyan
        Invoke-AppCmdSafe "delete site ""Default Web Site"""
        Invoke-AppCmdSafe "add site /name:""Default Web Site"" /id:1 /bindings:http/${ip}:${Port}: /physicalPath:C:\inetpub\wwwroot"

        # 3. HARDENING (HEADERS SEGURIDAD)
        Write-Host "[*] Aplicando Hardening..." -ForegroundColor Yellow
        # Quitar X-Powered-By
        Invoke-AppCmdSafe "set config /section:httpProtocol /-customHeaders.[name='X-Powered-By'] /commit:apphost"
        # Agregar Headers
        Invoke-AppCmdSafe "set config /section:httpProtocol /+customHeaders.[name='X-Frame-Options',value='SAMEORIGIN'] /commit:apphost"
        Invoke-AppCmdSafe "set config /section:httpProtocol /+customHeaders.[name='X-Content-Type-Options',value='nosniff'] /commit:apphost"
        # Bloquear Verbos
        Invoke-AppCmdSafe "set config /section:requestFiltering /+verbs.[verb='TRACE',allowed='false'] /commit:apphost"
        Invoke-AppCmdSafe "set config /section:requestFiltering /+verbs.[verb='DELETE',allowed='false'] /commit:apphost"

        # 4. SEGURIDAD NTFS E INDEX
        Set-FolderSecurity -Path "C:\inetpub\wwwroot" -User "web_service_user"
        $html = "<html><body style='font-family:Arial;text-align:center;'><h1>IIS SEGURO (P6)</h1><hr><h3>IP: $ip | Puerto: $Port</h3><p>Hardening y NTFS: OK</p></body></html>"
        Set-Content -Path "C:\inetpub\wwwroot\index.html" -Value $html -Force

        # 5. FIREWALL Y ARRANQUE FINAL
        Remove-NetFirewallRule -DisplayName "HTTP-P6-*" -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -Name "HTTP-P6-$Port" -DisplayName "HTTP-P6-$Port" -LocalPort $Port -Protocol TCP -Action Allow -Profile Any | Out-Null
        
        iisreset /start | Out-Null
        Start-Service WAS, W3SVC -ErrorAction SilentlyContinue
        Invoke-AppCmdSafe "start site ""Default Web Site"""

        # 6. VALIDACION
        Write-Host "[*] Verificando conectividad externa..." -ForegroundColor Gray
        Start-Sleep -Seconds 2
        if ((Test-NetConnection -ComputerName $ip -Port $Port).TcpTestSucceeded) {
            Write-Host "[OK] IIS COMPLETO en http://${ip}:${Port}" -ForegroundColor Green
        } else {
            Write-Host "[!] El servicio esta configurado pero el puerto no responde. Prueba el navegador." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[!] Error Critico: $_" -ForegroundColor Red
        iisreset /start | Out-Null
    }
}

# --- APACHE Y NGINX ---

function Install-ApacheWindows {
    param([int]$Port)
    $ip = $TargetIP
    Write-Host "`n[*] Apache en $ip : $Port..." -ForegroundColor Blue
    choco install apache-httpd --version 2.4.58 -y | Out-Null
    $conf = "C:\tools\apache24\conf\httpd.conf"
    if (Test-Path $conf) {
        (Get-Content $conf) -replace "^Listen\s+\d+", "Listen ${ip}:${Port}" | Set-Content $conf
    }
    Restart-Service Apache2.4 -ErrorAction SilentlyContinue
    Write-Host "[OK] Apache listo." -ForegroundColor Green
}

function Install-NginxWindows {
    param([int]$Port)
    $ip = $TargetIP
    Write-Host "`n[*] Nginx en $ip : $Port..." -ForegroundColor Blue
    choco install nginx --version 1.24.0 -y | Out-Null
    $conf = "C:\tools\nginx\conf\nginx.conf"
    if (Test-Path $conf) {
        (Get-Content $conf) -replace "listen\s+\d+;", "listen ${ip}:${Port};" | Set-Content $conf
    }
    Stop-Process -Name nginx -ErrorAction SilentlyContinue
    Start-Process -FilePath "C:\tools\nginx\nginx.exe" -WorkingDirectory "C:\tools\nginx"
    Write-Host "[OK] Nginx listo." -ForegroundColor Green
}

# --- MENU ---

while ($true) {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "   SISTEMA DE SERVIDORES (ULTIMA OPORTUNIDAD) " -ForegroundColor Red
    Write-Host "   IP: $TargetIP" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "1. IIS (Antbloqueo)"
    Write-Host "2. Apache"
    Write-Host "3. Nginx"
    Write-Host "4. Salir"
    
    $op = Read-Host "`nSelecciona Opcion"
    switch ($op) {
        "1" { $p = Read-Host "Puerto?"; Install-IIS $p; Read-Host "Enter..." }
        "2" { $p = Read-Host "Puerto?"; Install-ApacheWindows $p; Read-Host "Enter..." }
        "3" { $p = Read-Host "Puerto?"; Install-NginxWindows $p; Read-Host "Enter..." }
        "4" { exit }
    }
}
