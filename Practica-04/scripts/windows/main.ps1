#Requires -RunAsAdministrator
[CmdletBinding()]
Param()

# Cargar el modulo de funciones refactorizado
. .\funciones_ws.ps1

function Mostrar-MenuPrincipal {
    while ($true) {
        Clear-Host
        Write-Host "================================================="
        Write-Host "       WINDOWS SERVER - GESTOR DE SERVICIOS      "
        Write-Host "================================================="
        Write-Host "  [ 1 ] - Administracion de Acceso Remoto (SSH)  "
        Write-Host "  [ 2 ] - Administracion de Servidor DHCP        "
        Write-Host "  [ 3 ] - Administracion de Servidor DNS         "
        Write-Host "  [ 0 ] - Salir del Sistema                      "
        Write-Host "================================================="
        
        $opcion = Read-Host ">> Ingrese el numero de la accion a realizar"
        
        switch ($opcion) {
            "1" { Modulo-SSH }
            "2" { Modulo-DHCP }
            "3" { Modulo-DNS }
            "0" { Write-Host "Cerrando la aplicacion..."; exit }
            Default { 
                Write-Host "[!] Opcion no valida. Intente de nuevo."
                Start-Sleep -Seconds 2
            }
        }
    }
}

# Ejecucion del cuerpo principal
Mostrar-MenuPrincipal