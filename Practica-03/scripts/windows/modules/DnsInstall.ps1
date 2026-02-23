# windows/modules/DnsInstall.ps1

. "$PSScriptRoot\Common.ps1"

function Install-DnsRole {
    Write-Host "== Instalando DNS Server (Windows Server) ==" -ForegroundColor White
    $feat = Get-WindowsFeature DNS
    if ($feat.Installed) {
        ok "DNS ya esta instalado."
        return
    }
    
    info "Instalando caracteristica DNS..."
    Install-WindowsFeature DNS -IncludeManagementTools | Out-Null
    ok "DNS instalado correctamente."
}