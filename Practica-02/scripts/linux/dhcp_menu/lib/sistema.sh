#!/usr/bin/env bash
set -u

error(){ echo "[ERROR] $*" >&2; exit 1; }

asegurar_root() {
  [[ ${EUID:-999} -eq 0 ]] || error "Ejecuta como root: sudo ./main.sh"
}

instalar_paquete_dhcpd() {
  if rpm -q dhcp-server >/dev/null 2>&1; then
    echo "dhcp-server ya esta instalado."
    return 0
  fi

  echo "Instalando dhcp-server (Mageia)..."
  if command -v dnf >/dev/null 2>&1; then
    dnf -y install dhcp-server || error "Fallo dnf install dhcp-server"
  elif command -v urpmi >/dev/null 2>&1; then
    urpmi --auto dhcp-server || error "Fallo urpmi dhcp-server"
  else
    error "No encontre dnf ni urpmi."
  fi
}

