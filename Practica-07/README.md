# Práctica 07: Sistema de Aprovisionamiento Web Automatizado

Este proyecto implementa una solución automatizada para el despliegue de servidores HTTP en entornos Linux y Windows, operada exclusivamente mediante scripts interactivos.

## Estructura del Proyecto

```text
Practica-07/
├── scripts/
│   ├── linux/
│   │   ├── main.sh            # Script principal (Linux)
│   │   └── http_functions.sh  # Librería de funciones (Linux)
│   └── windows/
│       ├── main.ps1           # Script principal (Windows)
│       └── http_functions.ps1 # Librería de funciones (Windows)
└── README.md                  # Documentación técnica
```

## Características Técnicas

- **Gestión Dinámica**: Las versiones se consultan en tiempo real desde los repositorios oficiales (`apt` en Linux, `Chocolatey` en Windows).
- **Seguridad por Diseño**:
    - Ocultación de cabeceras de servidor (`ServerTokens`, `X-Powered-By`).
    - Implementación de `Security Headers` (`X-Frame-Options`, `X-Content-Type-Options`).
    - Gestión automática de Firewall (UFW en Linux, Windows Firewall).
    - Usuarios dedicados y permisos restringidos.
- **Validación Robusta**: Comprobación de disponibilidad de puertos y restricción de puertos reservados.

## Instrucciones de Uso

### Linux
1. Acceder al servidor vía SSH.
2. Navegar a `scripts/linux/`.
3. Dar permisos de ejecución: `chmod +x *.sh`.
4. Ejecutar con privilegios de superusuario: `sudo ./main.sh`.

### Windows
1. Acceder al servidor vía RDP o SSH (PowerShell).
2. Navegar a `scripts\windows\`.
3. Ejecutar como Administrador: `.\main.ps1`.
   - *Nota: Requiere Chocolatey instalado para Apache y Nginx.*

## Verificación
Para confirmar que el servidor está funcionando correctamente y que las cabeceras de seguridad están aplicadas, ejecute:
`curl -I http://localhost:[PUERTO]`
