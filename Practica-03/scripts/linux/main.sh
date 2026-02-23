#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$BASE_DIR/modules/common.sh"
source "$BASE_DIR/modules/bind_install.sh"
source "$BASE_DIR/modules/bind_zone.sh"
source "$BASE_DIR/modules/bind_status.sh"
source "$BASE_DIR/modules/bind_remove.sh"

check_root


while true; do
  clear || true
  echo "===== DNS CONFIGURACION    ========="
  echo "1) Instalar DNS"
  echo "2) Configurar DNS y Dominio"
  echo "3) Verificar estado del servicio DNS"
  echo "4) Eliminar dominio de la red"
  
  echo "0) Salir"
  echo "======================================="
  
  read -r -p "Opcion: " option
  case "$option" in
    1) install_bind_idempotent; pause ;;
    2) configure_zone_flow; pause ;;
    3) service_status; pause ;;
    4) remove_zone_flow; pause ;;
    0) exit 0 ;;
    *) echo "Opcion invalida"; pause ;;
  esac
done