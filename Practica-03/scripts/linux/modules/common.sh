#!/usr/bin/env bash

# Función para terminar el script con un mensaje de error
die() {
    local msg="$1"
    echo "[ERROR] $msg"
    exit 1
}

# Función para mostrar mensajes de información
info() {
    local msg="$1"
    echo "[INFO] $msg"
}

# Función para mostrar mensajes de éxito
ok() {
    local msg="$1"
    echo "[OK] $msg"
}

# Función para mostrar advertencias
warn() {
    local msg="$1"
    echo "[WARN] $msg"
}

# Función para pausar la ejecución y esperar la entrada del usuario
pause() {
    echo "[PAUSE] Presiona ENTER para continuar..."
    read -r
}

# Validación básica de IP v4
valid_ipv4() {
    local ip="$1"
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local IFS='.' ip1 ip2 ip3 ip4
        IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$ip"
        if ((ip1 >= 0 && ip1 <= 255 && ip2 >= 0 && ip2 <= 255 && ip3 >= 0 && ip3 <= 255 && ip4 >= 0 && ip4 <= 255)); then
            return 0
        fi
    fi
    return 1
}

# Leer IP con validación
prompt_ip() {
    local label="$1"
    while true; do
        read -r ip
        if valid_ipv4 "$ip"; then
            echo "$ip"
            return 0
        else
            echo "IP inválida. Ejemplo de formato correcto: 192.168.100.50"
        fi
    done
}

# Confirmación de respuesta S/N
prompt_yesno() {
    local label="$1"
    local defaultYes="$2"
    local suffix
    if [ "$defaultYes" = true ]; then
        suffix="[S/n]"
    else
        suffix="[s/N]"
    fi
    while true; do
        read -r response
        response="${response:-$defaultYes}"
        if [[ "$response" =~ ^(s|si|y|yes)$ ]]; then
            return 0
        elif [[ "$response" =~ ^(n|no)$ ]]; then
            return 1
        else
            echo "$label $suffix"
        fi
    done
}

# Elimina espacios al inicio y al final de una cadena
trim() {
    echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Función de validación de dominio (FQDN)
valid_fqdn_zone() {
    local domain="$1"
    # Expresión regular para validar FQDN (dominio)
    if [[ "$domain" =~ ^([a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}