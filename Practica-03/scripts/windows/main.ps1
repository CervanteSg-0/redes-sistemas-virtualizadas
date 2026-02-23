# windows/main.ps1

# Importación de los modulos
. "$PSScriptRoot\modules\Common.ps1"
. "$PSScriptRoot\modules\DnsInstall.ps1"
. "$PSScriptRoot\modules\DnsZone.ps1"
. "$PSScriptRoot\modules\DnsStatus.ps1"
. "$PSScriptRoot\modules\DnsRemove.ps1"

while ($true) {
    Clear-Host
    Write-Host "===== DNS CONFIGURACION (Windows) =====" -ForegroundColor Cyan
    Show-ServerIPInfo
    Write-Host "1) Instalar Servidor DNS"
    Write-Host "2) Configurar Zona y Dominio"
    Write-Host "3) Verificar estado del servicio DNS"
    Write-Host "4) Eliminar dominio de la red"
    Write-Host "5) Ver dominios configurados activos"
    Write-Host "6) Asignar IP estatica al servidor (Manual)"
    Write-Host "0) Salir"
    Write-Host "======================================="
    
    $op = Read-Host "Opcion"

    switch ($op) {
        "1" { 
            Install-DnsRole
            pause
        }
        "2" { 
            Configure-DnsZone
            pause
        }
        "3" { 
            Get-DnsStatus
            pause
        }
        "4" { 
            Remove-DnsZoneByName
            warn "CONSEJO: Ejecuta 'ipconfig /flushdns' en el cliente para limpiar la cache."
            pause
        }
        "5" {
            Get-ActiveZones
            pause
        }
        "6" {
            Manual-IPFlow
            pause
        }
        "0" { 
            exit
        }
        default { 
            warn "Opcion no valida. Intenta de nuevo."
            Start-Sleep -Seconds 1
        }
    }
}