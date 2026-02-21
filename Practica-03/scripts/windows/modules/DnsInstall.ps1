# windows/modules/DnsInstall.ps1

. "$PSScriptRoot\Common.ps1"

function Install-DnsRole {
    Write-Host "== Instalando DNS Server (Windows Server) =="
    $feat = Get-WindowsFeature DNS
    if ($feat.Installed) {
        Write-Host "[OK] DNS ya esta instalado."
        return
    }
    
    Install-WindowsFeature DNS -IncludeManagementTools | Out-Null
    Write-Host "[OK] DNS instalado."
}