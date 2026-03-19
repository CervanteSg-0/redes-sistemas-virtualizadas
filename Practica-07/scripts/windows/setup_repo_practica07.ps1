# ==============================================================================
# SETUP REPOSITORIO LOCAL FTP - PRACTICA 07
# ==============================================================================

$RepoBase = "C:\ftp_root\LocalUser\Public\http"
$OSList = @("Windows", "Linux")
$ServiceList = @("Apache", "Nginx", "Tomcat", "IIS")

Write-Host "[*] Inicializando Estructura de Repositorio FTP..." -ForegroundColor Cyan

foreach ($os in $OSList) {
    foreach ($ser in $ServiceList) {
        $path = "$RepoBase\$os\$ser"
        if (!(Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Host "[+] Creado: $path" -ForegroundColor Green
        }
        
        # Crear Dummy Installers para Pruebas
        $fileBase = if ($os -eq "Windows") { "$($ser.ToLower())_installer.msi" } else { "$($ser.ToLower())_installer.deb" }
        $fullFilePath = "$path\$fileBase"
        
        if (!(Test-Path $fullFilePath)) {
            "Contenido del instalador dummy para $ser en $os" | Set-Content $fullFilePath
            Write-Host "    [+] Generado instalador dummy: $fileBase" -ForegroundColor Yellow
            
            # Generar Hash SHA256
            $hashValue = (Get-FileHash -Path $fullFilePath -Algorithm SHA256).Hash
            # Formato compatible con sha256sum: [HASH] [FILENAME]
            "$hashValue $fileBase" | Set-Content "$fullFilePath.sha256"
            Write-Host "    [+] Generado hash: $fileBase.sha256" -ForegroundColor Cyan
        }
    }
}

Write-Host "`n[*] REPOSITORIO LISTO." -ForegroundColor Green
Write-Host "Ruta fisica: $RepoBase" -ForegroundColor Cyan
Write-Host "Acceso FTP (Public): ftp://127.0.0.1/http/" -ForegroundColor Cyan
