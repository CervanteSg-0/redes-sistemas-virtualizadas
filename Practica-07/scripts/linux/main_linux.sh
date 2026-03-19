#!/bin/bash

# ==============================================================================
# SCRIPT DE APROVISIONAMIENTO WEB - LINUX (Ubuntu/Debian)
# Practica 7 - FTP + SSL/TLS + Hash
# ==============================================================================

# Variables Globales
DOMAIN="www.reprobados.com"
CERT_DIR="/etc/ssl/certs"
KEY_DIR="/etc/ssl/private"
CERT_FILE="$CERT_DIR/reprobados.crt"
KEY_FILE="$KEY_DIR/reprobados.key"
FTP_SERVER="ftp://127.0.0.1" # Cambiar por la IP real si es necesario
FTP_USER="anonymous"
LOCAL_REPO="/tmp/practica07_repo"

mkdir -p $LOCAL_REPO

# ============================================================
# FUNCIONES DE SEGURIDAD (SSL/TLS)
# ============================================================

generate_cert() {
    echo "[*] Verificando Certificado para $DOMAIN..."
    if [ ! -f "$CERT_FILE" ]; then
        echo "[+] Generando Certificado Autofirmado con OpenSSL..."
        sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$KEY_FILE" -out "$CERT_FILE" \
            -subj "/C=MX/ST=CDMX/L=Mexico/O=Reprobados/CN=$DOMAIN"
        echo "[+] Certificado generado en $CERT_FILE"
    else
        echo "[+] Certificado existente encontrado."
    fi
}

configure_ssl_apache() {
    echo "[*] Configurando SSL en Apache..."
    generate_cert
    sudo a2enmod ssl
    sudo a2enmod rewrite
    
    # Crear VirtualHost 443
    CONFIG_FILE="/etc/apache2/sites-available/000-default-ssl.conf"
    sudo bash -c "cat > $CONFIG_FILE" <<EOF
<VirtualHost *:443>
    ServerName $DOMAIN
    DocumentRoot /var/www/html
    SSLEngine on
    SSLCertificateFile $CERT_FILE
    SSLCertificateKeyFile $KEY_FILE
    
    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
    
    # Redireccion HTTP -> HTTPS
    sudo bash -c "cat > /etc/apache2/sites-available/000-default.conf" <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    Redirect permanent / https://$DOMAIN/
</VirtualHost>
EOF

    sudo a2ensite 000-default-ssl
    sudo systemctl restart apache2
    echo "[+] SSL y Redireccion configurados en Apache."
}

configure_ssl_nginx() {
    echo "[*] Configurando SSL en Nginx..."
    generate_cert
    
    CONFIG_FILE="/etc/nginx/sites-available/default"
    sudo bash -c "cat > $CONFIG_FILE" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate $CERT_FILE;
    ssl_certificate_key $KEY_FILE;

    location / {
        root /var/www/html;
        index index.html index.htm;
    }
}
EOF
    sudo systemctl restart nginx
    echo "[+] SSL y Redireccion configurados en Nginx."
}

configure_ftps_vsftpd() {
    echo "[*] Configurando FTPS en vsftpd..."
    generate_cert
    
    CONFIG="/etc/vsftpd.conf"
    sudo sed -i 's/ssl_enable=NO/ssl_enable=YES/' $CONFIG
    echo "rsa_cert_file=$CERT_FILE" | sudo tee -a $CONFIG
    echo "rsa_private_key_file=$KEY_FILE" | sudo tee -a $CONFIG
    echo "allow_anon_ssl=YES" | sudo tee -a $CONFIG
    echo "force_local_data_ssl=YES" | sudo tee -a $CONFIG
    echo "force_local_logins_ssl=YES" | sudo tee -a $CONFIG
    echo "ssl_tlsv1=YES" | sudo tee -a $CONFIG
    echo "ssl_sslv2=NO" | sudo tee -a $CONFIG
    echo "ssl_sslv3=NO" | sudo tee -a $CONFIG
    
    sudo systemctl restart vsftpd
    echo "[+] FTPS activado exitosamente."
}

# ============================================================
# FUNCIONES DE REPOSITORIO FTP DINAMICO
# ============================================================

ftp_browser() {
    local os="Linux"
    local service=$1
    local remote_path="$FTP_SERVER/http/$os/$service/"
    
    echo "[*] Conectando a Repositorio FTP: $remote_path"
    files=$(curl -s -l "$remote_path")
    
    if [ -z "$files" ]; then
        echo "[-] No se encontraron archivos remotos."
        return 1
    fi

    echo -e "\nArchivos disponibles en $service:"
    options=($files)
    for i in "${!options[@]}"; do
        echo "[$i] ${options[$i]}"
    done
    
    read -p "Seleccione el numero del instalador: " choice
    if [[ $choice -lt 0 || $choice -ge ${#options[@]} ]]; then
        echo "[-] Seleccion invalida."
        return 1
    fi
    
    echo "${options[$choice]}"
}

download_and_verify() {
    local service=$1
    local filename=$2
    local remote_url="$FTP_SERVER/http/Linux/$service/$filename"
    local local_file="$LOCAL_REPO/$filename"
    local hash_url="$remote_url.sha256"
    local local_hash="$local_file.sha256"
    
    echo "[*] Descargando $filename..."
    curl -s -o "$local_file" "$remote_url"
    
    echo "[*] Descargando Hash (.sha256)..."
    curl -s -o "$local_hash" "$hash_url"
    
    if [ -f "$local_hash" ]; then
        echo "[*] Verificando integridad..."
        # El archivo .sha256 suele tener el formato: [HASH] [FILENAME]
        cd $LOCAL_REPO && sha256sum -c "$filename.sha256"
        if [ $? -eq 0 ]; then
            echo "[+] Integridad VERIFICADA."
            echo "$local_file"
        else
            echo "[-] ERROR: Hash mismatch!"
            return 1
        fi
    else
        echo "[!] No hay hash. Instalando sin validacion."
        echo "$local_file"
    fi
}

# ============================================================
# ORQUESTADOR DE INSTALACION
# ============================================================

install_orchestrator() {
    local service=$1
    echo -e "\n--- Instalacion de $service ---"
    echo "[1] WEB (apt)"
    echo "[2] FTP (Repositorio Privado)"
    read -p "Seleccione origen: " source
    
    if [ "$source" == "2" ]; then
        file=$(ftp_browser "$service")
        if [ $? -eq 0 ]; then
            bin_path=$(download_and_verify "$service" "$file")
            if [ -n "$bin_path" ]; then
                echo "[*] Instalando paquete local..."
                sudo dpkg -i "$bin_path" 2>/dev/null || sudo apt-get install -f -y
                echo "[+] $service instalado desde FTP."
            fi
        fi
    else
        echo "[*] Instalando via WEB (apt)..."
        sudo apt update && sudo apt install -y ${service,,}
        echo "[+] $service instalado via WEB."
    fi
    
    read -p "¿Desea activar SSL en este servicio? [S/N]: " activate_ssl
    if [[ $activate_ssl =~ ^[Ss]$ ]]; then
        case ${service,,} in
            apache*) configure_ssl_apache ;;
            nginx*) configure_ssl_nginx ;;
            *) echo "[!] Configuracion SSL manual requerida." ;;
        esac
    fi
}

# ============================================================
# MENU PRINCIPAL
# ============================================================

while true; do
    clear
    echo " +==========================================================+"
    echo " |   SISTEMA DE APROVISIONAMIENTO WEB - LINUX (UBUNTU)      |"
    echo " |        Practica 7 - FTP + SSL/TLS + Hash                 |"
    echo " +==========================================================+"
    echo ""
    echo " [1] Instalar Apache  (WEB o FTP + SSL opcional)"
    echo " [2] Instalar Nginx   (WEB o FTP + SSL opcional)"
    echo " [3] Instalar Tomcat  (WEB o FTP + SSL opcional)"
    echo " [4] Configurar FTPS  (SSL en vsftpd)"
    echo " [5] Ver estado de servicios"
    echo " [6] Salir"
    echo ""
    read -p "Opcion: " opt
    
    case $opt in
        1) install_orchestrator "Apache2" ;;
        2) install_orchestrator "Nginx" ;;
        3) install_orchestrator "Tomcat9" ;;
        4) configure_ftps_vsftpd ;;
        5) systemctl status apache2 nginx vsftpd | grep -E "Active:|Loaded:" ;;
        6) exit 0 ;;
        *) echo "Opcion no valida."; sleep 1 ;;
    esac
    echo ""
    read -p "Presione Enter para continuar..." dummy
done
