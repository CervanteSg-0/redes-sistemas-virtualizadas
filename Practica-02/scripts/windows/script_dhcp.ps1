$ErrorActionPreference = "Stop"

function IpToUInt32([string]$ip) {
  $addr = [System.Net.IPAddress]::Parse($ip)
  $b = $addr.GetAddressBytes()
  return [uint32](($b[0] -shl 24) -bor ($b[1] -shl 16) -bor ($b[2] -shl 8) -bor $b[3])
}

function IsIPv4([string]$s) {
  $ip = $null
  if (-not [System.Net.IPAddress]::TryParse($s, [ref]$ip)) { return $false }
  if ($ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { return $false }
  if ($s -eq "0.0.0.0" -or $s -eq "255.255.255.255") { return $false }
  return $true
}

function MaskIsValid([string]$m) {
  if (-not (IsIPv4 $m)) { return $false }
  $mi = IpToUInt32 $m
  if ($mi -eq 0 -or $mi -eq 0xFFFFFFFF) { return $false }
  $inv = [uint32](-bnot $mi)
  return (($inv -band ($inv + 1)) -eq 0)
}

function SameSubnet([string]$ip1, [string]$ip2, [string]$mask) {
  $m = IpToUInt32 $mask
  return ((IpToUInt32 $ip1 -band $m) -eq (IpToUInt32 $ip2 -band $m))
}

function ReadIPv4([string]$prompt, [string]$def) {
  while ($true) {
    $v = Read-Host "$prompt [$def]"
    if ([string]::IsNullOrWhiteSpace($v)) { $v = $def }
    if (IsIPv4 $v) { return $v }
    Write-Host "IP invalida (ej: 192.168.100.10). No se acepta '1000'." -ForegroundColor Yellow
  }
}

function ReadMask([string]$prompt, [string]$def) {
  while ($true) {
    $v = Read-Host "$prompt [$def]"
    if ([string]::IsNullOrWhiteSpace($v)) { $v = $def }
    if (MaskIsValid $v) { return $v }
    Write-Host "Máscara invalida (ej: 255.255.255.0)" -ForegroundColor Yellow
  }
}

function Ensure-DhcpRole {
  $f = Get-WindowsFeature DHCP
  if ($f.Installed) {
    Write-Host "DHCP Role ya instalado."
  } else {
    Write-Host "Instalando DHCP Role..."
    Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
  }
}

function Configure-Dhcp {
  Import-Module DhcpServer

  $scopeName = Read-Host "Nombre descriptivo del ambito [Scope-Sistemas]"
  if ([string]::IsNullOrWhiteSpace($scopeName)) { $scopeName = "Scope-Sistemas" }

  $mask   = ReadMask "Mascara (/24 para esta práctica)" "255.255.255.0"
  $start  = ReadIPv4 "Rango inicial" "192.168.100.50"
  $end    = ReadIPv4 "Rango final"   "192.168.100.150"

  # Validacion: pertenecer a 192.168.100.0/24
  if (-not (SameSubnet $start "192.168.100.0" $mask)) { throw "StartRange $start NO pertenece a 192.168.100.0/24" }
  if (-not (SameSubnet $end   "192.168.100.0" $mask)) { throw "EndRange $end NO pertenece a 192.168.100.0/24" }

  if ((IpToUInt32 $start) -gt (IpToUInt32 $end)) { throw "StartRange debe ser <= EndRange" }

  $gateway = ReadIPv4 "Gateway (Router)" "192.168.100.1"
  if (-not (SameSubnet $gateway "192.168.100.0" $mask)) { throw "Gateway $gateway NO pertenece a 192.168.100.0/24" }

  $dns     = ReadIPv4 "DNS" "192.168.100.20"

  $leaseDays = Read-Host "Lease en dias [8]"
  if ([string]::IsNullOrWhiteSpace($leaseDays)) { $leaseDays = "8" }
  if ($leaseDays -notmatch '^\d+$') { throw "Lease debe ser entero (dias)." }
  $lease = New-TimeSpan -Days ([int]$leaseDays)

  $scopeId = "192.168.100.0"

  $existing = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object { $_.ScopeId.IPAddressToString -eq $scopeId }

  if (-not $existing) {
    Write-Host "Creando scope $scopeId..."
    Add-DhcpServerv4Scope -Name $scopeName -StartRange $start -EndRange $end -SubnetMask $mask -State Active -LeaseDuration $lease | Out-Null
  } else {
    Write-Host "Scope ya existe. Actualizando nombre/lease/rangos..."
    Set-DhcpServerv4Scope -ScopeId $scopeId -Name $scopeName -StartRange $start -EndRange $end -LeaseDuration $lease -State Active | Out-Null
  }

  Write-Host "Aplicando opciones (Router/DNS)..."
  Set-DhcpServerv4OptionValue -ScopeId $scopeId -Router $gateway -DnsServer $dns | Out-Null

  Set-Service DHCPServer -StartupType Automatic
  Start-Service DHCPServer

  Write-Host "Listo. DHCP configurado."
}

function Monitor-Dhcp {
  Import-Module DhcpServer
  Write-Host "== Servicio =="
  Get-Service DHCPServer | Format-Table -Auto

  Write-Host "`n== Scopes =="
  Get-DhcpServerv4Scope | Format-Table -Auto

  Write-Host "`n== Opciones del scope 192.168.100.0 =="
  Get-DhcpServerv4OptionValue -ScopeId 192.168.100.0 | Format-List

  Write-Host "`n== Leases activas (scope 192.168.100.0) =="
  Get-DhcpServerv4Lease -ScopeId 192.168.100.0 | Select-Object IPAddress, ClientId, HostName, AddressState, LeaseExpiryTime | Format-Table -Auto
}

function Restart-Dhcp {
  Restart-Service DHCPServer
  Write-Host "Reiniciado DHCPServer."
}

while ($true) {
  Write-Host ""
  Write-Host "===== DHCP (Windows Server 2022) ====="
  Write-Host "1) Verificar/Instalar rol (idempotente)"
  Write-Host "2) Configurar DHCP (interactivo + validaciones)"
  Write-Host "3) Monitoreo (estado + leases)"
  Write-Host "4) Reiniciar servicio"
  Write-Host "5) Salir"
  $op = Read-Host "Opción"

  switch ($op) {
    "1" { Ensure-DhcpRole }
    "2" { Ensure-DhcpRole; Configure-Dhcp }
    "3" { Monitor-Dhcp }
    "4" { Restart-Dhcp }
    "5" { break }
    default { Write-Host "Opcion invalida." }
  }
}
