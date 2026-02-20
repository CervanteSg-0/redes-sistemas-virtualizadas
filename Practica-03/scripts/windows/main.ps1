# windows/main.ps1

# Importación de los módulos
. "$PSScriptRoot\modules\Common.ps1"
. "$PSScriptRoot\modules\DnsInstall.ps1"
. "$PSScriptRoot\modules\DnsZone.ps1"
. "$PSScriptRoot\modules\DnsStatus.ps1"
. "$PSScriptRoot\modules\DnsRemove.ps1"

while ($true) {
    Write-Host "===== Menú de Configuración ====="
    Write-Host "1) Instalar DNS"
    Write-Host "2) Configurar DNS y Dominio"
    Write-Host "3) Verificar estado del servicio DNS"
    Write-Host "4) Eliminar dominio de la red"
    Write-Host "0) Salir"
    
    $op = Read-Host "Seleccione una opción"

    switch ($op) {
        "1" { 
            Install-DnsRole
        }
        "2" { 
            Configure-DnsZone
        }
        "3" { 
            Get-DnsStatus
        }
        "4" { 
            Remove-DnsZoneByName
        }
        "0" { 
            break
        }
        default { 
            Write-Host "Opción no válida" 
        }
    }
}
