  #!/bin/bash

echo ""
echo "-------------------------------------------------------"
echo "       Angel Distro Mageia MSG Bienvenida - LINUX "
echo "-------------------------------------------------------"
echo ""

echo "Nombre del equipo: "
hostname
echo ""

echo "IP actual: "
ip -4 addr show | awk '/inet /{print " - " $2 " (" $NF ")"}'
echo ""

echo "Espacio en disco: "
df -h / | awk 'NR==1{print} NR==2{print}'

echo "________________________________________________________"
echo  ""
