param(
  [Parameter(Mandatory=$true)][string]$DnsServerIP,
  [Parameter(Mandatory=$true)][string]$ClientIP,
  [string[]]$Domains = @()
)

# Intentar cargar dominios dinamicamente desde el archivo de manifiesto si no se pasaron por parametro
$sharedFile = Join-Path $PSScriptRoot "..\dominios_activos.txt"
if ($Domains.Count -eq 0 -and (Test-Path $sharedFile)) {
    Write-Host "== Cargando dominios dinamicamente desde $sharedFile ==" -ForegroundColor Cyan
    $Domains = Get-Content $sharedFile | Where-Object { $_ -match "\." }
}

# Si sigue vacio, usar una lista de respaldo
if ($Domains.Count -eq 0) {
    Write-Host "== Usando lista de dominios por defecto (no se encontro manifiesto) ==" -ForegroundColor Gray
    $Domains = @("recursadores.com", "quierounavion.com", "apruebeme.com")
}

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

# Limpiar cache local para evitar "fantasmas" de dominios borrados
Write-Host "== Limpiando cache DNS local ==" -ForegroundColor Yellow
Clear-DnsClientCache

Write-Host "== Configurando DNS del cliente a $DnsServerIP (temporal en interfaz activa) =="
$ad = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1
if (-not $ad) { throw "No hay adaptador Up." }

Set-DnsClientServerAddress -InterfaceIndex $ad.IfIndex -ServerAddresses $DnsServerIP

Write-Host ""
Write-Host "== Iniciando Pruebas Multidominio ==" -ForegroundColor Cyan

foreach ($Domain in $Domains) {
    Write-Host "`n>>> Probando Dominio: $Domain <<<" -ForegroundColor Green
    
    Write-Host "[DNS] Resolviendo $Domain..."
    $res = Resolve-DnsName -Name $Domain -Server $DnsServerIP -ErrorAction SilentlyContinue
    if ($res) {
        $res | Select-Object Name, Type, IPAddress | Format-Table
    } else {
        Write-Host " [X] No se pudo resolver $Domain" -ForegroundColor Red
    }

    Write-Host "[PING] Comprobando respuesta de www.$Domain..."
    ping ("www." + $Domain) -n 2
}

Write-Host "`n== Validacion Final ==" -ForegroundColor Cyan
Write-Host "IP Esperada para todos los dominios locales: $ClientIP"
Write-Host "Si un dominio no registrado devuelve una IP publica (como reprobados.com), es por RECURSION externa." -ForegroundColor Gray
