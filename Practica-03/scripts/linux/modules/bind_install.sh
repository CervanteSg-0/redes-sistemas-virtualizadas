#!/usr/bin/env bash
set -euo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MOD_DIR/common.sh"

SERVICE_NAME="named"

# Verifica si BIND está instalado
is_bind_installed() {
  rpm -q bind >/dev/null 2>&1 || rpm -q bind9 >/dev/null 2>&1
}

# Instalar BIND si no está instalado
install_bind_idempotent() {
  echo "== Instalar BIND (idempotente) =="
  if is_bind_installed; then
    ok "BIND ya instalado."
    return 0
  fi

  if have_cmd dnf; then
    info "Usando dnf..."
    dnf -y install bind bind-utils bind-doc || dnf -y install bind9 bind9utils bind9-doc
  elif have_cmd urpmi; then
    info "Usando urpmi..."
    urpmi --auto bind bind-utils bind-doc || urpmi --auto bind9 bind9utils bind9-doc
  else
    die "No encontré dnf/urpmi."
  fi

  systemctl enable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
  ok "BIND instalado y servicio habilitado."
}