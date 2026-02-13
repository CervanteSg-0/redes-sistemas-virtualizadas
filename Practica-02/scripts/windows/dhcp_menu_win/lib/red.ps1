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
    if ( ($n -band 0xFF000000) -eq 0x7F000000 ) { return $false } # 127/8
    if ( ($n -band 0xFFFF0000) -eq 0xA9FE0000 ) { return $false } # 169.254/16
    if ( ($n -band 0xF0000000) -eq 0xE0000000 ) { return $false } # 224/4
    if ( ($n -band 0xF0000000) -eq 0xF0000000 ) { return $false } # 240/4

    return $true
}

function Leer-IPv4([string]$Prompt, [string]$Def = "") {
    while ($true) {
        $v = if ($Def) { Read-Host "$Prompt [$Def]" } else { Read-Host "$Prompt" }
        if ([string]::IsNullOrWhiteSpace($v) -and $Def) { $v = $Def }
        $v = $v.Trim()
        if (Es-IPv4Valida $v) { return $v }
        Write-Host "IP invalida."
    }
}

function Leer-IPv4Opcional([string]$Prompt) {
    while ($true) {
        $v = Read-Host "$Prompt (ENTER o -=omitir)"
        if ([string]::IsNullOrWhiteSpace($v)) { return "" }
        $v = $v.Trim()
        if ($v -eq "-") { return "" }
        if (Es-IPv4Valida $v) { return $v }
        Write-Host "IP invalida."
    }
}

function Leer-FinalConShorthand([string]$Prompt, [string]$IpInicio, [string]$Def = "") {
    $oct = $IpInicio.Split('.')
    $prefix = "$($oct[0]).$($oct[1]).$($oct[2])."
    while ($true) {
        $v = if ($Def) { Read-Host "$Prompt [$Def]" } else { Read-Host "$Prompt" }
        if ([string]::IsNullOrWhiteSpace($v) -and $Def) { $v = $Def }
        $v = $v.Trim()

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
        $v = $v.Trim()
        if ($v -match '^\d+$') { return [int]$v }
        Write-Host "Debe ser numero entero."
    }
}

function Incrementar-IP([string]$Ip) {
    $i = Convertir-IPaEntero $Ip
    return Convertir-EnteroaIP ([UInt32]($i + 1))
}

function Mascara-DesdePrefijo([int]$Prefix) {
    if ($Prefix -lt 0 -or $Prefix -gt 32) { return $null }
    if ($Prefix -eq 0) { return "0.0.0.0" }
    $mask = [uint32]0
    for ($i=0; $i -lt $Prefix; $i++) { $mask = $mask -bor ([uint32]1 -shl (31 - $i)) }
    return (Convertir-EnteroaIP $mask)
}

function PrefijoMinimo-QueCubreRango([string]$IpInicio, [string]$IpFinal) {
    $a = Convertir-IPaEntero $IpInicio
    $b = Convertir-IPaEntero $IpFinal
    $xor = $a -bxor $b
    if ($xor -eq 0) { return 32 }

    $msb = -1
    for ($i=31; $i -ge 0; $i--) {
        if ( ($xor -band (1 -shl $i)) -ne 0 ) { $msb = $i; break }
    }
    return (32 - ($msb + 1))
}

function Prefijo-ParaDHCPDesdeRango([string]$IpInicio, [string]$IpFinal) {
    # Calcula desde IPs, pero FORZA /24 si saliera mas especifico (ej /30 por rangos cortos)
    $p = PrefijoMinimo-QueCubreRango $IpInicio $IpFinal
    if ($p -gt 24) { return 24 }
    return $p
}

function Red-DeIP([string]$Ip, [string]$Mask) {
    $i = Convertir-IPaEntero $Ip
    $m = Convertir-IPaEntero $Mask
    return Convertir-EnteroaIP ([UInt32]($i -band $m))
}
