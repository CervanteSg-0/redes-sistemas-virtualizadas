param(
  [Parameter(Mandatory=$true)][string]$DnsServerIP,
  [Parameter(Mandatory=$true)][string]$ClientIP,
  [string]$Domain = "reprobados.com"
)

function Is-ValidIPv4([string]$ip) {
  if ([string]::IsNullOrWhiteSpace($ip)) { return $false }
  if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { return $false }
  foreach ($p in $ip.Split('.')) {
    $n = 0
    if (-not [int]::TryParse($p, [ref]$n)) { return $false }
    if ($n -lt 0 -or $n -gt 255) { return $false }
  }
  return $true
}

if (-not (Is-ValidIPv4 $DnsServerIP)) { throw "DnsServerIP invalido." }
if (-not (Is-ValidIPv4 $ClientIP)) { throw "ClientIP invalido." }

Write-Host "== Configurando DNS del cliente a $DnsServerIP (temporal en interfaz activa) =="
$ad = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1
if (-not $ad) { throw "No hay adaptador Up." }

Set-DnsClientServerAddress -InterfaceIndex $ad.IfIndex -ServerAddresses $DnsServerIP

Write-Host ""
Write-Host "== Pruebas =="
Write-Host "nslookup $Domain"
nslookup $Domain

Write-Host ""
Write-Host "nslookup www.$Domain"
nslookup ("www." + $Domain)

Write-Host ""
Write-Host "ping www.$Domain (solo para evidencia de resolucion)"
ping ("www." + $Domain) -n 4

Write-Host ""
Write-Host "== Validacion rapida =="
Write-Host "Esperado: que la IP devuelta sea $ClientIP"
