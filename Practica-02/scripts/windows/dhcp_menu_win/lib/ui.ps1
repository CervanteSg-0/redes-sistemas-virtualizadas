function Error-Salir([string]$Mensaje) {
    Write-Host "[ERROR] $Mensaje" -ForegroundColor Red
    throw $Mensaje
}

function Pausa-Enter {
    Read-Host "Enter para continuar..."
}

function Asegurar-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        Error-Salir "Ejecuta PowerShell como Administrador."
    }
}