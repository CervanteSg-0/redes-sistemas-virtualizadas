# Práctica 03: Servidores de Archivos y Protocolo FTP

Implementación y aseguramiento de servidores de transferencia de archivos (FTP) en entornos heterogéneos.

## Características Principales
- **Acceso Anónimo**: Configuración controlada de usuarios anónimos con permisos de solo lectura.
- **Estructura de Directorios**: Creación de carpetas compartidas (`public`, `reprobados`, `recursadores`) con permisos diferenciales.
- **Seguridad FTP**: Restricción de acceso local a los usuarios FTP (Chroot) y denegación de shells.
- **Multiplataforma**: Instalación de VSFTPD en Linux y el rol de FTP Server en IIS para Windows.

## Estructura de la Práctica
```text
Practica-03/
├── scripts/
│   ├── config_ftp.sh     # Instalación y hardening de VSFTPD
│   ├── setup_folders.sh  # Creación de estructura de archivos
│   └── setup_ftp.ps1     # Configuración de FTP en IIS
└── instrucciones-p3.md  # Guía de requerimientos
```

## Formas de Ejecución
### Linux (Mageia)
```bash
sudo ./scripts/config_ftp.sh
```
### Windows
```powershell
.\scripts\setup_ftp.ps1
```

## Requerimientos
- Puerto 21 (FTP) disponible.
- Gestor de paquetes `dnf` configurado.
