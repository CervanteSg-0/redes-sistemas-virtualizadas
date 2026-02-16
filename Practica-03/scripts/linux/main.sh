#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$BASE_DIR/modules/common.sh"
source "$BASE_DIR/modules/net_static.sh"
source "$BASE_DIR/modules/bind_install.sh"
source "$BASE_DIR/modules/bind_zone.sh"
source "$BASE_DIR/modules/bind_validate.sh"

need_root "$@"

while true; do
  clear || true
  echo "===== DNS Linux (Mageia) - BIND/named ====="
  echo "1) Verificar/Instalar BIND"
  echo "2) Verificar/Configurar IP fija"
  echo "3) Configurar zona + registros"
  echo "4) Validar sintaxis"
  echo "5) Estado servicio"
  echo "0) Salir"
  echo "=========================================="
  read -r -p "Opcion: " op
  case "${op:-}" in
    1) install_bind_idempotent; pause;;
    2) configure_static_ip; pause;;
    3) configure_zone_flow; pause;;
    4) validate_named; pause;;
    5) service_status; pause;;
    0) exit 0;;
    *) echo "Opcion invalida"; pause;;
  esac
done
