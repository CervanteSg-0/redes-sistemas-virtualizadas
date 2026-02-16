. "$PSScriptRoot\Common.ps1"

function Get-PrimaryUpAdapter {
  $ad = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } |
    Sort-Object -Property LinkSpeed -Descending |
    Select-Object -First 1
  if (-not $ad) { throw "No hay adaptadores Up." }
  return $ad
}

function Ensure-StaticIP {
  Write-Host "== Verificar/Configurar IP fija (Windows Server) =="
  $ad  = Get-PrimaryUpAdapter
  $ifc = Get-NetIPInterface -InterfaceIndex $ad.IfIndex -AddressFamily IPv4
  $cfg = Get-NetIPConfiguration -InterfaceIndex $ad.IfIndex
  $ip4 = $cfg.IPv4Address | Select-Object -First 1

  Write-Host "Adaptador: $($ad.Name)"
  Write-Host "IPv4 actual: $($ip4.IPAddress)"
  Write-Host "DHCP: $($ifc.Dhcp)"

  if ($ifc.Dhcp -ne "Enabled") {
    Write-Host "[OK] Parece IP fija."
    if (-not (Prompt-YesNo "Reconfigurar de todos modos?" $false)) { return }
  } else {
    Write-Host "[WARN] DHCP habilitado. Se requiere IP fija para DNS."
  }

  $newIP  = Prompt-IPv4 "IP fija para Windows Server (DNS)"
  $prefix = Prompt-Int "Prefijo CIDR" 1 32 24
  $gw     = (Read-Host "Gateway (opcional, ENTER omitir)").Trim()
  if (-not [string]::IsNullOrWhiteSpace($gw) -and -not (Is-ValidIPv4 $gw)) { throw "Gateway invalido." }

  $dns    = (Read-Host "DNS (opcional, ENTER omitir)").Trim()
  if (-not [string]::IsNullOrWhiteSpace($dns) -and -not (Is-ValidIPv4 $dns)) { throw "DNS invalido." }

  # Limpieza IPv4 (evitar conflictos)
  Get-NetIPAddress -InterfaceIndex $ad.IfIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -ne "127.0.0.1" } |
    ForEach-Object { Remove-NetIPAddress -InterfaceIndex $ad.IfIndex -IPAddress $_.IPAddress -Confirm:$false -ErrorAction SilentlyContinue }

  Set-NetIPInterface -InterfaceIndex $ad.IfIndex -AddressFamily IPv4 -Dhcp Disabled | Out-Null

  if (-not [string]::IsNullOrWhiteSpace($gw)) {
    New-NetIPAddress -InterfaceIndex $ad.IfIndex -IPAddress $newIP -PrefixLength $prefix -DefaultGateway $gw | Out-Null
  } else {
    New-NetIPAddress -InterfaceIndex $ad.IfIndex -IPAddress $newIP -PrefixLength $prefix | Out-Null
  }

  if (-not [string]::IsNullOrWhiteSpace($dns)) {
    Set-DnsClientServerAddress -InterfaceIndex $ad.IfIndex -ServerAddresses $dns | Out-Null
  }

  Write-Host "[OK] IP fija aplicada."
  Get-NetIPConfiguration -InterfaceIndex $ad.IfIndex | Format-List
}
