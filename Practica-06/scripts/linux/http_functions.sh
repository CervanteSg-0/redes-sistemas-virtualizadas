#!/bin/bash

# ==============================================================================
# Practica-07: http_functions.sh
# Librería de funciones para aprovisionamiento web automatizado en Linux
# ==============================================================================

# Colores para la interfaz
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para validar entrada (evitar caracteres especiales y nulos)
validate_input() {
    local input="$1"
    if [[ -z "$input" || "$input" =~ [^a-zA-Z0-9._-] ]]; then
        return 1
    fi
    return 0
}

# Función para verificar si un puerto está ocupado
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null ; then
        return 1 # Puerto ocupado
    else
        return 0 # Puerto libre
    fi
}

# Función para validar que el puerto no sea reservado
is_reserved_port() {
    local port=$1
    # Lista de puertos reservados y el 444 solicitado para la demostración
    local reserved=(21 22 23 25 53 110 143 443 444 3306 5432)
    for p in "${reserved[@]}"; do
        if [ "$port" -eq "$p" ]; then
            return 0 # Es reservado/bloqueado
        fi
    done
    return 1 # No es reservado
}

# Listar versiones dinámicamente (Adaptado para Mageia/DNF o URPMI)
get_versions() {
    local service=$1
    echo -e "${BLUE}Consultando versiones en repositorios de Mageia para $service...${NC}"
    
    if command -v dnf &> /dev/null; then
        # DNF es el estándar en Mageia moderno
        dnf --showduplicates list "$service" 2>/dev/null | awk '{print $2}' | grep -E '^[0-9]' | head -n 5
    elif command -v urpmq &> /dev/null; then
        # Respaldo para urpmi
        urpmq -m "$service" | head -n 5
    else
        echo -e "${RED}[AVISO] No se detectó dnf ni urpmi. Escriba 'latest'.${NC}"
    fi
}

# Configuración de Seguridad General (Mageia/RedHat Paths)
apply_security_config() {
    local service=$1
    local web_root=$2
    
    echo -e "${BLUE}Aplicando endurecimiento (security hardening) para $service...${NC}"
    
    case $service in
        apache2|httpd)
            local CONF="/etc/httpd/conf/httpd.conf"
            [ ! -f "$CONF" ] && CONF="/etc/apache2/httpd.conf" # Fallback Mageia
            
            # Ocultar versión y firma
            sed -i "s/^ServerTokens .*/ServerTokens Prod/" "$CONF" 2>/dev/null || echo "ServerTokens Prod" >> "$CONF"
            sed -i "s/^ServerSignature .*/ServerSignature Off/" "$CONF" 2>/dev/null || echo "ServerSignature Off" >> "$CONF"
            echo "TraceEnable Off" >> "$CONF"
            
            systemctl restart httpd
            ;;
        nginx)
            sed -i "s/# server_tokens off;/server_tokens off;/" /etc/nginx/nginx.conf
            systemctl restart nginx
            ;;
    esac
}

# Crear página index.html personalizada
create_custom_index() {
    local service=$1
    local version=$2
    local port=$3
    local path=$4
    
    cat <<EOF > "$path/index.html"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Servidor $service</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f0f2f5; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .card { background: white; padding: 2rem; border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,0.1); text-align: center; }
        h1 { color: #1a73e8; }
        .info { font-size: 1.2rem; margin: 10px 0; color: #5f6368; }
        .badge { background: #e8f0fe; color: #1967d2; padding: 5px 12px; border-radius: 20px; font-weight: bold; }
    </style>
</head>
<body>
    <div class="card">
        <h1>Servidor Provisionado</h1>
        <p class="info">Servidor: <span class="badge">$service</span></p>
        <p class="info">Versión: <span class="badge">$version</span></p>
        <p class="info">Puerto: <span class="badge">$port</span></p>
    </div>
</body>
</html>
EOF
    chown -R www-data:www-data "$path"
}

# Instalación de Apache (Mageia: apache)
install_apache() {
    local version=$1
    local port=$2
    
    echo -e "${BLUE}Instalando Apache en Mageia...${NC}"
    dnf install -y apache 2>/dev/null || urpmi --auto apache
    
    # Cambiar puerto
    sed -i "s/Listen 80/Listen $port/" /etc/httpd/conf/httpd.conf
    
    apply_security_config "httpd" "/var/www/html"
    create_custom_index "Apache/Mageia" "Latest" "$port" "/var/www/html"
    
    # Firewall Mageia (firewalld)
    firewall-cmd --permanent --add-port=$port/tcp 2>/dev/null
    firewall-cmd --reload 2>/dev/null
    
    systemctl enable httpd
    systemctl restart httpd
    echo -e "${GREEN}Apache configurado en el puerto $port.${NC}"
}

# Instalación de Nginx (Mageia)
install_nginx() {
    local version=$1
    local port=$2
    
    echo -e "${BLUE}Instalando Nginx en Mageia...${NC}"
    dnf install -y nginx 2>/dev/null || urpmi --auto nginx
    
    sed -i "s/listen 80;/listen $port;/" /etc/nginx/nginx.conf
    
    apply_security_config "nginx" "/var/www/html"
    create_custom_index "Nginx/Mageia" "Latest" "$port" "/var/www/html"
    
    firewall-cmd --permanent --add-port=$port/tcp 2>/dev/null
    firewall-cmd --reload 2>/dev/null
    
    systemctl enable nginx
    systemctl restart nginx
    echo -e "${GREEN}Nginx configurado en el puerto $port.${NC}"
}

# Instalación y configuración de Tomcat (MANUAL .tar.gz)
install_tomcat() {
    local port=$1
    local version="9.0.86" # Versión manual estable
    
    echo -e "${BLUE}Instalando Tomcat $version manualmente (Binarios)...${NC}"
    
    # 1. Crear usuario dedicado
    if ! id "tomcat" &>/dev/null; then
        useradd -m -U -d /opt/tomcat -s /bin/false tomcat
    fi
    
    # 2. Descargar y extraer
    cd /tmp
    wget -q https://archive.apache.org/dist/tomcat/tomcat-9/v$version/bin/apache-tomcat-$version.tar.gz
    mkdir -p /opt/tomcat
    tar xzvf apache-tomcat-$version.tar.gz -C /opt/tomcat --strip-components=1
    
    # 3. Permisos restringidos (Requerimiento de seguridad)
    chown -R tomcat:tomcat /opt/tomcat
    chmod -R 750 /opt/tomcat/conf
    
    # 4. Configurar puerto en server.xml
    sed -i "s/Connector port=\"8080\"/Connector port=\"$port\"/" /opt/tomcat/conf/server.xml
    
    # 5. Crear index personalizado
    create_custom_index "Tomcat" "$version" "$port" "/opt/tomcat/webapps/ROOT"
    
    # 6. Crear servicio systemd para manejo de variables de entorno
    cat <<EOF > /etc/systemd/system/tomcat.service
[Unit]
Description=Apache Tomcat 9 Web Application Container
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=/usr/lib/jvm/default-java"
Environment="CATALINA_PID=/opt/tomcat/temp/tomcat.pid"
Environment="CATALINA_HOME=/opt/tomcat"
ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable tomcat
    systemctl start tomcat
    
    ufw allow "$port/tcp" &>/dev/null
    echo -e "${GREEN}Tomcat configurado manualmente en el puerto $port.${NC}"
}
