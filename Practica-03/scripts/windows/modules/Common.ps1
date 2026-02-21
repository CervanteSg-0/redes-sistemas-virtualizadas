# windows/modules/Common.ps1

function die {
    param([string]$msg)
    Write-Host "[ERROR] $msg" -ForegroundColor Red
    exit 1
}

function info {
    param([string]$msg)
    Write-Host "[INFO] $msg" -ForegroundColor Green
}

function ok {
    param([string]$msg)
    Write-Host "[OK] $msg" -ForegroundColor Cyan
}

function warn {
    param([string]$msg)
    Write-Host "[WARN] $msg" -ForegroundColor Yellow
}

function pause {
    Write-Host "[PAUSE] Presiona ENTER para continuar..."
    Read-Host
}

# Validación básica de IP v4
function valid_ipv4 {
    param([string]$ip)
    if ($ip -match "^([0-9]{1,3}\.){3}[0-9]{1,3}$") {
        $parts = $ip.Split(".")
        foreach ($part in $parts) {
            if ($part -gt 255 -or $part -lt 0) {
                return $false
            }
        }
        return $true
    }
    return $false
}

# Leer IP con validación
function prompt_ip {
    param([string]$label)
    while ($true) {
        $v = (Read-Host $label).Trim()
        if (valid_ipv4 $v) {
            return $v
        } else {
            Write-Host "  IP invalida. Ej: 192.168.100.50"
        }
    }
}

# Funcion para confirmar con S/N
function prompt_yesno {
    param([string]$label, [bool]$defaultYes=$true)
    $suffix = if ($defaultYes) { "[S/n]" } else { "[s/N]" }
    while ($true) {
        $r = (Read-Host "$label $suffix").Trim().ToLower()
        if ($r -eq "") { return $defaultYes }
        if ($r -match '^(s|si|y|yes)$') { return $true }
        if ($r -match '^(n|no)$') { return $false }
        Write-Host "  Responde S o N."
    }
}