# Práctica 05: Documentación Técnica de Infraestructura

Consolidación de la infraestructura y generación de manuales técnicos para la operación de los sistemas virtualizados.

## Características Principales
- **Inventario**: Detalle técnico de hardware virtual y software instalado.
- **Topología**: Documentación de la arquitectura de red y direccionamiento IP.
- **Manuales**: Guías paso a paso para la recuperación de servicios.
- **Optimización**: Ajuste final de parámetros de kernel y políticas de seguridad local.

## Estructura de la Práctica
```text
Practica-05/
├── scripts/             # Scripts de reporte y diagnóstico
├── manuals/             # Documentos PDF/Markdown con guías
└── README.md
```

## Formas de Ejecución
Para generar un reporte de estado del sistema:
### Linux
```bash
sudo ./scripts/generate_report.sh
```
### Windows
```powershell
.\scripts\Get-SystemInventory.ps1
```

## Requerimientos
- Todos los servicios de las prácticas 1-4 deben estar operativos.
