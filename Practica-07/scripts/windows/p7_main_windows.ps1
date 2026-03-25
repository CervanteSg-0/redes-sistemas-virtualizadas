# p7_main_windows.ps1 - Menu interactivo de aprovisionamiento HTTP/FTP Windows
# Practica 7 | Windows Server 2022 | PowerShell como Administrador

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\p7_functions_windows.ps1"

function Main {
    fn_check_admin

    while ($true) {
        fn_show_header
        Write-Host " [1] Instalar IIS    (WEB o FTP + SSL opcional)" -ForegroundColor Cyan
        Write-Host " [2] Instalar Apache (WEB o FTP + SSL opcional)" -ForegroundColor Cyan
        Write-Host " [3] Instalar Nginx  (WEB o FTP + SSL opcional)" -ForegroundColor Cyan
        Write-Host " [4] Configurar FTPS Windows (Estructura FTP)" -ForegroundColor Magenta
        Write-Host " [5] Ver estado de servicios" -ForegroundColor Yellow
        Write-Host " [6] Escaner de instalaciones (Origen)" -ForegroundColor Yellow
        Write-Host " [0] Salir" -ForegroundColor Red
        Write-Host ""
        $opcion = Read-Host " Opcion"

        switch ($opcion) {
            "1" { fn_instalar_servicio_hibrido "IIS" "IIS" }
            "2" { fn_instalar_servicio_hibrido "Apache" "Apache" }
            "3" { fn_instalar_servicio_hibrido "Nginx" "Nginx" }
            "4" { fn_configurar_ftp_windows }
            "5" { fn_estado_servicios }
            "6" { fn_mostrar_resumen }
            "0" { 
                Write-Host "Saliendo..." -ForegroundColor Green
                exit 0 
            }
            default { fn_err "Opcion no valida."; Start-Sleep 1 }
        }
    }
}
Main
