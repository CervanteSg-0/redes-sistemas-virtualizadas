. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\DnsRole.ps1"

function Ensure-ZoneAndRecords {
  Write-Host "== Zona + Registros (Windows DNS) =="

  $domain = (Read-Host "Dominio [reprobados.com]").Trim()
  if ([string]::IsNullOrWhiteSpace($domain)) { $domain = "reprobados.com" }
  $domain = $domain.ToLower()

  if (-not (Is-ValidZoneName $domain)) { throw "Nombre de zona invalido. Ej: reprobados.com" }

  $clientIP = Prompt-IPv4 "IP del CLIENTE (Windows 10) a la que apuntara reprobados.com y www"
  $ttlSec   = Prompt-Int "TTL en segundos" 30 86400 300
  $wwwAsCname = Prompt-YesNo "Para www usar CNAME hacia raiz?" $true

  Ensure-DnsRole

  $zone = Get-DnsServerZone -Name $domain -ErrorAction SilentlyContinue
  if (-not $zone) {
    Add-DnsServerPrimaryZone -Name $domain -ZoneFile "$domain.dns" -DynamicUpdate NonsecureAndSecure | Out-Null
    Write-Host "[OK] Zona creada: $domain"
  } else {
    Write-Host "[OK] Zona ya existe: $domain"
  }

  # Root A (@) -> reemplazo idempotente
  $existingA = Get-DnsServerResourceRecord -ZoneName $domain -Name "@" -RRType "A" -ErrorAction SilentlyContinue
  if ($existingA) {
    foreach ($rr in $existingA) {
      Remove-DnsServerResourceRecord -ZoneName $domain -RRType "A" -Name "@" -RecordData $rr.RecordData.IPv4Address -Force -ErrorAction SilentlyContinue
    }
  }
  Add-DnsServerResourceRecordA -ZoneName $domain -Name "@" -IPv4Address $clientIP -TimeToLive ([TimeSpan]::FromSeconds($ttlSec)) | Out-Null
  Write-Host "[OK] A @ -> $clientIP"

  # www: CNAME o A (limpieza previa)
  $exWwwA     = Get-DnsServerResourceRecord -ZoneName $domain -Name "www" -RRType "A"     -ErrorAction SilentlyContinue
  $exWwwCname = Get-DnsServerResourceRecord -ZoneName $domain -Name "www" -RRType "CNAME" -ErrorAction SilentlyContinue

  if ($exWwwA) {
    foreach ($rr in $exWwwA) {
      Remove-DnsServerResourceRecord -ZoneName $domain -RRType "A" -Name "www" -RecordData $rr.RecordData.IPv4Address -Force -ErrorAction SilentlyContinue
    }
  }
  if ($exWwwCname) {
    foreach ($rr in $exWwwCname) {
      Remove-DnsServerResourceRecord -ZoneName $domain -RRType "CNAME" -Name "www" -RecordData $rr.RecordData.HostNameAlias -Force -ErrorAction SilentlyContinue
    }
  }

  if ($wwwAsCname) {
    Add-DnsServerResourceRecordCName -ZoneName $domain -Name "www" -HostNameAlias "$domain." -TimeToLive ([TimeSpan]::FromSeconds($ttlSec)) | Out-Null
    Write-Host "[OK] CNAME www -> $domain"
  } else {
    Add-DnsServerResourceRecordA -ZoneName $domain -Name "www" -IPv4Address $clientIP -TimeToLive ([TimeSpan]::FromSeconds($ttlSec)) | Out-Null
    Write-Host "[OK] A www -> $clientIP"
  }

  Write-Host "[OK] Zona y registros listos."
}