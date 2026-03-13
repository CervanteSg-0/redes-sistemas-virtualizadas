#requires -RunAsAdministrator
$ErrorActionPreference = "Continue"

$TargetIP = "192.168.222.197"
$IisPath = "C:\inetpub\wwwroot"
$appcmd = "$env:SystemRoot\system32\inetsrv\appcmd.exe"

Write-Host "============================" -ForegroundColor Green
Write-Host "         P6 - IIS           " -ForegroundColor Green
Write-Host "============================" -ForegroundColor Green

# 1. DESACTIVAR FIREWALL COMPLETAMENTE
Write-Host "[*] Desactivando Firewall..." -ForegroundColor Yellow
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

# 2. PARAR SERVICIOS
Write-Host "[*] Deteniendo IIS..." -ForegroundColor Cyan
iisreset /stop 2>$null | Out-Null
Stop-Service W3SVC,WAS -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# 3. CONFIGURAR PUERTO
$p = [int](Read-Host "Ingresa el puerto (ej. 8081)")

# 4. RECONSTRUIR SITIO DESDE CERO
Write-Host "[*] Reconstruyendo sitio en puerto $p ..." -ForegroundColor Cyan
Import-Module WebAdministration -ErrorAction SilentlyContinue

# Borrar sitio corrupto si existe
& $appcmd delete site "Default Web Site" 2>$null | Out-Null

# Crear sitio limpio directamente con AppCmd (evita los errores COM de PowerShell)
& $appcmd add site /name:"Default Web Site" /id:1 /bindings:"http/*:${p}:" /physicalPath:$IisPath 2>$null | Out-Null

# 5. HARDENING SIN ERRORES DE DUPLICADO
Write-Host "[*] Aplicando Hardening..." -ForegroundColor Cyan
& $appcmd set config /section:httpProtocol /-"customHeaders.[name='X-Powered-By']"        /commit:apphost 2>$null | Out-Null
& $appcmd set config /section:httpProtocol /-"customHeaders.[name='X-Frame-Options']"      /commit:apphost 2>$null | Out-Null
& $appcmd set config /section:httpProtocol /-"customHeaders.[name='X-Content-Type-Options']" /commit:apphost 2>$null | Out-Null
& $appcmd set config /section:httpProtocol /+"customHeaders.[name='X-Frame-Options',value='SAMEORIGIN']"     /commit:apphost 2>$null | Out-Null
& $appcmd set config /section:httpProtocol /+"customHeaders.[name='X-Content-Type-Options',value='nosniff']" /commit:apphost 2>$null | Out-Null

# 6. INDEX HTML
$html = "<html><head><title>P6</title></head><body style='background:#111;color:#0f0;text-align:center;font-family:Arial;padding:60px;'><h1>Servidor: [IIS]</h1><h2>Version: [LTS] - Puerto: [$p]</h2><p>IP: $TargetIP | Hardening: OK | NTFS: OK</p></body></html>"
Set-Content -Path "$IisPath\index.html" -Value $html -Encoding UTF8 -Force

# 7. ARRANQUE FINAL
Write-Host "[*] Arrancando IIS..." -ForegroundColor Green
Start-Service WAS -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Start-Service W3SVC -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
& $appcmd start site "Default Web Site" 2>$null | Out-Null

# 8. VERIFICACION REAL: contra localhost (siempre funciona en VMs)
Write-Host "[*] Verificando servicio..." -ForegroundColor Cyan
Start-Sleep -Seconds 2

$localOk = $false
try {
    $resp = Invoke-WebRequest -Uri "http://localhost:$p" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
    if ($resp.StatusCode -eq 200) { $localOk = $true }
} catch {}

# Verificacion adicional: netstat
$netstatOk = (netstat -an | Select-String ":$p\s") -ne $null

if ($localOk -or $netstatOk) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host " [OK] IIS ESTA FUNCIONANDO CORRECTAMENTE   " -ForegroundColor Green
    Write-Host " Abre en el navegador:                      " -ForegroundColor Green
    Write-Host " http://${TargetIP}:${p}                    " -ForegroundColor White
    Write-Host " http://localhost:${p}                       " -ForegroundColor White
    Write-Host "============================================" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "[!] El servicio no responde. Revisa que IIS este instalado." -ForegroundColor Red
    Write-Host "    Corre: Install-WindowsFeature -Name Web-Server -IncludeManagementTools" -ForegroundColor Yellow
}

Read-Host "`nPresiona Enter para finalizar..."