#!/bin/bash
# p8_join_ad_linux.sh
# Script para unir cliente Linux al dominio Active Directory (Practica 08)

# Colores para salida visual
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

fn_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
fn_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
fn_err() { echo -e "${RED}[ERROR]${NC} $1"; }

# Verificacion de permisos
if [[ $EUID -ne 0 ]]; then
   fn_err "Este script debe ejecutarse como root (sudo)."
   exit 1
fi

fn_install_deps() {
    fn_info "Actualizando e Instalando dependencias (realmd, sssd, adcli)..."
    # Detectar distro (Debian/Ubuntu por defecto para la demo)
    if [ -f /etc/debian_version ]; then
        apt update && apt install -y realmd sssd sssd-tools adcli samba-common-bin packagekit policykit-1
    elif [ -f /etc/redhat-release ]; then
        yum install -y realmd sssd adcli samba-common-tools
    else
        fn_err "Distribucion no soportada automaticamente. Instala realmd y sssd manualmente."
    fi
    fn_ok "Dependencias instaladas."
}

fn_join_domain() {
    read -p "Ingresa el nombre del dominio (ej: redes.local): " DOMAIN
    read -p "Ingresa el usuario administrador de AD (ej: Administrator): " ADMIN_USER
    
    fn_info "Descubriendo dominio $DOMAIN..."
    realm discover $DOMAIN
    
    fn_info "Uniendose al dominio $DOMAIN..."
    realm join $DOMAIN -U $ADMIN_USER --install=/
    
    if [ $? -eq 0 ]; then
        fn_ok "Union al dominio exitosa."
    else
        fn_err "Fallo la union al dominio."
        exit 1
    fi
}

fn_config_sssd() {
    fn_info "Configurando /etc/sssd/sssd.conf..."
    # Configurar fallback_homedir y use_fully_qualified_names
    SSSD_CONF="/etc/sssd/sssd.conf"
    
    if [ -f $SSSD_CONF ]; then
        # Cambiar fallback_homedir a /home/%u@%d
        sed -i 's|fallback_homedir = .*$|fallback_homedir = /home/%u@%d|' $SSSD_CONF
        # Opcional: permitir nombres cortos de usuario
        sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/' $SSSD_CONF
        
        systemctl restart sssd
        fn_ok "SSSD configurado y reiniciado."
    else
        fn_err "No se encontro $SSSD_CONF."
    fi
}

fn_config_sudo() {
    fn_info "Permitiendo privilegios SUDO a usuarios de AD..."
    SUDO_FILE="/etc/sudoers.d/ad-admins"
    echo "%domain\ admins ALL=(ALL) ALL" > $SUDO_FILE
    # Tambien permitimos a los grupos especificos de la practica
    echo "%G_Cuates ALL=(ALL) ALL" >> $SUDO_FILE
    echo "%G_NoCuates ALL=(ALL) ALL" >> $SUDO_FILE
    
    chmod 0440 $SUDO_FILE
    fn_ok "Sudoers configurado en $SUDO_FILE."
}

# Ejecucion del script
fn_install_deps
fn_join_domain
fn_config_sssd
fn_config_sudo

fn_ok "Configuracion completa. Prueba logueandote con: su - usuario@dominio"
