#!/usr/bin/env bash
set -euo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MOD_DIR/common.sh"

# Verifica si BIND está instalado
is_bind_installed() {
  # Verifica por paquete o por existencia del binario directamente
  rpm -q bind >/dev/null 2>&1 || \
  rpm -q bind9 >/dev/null 2>&1 || \
  command -v named >/dev/null 2>&1
}

# Comprobamos el gestor de paquetes
have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# Instalar BIND si no está instalado
install_bind_idempotent() {
  echo "== Instalando BIND (idempotente) =="

  if is_bind_installed; then
    ok "BIND ya instalado."
    configure_bind_global
    return 0
  fi

  # Verificación rápida de conectividad
  if ! ping -c 1 -W 2 google.com >/dev/null 2>&1; then
    warn "Parece que no tienes conexión a internet (ping falló)."
    warn "Si acabas de poner una IP estática, asegúrate de tener una Puerta de Enlace (Gateway) válida."
    echo ""
  fi

  if have_cmd dnf; then
    info "Usando dnf..."
    # Intentamos instalar los esenciales primero
    if ! dnf -y install bind bind-utils; then
       if ! dnf -y install bind9 bind9utils; then
          error "No se pudieron instalar los paquetes base de BIND."
          echo -e "\e[33m[TIP] El error 'Curl error (7)' indica FALTA DE INTERNET en la VM.\e[0m"
          echo -e "\e[33m[TIP] Ejecuta 'sudo dhclient ens34' temporalmente para recuperar internet e instalar.\e[0m"
          exit 1
       fi
    fi
    # Intentamos instalar la documentación como opcional
    dnf -y install bind-doc >/dev/null 2>&1 || dnf -y install bind9-doc >/dev/null 2>&1 || warn "No se pudo instalar la documentación opcional."
  elif have_cmd zypper; then
    info "Usando zypper..."
    zypper install -y bind bind-utils || die "No se pudieron instalar los paquetes base de BIND con zypper."
    zypper install -y bind-doc >/dev/null 2>&1 || warn "No se pudo instalar la documentación opcional."
  else
    die "No encontré dnf ni zypper. No puedo instalar BIND."
  fi

  systemctl enable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
  configure_bind_global
  ok "BIND instalado y servicio habilitado."
}

# Configura BIND para permitir consultas externas
configure_bind_global() {
  info "Configurando BIND para permitir consultas externas (LAB MODE)..."
  
  [[ -f "$NAMED_CONF" ]] || return 1
  
  # Backup de seguridad
  cp "$NAMED_CONF" "${NAMED_CONF}.bak" || true

  # 1. Escuchar en todas las interfaces (quitar restricción de 127.0.0.1)
  # Usamos una expresión más libre por si hay espacios extra
  sed -i 's/listen-on port 53 {[^;]*;};/listen-on port 53 { any; };/g' "$NAMED_CONF"
  
  # 2. Escuchar en IPv6 (any)
  sed -i 's/listen-on-v6 port 53 {[^;]*;};/listen-on-v6 port 53 { any; };/g' "$NAMED_CONF"
  
  # 3. Permitir consultas desde cualquier IP
  sed -i 's/allow-query\s*{[^;]*;};/allow-query { any; };/g' "$NAMED_CONF"

  # 4. Ajustes adicionales para laboratorios (DNSSEC)
  # A veces DNSSEC impide que zonas locales funcionen si no están firmadas
  if grep -q "dnssec-validation" "$NAMED_CONF"; then
      sed -i 's/dnssec-validation yes;/dnssec-validation no;/g' "$NAMED_CONF"
      info "Validacion DNSSEC desactivada para compatibilidad local."
  fi
  
  # Intentar abrir firewall si existe firewall-cmd
  if have_cmd firewall-cmd; then
     info "Abriendo puerto 53 en el firewall..."
     firewall-cmd --add-service=dns --permanent >/dev/null 2>&1 || true
     firewall-cmd --reload >/dev/null 2>&1 || true
  fi

  service_restart
}