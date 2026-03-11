# ==============================================================================
# Practica-07: main.ps1
# Script principal para el aprovisionamiento web en Windows
# ==============================================================================

# Cargar funciones
. (Join-Path $PSScriptRoot "http_functions.ps1")

# Verificar permisos de Administrador
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Este script debe ejecutarse como Administrador." -ForegroundColor Red
    exit 1
}

function Show-Menu {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "   SISTEMA DE APROVISIONAMIENTO WEB (WIN)   " -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "1. Instalar IIS (Obligatorio)"
    Write-Host "2. Instalar Apache Win64"
    Write-Host "3. Instalar Nginx"
    Write-Host "4. Salir"
    Write-Host "==========================================" -ForegroundColor Green
    $choice = Read-Host "Seleccione una opción"
    return $choice
}

while ($true) {
    $option = Show-Menu
    
    switch ($option) {
        "1" {
            $service = "IIS"
            $version = "Windows Feature"
        }
        "2" {
            $service = "apache-httpd"
            $versions = Get-ServiceVersions -PackageName $service
            Write-Host "Versiones disponibles:"
            $versions
            $version = Read-Host "Ingrese la versión exacta"
        }
        "3" {
            $service = "nginx"
            $versions = Get-ServiceVersions -PackageName $service
            Write-Host "Versiones disponibles:"
            $versions
            $version = Read-Host "Ingrese la versión exacta"
        }
        "4" {
            Write-Host "Saliendo..."
            exit
        }
        Default {
            Write-Host "Opción inválida" -ForegroundColor Red
            Start-Sleep -Seconds 2
            continue
        }
    }

    # Solicitar puerto
    while ($true) {
        $portStr = Read-Host "Ingrese el puerto de escucha"
        if ($portStr -match '^\d+$') {
            $port = [int]$portStr
            if (Test-IsReservedPort -Port $port) {
                Write-Host "[ERROR] El puerto $port está RESERVADO o es el 444 (Bloqueado para demostración)." -ForegroundColor Red
                continue
            }
            if (Test-PortAvailability -Port $port) {
                break
            } else {
                Write-Host "[ALERTA] Puerto OCUPADO por otro servicio. Elija uno diferente." -ForegroundColor Red
            }
        } else {
            Write-Host "El puerto debe ser numérico." -ForegroundColor Red
        }
    }

    # Ejecución
    switch ($service) {
        "IIS" { Install-IIS -Port $port }
        "apache-httpd" { Install-ApacheWindows -Version $version -Port $port }
        "nginx" { Install-NginxWindows -Version $version -Port $port }
    }
    
    Read-Host "Presione Enter para continuar..."
}
