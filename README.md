🚀 Pterodactyl All-in-One Installer & Manager (Panel · Wings · FastDL · Extras)

Este repositorio contiene un script avanzado en Bash diseñado para instalar, administrar, reparar y mantener un entorno completo de Pterodactyl en servidores Linux (VPS o dedicados).

El script centraliza todas las tareas críticas relacionadas con:

Pterodactyl Panel

Pterodactyl Wings (Daemon)

FastDL para Counter-Strike 1.6

phpMyAdmin

MariaDB / MySQL

Nginx / SSL

Firewall y puertos

Backups, usuarios y mantenimiento

Todo desde un menú interactivo, automatizado y seguro.

⚙️ Requisitos

Sistema basado en Debian / Ubuntu

Acceso root

VPS o servidor dedicado

Conectividad a internet

🚀 Instalación rápida

Ejecuta el script con:

bash <(curl -fsSL https://raw.githubusercontent.com/bri127-svg/fast-dl-/main/install.sh)

🔐 Seguridad inicial

Al iniciar, el script:

✅ Verifica que se ejecute como root

✅ Comprueba e instala dependencias básicas (curl, wget)

✅ Habilita servicios web existentes (Nginx / PHP-FPM)

✅ Maneja errores sin romper el sistema

📊 Panel de estado del sistema

Antes de cualquier acción, el script muestra:

Estado del Panel Pterodactyl

Estado de Wings

Estado de MariaDB

Estado de Nginx

Estado de PHP-FPM

Estado de FastDL

Estado de phpMyAdmin

Información del sistema:

OS

Kernel

Virtualización

CPU

RAM

Disco

IP pública

Uptime

🧩 Funciones principales del menú
1️⃣ Instalador del Panel Pterodactyl

Usa el instalador oficial comunitario

Configura:

Nginx o Apache

SSL (Let’s Encrypt o personalizado)

MariaDB

Redis

PHP 8.3

Crea usuario administrador

Genera archivo Data.txt con:

Credenciales del panel

Usuarios de base de datos

Rutas importantes

Configura cronjobs y servicios systemd

2️⃣ Instalador de Pterodactyl Wings

Instalación normal (IP) o con subdominio + SSL

Instala y configura:

Docker

Firewall (UFW o iptables)

systemd (wings.service)

Descarga binario oficial según arquitectura

Configura Nginx como proxy si se usa SSL

Ejecuta el token generado por el panel

Verifica que Wings quede operativo

3️⃣ phpMyAdmin

Instalar o desinstalar

Dos modos de acceso:

/phpmyadmin

Subdominio con SSL

Configuración segura de PHP-FPM y Nginx

Generación automática de blowfish_secret

4️⃣ Configuración de Base de Datos (Database Host)

Habilita acceso externo controlado

Crea usuario MySQL exclusivo para hosts

Guarda credenciales de forma segura

Inserta la información en el archivo Data.txt

5️⃣ Instalador FastDL CS 1.6 (completo)

Instalación y desinstalación

Configura:

Nginx + SSL

Dominio FastDL

UUID del servidor

Crea estructura:

maps, models, sound, sprites, gfx, resource

Copia archivos automáticamente desde /mnt/server/cstrike

Configura server.cfg

Scripts incluidos:

sync_fastdl.sh (sincronización)

fastdl_status.sh (estado)

Soporte para cron automático

Protección de archivos sensibles (cfg, logs, plugins)

6️⃣ Modo Reparación (Rescue)

Reparar:

MariaDB

Nginx

PHP-FPM

Wings

Reinstala servicios si es necesario

Diagnóstico automático

7️⃣ Limpieza Total del VPS ⚠️

⚠️ BORRA TODO

Elimina:

Panel

Wings

Docker

MariaDB

PHP

Nginx / Apache

Redis

Certificados SSL

Resetea firewall

Deja el VPS listo para empezar desde cero

8️⃣ Gestión de Puertos

Ver puertos abiertos

Abrir puertos (TCP / UDP)

Cerrar puertos

Compatible con:

UFW

iptables

9️⃣ Gestión Avanzada

Backups completos de servidores Wings

Crear usuarios admin del panel

Eliminar usuarios

Listar backups

Ejecutor remoto autenticado

Limpieza y restauración de themes

🔟 Gestión de Themes

Instalar / desinstalar NookTheme

Limpiador total de themes

Restauración del panel oficial

➕ Addons

Instalador RevIActyl

Instalador de addons Blueprint (.blueprint)

📁 Archivos importantes generados

/var/www/pterodactyl/ptero-summary/Data.txt

/var/www/pterodactyl/credenciales.txt

/root/fastdl_info.txt

/usr/local/bin/sync_fastdl.sh

/usr/local/bin/fastdl_status.sh

👨‍💻 Creadores

briancarlos.dev

CRM

⚠️ Advertencia

Este script realiza cambios profundos en el sistema.
Usar únicamente en VPS dedicados o entornos de prueba.
Leer cada opción antes de ejecutarla.
