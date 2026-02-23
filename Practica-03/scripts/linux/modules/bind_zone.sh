#!/usr/bin/env bash
set -euo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MOD_DIR/common.sh"
source "$MOD_DIR/bind_install.sh"

DOMAIN_DEFAULT="reprobados.com"
TTL_DEFAULT=300

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
    info "Agregado include de $NAMED_LOCAL en $NAMED_CONF"
  fi
}

remove_zone_block_named_local() {
  local domain="$1"
  [[ -f "$NAMED_LOCAL" ]] || touch "$NAMED_LOCAL"
  local tmp
  tmp="$(mktemp)"

  # elimina el bloque: zone "domain" ... { ... };
  awk -v dom="$domain" '
    BEGIN{inblk=0}
    $0 ~ "zone \""dom"\"" && $0 ~ "{" {inblk=1; next}
    inblk && $0 ~ /^\s*\};/ {inblk=0; next}
    inblk {next}
    {print}
  ' "$NAMED_LOCAL" > "$tmp"

  cat "$tmp" > "$NAMED_LOCAL"
  rm -f "$tmp"
}

zone_file_path_for_namedconf() {
  local domain="$1"
  local zone_dir zone_file_rel
  zone_dir="$(pick_zone_dir)"
  zone_file_rel="db.${domain}"

  if [[ "$zone_dir" == "/var/lib/named/var/named" ]]; then
    echo "var/named/${zone_file_rel}"
  else
    echo "${zone_dir}/${zone_file_rel}"
  fi
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

  chmod 644 "$zone_file" || true
  chown named:named "$zone_file" 2>/dev/null || chown root:named "$zone_file" 2>/dev/null || true
  ok "Archivo de zona generado: $zone_file"
}

upsert_zone_block() {
  local domain="$1"
  local zone_path
  zone_path="$(zone_file_path_for_namedconf "$domain")"

  ensure_named_local_included
  remove_zone_block_named_local "$domain"

  cat >> "$NAMED_LOCAL" <<EOF

zone "${domain}" IN {
  type master;
  file "${zone_path}";
  allow-query { any; };
};
EOF

  ok "Bloque de zona actualizado en $NAMED_LOCAL"
}

configure_zone_flow() {
  echo "== Configurar Zona + Registros (Linux/Mageia) =="

  local domain client_ip ttl
  read -r -p "Dominio [${DOMAIN_DEFAULT}]: " domain
  domain="$(trim "${domain:-$DOMAIN_DEFAULT}" | tr '[:upper:]' '[:lower:]')"

  valid_fqdn_zone "$domain" || die "Nombre de zona invalido. Ej: reprobados.com"

  client_ip="$(prompt_ip "IP del CLIENTE (Windows 10) (tu caso: 192.168.100.60)")"

  ttl="$TTL_DEFAULT"

  install_bind_idempotent
  upsert_zone_block "$domain"
  write_zone_file "$domain" "$client_ip" "$ttl"

  info "Validando configuracion..."
  named-checkconf || die "named-checkconf FALLO. Revisa $NAMED_CONF y $NAMED_LOCAL"

  info "Reiniciando servicio y limpiando cache..."
  service_restart
  if command -v rndc >/dev/null 2>&1; then
      rndc flush || true
  fi
  
  # Actualizar manifiesto compartido para el cliente
  update_shared_domains_list
  
  service_status
  show_listen_53

  ok "Zona lista: $domain (apunta a $client_ip)"
}

update_shared_domains_list() {
    local shared_file="$BASE_DIR/../dominios_activos.txt"
    info "Actualizando lista de dominios compartida..."
    if [[ -f "$NAMED_LOCAL" ]]; then
        grep "zone" "$NAMED_LOCAL" | cut -d'"' -f2 > "$shared_file"
        chmod 666 "$shared_file" 2>/dev/null || true
    fi
}