Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path

. "$BaseDir\lib\ui.ps1"
. "$BaseDir\lib\red.ps1"
. "$BaseDir\lib\dhcp.ps1"

function Menu-Principal {
    while ($true) {
        Write-Host ""
        Write-Host "===== DHCP (Windows Server 2022) ====="
        Write-Host "1) Verificar si DHCP esta instalado"
        Write-Host "2) Instalar DHCP (idempotente)"
        Write-Host "3) Configurar ambito (IP fija = IP inicial; pool = inicial+1..final)"
        Write-Host "4) Monitoreo (status, scopes, leases)"
        Write-Host "5) Reiniciar servicio DHCP"
        Write-Host "6) Salir"
        $op = Read-Host "Opcion"

        switch ($op) {
            "1" { if (DHCP-EstaInstalado) { Write-Host "DHCP: INSTALADO" } else { Write-Host "DHCP: NO instalado" }; Pausa-Enter }
            "2" { DHCP-Instalar; Pausa-Enter }
            "3" { DHCP-ConfigurarAmbitoInteractivo; Pausa-Enter }
            "4" { DHCP-Monitoreo; Pausa-Enter }
            "5" { DHCP-ReiniciarServicio; Write-Host "Reiniciado."; Pausa-Enter }
            "6" { return }
            default { Write-Host "Opcion invalida." }
        }
    }
}

Menu-Principal
