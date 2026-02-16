#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

show_ip_status() {
  echo "== IP / Rutas =="
  ip -br addr || true
  echo ""
  ip route || true
}

detect_dhcp_like() {
  # heuristica: si NM existe y ipv4.method=auto => DHCP
  if have_cmd nmcli; then
    local con method
    con="$(nmcli -t -f NAME,DEVICE con show --active | head -n1 | cut -d: -f1 || true)"
    if [[ -n "$con" ]]; then
      method="$(nmcli -t -f ipv4.method con show "$con" | cut -d: -f2 || true)"
      [[ "$method" == "auto" ]] && return 0
      return 1
    fi
  fi
  pgrep -x dhclient >/dev/null 2>&1 && return 0
  return 1
}

configure_static_ip() {
  echo "== Configurar IP fija (Mageia) =="
  show_ip_status

  if detect_dhcp_like; then
    echo "[WARN] Detecte metodo DHCP/auto. Se recomienda IP fija para DNS."
  else
    echo "[OK] No detecte DHCP (probable IP fija)."
    if ! prompt_yesno "Reconfigurar de todos modos?" "n"; then
      return 0
    fi
  fi

  echo ""
  echo "Interfaces:"
  ip -o link show | awk -F': ' '{print " - " $2}'
  local iface ipaddr prefix gw dns1 con

  while true; do
    read -r -p "Interfaz (ej: enp0s8/ens33): " iface
    iface="$(trim "${iface:-}")"
    [[ -n "$iface" ]] && ip link show "$iface" >/dev/null 2>&1 && break
    echo "  Interfaz invalida."
  done

  ipaddr="$(prompt_ip "IP fija del servidor DNS (Mageia)")"

  while true; do
    read -r -p "Prefijo CIDR (ej: 24): " prefix
    prefix="$(trim "${prefix:-}")"
    valid_prefix "$prefix" && break
    echo "  Prefijo invalido (1-32)."
  done

  read -r -p "Gateway (opcional, ENTER omitir): " gw
  gw="$(trim "${gw:-}")"
  [[ -z "$gw" ]] || valid_ipv4 "$gw" || die "Gateway invalido."

  read -r -p "DNS (opcional, ENTER omitir): " dns1
  dns1="$(trim "${dns1:-}")"
  [[ -z "$dns1" ]] || valid_ipv4 "$dns1" || die "DNS invalido."

  have_cmd nmcli || die "No hay nmcli. Configura red manualmente segun tu entorno."

  con="$(nmcli -t -f NAME,DEVICE con show --active | awk -F: -v ifc="$iface" '$2==ifc{print $1; exit}')"
  [[ -n "$con" ]] || die "No pude obtener conexion activa de NetworkManager para $iface."

  echo "[INFO] Aplicando nmcli en conexion: $con"
  nmcli con mod "$con" ipv4.method manual ipv4.addresses "${ipaddr}/${prefix}"
  if [[ -n "$gw" ]]; then nmcli con mod "$con" ipv4.gateway "$gw"; else nmcli con mod "$con" -ipv4.gateway; fi
  if [[ -n "$dns1" ]]; then nmcli con mod "$con" ipv4.dns "$dns1"; else nmcli con mod "$con" -ipv4.dns; fi
  nmcli con up "$con"

  echo "[OK] IP fija aplicada."
  show_ip_status
}
