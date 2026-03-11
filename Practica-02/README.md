# Práctica 02: Administración de Usuarios y Servicios de Red

Enfoque en la gestión centralizada de identidades y el control de servicios esenciales del sistema operativo.

## Características Principales
- **Gestión de Identidades**: Creación masiva de usuarios y grupos via script.
- **Seguridad de Acceso**: Configuración de permisos de carpetas y políticas de contraseñas.
- **Servicios**: Control de servicios SSH y HTTP mediante automatización.
- **Auditoría**: Generación de logs para monitorear el estado de los procesos.

## Estructura de la Práctica
```text
Practica-02/
├── scripts/
│   ├── add_users.sh        # Script masivo para identidades Linux
│   ├── config_services.sh  # Automatización de SSH/Apache
│   └── setup_windows.ps1   # Configuración de roles Windows
└── README.md
```

## Formas de Ejecución
### Linux
Para gestionar usuarios y servicios:
```bash
sudo ./scripts/add_users.sh      # Para crear la estructura de usuarios
sudo ./scripts/config_services.sh # Para habilitar y asegurar servicios
```

### Windows
```powershell
# Ejecutar con permisos de Administrador
.\scripts\setup_windows.ps1
```

## Requerimientos
- Privilegios de Superusuario (sudo) en Linux.
- Rol de Administrador en Windows.