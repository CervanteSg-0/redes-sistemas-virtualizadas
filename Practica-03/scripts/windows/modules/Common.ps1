Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    throw "Ejecuta PowerShell COMO ADMINISTRADOR."
  }
}

function Pause-Enter { Write-Host ""; Read-Host "ENTER para continuar" | Out-Null }

function Is-ValidIPv4([string]$ip) {
  if ([string]::IsNullOrWhiteSpace($ip)) { return $false }
  if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { return $false }
  foreach ($p in $ip.Split('.')) {
    $n = 0
    if (-not [int]::TryParse($p, [ref]$n)) { return $false }
    if ($n -lt 0 -or $n -gt 255) { return $false }
  }
  if ($ip -eq "0.0.0.0" -or $ip -eq "255.255.255.255") { return $false }
  return $true
}

function Prompt-IPv4([string]$label) {
  while ($true) {
    $v = (Read-Host $label).Trim()
    if (Is-ValidIPv4 $v) { return $v }
    Write-Host "  IP invalida. Ej: 192.168.100.40"
  }
}

function Prompt-Int([string]$label, [int]$min, [int]$max, [int]$default) {
  while ($true) {
    $raw = (Read-Host "$label [$default]").Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { return $default }
    $n = 0
    if ([int]::TryParse($raw, [ref]$n) -and $n -ge $min -and $n -le $max) { return $n }
    Write-Host "  Valor invalido ($min-$max)."
  }
}

function Prompt-YesNo([string]$label, [bool]$defaultYes=$true) {
  $suffix = if ($defaultYes) { "[S/n]" } else { "[s/N]" }
  while ($true) {
    $r = (Read-Host "$label $suffix").Trim().ToLower()
    if ([string]::IsNullOrWhiteSpace($r)) { return $defaultYes }
    if ($r -match '^(s|si|y|yes)$') { return $true }
    if ($r -match '^(n|no)$') { return $false }
    Write-Host "  Responde S o N."
  }
}

function Is-ValidZoneName([string]$zoneName) {
  if ([string]::IsNullOrWhiteSpace($zoneName)) { return $false }
  $z = $zoneName.Trim().ToLower()
  # Validacion basica de FQDN: labels 1-63, total <= 253, termina con TLD 2-63
  return ($z -match '^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$')
}