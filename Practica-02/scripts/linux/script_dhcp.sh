#!/usr/bin/env bash
set -u

SEG_NET="192.168.100.0"
SEG_MASK="255.255.255.0"

CONF="/etc/dhcpd.conf"
LEASES_PRIMARY="/var/lib/dhcpd/dhcpd.leases"
LEASES_FALLBACK="/var/lib/dhcp/dhcpd.leases"

die(){ echo "[ERROR] $*" >&2; exit 1; }
pause(){ read -r -p "Enter para continuar..." _; }

ip_to_int() {
  local ip="$1" a b c d
  IFS=. read -r a b c d <<<"$ip" || return 1
  echo $(( (a<<24) + (b<<16) + (c<<8) + d ))
}

is_ipv4() {
  local ip="$1" a b c d
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r a b c d <<<"$ip" || return 1
  for o in "$a" "$b" "$c" "$d"; do
    [[ "$o" =~ ^[0-9]+$ ]] || return 1
    (( o>=0 && o<=255 )) || return 1
  done
  [[ "$ip" != "0.0.0.0" && "$ip" != "255.255.255.255" ]] || return 1
  return 0
}

mask_is_valid() {
  local m="$1"
  is_ipv4 "$m" || return 1
  local mi inv
  mi=$(ip_to_int "$m") || return 1
  (( mi != 0 && mi != 4294967295 )) || return 1
  inv=$(( (4294967295 ^ mi) ))
  # inv debe ser 000..0111..1 => inv & (inv+1) == 0
  (( (inv & (inv + 1)) == 0 )) || return 1
  return 0
}

same_subnet() {
  local ip1="$1" ip2="$2" mask="$3"
  local i1 i2 m
  i1=$(ip_to_int "$ip1") || return 1
  i2=$(ip_to_int "$ip2") || return 1
  m=$(ip_to_int "$mask") || return 1
  (( (i1 & m) == (i2 & m) ))
}

read_ipv4() {
  local prompt="$1" def="${2:-}" v
  while true; do
    if [[ -n "$def" ]]; then
      read -r -p "$prompt [$def]: " v
      v="${v:-$def}"
    else
      read -r -p "$prompt: " v
    fi
    if is_ipv4 "$v"; then echo "$v"; return 0; fi
    echo "IP inválida. Ejemplo valido: 192.168.100.10 (no 1000, no 0.0.0.0)."
  done
}

read_ipv4_optional() {
  local prompt="$1" def="${2:-}" v
  while true; do
    if [[ -n "$def" ]]; then
      read -r -p "$prompt [$def] (ENTER=usar, -=omitir): " v
      [[ -z "$v" ]] && v="$def"
      [[ "$v" == "-" ]] && echo "" && return 0
    else
      read -r -p "$prompt (ENTER o -=omitir): " v
      [[ -z "$v" || "$v" == "-" ]] && echo "" && return 0
    fi

    if is_ipv4 "$v"; then echo "$v"; return 0; fi
    echo "IP inválida. Ejemplo: 192.168.100.1"
  done
}


read_mask() {
  local prompt="$1" def="${2:-}"
  local v
  while true; do
    read -r -p "$prompt [$def]: " v
    v="${v:-$def}"
    if mask_is_valid "$v"; then echo "$v"; return 0; fi
    echo "Máscara inválida. Ejemplo: 255.255.255.0"
  done
}

pick_leases_file() {
  [[ -f "$LEASES_PRIMARY" ]] && echo "$LEASES_PRIMARY" && return
  [[ -f "$LEASES_FALLBACK" ]] && echo "$LEASES_FALLBACK" && return
  echo "$LEASES_PRIMARY"
}

ensure_root() {
  [[ ${EUID:-999} -eq 0 ]] || die "Ejecuta como root: sudo bash main.sh"
}

pkg_install() {
  if rpm -q dhcp-server >/dev/null 2>&1; then
    echo "dhcp-server ya esta instalado."
    return 0
  fi

  echo "Instalando dhcp-server (Mageia)..."
  if command -v dnf >/dev/null 2>&1; then
    dnf -y install dhcp-server || die "Falló dnf install dhcp-server"
  elif command -v urpmi >/dev/null 2>&1; then
    urpmi --auto dhcp-server || die "Falló urpmi dhcp-server"
  else
    die "No encontre dnf ni urpmi. Instala dhcp-server manualmente."
  fi
}

svc_restart() {
  systemctl enable --now dhcpd >/dev/null 2>&1 || true
  systemctl restart dhcpd || die "No pude reiniciar dhcpd. Revisa: journalctl -u dhcpd -n 50 --no-pager"
}

svc_status() {
  echo "== Servicio dhcpd =="
  systemctl --no-pager -l status dhcpd || true
  echo
  echo "== Últimos logs (dhcpd) =="
  journalctl -u dhcpd -n 40 --no-pager || true
}

leases_active() {
  local lf
  lf="$(pick_leases_file)"
  [[ -f "$lf" ]] || { echo "No existe lease file aun: $lf"; return 0; }

  echo "== Leases activas ($lf) =="
  awk '
    $1=="lease" {ip=$2; inlease=1; state=""; mac=""; host=""; next}
    inlease && $1=="binding" && $2=="state" {state=$3}
    inlease && $1=="hardware" && $2=="ethernet" {mac=$3; gsub(";","",mac)}
    inlease && $1=="client-hostname" {host=$2; gsub(/[";]/,"",host)}
    inlease && $1=="}" {
      if (state=="active") {
        printf "%-15s  %-17s  %s\n", ip, mac, host
      }
      inlease=0
    }
  ' "$lf" | sort -V
}

configure_dhcp() {
  local scopeName start end mask gw dns iface leaseDays leaseSec segNet
  scopeName=""
  read -r -p "Nombre descriptivo del ambito [Scope-Sistemas]: " scopeName
  scopeName="${scopeName:-Scope-Sistemas}"

  start=$(read_ipv4 "Rango inicial" "192.168.100.50")
  end=$(read_ipv4 "Rango final" "192.168.100.150")
  mask=$(read_mask "Mascara (debe ser /24 para esta práctica)" "$SEG_MASK")

  # Validación: start/end dentro del segmento 192.168.100.0/24 y orden correcto
  segNet="$SEG_NET"
  if ! same_subnet "$start" "$segNet" "$mask"; then
    die "El rango inicial $start NO pertenece a $segNet/$mask"
  fi
  if ! same_subnet "$end" "$segNet" "$mask"; then
    die "El rango final $end NO pertenece a $segNet/$mask"
  fi

  local si ei
  si=$(ip_to_int "$start"); ei=$(ip_to_int "$end")
  (( si <= ei )) || die "El rango inicial debe ser <= rango final"

  gw=$(read_ipv4 "Gateway (Router) en la misma subred" "192.168.100.1")
  same_subnet "$gw" "$segNet" "$mask" || die "Gateway $gw NO pertenece a $segNet/$mask"

  dns=$(read_ipv4 "DNS (IPv4)" "192.168.100.20")

  read -r -p "Lease Time en dias [8]: " leaseDays
  leaseDays="${leaseDays:-8}"
  [[ "$leaseDays" =~ ^[0-9]+$ ]] || die "Lease days debe ser numero entero."
  leaseSec=$(( leaseDays * 86400 ))

  echo "Interfaces disponibles:"
  ip -o link show | awk -F': ' '{print " - " $2}' | sed 's/@.*//' | grep -v '^ - lo$' || true
  read -r -p "Interfaz donde escuchara DHCP (la de la red interna) [eth0]: " iface
  iface="${iface:-eth0}"

  # Backup
  if [[ -f "$CONF" ]]; then
    cp -a "$CONF" "${CONF}.bak.$(date +%F_%H%M%S)" || true
  fi

  cat >"$CONF" <<EOF
authoritative;
ddns-update-style none;

default-lease-time ${leaseSec};
max-lease-time ${leaseSec};

option subnet-mask ${mask};
option broadcast-address 192.168.100.255;
option routers ${gw};
option domain-name-servers ${dns};

subnet 192.168.100.0 netmask ${mask} {
  range ${start} ${end};
}
EOF

  # Lease file
  local lf
  lf="$(pick_leases_file)"
  mkdir -p "$(dirname "$lf")" || true
  touch "$lf" || true

  # Intento de limitar interfaz (comun en distros tipo RHEL/Mageia)
  mkdir -p /etc/sysconfig || true
  cat >/etc/sysconfig/dhcpd <<EOF
DHCPD_INTERFACE="${iface}"
DHCPDARGS="${iface}"
EOF

  echo "Validando sintaxis..."
  dhcpd -t -cf "$CONF" || die "Error en la configuracion. Corrige $CONF"

  # Firewall si existe firewalld
  if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-service=dhcp >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
  fi

  echo "Reiniciando dhcpd..."
  svc_restart

  echo "Listo. Config aplicada en $CONF"
}

menu() {
  while true; do
    echo
    echo "===== DHCP (Mageia / ISC dhcpd) ====="
    echo "1) Verificar/Instalar dhcp-server (idempotente)"
    echo "2) Configurar DHCP (interactivo + validaciones)"
    echo "3) Monitoreo: estado + leases activas"
    echo "4) Reiniciar servicio dhcpd"
    echo "5) Salir"
    read -r -p "Opcion: " op

    case "$op" in
      1) ensure_root; pkg_install; pause ;;
      2) ensure_root; pkg_install; configure_dhcp; pause ;;
      3) svc_status; leases_active; pause ;;
      4) ensure_root; svc_restart; echo "Reiniciado."; pause ;;
      5) exit 0 ;;
      *) echo "Opcion invalida." ;;
    esac
  done
}

menu
