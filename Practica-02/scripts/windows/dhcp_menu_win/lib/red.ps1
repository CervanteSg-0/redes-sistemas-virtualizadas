function Convertir-IPaEntero([string]$Ip) {
    $bytes = [System.Net.IPAddress]::Parse($Ip).GetAddressBytes()
    [Array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function Convertir-EnteroaIP([UInt32]$Num) {
    $bytes = [BitConverter]::GetBytes($Num)
    [Array]::Reverse($bytes)
    return ([System.Net.IPAddress]::new($bytes)).ToString()
}

function Es-IPv4Formato([string]$Ip) {
    return $Ip -match '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
}

function Es-IPv4Valida([string]$Ip) {
    if (-not (Es-IPv4Formato $Ip)) { return $false }

    $parts = $Ip.Split('.')
    foreach ($p in $parts) {
        if ($p -notmatch '^\d+$') { return $false }
        $n = [int]$p
        if ($n -lt 0 -or $n -gt 255) { return $false }
    }

    if ($Ip -eq "0.0.0.0" -or $Ip -eq "255.255.255.255") { return $false }

    $n = Convertir-IPaEntero $Ip
    if ( ($n -band 0xFF000000) -eq 0x7F000000 ) { return $false }
    if ( ($n -band 0xFFFF0000) -eq 0xA9FE0000 ) { return $false }
    if ( ($n -band 0xF0000000) -eq 0xE0000000 ) { return $false }
    if ( ($n -band 0xF0000000) -eq 0xF0000000 ) { return $false }

    return $true
}

function Mascara-EsValida([string]$Mask) {
    if (-not (Es-IPv4Formato $Mask)) { return $false }
    $mi = Convertir-IPaEntero $Mask
    if ($mi -eq 0 -or $mi -eq 0xFFFFFFFF) { return $false }
    $inv = 0xFFFFFFFF -bxor $mi
    return ( ($inv -band ($inv + 1)) -eq 0 )
}

function Misma-Subred([string]$Ip1, [string]$Ip2, [string]$Mask) {
    $i1 = Convertir-IPaEntero $Ip1
    $i2 = Convertir-IPaEntero $Ip2
    $m  = Convertir-IPaEntero $Mask
    return ( ($i1 -band $m) -eq ($i2 -band $m) )
}

function Red-DeIP([string]$Ip, [string]$Mask) {
    $i = Convertir-IPaEntero $Ip
    $m = Convertir-IPaEntero $Mask
    return Convertir-EnteroaIP ([UInt32]($i -band $m))
}

function Incrementar-IP([string]$Ip) {
    $i = Convertir-IPaEntero $Ip
    return Convertir-EnteroaIP ([UInt32]($i + 1))
}

function Prefijo-DesdeMascara([string]$Mask) {
    $maskInt = Convertir-IPaEntero $Mask
    $bits = 0
    for ($b=31; $b -ge 0; $b--) {
        if ( ($maskInt -band (1 -shl $b)) -ne 0 ) { $bits++ }
    }
    if ($bits -le 0) { return 24 }
    return $bits
}

function Leer-IPv4([string]$Prompt, [string]$Def = "") {
    while ($true) {
        $v = if ($Def) { Read-Host "$Prompt [$Def]" } else { Read-Host "$Prompt" }
        if ([string]::IsNullOrWhiteSpace($v) -and $Def) { $v = $Def }
        if (Es-IPv4Valida $v) { return $v }
        Write-Host "IP invalida."
    }
}

function Leer-IPv4Opcional([string]$Prompt) {
    while ($true) {
        $v = Read-Host "$Prompt (ENTER o -=omitir)"
        if ([string]::IsNullOrWhiteSpace($v) -or $v -eq "-") { return "" }
        if (Es-IPv4Valida $v) { return $v }
        Write-Host "IP invalida."
    }
}

function Leer-Mascara([string]$Prompt, [string]$Def = "255.255.255.0") {
    while ($true) {
        $v = Read-Host "$Prompt [$Def]"
        if ([string]::IsNullOrWhiteSpace($v)) { $v = $Def }
        if (Mascara-EsValida $v) { return $v }
        Write-Host "Mascara invalida."
    }
}

function Leer-FinalConShorthand([string]$Prompt, [string]$IpInicio, [string]$Def = "") {
    $oct = $IpInicio.Split('.')
    $prefix = "$($oct[0]).$($oct[1]).$($oct[2])."
    while ($true) {
        $v = if ($Def) { Read-Host "$Prompt [$Def]" } else { Read-Host "$Prompt" }
        if ([string]::IsNullOrWhiteSpace($v) -and $Def) { $v = $Def }

        if ($v -match '^\d{1,3}$') {
            $n = [int]$v
            if ($n -lt 0 -or $n -gt 255) { Write-Host "Final invalido (0-255)."; continue }
            $v = $prefix + $n
        }

        if (Es-IPv4Valida $v) { return $v }
        Write-Host "IP invalida."
    }
}

function Leer-Entero([string]$Prompt, [int]$Def) {
    while ($true) {
        $v = Read-Host "$Prompt [$Def]"
        if ([string]::IsNullOrWhiteSpace($v)) { return $Def }
        if ($v -match '^\d+$') { return [int]$v }
        Write-Host "Debe ser numero entero."
    }
}

