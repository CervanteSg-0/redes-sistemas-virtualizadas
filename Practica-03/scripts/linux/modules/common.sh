#!/usr/bin/env bash

# Global Variables
SERVICE_NAME="named"
NAMED_CONF="/etc/named.conf"
NAMED_LOCAL="/etc/named.conf.local"

# Función para terminar el script con un mensaje de error
die() {
    local msg="$1"
    echo -e "\e[31m[ERROR] $msg\e[0m"
    exit 1
}

# Función para mostrar mensajes de información
info() {
    local msg="$1"
    echo -e "\e[34m[INFO] $msg\e[0m"
}

# Función para mostrar mensajes de éxito
ok() {
    local msg="$1"
    echo -e "\e[32m[OK] $msg\e[0m"
}

# Función para mostrar advertencias
warn() {
    local msg="$1"
    echo -e "\e[33m[WARN] $msg\e[0m"
}

# Función para pausar la ejecución y esperar la entrada del usuario
pause() {
    echo ""
    echo "[PAUSE] Presiona ENTER para continuar..."
    # redirection for read to work from stdin when backgrounded
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
    local ip
    while true; do
        read -r -p "$label : " ip
        if valid_ipv4 "$ip"; then
            echo "$ip"
            return 0
        else
            echo "  IP inválida. Ejemplo de formato correcto: 192.168.100.50"
        fi
    done
}

# Confirmación de respuesta S/N
prompt_yesno() {
    local label="$1"
    local defaultYes="${2:-true}"
    local suffix
    if [ "$defaultYes" = true ]; then
        suffix="[S/n]"
    else
        suffix="[s/N]"
    fi
    
    local response
    while true; do
        read -r -p "$label $suffix: " response
        if [[ -z "$response" ]]; then
            if [ "$defaultYes" = true ]; then return 0; else return 1; fi
        fi
        if [[ "$response" =~ ^(s|si|y|yes)$ ]]; then
            return 0
        elif [[ "$response" =~ ^(n|no)$ ]]; then
            return 1
        else
            echo "  Responde S o N."
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

service_restart() {
    info "Reiniciando servicio $SERVICE_NAME..."
    systemctl restart "$SERVICE_NAME" || warn "No se pudo reiniciar $SERVICE_NAME"
}

show_listen_53() {
    info "== Puertos escuchando 53 (DNS) =="
    if command -v ss >/dev/null 2>&1; then
        ss -tunlp | grep :53 || echo "Nada escuchando en el puerto 53"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tunlp | grep :53 || echo "Nada escuchando en el puerto 53"
    else
        echo "No se encontro 'ss' ni 'netstat' para verificar puertos."
    fi
}

service_status() {
    info "== Estado del servicio $SERVICE_NAME =="
    systemctl --no-pager -l status "$SERVICE_NAME" || true
    echo ""
    show_listen_53
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "Este script debe ejecutarse como root (sudo)."
    fi
}

list_active_zones() {
    info "== Dominios/Zonas DNS Activas (en $NAMED_LOCAL) =="
    if [[ ! -f "$NAMED_LOCAL" ]]; then
        echo "No se encontro el archivo $NAMED_LOCAL"
        return
    fi
    grep "zone" "$NAMED_LOCAL" | cut -d'"' -f2 | sed 's/^/ - /' || echo "No hay zonas configuradas manualmente."
}

manual_ip_flow() {
    info "== Asignar IP Estatica Manualmente =="
    local iface ip mask gw dns1
    
    echo "Interfaces disponibles:"
    ip -o link show | awk -F': ' '{print $2}' | sed 's/@.*//' | grep -v '^lo$' | sed 's/^/ - /'
    
    read -r -p "Interfaz [ens34]: " iface
    iface="${iface:-ens34}"
    
    ip="$(prompt_ip "IP Estatica para el servidor")"
    
    echo -e "\e[33m[!] ADVERTENCIA: Si dejas la Puerta de Enlace vacía, podrías perder internet en la VM.\e[0m"
    mask="$(read -r -p "Mascara [255.255.255.0]: " m; echo "${m:-255.255.255.0}")"
    gw="$(read -r -p "Puerta de enlace (ENTER para omitir): " g; echo "$g")"
    dns1="$(read -r -p "DNS Primario (ENTER para omitir): " d; echo "$d")"
    
    info "Aplicando configuracion..."
    # Usar nmcli para mayor persistencia
    if command -v nmcli >/dev/null 2>&1; then
        local con
        con="$(nmcli -t -f NAME,DEVICE con show --active | awk -F: -v d="$iface" '$2==d{print $1; exit}')"
        [[ -z "$con" ]] && con="$(nmcli -t -f NAME,DEVICE con show | awk -F: -v d="$iface" '$2==d{print $1; exit}')"
        
        if [[ -n "$con" ]]; then
            nmcli con mod "$con" ipv4.method manual ipv4.addresses "$ip/24"
            if [[ -n "$gw" ]]; then
                nmcli con mod "$con" ipv4.gateway "$gw"
            else
                nmcli con mod "$con" ipv4.gateway ""
            fi
            if [[ -n "$dns1" ]]; then
                nmcli con mod "$con" ipv4.dns "$dns1"
            else
                nmcli con mod "$con" ipv4.dns ""
            fi
            nmcli con up "$con"
            ok "Configuracion aplicada via nmcli."
        else
            warn "No se encontro conexion activa para $iface. Usando comando 'ip' (temporal)."
            ip addr flush dev "$iface" >/dev/null 2>&1 || true
            ip addr add "$ip/24" dev "$iface"
            ip link set "$iface" up
        fi
    else
        ip addr flush dev "$iface" >/dev/null 2>&1 || true
        ip addr add "$ip/24" dev "$iface"
        ip link set "$iface" up
        ok "IP asignada (temporal, no se encontro nmcli)."
    fi
}
