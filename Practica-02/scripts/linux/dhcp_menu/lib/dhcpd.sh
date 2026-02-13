#!/usr/bin/env bash
set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/red.sh"

CONF="/etc/dhcpd.conf"
LEASES_PRIMARY="/var/lib/dhcpd/dhcpd.leases"
LEASES_FALLBACK="/var/lib/dhcp/dhcpd.leases"

error(){ echo "[ERROR] $*" >&2; exit 1; }

archivo_leases() {
  [[ -f "$LEASES_PRIMARY" ]] && echo "$LEASES_PRIMARY" && return
  [[ -f "$LEASES_FALLBACK" ]] && echo "$LEASES_FALLBACK" && return
  echo "$LEASES_PRIMARY"
}

reiniciar_servicio_dhcpd() {
  systemctl enable --now dhcpd >/dev/null 2>&1 || true
  systemctl restart dhcpd || error "No pude reiniciar dhcpd. Revisa: journalctl -xeu dhcpd --no-pager | tail -n 80"
}

estado_servicio_dhcpd() {
  echo "== Servicio dhcpd =="
  systemctl --no-pager -l status dhcpd || true
  echo
  echo "== Ultimos logs (dhcpd) =="
  journalctl -u dhcpd -n 50 --no-pager || true
}

leases_activas() {
  local lf
  lf="$(archivo_leases)"
  [[ -f "$lf" ]] || { echo "No existe lease file aun: $lf"; return 0; }

  echo "== Leases activas ($lf) =="
  awk '
    $1=="lease" {ip=$2; inlease=1; state=""; mac=""; host=""; next}
    inlease && $1=="binding" && $2=="state" {state=$3}
    inlease && $1=="hardware" && $2=="ethernet" {mac=$3; gsub(";","",mac)}
    inlease && $1=="client-hostname" {host=$2; gsub(/[";]/,"",host)}
    inlease && $1=="}" {
      if (state=="active") printf "%-15s  %-17s  %s\n", ip, mac, host
      inlease=0
    }
  ' "$lf" | sort -V
}

mostrar_interfaces() {
  ip -o link show | awk -F': ' '{print $2}' | sed 's/@.*//' | grep -v '^lo$' || true
}

tiene_ipv4_en_interfaz() {
  local iface="$1"
  ip -4 addr show dev "$iface" | grep -q "inet "
}

poner_ip_temporal_si_falta() {
  local iface="$1" ip_tmp="$2" mask="$3"
  local pref
  pref="$(prefijo_desde_mascara "$mask")"
  ip link set "$iface" up >/dev/null 2>&1 || true

  if ! tiene_ipv4_en_interfaz "$iface"; then
    echo "Asignando IP temporal $ip_tmp/$pref a $iface ..."
    ip addr add "$ip_tmp/$pref" dev "$iface" >/dev/null 2>&1 || true
  fi
}

# Mageia: systemd usa $INTERFACES desde /etc/sysconfig/dhcpd
escribir_sysconfig_mageia() {
  local iface="$1" leasefile="$2"
  mkdir -p /etc/sysconfig || true
  cat >/etc/sysconfig/dhcpd <<EOF
INTERFACES="${iface}"
OPTIONS=""
CONFIGFILE="${CONF}"
LEASEFILE="${leasefile}"
EOF
}

# Asegura que dhcpd.conf siempre tenga subnet valido (evita error por conf vacio)
escribir_conf_base() {
  local red="$1" mask="$2"
  if [[ -f "$CONF" ]]; then
    cp -a "$CONF" "${CONF}.bak.$(date +%F_%H%M%S)" >/dev/null 2>&1 || true
  fi
  cat >"$CONF" <<EOF
authoritative;
ddns-update-style none;

default-lease-time 600;
max-lease-time 600;

subnet ${red} netmask ${mask} {
}
EOF
}

# NetworkManager: modifica la conexion que corresponde a ens34 (no deja IP vieja pegada)
aplicar_ip_estatica_nmcli() {
  local iface="$1" ip_srv="$2" mask="$3" gw="$4" dns1="$5" dns2="$6"

  command -v nmcli >/dev/null 2>&1 || return 1

  local con pref dnsline
  con="$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | awk -F: -v d="$iface" '$2==d{print $1; exit}')"
  [[ -z "$con" ]] && con="$(nmcli -t -f NAME,DEVICE con show 2>/dev/null | awk -F: -v d="$iface" '$2==d{print $1; exit}')"
  [[ -z "$con" ]] && return 1

  pref="$(prefijo_desde_mascara "$mask")"

  nmcli con mod "$con" ipv4.method manual
  nmcli con mod "$con" ipv4.addresses "${ip_srv}/${pref}"

  if [[ -n "$gw" ]]; then
    nmcli con mod "$con" ipv4.gateway "$gw"
  else
    nmcli con mod "$con" ipv4.gateway ""
  fi

  dnsline=""
  if [[ -n "$dns1" && -n "$dns2" ]]; then
    dnsline="${dns1} ${dns2}"
  elif [[ -n "$dns1" ]]; then
    dnsline="${dns1}"
  fi
  nmcli con mod "$con" ipv4.dns "$dnsline"

  nmcli con down "$con" >/dev/null 2>&1 || true
  nmcli con up "$con" >/dev/null 2>&1 || true
  return 0
}

# Fallback ifcfg (si nmcli falla)
aplicar_ip_estatica_ifcfg() {
  local iface="$1" ip_srv="$2" mask="$3" gw="$4" dns1="$5" dns2="$6"
  local dir="/etc/sysconfig/network-scripts"
  local file="${dir}/ifcfg-${iface}"
  mkdir -p "$dir" || true
  [[ -f "$file" ]] && cp -a "$file" "${file}.bak.$(date +%F_%H%M%S)" >/dev/null 2>&1 || true

  {
    echo "DEVICE=${iface}"
    echo "ONBOOT=yes"
    echo "BOOTPROTO=static"
    echo "IPADDR=${ip_srv}"
    echo "NETMASK=${mask}"
    [[ -n "$gw" ]] && echo "GATEWAY=${gw}"
    [[ -n "$dns1" ]] && echo "DNS1=${dns1}"
    [[ -n "$dns2" ]] && echo "DNS2=${dns2}"
  } >"$file"

  systemctl restart NetworkManager >/dev/null 2>&1 || true
  systemctl restart network >/dev/null 2>&1 || true
}

aplicar_ip_estatica_servidor() {
  local iface="$1" ip_srv="$2" mask="$3" gw="$4" dns1="$5" dns2="$6"
  echo "Aplicando IP estatica en $iface: $ip_srv/$mask"
  if ! aplicar_ip_estatica_nmcli "$iface" "$ip_srv" "$mask" "$gw" "$dns1" "$dns2"; then
    aplicar_ip_estatica_ifcfg "$iface" "$ip_srv" "$mask" "$gw" "$dns1" "$dns2"
  fi
}

configurar_dhcp_interactivo() {
  local nombre ip_inicio ip_final mask iface lease_sec
  local ip_srv ip_pool_inicio
  local gw dns1 dns2
  local red broadcast
  local si ei psi
  local lf

  read -r -p "Nombre descriptivo del ambito [Scope-1]: " nombre
  nombre="${nombre:-Scope-1}"
  nombre="$(echo "$nombre" | tr -d '"')"

  echo "Interfaces disponibles:"
  mostrar_interfaces | sed 's/^/ - /'
  read -r -p "Interfaz de red interna [ens34]: " iface
  iface="${iface:-ens34}"

  # IP inicial = IP estatica del servidor
  ip_inicio="$(leer_ipv4 "Rango inicial (se usa como IP fija del servidor)")"
  mask="$(leer_mascara "Mascara" "255.255.255.0")"
  ip_final="$(leer_ipv4_final_con_shorthand "Rango final" "$ip_inicio")"

  misma_subred "$ip_inicio" "$ip_final" "$mask" || error "Inicio y final no estan en la misma subred"
  si="$(ip_a_entero "$ip_inicio")"
  ei="$(ip_a_entero "$ip_final")"
  (( si < ei )) || error "El rango inicial debe ser menor que el rango final"

  ip_srv="$ip_inicio"
  ip_pool_inicio="$(incrementar_ip "$ip_inicio")"
  psi="$(ip_a_entero "$ip_pool_inicio")"
  (( psi <= ei )) || error "Pool invalido: (inicio+1) es mayor que final"

  # Gateway opcional
  gw="$(leer_ipv4_opcional "Puerta de enlace (opcional)" "")"
  [[ -n "$gw" ]] && misma_subred "$gw" "$ip_inicio" "$mask" || { [[ -n "$gw" ]] && error "Gateway fuera de subred"; }

  # DNS primario opcional; si se omite, no se pregunta secundario
  dns1="$(leer_ipv4_opcional "DNS primario (opcional)" "")"
  dns2=""
  if [[ -n "$dns1" ]]; then
    dns2="$(leer_ipv4_opcional "DNS secundario (opcional)" "")"
  fi

  read -r -p "Lease time en segundos " lease_sec
  lease_sec="${lease_sec:-86400}"
  [[ "$lease_sec" =~ ^[0-9]+$ ]] || error "Lease debe ser numero entero (segundos)"
  (( lease_sec >= 60 && lease_sec <= 100000000 )) || error "Lease fuera de rango (60..100000000)"

  red="$(red_de_ip "$ip_inicio" "$mask")" || error "No pude calcular red"
  broadcast="$(broadcast_de_red "$red" "$mask")" || error "No pude calcular broadcast"

  # Asegurar IP temporal si la interfaz estaba sin IP (evita fallas raras)
  poner_ip_temporal_si_falta "$iface" "$(incrementar_ip "$red")" "$mask"

  # Aplicar IP estatica definitiva del server en ens34 (NM)
  aplicar_ip_estatica_servidor "$iface" "$ip_srv" "$mask" "$gw" "$dns1" "$dns2"

  # Lease file + sysconfig (Mageia INTERFACES)
  lf="$(archivo_leases)"
  mkdir -p "$(dirname "$lf")" || true
  touch "$lf" || true
  escribir_sysconfig_mageia "$iface" "$lf"

  # Construir opciones solo si existen
  local opt_routers="" opt_dns=""
  [[ -n "$gw" ]] && opt_routers="option routers ${gw};"
  if [[ -n "$dns1" && -n "$dns2" ]]; then
    opt_dns="option domain-name-servers ${dns1}, ${dns2};"
  elif [[ -n "$dns1" ]]; then
    opt_dns="option domain-name-servers ${dns1};"
  fi

  # Escribir conf definitivo: range = (inicio+1) .. final
  if [[ -f "$CONF" ]]; then
    cp -a "$CONF" "${CONF}.bak.$(date +%F_%H%M%S)" >/dev/null 2>&1 || true
  fi

  cat >"$CONF" <<EOF
authoritative;
ddns-update-style none;

default-lease-time ${lease_sec};
max-lease-time ${lease_sec};

option subnet-mask ${mask};
option broadcast-address ${broadcast};
${opt_routers}
${opt_dns}

subnet ${red} netmask ${mask} {
  range ${ip_pool_inicio} ${ip_final};
}
EOF

  echo "Validando sintaxis..."
  dhcpd -t -cf "$CONF" || error "Error en la configuracion. Revisa $CONF"

  echo "Reiniciando dhcpd..."
  reiniciar_servicio_dhcpd

  echo "Listo."
  echo "IP fija servidor: ${ip_srv}/${mask} en ${iface}"
  echo "Pool DHCP: ${ip_pool_inicio} - ${ip_final}"
  echo "Config: $CONF"
}

