# Práctica 04: Refactorización y Modularización de Scripts

Evolución de la automatización mediante el uso de librerías de funciones y arquitectura modular para la gestión de sistemas.

## Características Principales
- **Arquitectura de Funciones**: Separación de la lógica de interfaz (Main) y la lógica de negocio (Funciones).
- **Gestión DNS**: Automatización de la configuración de servidores de nombres y zonas.
- **Validación de Datos**: Implementación de Regex para validar entradas de usuario (IPs, Nombres, Puertos).
- **Hardening**: Scripts diseñados para aplicar cambios de seguridad en masa de forma silenciosa.

## Estructura de la Práctica
```text
Practica-04/
├── scripts/
│   ├── linux/
│   │   ├── main.sh               # Punto de entrada
│   │   └── funciones_mageia.sh    # Librería de funciones para Mageia
│   └── windows/
│       ├── main.ps1              # Punto de entrada
│       └── funciones_ws.ps1       # Librería de funciones PowerShell
```

## Formas de Ejecución
### Linux
```bash
cd scripts/linux
chmod +x *.sh
sudo ./main.sh
```

### Windows
```powershell
cd scripts\windows
.\main.ps1
```

## Requerimientos
- Linux Mageia 8/9.
- Windows Server configurado con ejecución de scripts habilitada (`Set-ExecutionPolicy RemoteSigned`).
