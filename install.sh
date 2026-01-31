#!/bin/bash

clear
echo "======================================="
echo " FASTDL INSTALLER"
echo " Pterodactyl + Nginx"
echo " Creado por By Team Vhl"
echo "======================================="

# ROOT CHECK
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ejecuta este instalador como root"
  exit 1
fi

# INPUTS
echo ""
read -p "➡ Dominio o IP para FastDL (ej: fastdl.midominio.com): " FASTDL_DOMAIN

if [ -z "$FASTDL_DOMAIN" ]; then
  echo "❌ Debes ingresar un dominio o IP"
  exit 1
fi

PTERO_PATH="/var/lib/pterodactyl/volumes"

echo ""
echo "[1/6] Actualizando sistema..."
apt update -y >/dev/null 2>&1

echo "[2/6] Instalando Nginx..."
apt install nginx -y >/dev/null 2>&1

echo "[3/6] Asignando permisos Pterodactyl..."
gpasswd -a www-data pterodactyl >/dev/null 2>&1
chmod 755 /var/lib/pterodactyl
chmod 755 /var/lib/pterodactyl/volumes

echo "[4/6] Creando configuracion FastDL..."
cat <<EOF > /etc/nginx/sites-available/fastdl.conf
server {
    listen 80;
    listen [::]:80;

    server_name $FASTDL_DOMAIN;
    root $PTERO_PATH;

    location / {
        try_files \$uri \$uri/ =404;
        autoindex on;
    }

    location ~\\.(sma|amxx|sp|smx|cfg|ini|log|bak|dat|sql|sq3|so|dll|php|zip|rar|jar|sh)$ {
        return 403;
    }

    location ~ /(addons|cfg|logs) {
        deny all;
    }
}
EOF

echo "[5/6] Activando FastDL..."
ln -s /etc/nginx/sites-available/fastdl.conf /etc/nginx/sites-enabled/fastdl.conf 2>/dev/null
rm -f /etc/nginx/sites-enabled/default

echo "[6/6] Reiniciando Nginx..."
nginx -t || { echo "❌ Error en Nginx"; exit 1; }
systemctl restart nginx

echo ""
echo "======================================="
echo " ✅ FASTDL INSTALADO CORRECTAMENTE"
echo "======================================="
echo " 🌐 URL: http://$FASTDL_DOMAIN"
echo " 📂 Ruta: $PTERO_PATH"
echo ""
echo " 🔎 Prueba:"
echo " http://$FASTDL_DOMAIN/ID_DEL_SERVER/cstrike/maps/mapa.bsp"
echo ""
echo " ⚠️ Cierra sesion SSH y vuelve a entrar"
echo "======================================="
