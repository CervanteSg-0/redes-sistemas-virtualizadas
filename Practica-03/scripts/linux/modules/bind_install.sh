#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

SERVICE_NAME="named"

is_bind_installed() {
  rpm -q bind >/dev/null 2>&1 || rpm -q bind9 >/dev/null 2>&1
}

install_bind_idempotent() {
  echo "== Instalar BIND (idempotente) =="
  if is_bind_installed; then
    echo "[OK] BIND ya instalado."
    return 0
  fi

  if have_cmd dnf; then
    dnf -y install bind bind-utils bind-doc || dnf -y install bind9 bind9utils bind9-doc
  elif have_cmd urpmi; then
    urpmi --auto bind bind-utils bind-doc || urpmi --auto bind9 bind9utils bind9-doc
  else
    die "No encontre dnf/urpmi."
  fi

  systemctl enable --now "$SERVICE_NAME" || true
  echo "[OK] BIND instalado y servicio habilitado."
}

service_status() {
  systemctl --no-pager -l status "$SERVICE_NAME" || true
}

service_restart() {
  systemctl enable --now "$SERVICE_NAME" || true
  systemctl restart "$SERVICE_NAME"
}
