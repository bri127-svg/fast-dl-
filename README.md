Pterodactyl All-in-One Installer & Manager
Panel · Wings · FastDL · Extras

Este repositorio incluye un script avanzado en Bash diseñado para instalar, administrar y mantener entornos completos de Pterodactyl en servidores Linux (VPS o dedicados).

La herramienta centraliza en un menú interactivo automatizado todas las tareas esenciales relacionadas con la infraestructura del servidor, facilitando la implementación, gestión y mantenimiento del sistema.

REQUISITOS

- Sistema basado en Debian o Ubuntu
- Acceso root
- VPS o servidor dedicado
- Conexión a internet

INSTALACIÓN RÁPIDA

Ejecutar el siguiente comando:

bash <(curl -fsSL https://raw.githubusercontent.com/bri127-svg/fast-dl-/main/install.sh)

SEGURIDAD Y VERIFICACIÓN INICIAL

El script realiza automáticamente:

- Verificación de ejecución como usuario root
- Instalación de dependencias esenciales
- Comprobación de servicios web existentes
- Manejo seguro de errores del sistema

MONITOREO DEL SISTEMA

Incluye un panel que muestra el estado de:

- Pterodactyl Panel
- Wings
- MariaDB
- Nginx
- PHP-FPM
- FastDL
- phpMyAdmin

También muestra información del sistema como:

- Sistema operativo
- Kernel
- Virtualización
- CPU
- RAM
- Disco
- IP pública
- Uptime

FUNCIONES PRINCIPALES

El menú interactivo permite:

- Instalación automática de Pterodactyl Panel
- Configuración de Pterodactyl Wings
- Gestión de phpMyAdmin
- Configuración segura de bases de datos
- Instalación completa de FastDL para Counter-Strike 1.6
- Modo reparación de servicios
- Gestión de firewall y puertos
- Backups y administración avanzada
- Instalación de themes y addons

El script genera automáticamente archivos de credenciales, configuraciones y scripts auxiliares para facilitar la administración del servidor.

ADVERTENCIA

Este script realiza modificaciones profundas en el sistema.  
Se recomienda utilizarlo únicamente en VPS dedicados o entornos de prueba y revisar cuidadosamente cada opción antes de ejecutarla.

AUTOR

briancarlos.dev
