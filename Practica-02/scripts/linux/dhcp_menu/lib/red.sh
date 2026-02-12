#!/usr/bin/env bash
set -u

ip_a_entero() {
  local ip="$1" a b c d
  IFS=. read -r a b c d <<<"$ip" || return 1
  echo $(( (a<<24) + (b<<16) + (c<<8) + d ))
}

entero_a_ip() {
  local n="$1"
  echo "$(( (n>>24) & 255 )).$(( (n>>16) & 255 )).$(( (n>>8) & 255 )).$(( n & 255 ))"
}

es_ipv4_formato() {
  local ip="$1" a b c d
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r a b c d <<<"$ip" || return 1
  for o in "$a" "$b" "$c" "$d"; do
    [[ "$o" =~ ^[0-9]+$ ]] || return 1
    (( o>=0 && o<=255 )) || return 1
  done
  return 0
}

# Rechaza: 0.0.0.0, 255.255.255.255, loopback 127/8, link-local 169.254/16, multicast 224/4, reservado 240/4
es_ipv4_valida() {
  local ip="$1"
  es_ipv4_formato "$ip" || return 1
  [[ "$ip" != "0.0.0.0" && "$ip" != "255.255.255.255" ]] || return 1

  local n
  n="$(ip_a_entero "$ip")" || return 1
  (( (n & 0xFF000000) != 0x7F000000 )) || return 1
  (( (n & 0xFFFF0000) != 0xA9FE0000 )) || return 1
  (( (n & 0xF0000000) != 0xE0000000 )) || return 1
  (( (n & 0xF0000000) != 0xF0000000 )) || return 1
  return 0
}

mascara_es_valida() {
  local m="$1"
  es_ipv4_formato "$m" || return 1
  local mi inv
  mi=$(ip_a_entero "$m") || return 1
  (( mi != 0 && mi != 4294967295 )) || return 1
  inv=$(( 4294967295 ^ mi ))
  (( (inv & (inv + 1)) == 0 )) || return 1
  return 0
}

misma_subred() {
  local ip1="$1" ip2="$2" mask="$3"
  local i1 i2 m
  i1=$(ip_a_entero "$ip1") || return 1
  i2=$(ip_a_entero "$ip2") || return 1
  m=$(ip_a_entero "$mask") || return 1
  (( (i1 & m) == (i2 & m) ))
}

red_de_ip() {
  local ip="$1" mask="$2"
  local i m
  i=$(ip_a_entero "$ip") || return 1
  m=$(ip_a_entero "$mask") || return 1
  entero_a_ip $(( i & m ))
}

broadcast_de_red() {
  local red="$1" mask="$2"
  local r m
  r=$(ip_a_entero "$red") || return 1
  m=$(ip_a_entero "$mask") || return 1
  entero_a_ip $(( r | (4294967295 ^ m) ))
}

incrementar_ip() {
  local ip="$1"
  local i
  i=$(ip_a_entero "$ip") || return 1
  entero_a_ip $(( i + 1 ))
}

prefijo_desde_mascara() {
  local mask="$1" o1 o2 o3 o4
  IFS=. read -r o1 o2 o3 o4 <<<"$mask"
  local count=0 o
  for o in "$o1" "$o2" "$o3" "$o4"; do
    case "$o" in
      255) count=$((count+8));;
      254) count=$((count+7));;
      252) count=$((count+6));;
      248) count=$((count+5));;
      240) count=$((count+4));;
      224) count=$((count+3));;
      192) count=$((count+2));;
      128) count=$((count+1));;
      0) count=$((count+0));;
      *) echo 24; return 0;;
    esac
  done
  echo "$count"
}

leer_ipv4() {
  local prompt="$1" def="${2:-}" v
  while true; do
    if [[ -n "$def" ]]; then
      read -r -p "$prompt [$def]: " v
      v="${v:-$def}"
    else
      read -r -p "$prompt: " v
    fi
    if es_ipv4_valida "$v"; then echo "$v"; return 0; fi
    echo "IP invalida."
  done
}

leer_ipv4_opcional() {
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
    if es_ipv4_valida "$v"; then echo "$v"; return 0; fi
    echo "IP invalida."
  done
}

leer_ipv4_final_con_shorthand() {
  local prompt="$1" ip_inicio="$2" def="${3:-}" v
  local a b c _
  IFS=. read -r a b c _ <<<"$ip_inicio"

  while true; do
    if [[ -n "$def" ]]; then
      read -r -p "$prompt [$def]: " v
      v="${v:-$def}"
    else
      read -r -p "$prompt: " v
    fi

    if [[ "$v" =~ ^[0-9]{1,3}$ ]]; then
      (( v>=0 && v<=255 )) || { echo "Final invalido (0-255)."; continue; }
      v="${a}.${b}.${c}.${v}"
    fi

    if es_ipv4_valida "$v"; then echo "$v"; return 0; fi
    echo "IP invalida."
  done
}

leer_mascara() {
  local prompt="$1" def="${2:-255.255.255.0}" v
  while true; do
    read -r -p "$prompt [$def]: " v
    v="${v:-$def}"
    if mascara_es_valida "$v"; then echo "$v"; return 0; fi
    echo "Mascara invalida."
  done
}

