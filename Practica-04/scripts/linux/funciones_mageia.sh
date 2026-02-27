#!/bin/bash

#Funciones modulares para Mageia Server 

# Variables
ZONAS_DNS="/var/named/zones"
CONF_DNS="/etc/named.conf"
CONF_DHCP="/etc/dhcpd.conf"
DHCP_PKG="dhcp-server"

# Funciones de utilidad
pausa_tecla() {
    echo -e "\n\e[1;33m[<] Presiona [Enter] para continuar...\e[0m"
    read -r
}

instalar_paquete() {
    local paquete=$1
    echo "Verificando/Instalando paquete: $paquete"
    if ! rpm -q "$paquete" > /dev/null 2>&1; then
        dnf install -y "$paquete"
    else
        echo "El paquete $paquete ya se encuentra instalado."
    fi
}

inicializar_carpetas() {
    # Crear carpetas si es necesario (Reordenado para que esten disponibles dende el principio)
    mkdir -p /etc/dhcp
    mkdir -p /var/named/zones
    mkdir -p /etc/ssh
}

# ==========================================
# MODULO: SSH
# ==========================================
modulo_ssh() {
    clear
    echo "============================================="
    echo "       CONFIGURACION DE SERVICIO SSH         "
    echo "============================================="
    instalar_paquete openssh-server

    # Respaldar configuracion
    [ ! -f /etc/ssh/sshd_config.bak ] && cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null

    # Permitir root login por red de manera automatica
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    if ! grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config; then
        echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
    fi

    # Habilitar en servicios de systemd (Mageia)
    systemctl enable sshd
    systemctl restart sshd

    echo -e "\e[1;32m[OK] Servicio SSH habilitado y reiniciado correctamente.\e[0m"
    pausa_tecla
}

# ==========================================
# MODULO: DHCP (ISC DHCP)
# ==========================================
modulo_dhcp() {
    while true; do
        clear
        echo "============================================="
        echo "           GESTOR DE DHCP (ISC DHCP)         "
        echo "============================================="
        echo " A - Verificar estado de servicio"
        echo " B - Instalar e iniciar Servidor DHCP"
        echo " C - Configurar Nuevo Ambito"
        echo " R - Regresar"
        echo "============================================="
        read -p ">> Seleccione: " sub_op

        case ${sub_op^^} in
            A)
                if rpm -qa | grep -q "^$DHCP_PKG"; then
                    echo -e "\e[1;32mEl servidor DHCP ($DHCP_PKG) local ESTA instalado.\e[0m"
                    systemctl status dhcpd --no-pager | grep "Active:"
                else
                    echo -e "\e[1;31mEl servidor DHCP NO esta instalado.\e[0m"
                fi
                pausa_tecla
                ;;
            B)
                instalar_paquete $DHCP_PKG
                systemctl enable dhcpd
                echo -e "\e[1;32mPaquete instalado y servicio habilitado.\e[0m"
                pausa_tecla
                ;;
            C)
                configurar_ambito_dhcp
                ;;
            R)
                break
                ;;
            *)
                echo -e "\e[1;31mOpcion no valida.\e[0m"
                sleep 1
                ;;
        esac
    done
}

configurar_ambito_dhcp() {
    echo "---- Asistente Rapido de Ambito DHCP (Mageia) ----"
    
    # Automatizacion de inferfaz
    ifs=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$')
    echo "Interfaces del servidor disponibles:"
    i=1
    declare -A iface_map
    for iface in $ifs; do
        echo " $i) $iface"
        iface_map[$i]=$iface
        ((i++))
    done
    read -p "Seleccione numero para aplicar (o el nombre exacto): " num_if
    
    # Validar si ingreso el nombre directo
    if [[ " $ifs " =~ " $num_if " ]]; then
        INTERFAZ=$num_if
    else
        INTERFAZ=${iface_map[$num_if]}
    fi

    if [ -z "$INTERFAZ" ]; then
        echo -e "\e[1;31mInterfaz descartada. Opcion invalida.\e[0m"
        pausa_tecla
        return
    fi
    
    read -p "  Direccion IP de Red (Ej. 192.168.10.0): " RED_IP
    read -p "  Mascara Subred (Defecto: 255.255.255.0): " MASCARA
    MASCARA=${MASCARA:-255.255.255.0}
    read -p "  Rango Inicial para Clientes: " RANGO_INI
    read -p "  Rango Final para Clientes: " RANGO_FIN
    read -p "  Puerta de Enlace (Router) [Opcional]: " GATEWAY
    read -p "  Servidor DNS (Primario) [Opcional]: " DNS_IP
    read -p "  Tiempo de Concesion (Defecto: 600): " TIEMPO
    TIEMPO=${TIEMPO:-600}

    # Configuramos la ip fija si el usuario decide
    read -p "Desea fijar la IP Base para el Servidor? (s/n): " FIJAR
    if [ "${FIJAR^^}" == "S" ]; then
        read -p "  IP Estatica del Server en $INTERFAZ: " IP_SERVER
        read -p "  Prefijo en CIDR (Ej. 24 para 255.255.255.0 ó 16 para 255.255.0.0): " CIDR
        
        ip addr flush dev "$INTERFAZ"
        ip addr add "$IP_SERVER/$CIDR" dev "$INTERFAZ"
        ip link set "$INTERFAZ" up
    fi

    echo "Respaldando anterior configuracion..."
    [ ! -f $CONF_DHCP.bak ] && cp $CONF_DHCP $CONF_DHCP.bak 2>/dev/null

    echo "Generando archivo de configuracion dhcpd.conf..."
    
    # Preparar sintaxis para opciones opcionales para evitar errores
    OPCION_ROUTER=""
    OPCION_DNS=""
    [ -n "$GATEWAY" ] && OPCION_ROUTER="    option routers $GATEWAY;"
    [ -n "$DNS_IP" ] && OPCION_DNS="    option domain-name-servers $DNS_IP;"

    cat <<EOF > $CONF_DHCP
# Configuracion DHCP generada via Gestor de Mageia
default-lease-time $TIEMPO;
max-lease-time $((TIEMPO * 2));
authoritative;

subnet $RED_IP netmask $MASCARA {
    range $RANGO_INI $RANGO_FIN;
$OPCION_ROUTER
$OPCION_DNS
}
EOF

    # Registrar la interfaz en sysconfig para el servicio (necesario en Mageia)
    mkdir -p /etc/sysconfig
    if grep -q "^DHCPDARGS" /etc/sysconfig/dhcpd 2>/dev/null; then
        sed -i "s/^DHCPDARGS.*/DHCPDARGS=\"$INTERFAZ\"/" /etc/sysconfig/dhcpd
    else
        echo "DHCPDARGS=\"$INTERFAZ\"" >> /etc/sysconfig/dhcpd
    fi

    echo -e "\n\e[1;33m[*] Iniciando DHCP. Si falla, asegurate de que la interfaz '$INTERFAZ' tenga una IP estatica dentro de la red que acabas de configurar.\e[0m"
    systemctl restart dhcpd
    
    if systemctl is-active --quiet dhcpd; then
        echo -e "\e[1;32mAmbito configurado y DHCPD corriendo correctamente.\e[0m"
    else
        echo -e "\e[1;31m[!] Falla al iniciar el servicio DHCP. Ejecuta 'systemctl status dhcpd' para ver detalles.\e[0m"
    fi
    pausa_tecla
}

# ==========================================
# MODULO: DNS (BIND9)
# ==========================================
reconstruir_named_conf() {
    cat << EOF > $CONF_DNS
options {
    directory "/var/named";
    dump-file "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    listen-on { any; };
    allow-query { any; };
    recursion yes;
};

logging {
    channel default_debug {
        file "data/named.run";
        severity dynamic;
    };
};
EOF

    # Anexar las zonas a BIND
    for config_zona in "$ZONAS_DNS"/db.*; do
        if [ -f "$config_zona" ]; then
            nombre_dom=$(basename "$config_zona" | sed 's/db\.//')
            echo "zone \"$nombre_dom\" IN { type master; file \"$config_zona\"; };" >> $CONF_DNS
        fi
    done

    systemctl restart named
}

modulo_dns() {
    while true; do
        clear
        echo "============================================="
        echo "            GESTOR DE DNS (BIND9)            "
        echo "============================================="
        echo " 1) Preparar e Instalar Servicio DNS"
        echo " 2) Dar de alta un Dominio/Zona"
        echo " 3) Dar de baja un Dominio/Zona"
        echo " 4) Analizar lista de Dominios"
        echo " 5) Regresar"
        echo "============================================="
        read -p ">> Opcion de red: " sub_op

        case "$sub_op" in
            1)
                instalar_paquete bind
                systemctl enable named
                reconstruir_named_conf
                echo -e "\e[1;32mEl servicio ha sido preparado para recibir zonas.\e[0m"
                pausa_tecla
                ;;
            2)
                read -p "  Dominio nuevo (Ej. prueba.com): " DOMINIO
                read -p "  Direccion IP a apuntar: " IP_RESOL
                
                # Desplegar layout de Zona DNS
                cat << EOF > "$ZONAS_DNS/db.$DOMINIO"
\$TTL 86400
@   IN  SOA ns1.$DOMINIO. admin.$DOMINIO. (
        2024010101  ; Serial
        3600        ; Refresh
        1800        ; Retry
        604800      ; Expire
        86400 )     ; Minimum TTL
;
@       IN  NS      ns1.$DOMINIO.
@       IN  A       $IP_RESOL
ns1     IN  A       $IP_RESOL
www     IN  A       $IP_RESOL
EOF
                # Permisos adecuados para named
                chown -R root:named "$ZONAS_DNS" 2>/dev/null
                chmod 640 "$ZONAS_DNS/db.$DOMINIO" 2>/dev/null

                reconstruir_named_conf
                echo -e "\e[1;32m¡Registro de la zona $DOMINIO concluido!\e[0m"
                pausa_tecla
                ;;
            3)
                read -p "  Digite el dominio exacto para eliminar: " DEL_DOM
                if [ -f "$ZONAS_DNS/db.$DEL_DOM" ]; then
                    rm -f "$ZONAS_DNS/db.$DEL_DOM"
                    reconstruir_named_conf
                    echo -e "\e[1;32mEl dominio especificado ha sido revocado.\e[0m"
                else
                    echo -e "\e[1;31mNo existe la zona actualmente.\e[0m"
                fi
                pausa_tecla
                ;;
            4)
                echo "---- ZONAS REGISTRADAS EN SERVIDOR ----"
                if ls "$ZONAS_DNS"/db.* 1> /dev/null 2>&1; then
                    ls "$ZONAS_DNS" | grep "^db\." | sed 's/db\.//'
                else
                    echo "No existen dominios."
                fi
                echo "---------------------------------------"
                pausa_tecla
                ;;
            5)
                break
                ;;
            *)
                echo "Comando erroneamente dado. Intente de nuevo."
                sleep 1
                ;;
        esac
    done
}
