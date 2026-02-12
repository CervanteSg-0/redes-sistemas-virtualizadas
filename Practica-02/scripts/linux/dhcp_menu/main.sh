#!/usr/bin/env bash
set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$BASE_DIR/lib/red.sh"
. "$BASE_DIR/lib/sistema.sh"
. "$BASE_DIR/lib/dhcpd.sh"

pausa() { read -r -p "Enter para continuar..." _; }

menu() {
  while true; do
    echo
    echo "===== DHCP (Mageia / ISC dhcpd) ====="
    echo "1) Verificar/Instalar dhcp-server"
    echo "2) Configurar DHCP (interactivo + IP estatica + validaciones)"
    echo "3) Monitoreo: estado + leases activas"
    echo "4) Reiniciar servicio dhcpd"
    echo "5) Salir"
    read -r -p "Opcion: " op

    case "$op" in
      1)
        asegurar_root
        instalar_paquete_dhcpd
        echo "Instalado/verificado."
        pausa
        ;;
      2)
        asegurar_root
        instalar_paquete_dhcpd
        configurar_dhcp_interactivo
        pausa
        ;;
      3)
        estado_servicio_dhcpd
        leases_activas
        pausa
        ;;
      4)
        asegurar_root
        reiniciar_servicio_dhcpd
        echo "Reiniciado."
        pausa
        ;;
      5) exit 0 ;;
      *) echo "Opcion invalida." ;;
    esac
  done
}

menu

