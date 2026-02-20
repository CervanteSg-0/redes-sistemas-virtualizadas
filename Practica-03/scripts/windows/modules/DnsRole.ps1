. "$PSScriptRoot\Common.ps1"

function Ensure-DnsRole {
  Write-Host "== DNS Role (idempotente) =="
  $feat = Get-WindowsFeature DNS
  if ($feat.Installed) {
    Write-Host "[OK] DNS ya instalado."
    return
  }
  Install-WindowsFeature DNS -IncludeManagementTools | Out-Null
  Write-Host "[OK] DNS instalado."
}