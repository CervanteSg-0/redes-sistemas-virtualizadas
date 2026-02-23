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
  ok "BIND instalado y servicio habilitado."
}