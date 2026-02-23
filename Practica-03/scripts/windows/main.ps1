# windows/main.ps1

# Importación de los modulos
. "$PSScriptRoot\modules\Common.ps1"
. "$PSScriptRoot\modules\DnsInstall.ps1"
. "$PSScriptRoot\modules\DnsZone.ps1"
. "$PSScriptRoot\modules\DnsStatus.ps1"
. "$PSScriptRoot\modules\DnsRemove.ps1"

while ($true) {
    Write-Host "===== Menu de Configuracion ====="
    Write-Host "1) Instalar DNS"
    Write-Host "2) Configurar DNS y Dominio"
    Write-Host "3) Verificar estado del servicio DNS"
    Write-Host "4) Eliminar dominio de la red"
    Write-Host "5) Ver dominios configurados activos"
    Write-Host "0) Salir"
    
    $op = Read-Host "Seleccione una opcion"

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
            Write-Host "CONSEJO: Ejecuta 'ipconfig /flushdns' en el cliente para limpiar la cache." -ForegroundColor Yellow
            pause
        }
        "5" {
            Get-ActiveZones
            pause
        }
        "0" { 
            break
        }
        default { 
            Write-Host "Opcion no valida" 
        }
    }
}