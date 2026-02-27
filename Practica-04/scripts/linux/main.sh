#!/bin/bash

# ==========================================
# SCRIPT PRINCIPAL PARA MAGEIA LINUX
# ==========================================

# Carga de funciones modulares
source ./funciones_mageia.sh

# Verificacion de privilegios
if [ "$EUID" -ne 0 ]; then
  echo -e "\e[1;31m[ERROR] Por favor, ejecuta este script como root o usando sudo.\e[0m"
  exit 1
fi

# Inicializar y crear carpetas requeridas antes de menu
inicializar_carpetas

menu_principal() {
    while true; do
        clear
        echo -e "\e[1;34m*********************************************\e[0m"
        echo -e "\e[1;32m      MAGEIA SERVER - GESTOR DE SERVICIOS    \e[0m"
        echo -e "\e[1;34m*********************************************\e[0m"
        echo -e "\e[1;36m  [ 1 ] - Instalacion y Config. de SSH\e[0m"
        echo -e "\e[1;36m  [ 2 ] - Administracion DHCP (ISC)\e[0m"
        echo -e "\e[1;36m  [ 3 ] - Administracion DNS (BIND)\e[0m"
        echo -e "\e[1;31m  [ 0 ] - Salir del Sistema\e[0m"
        echo -e "\e[1;34m*********************************************\e[0m"
        read -p ">> Indique la accion a realizar: " opcion

        case $opcion in
            1) modulo_ssh ;;
            2) modulo_dhcp ;;
            3) modulo_dns ;;
            0) echo "Terminando programa..."; exit 0 ;;
            *) echo -e "\e[1;31m[ERROR] - Opcion no valida.\e[0m"; sleep 2 ;;
        esac
    done
}

# Llamada a arranque principal
menu_principal
