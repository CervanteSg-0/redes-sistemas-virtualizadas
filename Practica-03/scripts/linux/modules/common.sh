#!/usr/bin/env bash
set -euo pipefail

die(){ echo "[ERROR] $*" >&2; exit 1; }
pause(){ read -r -p "ENTER para continuar..." _; }

need_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
  fi
}

have_cmd(){ command -v "$1" >/dev/null 2>&1; }

trim(){ echo "$1" | xargs; }

valid_ipv4() {
  local ip="${1:-}"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r a b c d <<<"$ip"
  for o in "$a" "$b" "$c" "$d"; do
    [[ "$o" =~ ^[0-9]+$ ]] || return 1
    (( o >= 0 && o <= 255 )) || return 1
  done
  [[ "$ip" != "0.0.0.0" && "$ip" != "255.255.255.255" ]] || return 1
  return 0
}

valid_prefix() {
  local p="${1:-}"
  [[ "$p" =~ ^[0-9]{1,2}$ ]] || return 1
  (( p >= 1 && p <= 32 )) || return 1
  return 0
}

prompt_ip() {
  local label="$1" v
  while true; do
    read -r -p "$label: " v
    v="$(trim "${v:-}")"
    valid_ipv4 "$v" && { echo "$v"; return 0; }
    echo "  IP invalida. Ej: 192.168.100.10"
  done
}

prompt_yesno() {
  local label="$1" default="${2:-y}" r
  while true; do
    if [[ "$default" == "y" ]]; then
      read -r -p "$label [S/n]: " r
      r="${r:-S}"
    else
      read -r -p "$label [s/N]: " r
      r="${r:-N}"
    fi
    r="$(echo "$r" | tr '[:upper:]' '[:lower:]' | xargs)"
    case "$r" in
      s|si|y|yes) return 0 ;;
      n|no) return 1 ;;
      *) echo "  Responde S o N." ;;
    esac
  done
}
