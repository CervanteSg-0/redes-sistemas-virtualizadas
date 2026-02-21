#!/usr/bin/env bash
set -euo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MOD_DIR/common.sh"
source "$MOD_DIR/bind_install.sh"
source "$MOD_DIR/bind_zone.sh"

remove_zone_files() {
  local domain="$1"
  local zone_dir zone_file
  zone_dir="$(pick_zone_dir)"
  zone_file="${zone_dir}/db.${domain}"

  if [[ -f "$zone_file" ]]; then
    rm -f "$zone_file"
    ok "Eliminado archivo de zona: $zone_file"
  else
    info "No existe archivo de zona: $zone_file (ok)"
  fi
}

remove_zone_flow() {
  echo "== Eliminar Zona DNS (Linux/Mageia) =="

  local domain
  read -r -p "Nombre de zona a eliminar : " domain
  domain="$(trim "$domain" | tr '[:upper:]' '[:lower:]')"
  valid_fqdn_zone "$domain" || die "Nombre de zona invalido."

  # Confirmación fuerte
  echo ""
  echo "Se eliminará la zona '$domain' del servidor BIND:"
  echo " - Se removerá el bloque en: $NAMED_LOCAL"
  echo " - Se intentará borrar el archivo db.${domain}"
  echo ""
  prompt_yesno "¿Confirmas eliminar '$domain'?" "n" || { info "Cancelado."; return 0; }

  install_bind_idempotent
  ensure_named_local_included

  # Quitar bloque de zona
  remove_zone_block_named_local "$domain"
  ok "Bloque de zona removido de $NAMED_LOCAL"

  # Borrar archivo de zona
  remove_zone_files "$domain"

  # Validar y reiniciar
  info "Validando configuracion..."
  named-checkconf || die "named-checkconf FALLO despues de borrar. Revisa $NAMED_LOCAL"

  info "Reiniciando servicio..."
  service_restart
  service_status

  ok "Zona eliminada: $domain"
}