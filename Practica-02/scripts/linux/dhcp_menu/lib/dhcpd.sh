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
  systemctl restart dhcpd || error "No pude reiniciar dhcpd. Revisa: journalctl -u dhcpd -n 50 --no-pager"
}

estado_servicio_dhcpd() {
  echo "== Servicio dhcpd =="
  systemctl --no-pager -l status dhcpd || true
  echo
  echo "== Ultimos logs (dhcpd) =="
  journalctl -u dhcpd -n 40 --no-pager || true
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
      if (state=="active") {
        printf "%-15s  %-17s  %s\n", ip, mac, host
      }
      inlease=0
    }
  ' "$lf" | sort -V
}

mostrar_interfaces() {
  ip -o link show | awk -F': ' '{print $2}' | sed 's/@.*//' | grep -v '^lo$' || true
}

aplicar_ip_estatica_servidor() {
  local iface="$1" ip_srv="$2" mask="$3" gw="$4" dns1="$5" dns2="$6"

  # Intento con NetworkManager (nmcli)
  if command -v nmcli >/dev/null 2>&1; then
    local con
    con="$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | awk -F: -v d="$iface" '$2==d{print $1; exit}')"
    if [[ -z "$con" ]]; then
      con="$(nmcli -t -f NAME,DEVICE con show 2>/dev/null | awk -F: -v d="$iface" '$2==d{print $1; exit}')"
    fi
    if [[ -n "$con" ]]; then
      echo "Aplicando IP estatica via nmcli en $iface (conexion: $con)..."
      nmcli con mod "$con" ipv4.method manual || true
      nmcli con mod "$con" ipv4.addresses "${ip_srv}/$(prefijo_desde_mascara "$mask")" || true

      if [[ -n "$gw" ]]; then
        nmcli con mod "$con" ipv4.gateway "$gw" || true
      else
        nmcli con mod "$con" ipv4.gateway "" || true
      fi

      # DNS: nmcli acepta lista separada por espacio/coma segun version; usamos espacio.
      if [[ -n "$dns1" && -n "$dns2" ]]; then
        nmcli con mod "$con" ipv4.dns "$dns1 $dns2" || true
      elif [[ -n "$dns1" ]]; then
        nmcli con mod "$con" ipv4.dns "$dns1" || true
      else
        nmcli con mod "$con" ipv4.dns "" || true
      fi

      nmcli con up "$con" >/dev/null 2>&1 || true
      return 0
    fi
  fi

  # Fallback: ifcfg (Mageia/RHEL-like)
  local ifcfg_dir="/etc/sysconfig/network-scripts"
  local ifcfg_file="${ifcfg_dir}/ifcfg-${iface}"
  mkdir -p "$ifcfg_dir" || true
  [[ -f "$ifcfg_file" ]] && cp -a "$ifcfg_file" "${ifcfg_file}.bak.$(date +%F_%H%M%S)" || true

  echo "Aplicando IP estatica via ifcfg en $iface ($ifcfg_file)..."
  {
    echo "DEVICE=${iface}"
    echo "ONBOOT=yes"
    echo "BOOTPROTO=static"
    echo "IPADDR=${ip_srv}"
    echo "NETMASK=${mask}"
    [[ -n "$gw" ]] && echo "GATEWAY=${gw}"
    [[ -n "$dns1" ]] && echo "DNS1=${dns1}"
    [[ -n "$dns2" ]] && echo "DNS2=${dns2}"
  } > "$ifcfg_file"

  systemctl restart NetworkManager >/dev/null 2>&1 || true
  systemctl restart network >/dev/null 2>&1 || true
}

# Convierte mascara a prefijo (/24) para nmcli
prefijo_desde_mascara() {
  local mask="$1" o1 o2 o3 o4
  IFS=. read -r o1 o2 o3 o4 <<<"$mask"
  local bin count=0
  for o in "$o1" "$o2" "$o3" "$o4"; do
    bin=$(printf "%08d" "$(echo "obase=2;$o" | bc 2>/dev/null)" 2>/dev/null)
    count=$(( count + ${bin//0/} ))
  done
  # fallback simple si bc falla
  if [[ -z "$count" || "$count" -le 0 ]]; then
    case "$mask" in
      255.255.255.0) echo 24 ;;
      255.255.0.0) echo 16 ;;
      255.0.0.0) echo 8 ;;
      *) echo 24 ;;
    esac
  else
    echo "$count"
  fi
}

configurar_dhcp_interactivo() {
  local nombre_ambito ip_inicio ip_final mask
  local ip_servidor ip_pool_inicio
  local gw dns1 dns2
  local lease_sec iface
  local red broadcast
  local si ei psi pei

  read -r -p "Nombre descriptivo del ambito [Scope-1]: " nombre_ambito
  nombre_ambito="${nombre_ambito:-Scope-1}"
  nombre_ambito="$(echo "$nombre_ambito" | tr -d '"')"

  ip_inicio="$(leer_ipv4 "Rango inicial (se usa como IP fija del servidor)")"
  mask="$(leer_mascara "Mascara" "255.255.255.0")"

  ip_final="$(leer_ipv4_final_con_shorthand "Rango final" "$ip_inicio")"

  # Validar misma subred y orden
  misma_subred "$ip_inicio" "$ip_final" "$mask" || error "Inicio y final no estan en la misma subred segun mascara $mask"

  si="$(ip_a_entero "$ip_inicio")"
  ei="$(ip_a_entero "$ip_final")"
  (( si < ei )) || error "El rango inicial debe ser menor que el rango final"

  ip_servidor="$ip_inicio"
  ip_pool_inicio="$(incrementar_ip "$ip_inicio")"

  psi="$(ip_a_entero "$ip_pool_inicio")"
  (( psi <= ei )) || error "El pool quedo invalido: (inicio+1) es mayor que final"

  red="$(red_de_ip "$ip_inicio" "$mask")" || error "No pude calcular red"
  broadcast="$(broadcast_de_red "$red" "$mask")" || error "No pude calcular broadcast"

  # Gateway opcional
  gw="$(leer_ipv4_opcional "Puerta de enlace (opcional)" "")"
  if [[ -n "$gw" ]]; then
    misma_subred "$gw" "$ip_inicio" "$mask" || error "Gateway no pertenece a la subred"
  fi

  # DNS primario opcional; si se omite, no preguntar secundario
  dns1="$(leer_ipv4_opcional "DNS primario (opcional)" "")"
  dns2=""
  if [[ -n "$dns1" ]]; then
    dns2="$(leer_ipv4_opcional "DNS secundario (opcional)" "")"
  fi

  # Lease en segundos
  read -r -p "Lease time en segundos [86400]: " lease_sec
  lease_sec="${lease_sec:-86400}"
  [[ "$lease_sec" =~ ^[0-9]+$ ]] || error "Lease debe ser numero entero (segundos)"
  (( lease_sec >= 60 && lease_sec <= 31536000 )) || error "Lease fuera de rango razonable (60..31536000)"

  echo "Interfaces disponibles:"
  mostrar_interfaces | sed 's/^/ - /'
  read -r -p "Interfaz de la red interna [eth0]: " iface
  iface="${iface:-eth0}"

  # Backup conf
  if [[ -f "$CONF" ]]; then
    cp -a "$CONF" "${CONF}.bak.$(date +%F_%H%M%S)" || true
  fi

  echo "Aplicando IP estatica al servidor: $ip_servidor / $mask en $iface"
  aplicar_ip_estatica_servidor "$iface" "$ip_servidor" "$mask" "$gw" "$dns1" "$dns2"

  # Construir opciones solo si existen
  local opt_routers="" opt_dns=""
  [[ -n "$gw" ]] && opt_routers="option routers ${gw};"
  if [[ -n "$dns1" && -n "$dns2" ]]; then
    opt_dns="option domain-name-servers ${dns1}, ${dns2};"
  elif [[ -n "$dns1" ]]; then
    opt_dns="option domain-name-servers ${dns1};"
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

  # Lease file
  local lf
  lf="$(archivo_leases)"
  mkdir -p "$(dirname "$lf")" || true
  touch "$lf" || true

  # Limitar interfaz (sysconfig)
  mkdir -p /etc/sysconfig || true
  cat >/etc/sysconfig/dhcpd <<EOF
DHCPD_INTERFACE="${iface}"
DHCPDARGS="${iface}"
EOF

  echo "Validando sintaxis..."
  dhcpd -t -cf "$CONF" || error "Error en la configuracion. Corrige $CONF"

  # Firewall si existe firewalld
  if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-service=dhcp >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
  fi

  echo "Reiniciando dhcpd..."
  reiniciar_servicio_dhcpd

  echo "Listo."
  echo "IP fija del servidor: ${ip_servidor}"
  echo "Pool DHCP: ${ip_pool_inicio} - ${ip_final}"
  echo "Config: $CONF"
}
