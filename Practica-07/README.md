# Documentación Técnica - Práctica 07

## Infraestructura de Despliegue Profesional con SSL/TLS

Este proyecto integra la automatización de la seguridad en canales (SSL/HTTPS/FTPS), un repositorio privado dinámico y la validación de integridad de archivos para una infraestructura redundante y segura.

### Orquestador de Instalación Híbrida

El script centralizado permite elegir el origen de los binarios:
1.  **Origen WEB:** Utiliza gestores de paquetes oficiales (`apt` o instaladores MSI descargados de la web).
2.  **Origen FTP (Privado):** 
    *   Se conecta al servidor central mediante `Invoke-WebRequest` o `curl`.
    *   Navega dinámicamente por `/http/[OS]/[Servicio]/[Versiones]`.
    *   Descarga el binario y un archivo `.sha256` asociado.
    *   **Validación de Integridad:** Se calcula el hash localmente y se compara con el reporte remoto.

### Cifrado de Canales

- **HTTP a HTTPS:** Implementación de redirección HTTP 301 para forzar el uso de TLS (HSTS básico).
- **FTPS (Control y Datos):** Configuración de canales de control y transferencia de archivos cifrados.

---

### Guía de Operación

#### 1. Preparar el repositorio (Opcional)
Ejecute el script de configuración del repositorio para crear la estructura de carpetas y archivos de prueba:
`powershell -ExecutionPolicy Bypass -File .\scripts\windows\setup_repo_practica07.ps1`

#### 2. Ejecutar el Orquestador (Windows)
`powershell -ExecutionPolicy Bypass -File .\scripts\windows\main_windows.ps1`

#### 3. Ejecutar el Orquestador (Linux)
`sudo bash ./scripts/linux/main_linux.sh`
