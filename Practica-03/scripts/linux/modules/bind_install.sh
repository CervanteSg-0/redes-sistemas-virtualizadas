#!/usr/bin/env bash
set -euo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MOD_DIR/common.sh"

# Verifica si BIND está instalado
is_bind_installed() {
  rpm -q bind >/dev/null 2>&1 || rpm -q bind9 >/dev/null 2>&1
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

  if have_cmd dnf; then
    info "Usando dnf..."
    dnf -y install bind bind-utils bind-doc || dnf -y install bind9 bind9utils bind9-doc
  elif have_cmd zypper; then
    info "Usando zypper..."
    zypper install -y bind bind-utils bind-doc || zypper install -y bind9 bind9utils bind9-doc
  else
    die "No encontré dnf ni zypper. No puedo instalar BIND."
  fi

  systemctl enable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
  ok "BIND instalado y servicio habilitado."
}