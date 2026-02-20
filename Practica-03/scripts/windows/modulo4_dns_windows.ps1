# =============================================================================
# MÓDULO 4 — IP FIJA + DNS SERVER (WINDOWS SERVER - PowerShell)
# Proyecto: Servidor DNS - reprobados.com
# Descripción: Verifica IP estática, instala rol DNS Server, configura zona
#              directa para reprobados.com con registros A y CNAME, y valida.
# Uso: .\modulo4_dns_windows.ps1 [-Dominio "reprobados.com"] [-ClienteIP "192.168.1.20"]
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Dominio = "reprobados.com",

    [Parameter(Mandatory=$false)]
    [string]$ClienteIP = "",          # IP de la VM cliente (registros A apuntarán aquí)

    [Parameter(Mandatory=$false)]
    [string]$InterfazNombre = ""      # Nombre de interfaz (vacío = autodetectar)
)

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURACIÓN DE COLORES Y HELPERS
# ─────────────────────────────────────────────────────────────────────────────
function Write-Banner {
    param([string]$Titulo, [string]$Color = "Cyan")
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor $Color
    Write-Host "║  $Titulo" -ForegroundColor $Color -NoNewline
    Write-Host (" " * (62 - $Titulo.Length)) -NoNewline
    Write-Host "║" -ForegroundColor $Color
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor $Color
    Write-Host ""
}

function Write-OK   { param([string]$msg) Write-Host "[✓] $msg" -ForegroundColor Green }
function Write-WARN { param([string]$msg) Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-ERR  { param([string]$msg) Write-Host "[✗] $msg" -ForegroundColor Red }
function Write-INFO { param([string]$msg) Write-Host "[→] $msg" -ForegroundColor Blue }

# Contador de errores global
$script:ErroresTotal = 0

# ─────────────────────────────────────────────────────────────────────────────
# MÓDULO 4A — VERIFICACIÓN Y ASIGNACIÓN DE IP FIJA (WINDOWS)
# ─────────────────────────────────────────────────────────────────────────────
function Verificar-IPFija {
    Write-Banner "MÓDULO 4A — VERIFICACIÓN DE IP FIJA (WINDOWS)"

    # ── Verificar privilegios de administrador ────────────────────────────
    $esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $esAdmin) {
        Write-ERR "Este script debe ejecutarse como Administrador."
        exit 1
    }

    # ── Obtener interfaz activa ────────────────────────────────────────────
    if ([string]::IsNullOrEmpty($InterfazNombre)) {
        $adaptador = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Name -notlike "*Loopback*" } | Select-Object -First 1
        if (-not $adaptador) {
            Write-ERR "No se encontró interfaz de red activa."
            exit 1
        }
        $InterfazNombre = $adaptador.Name
    }

    Write-INFO "Interfaz de red: $InterfazNombre"

    # ── Verificar tipo de asignación IP ────────────────────────────────────
    $ipConfig = Get-NetIPAddress -InterfaceAlias $InterfazNombre -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $dhcpConfig = Get-NetIPInterface -InterfaceAlias $InterfazNombre -AddressFamily IPv4 -ErrorAction SilentlyContinue

    if (-not $ipConfig) {
        Write-WARN "La interfaz '$InterfazNombre' no tiene IP IPv4 asignada."
        Solicitar-DatosRed -InterfazNombre $InterfazNombre
        return
    }

    $ipActual = $ipConfig.IPAddress | Select-Object -First 1
    Write-INFO "IP actual en '$InterfazNombre': $ipActual"

    # Verificar si es estática (DHCP deshabilitado)
    if ($dhcpConfig.Dhcp -eq "Disabled") {
        Write-OK "IP estática detectada: $ipActual"
        $script:DnsServerIP = $ipActual
        Write-OK "Esta IP se usará como dirección del servidor DNS: $($script:DnsServerIP)"
    } else {
        Write-WARN "La IP '$ipActual' es asignada por DHCP. Se configurará IP estática."
        Solicitar-DatosRed -InterfazNombre $InterfazNombre -IPActual $ipActual
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# FUNCIÓN: Validar formato de IP
# ─────────────────────────────────────────────────────────────────────────────
function Validar-IP {
    param([string]$IP)
    try {
        [System.Net.IPAddress]::Parse($IP) | Out-Null
        return $true
    } catch {
        return $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# FUNCIÓN: Solicitar datos de red y configurar IP estática
# ─────────────────────────────────────────────────────────────────────────────
function Solicitar-DatosRed {
    param(
        [string]$InterfazNombre,
        [string]$IPActual = ""
    )

    Write-Host "`n══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host "  Se configurará una IP estática. Esta será la IP del servidor DNS." -ForegroundColor Yellow
    Write-Host "══════════════════════════════════════════════════════════════`n" -ForegroundColor Yellow

    # ── IP estática ────────────────────────────────────────────────────────
    do {
        $inputIP = Read-Host "Dirección IP estática para el servidor DNS"
        $valida = Validar-IP -IP $inputIP
        if (-not $valida) { Write-ERR "IP inválida. Formato: X.X.X.X" }
    } while (-not $valida)

    # ── Prefijo ────────────────────────────────────────────────────────────
    do {
        $inputPrefijo = Read-Host "Prefijo de subred CIDR (ej: 24)"
        $prefijoBueno = ($inputPrefijo -match '^\d+$') -and ([int]$inputPrefijo -ge 8) -and ([int]$inputPrefijo -le 30)
        if (-not $prefijoBueno) { Write-ERR "Prefijo inválido. Debe ser un número entre 8 y 30." }
    } while (-not $prefijoBueno)

    # ── Gateway ────────────────────────────────────────────────────────────
    $gwSugerido = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop
    do {
        $inputGW = Read-Host "Gateway (puerta de enlace) [$gwSugerido]"
        if ([string]::IsNullOrEmpty($inputGW)) { $inputGW = $gwSugerido }
        $gwBueno = Validar-IP -IP $inputGW
        if (-not $gwBueno) { Write-ERR "Gateway inválido." }
    } while (-not $gwBueno)

    # ── DNS externo ────────────────────────────────────────────────────────
    $dnsBkDefault = "8.8.8.8"
    $inputDNSBackup = Read-Host "DNS externo de respaldo [$dnsBkDefault]"
    if ([string]::IsNullOrEmpty($inputDNSBackup)) { $inputDNSBackup = $dnsBkDefault }

    # ── Resumen y confirmación ─────────────────────────────────────────────
    Write-Host "`n┌──────────────────────────────────────────────┐" -ForegroundColor Blue
    Write-Host "│         RESUMEN DE CONFIGURACIÓN              │" -ForegroundColor Blue
    Write-Host "├──────────────────────────────────────────────┤" -ForegroundColor Blue
    Write-Host "│ Interfaz   : $InterfazNombre"
    Write-Host "│ IP Estática: $inputIP/$inputPrefijo"
    Write-Host "│ Gateway    : $inputGW"
    Write-Host "│ DNS Backup : $inputDNSBackup"
    Write-Host "└──────────────────────────────────────────────┘`n" -ForegroundColor Blue

    $confirmar = Read-Host "¿Aplicar esta configuración? [s/N]"
    if ($confirmar.ToLower() -ne "s") {
        Write-WARN "Configuración cancelada por el usuario."
        exit 1
    }

    # ── Aplicar IP estática ────────────────────────────────────────────────
    Write-INFO "Eliminando configuración DHCP existente..."
    Remove-NetIPAddress -InterfaceAlias $InterfazNombre -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetRoute -InterfaceAlias $InterfazNombre -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue

    Write-INFO "Asignando IP estática $inputIP/$inputPrefijo..."
    New-NetIPAddress -InterfaceAlias $InterfazNombre `
                     -IPAddress $inputIP `
                     -PrefixLength ([int]$inputPrefijo) `
                     -DefaultGateway $inputGW `
                     -ErrorAction Stop | Out-Null

    Write-INFO "Configurando servidores DNS: 127.0.0.1, $inputDNSBackup..."
    Set-DnsClientServerAddress -InterfaceAlias $InterfazNombre `
                                -ServerAddresses ("127.0.0.1", $inputDNSBackup) `
                                -ErrorAction Stop

    $script:DnsServerIP = $inputIP
    Write-OK "IP estática configurada exitosamente: $($script:DnsServerIP)"
}

# ─────────────────────────────────────────────────────────────────────────────
# MÓDULO 4B — INSTALACIÓN DEL ROL DNS SERVER (WINDOWS)
# ─────────────────────────────────────────────────────────────────────────────
function Instalar-RolDNS {
    Write-Banner "MÓDULO 4B — INSTALACIÓN ROL DNS SERVER"

    # Verificar si ya está instalado
    $rolDNS = Get-WindowsFeature -Name DNS -ErrorAction SilentlyContinue
    if ($rolDNS -and $rolDNS.Installed) {
        Write-OK "El rol DNS Server ya está instalado. Se omite la instalación."
        return
    }

    Write-INFO "Instalando rol DNS Server..."
    try {
        $resultado = Install-WindowsFeature -Name DNS -IncludeManagementTools -ErrorAction Stop
        if ($resultado.Success) {
            Write-OK "Rol DNS Server instalado correctamente."
            if ($resultado.RestartNeeded -eq "Yes") {
                Write-WARN "Se requiere reinicio. Reinicie y vuelva a ejecutar el script."
                # No reiniciamos automáticamente para evitar pérdida de trabajo
            }
        } else {
            Write-ERR "Error al instalar el rol DNS Server."
            $script:ErroresTotal++
        }
    } catch {
        Write-ERR "Excepción al instalar DNS: $_"
        $script:ErroresTotal++
    }

    # Iniciar y configurar servicio DNS
    Write-INFO "Habilitando y arrancando servicio DNS..."
    Set-Service -Name DNS -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name DNS -ErrorAction SilentlyContinue
    $svc = Get-Service -Name DNS -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-OK "Servicio DNS en ejecución."
    } else {
        Write-ERR "El servicio DNS no está en ejecución."
        $script:ErroresTotal++
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# MÓDULO 4C — CONFIGURACIÓN DE ZONA Y REGISTROS DNS
# ─────────────────────────────────────────────────────────────────────────────
function Configurar-ZonaDNS {
    Write-Banner "MÓDULO 4C — CONFIGURACIÓN DE ZONA Y REGISTROS DNS"

    # ── Validar que ClienteIP esté definida ───────────────────────────────
    if ([string]::IsNullOrEmpty($ClienteIP)) {
        $ClienteIP = $script:DnsServerIP
        Write-WARN "ClienteIP no especificada. Se usará la IP del servidor: $ClienteIP"
    }

    Write-INFO "Dominio     : $Dominio"
    Write-INFO "DNS Server  : $($script:DnsServerIP)"
    Write-INFO "Cliente IP  : $ClienteIP"

    # ── Crear o verificar zona primaria ───────────────────────────────────
    Write-INFO "Verificando zona DNS '$Dominio'..."
    $zonaExistente = Get-DnsServerZone -Name $Dominio -ErrorAction SilentlyContinue

    if ($zonaExistente) {
        Write-WARN "La zona '$Dominio' ya existe. Se verificarán los registros."
    } else {
        Write-INFO "Creando zona primaria '$Dominio'..."
        try {
            Add-DnsServerPrimaryZone -Name $Dominio `
                                     -ZoneFile "db.$Dominio.dns" `
                                     -DynamicUpdate None `
                                     -ErrorAction Stop
            Write-OK "Zona '$Dominio' creada exitosamente."
        } catch {
            Write-ERR "Error al crear zona: $_"
            $script:ErroresTotal++
            return
        }
    }

    # ── Función auxiliar para crear/actualizar registro A ─────────────────
    function Set-RegistroA {
        param([string]$Nombre, [string]$IP, [string]$Zona)

        $registroExistente = Get-DnsServerResourceRecord -ZoneName $Zona `
                                                          -Name $Nombre `
                                                          -RRType A `
                                                          -ErrorAction SilentlyContinue

        if ($registroExistente) {
            Write-WARN "Registro A '$Nombre.$Zona' ya existe → $($registroExistente.RecordData.IPv4Address). Eliminando para recrear..."
            Remove-DnsServerResourceRecord -ZoneName $Zona `
                                            -Name $Nombre `
                                            -RRType A `
                                            -Force `
                                            -ErrorAction SilentlyContinue
        }

        try {
            Add-DnsServerResourceRecordA -ZoneName $Zona `
                                          -Name $Nombre `
                                          -IPv4Address $IP `
                                          -TimeToLive ([TimeSpan]::FromHours(1)) `
                                          -ErrorAction Stop
            Write-OK "Registro A creado: $Nombre.$Zona → $IP"
        } catch {
            Write-ERR "Error al crear registro A '$Nombre': $_"
            $script:ErroresTotal++
        }
    }

    # ── Función auxiliar para crear/actualizar registro CNAME ─────────────
    function Set-RegistroCNAME {
        param([string]$Alias, [string]$Target, [string]$Zona)

        $registroExistente = Get-DnsServerResourceRecord -ZoneName $Zona `
                                                          -Name $Alias `
                                                          -RRType CName `
                                                          -ErrorAction SilentlyContinue
        if ($registroExistente) {
            Write-WARN "Registro CNAME '$Alias' ya existe. Eliminando para recrear..."
            Remove-DnsServerResourceRecord -ZoneName $Zona `
                                            -Name $Alias `
                                            -RRType CName `
                                            -Force `
                                            -ErrorAction SilentlyContinue
        }

        try {
            Add-DnsServerResourceRecordCName -ZoneName $Zona `
                                              -Name $Alias `
                                              -HostNameAlias "$Target." `
                                              -TimeToLive ([TimeSpan]::FromHours(1)) `
                                              -ErrorAction Stop
            Write-OK "Registro CNAME creado: $Alias.$Zona → $Target"
        } catch {
            Write-ERR "Error al crear CNAME '$Alias': $_"
            $script:ErroresTotal++
        }
    }

    # ── Crear registros ────────────────────────────────────────────────────
    Write-INFO "Creando/verificando registros DNS..."

    # Registro A para el dominio raíz (@)
    Set-RegistroA -Nombre "@" -IP $ClienteIP -Zona $Dominio

    # Registro A para ns1 (servidor de nombres)
    Set-RegistroA -Nombre "ns1" -IP $script:DnsServerIP -Zona $Dominio

    # Registro A para www (subdominio)
    Set-RegistroA -Nombre "www" -IP $ClienteIP -Zona $Dominio

    # Alternativa: CNAME para www (comentado, descomente si se prefiere)
    # Set-RegistroCNAME -Alias "www" -Target $Dominio -Zona $Dominio

    Write-OK "Registros DNS configurados para '$Dominio'."
}

# ─────────────────────────────────────────────────────────────────────────────
# MÓDULO 4D — VALIDACIÓN Y PRUEBAS (WINDOWS)
# ─────────────────────────────────────────────────────────────────────────────
function Validar-DNS {
    Write-Banner "MÓDULO 4D — VALIDACIÓN Y PRUEBAS DE RESOLUCIÓN"

    $reporteFile = "C:\Temp\reporte_dns_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    New-Item -ItemType Directory -Path "C:\Temp" -Force -ErrorAction SilentlyContinue | Out-Null

    $reporte = @()
    $reporte += "============================================================"
    $reporte += " REPORTE DNS — $Dominio"
    $reporte += " Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $reporte += " DNS Server: $($script:DnsServerIP)"
    $reporte += " Cliente IP: $ClienteIP"
    $reporte += "============================================================"

    # ── [1] Estado del servicio DNS ───────────────────────────────────────
    Write-Host "`n[1/4] ESTADO DEL SERVICIO DNS" -ForegroundColor Blue
    $svc = Get-Service -Name DNS -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-OK "Servicio DNS: ACTIVO"
        $reporte += "[✓] Servicio DNS: ACTIVO"
    } else {
        Write-ERR "Servicio DNS: $($svc.Status) (esperado: Running)"
        $reporte += "[✗] Servicio DNS: $($svc.Status)"
        $script:ErroresTotal++
    }

    # ── [2] Verificar zona existe ──────────────────────────────────────────
    Write-Host "`n[2/4] VERIFICACIÓN DE ZONA" -ForegroundColor Blue
    $zona = Get-DnsServerZone -Name $Dominio -ErrorAction SilentlyContinue
    if ($zona) {
        Write-OK "Zona '$Dominio' existe. Tipo: $($zona.ZoneType)"
        $reporte += "[✓] Zona $Dominio existe"

        # Mostrar todos los registros
        Write-INFO "Registros en la zona '$Dominio':"
        $registros = Get-DnsServerResourceRecord -ZoneName $Dominio -ErrorAction SilentlyContinue
        $registros | Format-Table -AutoSize
        $registros | ForEach-Object { $reporte += "  $($_.HostName) $($_.RecordType) $($_.RecordData)" }
    } else {
        Write-ERR "Zona '$Dominio' no encontrada."
        $reporte += "[✗] Zona $Dominio no encontrada"
        $script:ErroresTotal++
    }

    # ── [3] Pruebas nslookup ───────────────────────────────────────────────
    Write-Host "`n[3/4] PRUEBAS nslookup" -ForegroundColor Blue

    function Probar-Nslookup {
        param([string]$Nombre, [string]$IPEsperada, [string]$Servidor)

        Write-INFO "nslookup $Nombre $Servidor"
        $resultado = nslookup $Nombre $Servidor 2>&1 | Out-String
        Write-Host $resultado

        $ipResuelta = ($resultado -split "`n" | Where-Object { $_ -match "Address:" -and $_ -notmatch "#53" } | Select-Object -Last 1) -replace "Address:\s+", "" | ForEach-Object { $_.Trim() }

        if ($ipResuelta -eq $IPEsperada) {
            Write-OK "nslookup $Nombre → $ipResuelta (coincide)"
            $script:reporte += "[✓] nslookup $Nombre → $ipResuelta"
        } else {
            Write-ERR "nslookup $Nombre → '$ipResuelta' (esperado: $IPEsperada)"
            $script:reporte += "[✗] nslookup $Nombre → $ipResuelta (esperado: $IPEsperada)"
            $script:ErroresTotal++
        }
    }

    Probar-Nslookup -Nombre $Dominio -IPEsperada $ClienteIP -Servidor $script:DnsServerIP
    Probar-Nslookup -Nombre "www.$Dominio" -IPEsperada $ClienteIP -Servidor $script:DnsServerIP

    # ── [4] Pruebas Resolve-DnsName ────────────────────────────────────────
    Write-Host "`n[4/4] PRUEBAS Resolve-DnsName (PowerShell)" -ForegroundColor Blue

    function Probar-ResolveDNS {
        param([string]$Nombre, [string]$IPEsperada)

        Write-INFO "Resolve-DnsName $Nombre -Server $($script:DnsServerIP)"
        try {
            $resultado = Resolve-DnsName -Name $Nombre `
                                          -Server $script:DnsServerIP `
                                          -Type A `
                                          -ErrorAction Stop
            $ipResuelta = $resultado | Where-Object { $_.Type -eq "A" } | Select-Object -ExpandProperty IPAddress -First 1

            if ($ipResuelta -eq $IPEsperada) {
                Write-OK "Resolve-DnsName '$Nombre' → $ipResuelta (coincide)"
                $reporte += "[✓] Resolve-DnsName $Nombre → $ipResuelta"
            } else {
                Write-ERR "Resolve-DnsName '$Nombre' → '$ipResuelta' (esperado: $IPEsperada)"
                $reporte += "[✗] Resolve-DnsName $Nombre → $ipResuelta (esperado: $IPEsperada)"
                $script:ErroresTotal++
            }
        } catch {
            Write-ERR "Error al resolver '$Nombre': $_"
            $reporte += "[✗] Error al resolver $Nombre : $_"
            $script:ErroresTotal++
        }
    }

    Probar-ResolveDNS -Nombre $Dominio -IPEsperada $ClienteIP
    Probar-ResolveDNS -Nombre "www.$Dominio" -IPEsperada $ClienteIP

    # ── Prueba de ping ─────────────────────────────────────────────────────
    Write-INFO "Ping a $Dominio..."
    $pingResult = Test-Connection -ComputerName $Dominio -Count 3 -ErrorAction SilentlyContinue
    if ($pingResult) {
        Write-OK "Ping a '$Dominio': EXITOSO (IP: $($pingResult[0].Address))"
        $reporte += "[✓] Ping $Dominio → $($pingResult[0].Address)"
    } else {
        Write-WARN "Ping a '$Dominio': Sin respuesta (puede bloquearse por firewall)"
        $reporte += "[!] Ping $Dominio : Sin respuesta"
    }

    # ── Guardar reporte ────────────────────────────────────────────────────
    $reporte | Out-File -FilePath $reporteFile -Encoding UTF8
    Write-INFO "Reporte guardado en: $reporteFile"

    return $script:ErroresTotal
}

# ─────────────────────────────────────────────────────────────────────────────
# SCRIPT PRINCIPAL
# ─────────────────────────────────────────────────────────────────────────────
Write-Banner "DNS SERVER WINDOWS — reprobados.com" -Color Cyan

# Variable global para IP del servidor
$script:DnsServerIP = ""

# Ejecutar módulos en orden
Verificar-IPFija
Instalar-RolDNS
Configurar-ZonaDNS
$errores = Validar-DNS

# ── Resumen final ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                 RESUMEN FINAL WINDOWS DNS                   ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║ Dominio    : $Dominio" -ForegroundColor Cyan
Write-Host "║ DNS Server : $($script:DnsServerIP)" -ForegroundColor Cyan
Write-Host "║ Cliente IP : $ClienteIP" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan

if ($errores -eq 0) {
    Write-Host "║  ✓ TODAS LAS PRUEBAS PASARON — DNS operativo                ║" -ForegroundColor Green
} else {
    Write-Host "║  ✗ SE ENCONTRARON $errores ERROR(ES) — Revise el reporte      ║" -ForegroundColor Red
}
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

exit $errores
