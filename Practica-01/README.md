# Práctica 01: Entornos de Virtualización y Conectividad Base

Esta práctica marca el inicio del curso, enfocándose en el despliegue de la infraestructura virtual necesaria y la validación de la comunicación entre diferentes sistemas operativos.

## Características Principales
- **Virtualización**: Despliegue de máquinas virtuales Linux (Mageia) y Windows Server.
- **Redes**: Configuración de adaptadores de red (NAT y Bridge) para permitir comunicación inter-VM.
- **Validación**: Pruebas de conectividad ICMP (ping) y resolución de nombres básica.
- **Gestión**: Primer acercamiento a los gestores de paquetes `dnf` y `Server Manager`.

## Estructura de la Práctica
```text
Practica-01/
├── scripts/             # Scripts de validación de red
├── files_entregables/   # Reportes de configuración
└── images/              # Evidencias de la topología virtual
```

## Formas de Ejecución
### Linux (Mageia)
Para validar la configuración de red inicial:
1. Otorgue permisos: `chmod +x scripts/*.sh`
2. Ejecute: `./scripts/check_connectivity.sh`

### Windows
1. Abra PowerShell como Administrador.
2. Ejecute el script de validación: `.\scripts\Validate-InitialSetup.ps1`

## Requerimientos
- VirtualBox o VMware instalado.
- ISO de Mageia Linux y Windows Server 2022.
