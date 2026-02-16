#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"
source "$(dirname "$0")/bind_install.sh"

DOMAIN_DEFAULT="reprobados.com"
TTL_DEFAULT=300

NAMED_CONF="/etc/named.conf"
NAMED_LOCAL="/etc/named.conf.local"
ZONE_DIR_CANDIDATES=(
  "/var/lib/named/var/named"
  "/var/named"
  "/var/cache/bind"
)

pick_zone_dir() {
  local d
  for d in "${ZONE_DIR_CANDIDATES[@]}"; do
    [[ -d "$d" ]] && { echo "$d"; return 0; }
  done
  mkdir -p "/var/named"
  echo "/var/named"
}

ensure_named_local_included() {
  [[ -f "$NAMED_CONF" ]] || die "No existe $NAMED_CONF. Instala BIND primero."
  [[ -f "$NAMED_LOCAL" ]] || touch "$NAMED_LOCAL"

  if ! grep -qE "include\s+\"$NAMED_LOCAL\"" "$NAMED_CONF"; then
    echo "" >> "$NAMED_CONF"
    echo "include \"$NAMED_LOCAL\";" >> "$NAMED_CONF"
  fi
}

remove_existing_zone_block() {
  local domain="$1"
  local tmp
  tmp="$(mktemp)"
  awk -v dom="$domain" '
    BEGIN{inblk=0}
    $0 ~ "zone \""dom"\"" {inblk=1}
    inblk && $0 ~ /^\};/ {inblk=0; next}
    inblk {next}
    {print}
  ' "$NAMED_LOCAL" > "$tmp"
  cat "$tmp" > "$NAMED_LOCAL"
  rm -f "$tmp"
}

upsert_zone_block() {
  local domain="$1"
  local zone_dir zone_path zone_file_rel
  zone_dir="$(pick_zone_dir)"
  zone_file_rel="db.${domain}"

  if [[ "$zone_dir" == "/var/lib/named/var/named" ]]; then
    zone_path="var/named/${zone_file_rel}"
  else
    zone_path="${zone_dir}/${zone_file_rel}"
  fi

  ensure_named_local_included
  remove_existing_zone_block "$domain"

  cat >> "$NAMED_LOCAL" <<EOF

zone "${domain}" IN {
  type master;
  file "${zone_path}";
  allow-query { any; };
};
EOF
}

write_zone_file() {
  local domain="$1" client_ip="$2" ttl="$3"
  local zone_dir zone_file serial
  zone_dir="$(pick_zone_dir)"
  mkdir -p "$zone_dir"
  zone_file="${zone_dir}/db.${domain}"
  serial="$(date +%Y%m%d%H)"

  cat > "$zone_file" <<EOF
\$TTL ${ttl}
@   IN  SOA ns1.${domain}. admin.${domain}. (
        ${serial} ; serial
        3600      ; refresh
        900       ; retry
        604800    ; expire
        ${ttl}    ; minimum
)
    IN  NS  ns1.${domain}.
ns1 IN  A   ${client_ip}

@   IN  A   ${client_ip}
www IN  CNAME @
EOF

  chmod 640 "$zone_file" || true
  chown root:named "$zone_file" 2>/dev/null || true
}

configure_zone_flow() {
  echo "== Configurar Zona + Registros (Linux) =="
  local domain client_ip ttl

  read -r -p "Dominio [${DOMAIN_DEFAULT}]: " domain
  domain="$(trim "${domain:-$DOMAIN_DEFAULT}")"
  [[ -n "$domain" ]] || die "Dominio vacio."

  client_ip="$(prompt_ip "IP del CLIENTE (Windows 10)")"

  read -r -p "TTL en segundos [${TTL_DEFAULT}]: " ttl
  ttl="$(trim "${ttl:-$TTL_DEFAULT}")"
  [[ "$ttl" =~ ^[0-9]+$ ]] || die "TTL invalido."
  (( ttl >= 30 && ttl <= 86400 )) || die "TTL fuera de rango (30-86400)."

  install_bind_idempotent
  upsert_zone_block "$domain"
  write_zone_file "$domain" "$client_ip" "$ttl"

  echo "[INFO] Validando..."
  named-checkconf || die "named-checkconf fallo."

  echo "[INFO] Reiniciando servicio..."
  service_restart
  service_status

  echo "[OK] Zona lista: $domain"
}
