#!/usr/bin/env bash

# ==============================
# VARIABLES
# ==============================
WINGS_PORT=${WINGS_PORT:-8080}
WINGS_BIN="/usr/local/bin/wings"
WINGS_SERVICE="/etc/systemd/system/wings.service"

# ==============================
# FUNCIONES LOG
# ==============================
log_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
log_ok()   { echo -e "\e[32m[OK]\e[0m   $1"; }
log_warn() { echo -e "\e[33m[WARN]\e[0m $1"; }
log_err()  { echo -e "\e[31m[ERR]\e[0m  $1"; }

# ==============================
# COLORES
# ==============================
C_RESET="\e[0m"
C_OK="\e[1;32m"
C_WARN="\e[1;33m"
C_TITLE="\e[1;36m"

# ==============================
# VERIFICADOR DE ROOT
# ==============================
if [ "$(id -u)" -ne 0 ]; then
  echo "Este script debe ejecutarse como root."
  exit 1
fi

# ==============================
# INSTALAR DEPENDENCIAS BÁSICAS
# ==============================
log_info "Verificando dependencias básicas..."

# Lista de paquetes mínimos
for pkg in curl wget; do
  if ! command -v "$pkg" >/dev/null 2>&1; then
    log_warn "$pkg no está instalado. Instalando..."
    apt install -y "$pkg"
  fi
done

log_ok "Dependencias básicas verificadas"

# ==============================
# HABILITAR SERVICIOS WEB
# ==============================
log_info "Habilitando servicios web (Nginx y PHP-FPM)..."

for svc in nginx php8.3-fpm; do
  if systemctl list-unit-files | grep -q "^$svc.service"; then
    systemctl enable --now "$svc"
    log_ok "$svc habilitado y en ejecución"
  else
    log_warn "Servicio $svc no encontrado, omitiendo"
  fi
done

# ==============================
# VARIABLES SUDO COMPATIBLE
# ==============================
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

apt_force_unlock() { return 0; }

command -v lsb_release >/dev/null 2>&1 || lsb_release() { return 1; }
command -v systemd-detect-virt >/dev/null 2>&1 || systemd-detect-virt() { echo "Físico/Nativo"; }
command -v lscpu >/dev/null 2>&1 || lscpu() { cat /proc/cpuinfo; }
command -v free >/dev/null 2>&1 || free() { awk 'BEGIN{print "Mem: N/A N/A N/A"}'; }
command -v curl >/dev/null 2>&1 || curl() { return 1; }

# ==============================
# FUNCIONES AUXILIARES
# ==============================
mensaje() {
  echo "[INFO] $1"
}

exito() {
  echo "[ OK ] $1"
}

advertencia() {
  echo "[WARN] $1"
}

error() {
  echo "[ERROR] $1"
}

header() {
  clear
}

log() {
  echo "$1"
}

panel_webserver() {
  return 0
}

# ==============================
# ESTADO INFORMATIVO
# ==============================
check_panel() {
  if [ -d "/var/www/pterodactyl" ]; then
    if systemctl is-active --quiet nginx || systemctl is-active --quiet apache2; then
      echo "Funcionando 💙 (Panel activo y responde)"
    else
      echo "Instalado ⚠️ (Panel instalado pero sin webserver)"
    fi
  else
    echo "No instalado ❌ (Panel no instalado)"
  fi
}

check_wings() {
  if systemctl list-unit-files | grep -q '^wings.service'; then
    if systemctl is-active --quiet wings; then
      echo "Funcionando 💙 (Daemon activo)"
    else
      echo "Instalado ⚠️ (Daemon instalado pero detenido)"
    fi
  else
    echo "No instalado ❌ (No instalado)"
  fi
}

check_mariadb() {
  if command -v mariadb >/dev/null 2>&1 || command -v mysql >/dev/null 2>&1; then
    if systemctl is-active --quiet mariadb || systemctl is-active --quiet mysql; then
      echo "Funcionando 💙 (Servicio activo y responde)"
    else
      echo "Instalado ⚠️ (Servicio instalado pero detenido)"
    fi
  else
    echo "No instalado ❌ (No instalado)"
  fi
}

check_nginx() {
  if command -v nginx >/dev/null 2>&1; then
    if systemctl is-active --quiet nginx; then
      echo "Funcionando 💙 (Servicio activo)"
    else
      echo "Instalado ⚠️ (No iniciado)"
    fi
  else
    echo "No instalado ❌ (No instalado)"
  fi
}

check_phpfpm() {
  if systemctl list-unit-files | grep -q 'php.*-fpm.service'; then
    if systemctl is-active --quiet php8.3-fpm 2>/dev/null || systemctl is-active --quiet php-fpm 2>/dev/null; then
      echo "Funcionando 💙 (PHP-FPM activo)"
    else
      echo "Instalado ⚠️ (PHP-FPM instalado pero detenido)"
    fi
  else
    echo "No instalado ❌ (PHP-FPM no instalado)"
  fi
}

check_phpmyadmin() {
  if [ -d "/usr/share/phpmyadmin" ]; then
    if systemctl is-active --quiet nginx; then
      echo "Funcionando 💙 (phpMyAdmin disponible)"
    else
      echo "Instalado ⚠️ (Nginx detenido)"
    fi
  else
    echo "No instalado ❌ (No instalado)"
  fi
}

check_fastdl() {
  if [ ! -f "/etc/nginx/sites-available/fastdl.conf" ]; then
    echo "No instalado ❌ (No instalado)"
    return
  fi

  if ! systemctl is-active --quiet nginx; then
    echo "Caído ❌ (Nginx detenido)"
    return
  fi

  local FASTDL_DIR UUID DOMINIO HTTPS_CODE

  FASTDL_DIR=$(find /var/lib/pterodactyl/volumes -maxdepth 2 -type d -name cstrike 2>/dev/null | head -n 1)
  [ -z "$FASTDL_DIR" ] && { echo "Problema ⚠️ (Archivos no encontrados)"; return; }

  UUID=$(basename "$(dirname "$FASTDL_DIR")")
  DOMINIO=$(awk '/server_name/ {print $2}' /etc/nginx/sites-available/fastdl.conf | tr -d ';' | head -n 1)
  [ -z "$DOMINIO" ] && { echo "Problema ⚠️ (Dominio no detectado)"; return; }

  HTTPS_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "https://$DOMINIO/$UUID/cstrike/")

  case "$HTTPS_CODE" in
    200) echo "Funcionando 💙 (HTTPS OK | $DOMINIO)" ;;
    403|404) echo "Problema ⚠️ (HTTPS $HTTPS_CODE | $DOMINIO)" ;;
    000) echo "Caído ❌ (Sin respuesta | $DOMINIO)" ;;
    *) echo "Problema ⚠️ (HTTPS $HTTPS_CODE | $DOMINIO)" ;;
  esac
}

mostrar_estado() {
  echo ""
  echo -e "${C_TITLE}==================== ESTADO ====================${C_RESET}"

  printf "Panel:          %s\n" "$(check_panel)"
  printf "Wings:          %s\n" "$(check_wings)"
  printf "MariaDB:        %s\n" "$(check_mariadb)"
  printf "Nginx:          %s\n" "$(check_nginx)"
  printf "PHP-FPM:        %s\n" "$(check_phpfpm)"
  printf "FastDL:         %s\n" "$(check_fastdl)"
  printf "phpMyAdmin:     %s\n" "$(check_phpmyadmin)"

  echo -e "${C_TITLE}================================================${C_RESET}"
  echo ""
}

# ==============================
# MODO REPARACIÓN (RESCUE)
# ==============================
rescue_mariadb() {
  log_info "Reparando MariaDB..."

  systemctl unmask mariadb mysql 2>/dev/null || true
  systemctl stop mariadb mysql 2>/dev/null || true

  if ! command -v mariadb >/dev/null && ! command -v mysql >/dev/null; then
    apt update -y
    apt install -y mariadb-server mariadb-client
  fi

  systemctl enable mariadb
  systemctl restart mariadb

  if mysql -u root -e "SELECT 1;" &>/dev/null; then
    log_ok "MariaDB funcionando"
  else
    log_err "MariaDB sigue fallando"
  fi

  read -p "Presiona Enter para continuar..."
}

rescue_nginx() {
  log_info "Reparando Nginx..."

  if ! command -v nginx >/dev/null; then
    apt update -y
    apt install -y nginx
  fi

  nginx -t || true
  systemctl enable nginx
  systemctl restart nginx

  systemctl is-active --quiet nginx \
    && log_ok "Nginx funcionando" \
    || log_err "Nginx falló"

  read -p "Presiona Enter para continuar..."
}

rescue_phpfpm() {
  log_info "Reparando PHP-FPM..."

  if ! systemctl list-unit-files | grep -q php8.3-fpm; then
    apt update -y
    apt install -y php8.3-fpm php8.3-mysql
  fi

  systemctl enable php8.3-fpm
  systemctl restart php8.3-fpm

  systemctl is-active --quiet php8.3-fpm \
    && log_ok "PHP-FPM funcionando" \
    || log_err "PHP-FPM falló"

  read -p "Presiona Enter para continuar..."
}

rescue_wings() {
  log_info "Reiniciando Wings..."
  systemctl restart wings 2>/dev/null || true

  systemctl is-active --quiet wings \
    && log_ok "Wings funcionando" \
    || log_err "Wings falló"

  read -p "Presiona Enter para continuar..."
}

menu_rescue() {
  clear
  echo "====== REPARACIÓN ======"
  echo "1) Reparar MariaDB"
  echo "2) Reparar Nginx"
  echo "3) Reparar PHP-FPM"
  echo "4) Reparar Wings"
  echo "0) Volver"
  echo ""
  read -p "Opción: " opt

  case "$opt" in
    1) rescue_mariadb ;;
    2) rescue_nginx ;;
    3) rescue_phpfpm ;;
    4) rescue_wings ;;
  esac
}

mostrar_menu() {
  clear
  mostrar_estado
  
  echo -e "\e[1;36m══════════════════════════════════════════════════\e[0m"
  echo -e "\e[1;36m         PANEL DE CONTROL - SYSTEM INFO           \e[0m"
  echo -e "\e[1;36m      Creditos:briancarlos.dev | BCF Studio       \e[0m"
  echo -e "\e[1;36m══════════════════════════════════════════════════\e[0m"

  echo -e "\e[1;33m◈ INFORMACIÓN DEL SISTEMA ◈\e[0m"
  echo -e "\e[90m─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─\e[0m"
  
  OS_INFO=$(lsb_release -ds 2>/dev/null || grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"' || echo "No detectado")
  VIRT_INFO=$(systemd-detect-virt 2>/dev/null || echo "Físico/Nativo")
  CPU_INFO=$(lscpu | grep "Model name" | cut -d: -f2 | xargs | head -1)
  CPU_CORES=$(nproc)
  RAM_TOTAL=$(free -h | awk '/^Mem:/ {print $2}')
  RAM_USED=$(free -h | awk '/^Mem:/ {print $3}')
  RAM_FREE=$(free -h | awk '/^Mem:/ {print $7}')
  DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
  DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
  DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')
  PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
  LOCATION="The Netherlands (nl)"
  UPTIME=$(uptime -p | sed 's/up //' 2>/dev/null || echo "N/A")
  KERNEL=$(uname -r)
  
  echo -e "\e[1;37mSistema:\e[0m          \e[97m$OS_INFO\e[0m"
  echo -e "\e[1;37mKernel:\e[0m           \e[97m$KERNEL\e[0m"
  echo -e "\e[1;37mVirtualización:\e[0m   \e[97m$VIRT_INFO\e[0m"
  echo -e "\e[1;37mUptime:\e[0m           \e[92m$UPTIME\e[0m"
  echo -e "\e[1;37mProcesador:\e[0m       \e[97m$CPU_INFO\e[0m"
  echo -e "\e[1;37mNúcleos:\e[0m          \e[93m$CPU_CORES\e[0m"
  echo -e "\e[1;37mRAM Total:\e[0m        \e[97m$RAM_TOTAL\e[0m \e[90m(Usada: $RAM_USED / Libre: $RAM_FREE)\e[0m"
  echo -e "\e[1;37mDisco Total:\e[0m      \e[97m$DISK_TOTAL\e[0m \e[90m(Usado: $DISK_USED / Libre: $DISK_FREE)\e[0m"
  echo -e "\e[1;37mIP Pública:\e[0m       \e[96m$PUBLIC_IP\e[0m"
  echo -e "\e[1;37mUbicación:\e[0m        \e[95m$LOCATION\e[0m"
  
  echo ""
  echo -e "\e[1;33m◈ MENÚ DE OPCIONES ◈\e[0m"
  echo -e "\e[90m─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─\e[0m"
  echo ""
  echo -e "  \e[1;32m› [1]\e[0m Instalar Panel Pterodactyl"
  echo -e "  \e[1;32m› [2]\e[0m Instalar Wings (Daemon)"
  echo -e "  \e[1;32m› [3]\e[0m Instalar phpMyAdmin"
  echo -e "  \e[1;32m› [4]\e[0m Configurar Base de Datos"
  echo -e "  \e[1;33m› [5]\e[0m Corregir MariaDB (bind-address)"
  echo -e "  \e[1;36m› [6]\e[0m Instalar FastDL"
  echo -e "  \e[1;33m› [7]\e[0m Reparación (Rescue)"
  echo -e "  \e[1;31m› [8]\e[0m Limpieza Total (BORRA TODO)"
  echo -e "  \e[1;34m› [9]\e[0m Gestión de Puertos"
  echo -e "  \e[1;35m› [10]\e[0m Gestión Avanzada (Backup/Usuarios)"
  echo -e "  \e[1;35m› [11]\e[0m Gestión de Temas (NookTheme)"
  echo -e "  \e[1;35m› [12]\e[0m Ejecutar Comandos para intalacion de el nebula"
  echo -e "  \e[1;35m› [13]\e[0m Instalar Addon RevIActyl"
  echo -e "  \e[1;35m› [14]\e[0m Limpiador de Themes (Restaurar Panel)"
  echo -e "  \e[1;35m› [15]\e[0m Instalar Addon Blueprint (FONDO DE SERVIDOR)"
  echo -e "  \e[1;36m› [16]\e[0m Instalar wings + Docker sin token"
  echo -e "  \e[1;36m› [17]\e[0m Instalador Certificado SSL (simplificado)"
  echo ""
  echo -e "  \e[1;31m› [0]\e[0m Salir del programa"
  echo -e "\e[90m────────────────────────────────────────────────────\e[0m"
  echo -ne "\e[1;36m▷ \e[0mSeleccione una opción [0-10]: "
}

# ==============================
# INSTALADOR DEL PANEL (BCF Studio)
# ==============================

instalar_panel() {
  log_info "Iniciando instalador externo de Pterodactyl..."
  
  local installer_file
  installer_file=$(mktemp /tmp/ptero-installer-XXXXXX.sh)
  
  cat << 'EOF' > "$installer_file"
#!/usr/bin/env bash

########################################################################
#                                                                      #
#            Pterodactyl Installer, Updater, Remover and More          #
#            Copyright 2025, Malthe K, <me@malthe.cc>                 # 
#  https://github.com/guldkage/Pterodactyl-Installer/blob/main/LICENSE #
#                                                                      #
#  This script is not associated with the official Pterodactyl Panel.  #
#  You may not remove this line                                        #
#                                                                      #
########################################################################

set -euo pipefail

### VARIABLES ###
dist="$(. /etc/os-release && echo "$ID")"
version="$(. /etc/os-release && echo "$VERSION_ID")"
USERPASSWORD=""
WINGSNOQUESTIONS=false
INSTALLBOTH=${INSTALLBOTH:-false}

for var in FQDN WEBSERVER EMAIL SSLSTATUS CUSTOMSSL USERNAME FIRSTNAME LASTNAME; do
    declare "$var=Not set.."
done

function trap_ctrlc() {
    echo ""
    echo "Bye!"
    exit 2
}
trap "trap_ctrlc" 2

warning() {
    echo -e '\e[31m'"$1"'\e[0m'
}

send_summary() {
    clear
    if [ -d "/var/www/pterodactyl" ]; then
        warning "[!] WARNING: Pterodactyl is already installed. This script have a high chance of failing."
    fi
    echo ""
    echo "[!] Summary:"
    echo "    Panel URL: $FQDN"
    echo "    Webserver: $WEBSERVER"
    echo "    Email: $EMAIL"
    echo "    SSL: $SSLSTATUS"
    echo "    Custom SSL: $CUSTOMSSL"
    echo "    Username: $USERNAME"
    echo "    First name: $FIRSTNAME"
    echo "    Last name: $LASTNAME"
    if [ -n "$USERPASSWORD" ]; then
        echo "    Password: $(printf "%0.s*" $(seq 1 ${#USERPASSWORD}))"
    else
        echo "    Password: Not set.."
    fi
    echo ""
}

if [ -d "/var/www/pterodactyl" ]; then
    echo ""
    echo "[!] WARNING: Pterodactyl is already installed!"
    echo ""
    echo "Choose one of the following options:"
    echo "  1) Uninstall Pterodactyl automatically (deletes everything related to the panel)"
    echo "  2) Continue anyway (may cause errors!)"
    echo "  3) Cancel installation"
    echo ""

    while true; do
        read -rp "Enter your choice (1/2/3): " CHOICE
        case "$CHOICE" in
            1)
                echo "[!] Running automatic uninstallation..."
                if [ -d "/var/www/pterodactyl" ]; then
                    rm -rf /var/www/pterodactyl || { echo "Error: Failed to remove panel files."; exit 1; }
                else
                    echo "Panel files not found, skipping removal."
                fi
        
                [ -f "/etc/systemd/system/pteroq.service" ] && rm /etc/systemd/system/pteroq.service
                [ -f "/root/ptero-summary.txt" ] && rm /root/ptero-summary.txt
                [ -f "/etc/nginx/sites-enabled/pterodactyl.conf" ] && unlink /etc/nginx/sites-enabled/pterodactyl.conf
                [ -f "/etc/apache2/sites-enabled/pterodactyl.conf" ] && unlink /etc/apache2/sites-enabled/pterodactyl.conf
        
                DB_NAME="panel"
                USERS=("pterodactyl" "pterodactyluser")
        
                mariadb -u root -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`;" || { echo "Could not delete database '${DB_NAME}'."; exit 1; }
        
                for user in "${USERS[@]}"; do
                    mariadb -u root -e "DROP USER IF EXISTS '${user}'@'127.0.0.1';" || { echo "Could not delete user '${user}'."; exit 1; }
                done
                break
                ;;
            2)
                echo "[!] Continuing anyway"
                break
                ;;
            3)
                echo "[!] Install cancelled"
                exit 1
                ;;
            *)
                echo "[!] Invalid selection. Please select 1, 2, or 3."
                ;;
        esac
    done
fi

panel_input() {
    local prompt="$1"
    local var_name="$2"
    local max_length="$3"
    local hide_input="${4:-}"
    
    while :; do
        echo "$prompt"
        
        if [ "$hide_input" == "true" ]; then
            local input=""
            while IFS= read -r -s -n 1 char; do
                if [[ $char == $'\0' ]]; then
                    break
                elif [[ $char == $'\177' ]]; then
                    if [ -n "$input" ]; then
                        input="${input%?}"
                        echo -en "\b \b"
                    fi
                else
                    echo -n '*'
                    input+="$char"
                fi
            done
            echo
        else
            read -r input
        fi

        if [ -z "$input" ]; then
            echo "[!] This field cannot be empty."
        elif [ ${#input} -gt "$max_length" ]; then
            echo "[!] Input cannot be more than $max_length characters."
        elif [[ "$input" =~ [æøåÆØÅ] ]]; then
            echo "[!] Invalid characters detected. Only A-Z, a-z, 0-9, and common symbols are allowed."
        else
            eval "$var_name=\"$input\""
            break
        fi
    done
}

panel_validate_ssl_files() {
    local cert_path="$1"
    local key_path="$2"
    
    if [ ! -f "$cert_path" ]; then
        echo "[!] Error: Fullchain certificate file does not exist at $cert_path."
        exit 1
    fi
    if [ ! -f "$key_path" ]; then
        echo "[!] Error: Private key file does not exist at $key_path."
        exit 1
    fi

    if ! openssl x509 -in "$cert_path" -noout; then
        echo "[!] Error: $cert_path is not a valid SSL certificate."
        exit 1
    fi

    if ! openssl rsa -in "$key_path" -check -noout; then
        echo "[!] Error: $key_path is not a valid private key."
        exit 1
    fi
    
    echo "[+] SSL files are valid."
    panel_email
}

panel_webserver() {
    send_summary
    echo "[!]selecciona tu web server"
    echo "    (1) NGINX (recomendado)"
    echo "    (2) Apache"
    echo "    Input 1-2"
    read -r option
    case $option in
        1) 
            WEBSERVER="NGINX"
            panel_fqdn
            ;;
        2) 
            WEBSERVER="Apache"
            panel_fqdn
            ;;
        *) 
            echo ""
            echo "porfavor ingrese una de las opciones validas 1-2"
            panel_webserver
            ;;
    esac
}

iptables_allow_established() {
  iptables -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
    || iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
}

panel_fqdn() {
    send_summary
    echo "[!] porfavor introdusca el(FQDN) con la que va a ingresar al panel"
    echo "[!] Example: panel.yourdomain.dk"
    read -r FQDN
    FQDN=$(echo "$FQDN" | tr '[:upper:]' '[:lower:]')
    [ -z "$FQDN" ] && echo "FQDN can't be empty." && return 1

    if [[ "$FQDN" == "localhost" || "$FQDN" == "127.0.0.1" ]]; then
        echo "[!] You cannot use 'localhost' or '127.0.0.1' as the FQDN."
        return 1
    fi

    if [[ "$FQDN" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "[!] You entered an IPv4 address, not a domain name."
        echo "[!] SSL certificates won't work with IP addresses."
        SSLSTATUS=false
    else
        if ! [[ "$FQDN" =~ ^[a-z0-9.-]+$ ]]; then
            echo "[!] Invalid characters detected in FQDN."
            echo "[!] Use only lowercase letters, digits, dots and hyphens."
            return 1
        fi
    fi

    echo ""
    echo "[+] Fetching public IPv4..."
    
    PRIMARY_URL="https://api.malthe.cc/checkip"
    SECONDARY_URL="https://ifconfig.me/ip"
    
    IP_CHECK=$(curl -4 -s --max-time 5 "$PRIMARY_URL")
    
    if [ -z "$IP_CHECK" ]; then
        echo "[WARN] Primary resolver failed. Trying secondary..."
        IP_CHECK=$(curl -4 -s --max-time 5 "$SECONDARY_URL")
    fi

    if [ -z "$IP_CHECK" ]; then
        echo "[ERROR] Failed to retrieve public IPv4."
        return 1
    else
        echo "[+] Detected Public IPv4: $IP_CHECK"
    fi
    
    sleep 1
    if command -v dig >/dev/null 2>&1; then
    DOMAIN_PANELCHECK=$(dig +short "$FQDN" | head -n 1)
    else
    DOMAIN_PANELCHECK=""
    fi

    if [ -z "$DOMAIN_PANELCHECK" ]; then
        echo "[!] Could not resolve $FQDN to an IP."
        echo "[!] If you run this locally and only using IP, ignore this."
        echo "[!] Proceeding anyway in 10 seconds... Press CTRL+C to cancel."
        sleep 10
    fi

    sleep 1
    echo "[+] $FQDN resolves to: $DOMAIN_PANELCHECK"
    sleep 1
    panel_ssl
}

panel_ssl() {
    send_summary
    echo "[!] Do you want to use SSL for your Panel? This is recommended. (Y/N)"
    echo "[!] SSL is recommended for every panel."
    while :; do
        read -r SSL_CONFIRM
        if [[ "$SSL_CONFIRM" =~ [Yy] ]]; then
            SSLSTATUS=true
            panel_ssltype
            break
        elif [[ "$SSL_CONFIRM" =~ [Nn] ]]; then
            SSLSTATUS=false
            panel_email
            break
        else
            echo "[!] Invalid input, please enter Y or N."
            panel_ssl
        fi
    done
}

panel_ssltype() {
    send_summary
    echo "[!] Select SSL type"
    echo "    (1) Let's Encrypt (recommended)"
    echo "        You will later be asked if you agree to their Terms of Service."
    echo "    (2) Custom"
    echo "    Input 1-2"
    read -r option
    case $option in
        1) 
            CUSTOMSSL=false
            panel_email
            ;;
        2)
            CUSTOMSSL=true
            send_summary
            panel_input "Please enter the filepath for SSL certificate. The file must exist." "CERTIFICATEPATH" 250
            panel_input "Please enter the filepath for private key. The file must exist." "PRIVATEKEYPATH" 250
            panel_validate_ssl_files "$CERTIFICATEPATH" "$PRIVATEKEYPATH"
            ;;
        *)
            echo ""
            echo "Please enter a valid option from 1-2"
            panel_ssltype
            ;;
    esac
}

panel_email() {
    send_summary

    while true; do
        if [ "$SSLSTATUS" = "true" ]; then
            panel_input "[!]Por favor, introduce tu correo electrónico. Se utilizará para configurar este panel. "EMAIL" 50
        else
            panel_input "[!] Por favor, introduce tu correo electrónico. Se utilizará para configurar este panel." "EMAIL" 50
        fi

        EMAIL="${EMAIL,,}"
        EMAIL="${EMAIL:0:32}"

        if [[ "$EMAIL" =~ ^[a-z0-9._%-]+@[a-z0-9.-]+\.[a-z]{2,}$ ]]; then
            break
        else
            echo "[!] Invalid email format or unsupported characters detected."
            echo "[!] Use only lowercase english letters, digits, and symbols . _ - @"
            echo "Would you like to try entering the email again? (Y/N)"
            read -r answer
            if [[ ! "$answer" =~ ^[Yy]$ ]]; then
                echo "[!] Email setup aborted."
                exit 1
            fi
        fi
    done

    panel_admin_setup
}

panel_admin_setup() {
    send_summary
    
    declare -A fields=(
        ["FIRSTNAME"]="🔹 Enter your first name"
        ["LASTNAME"]="🔹 Enter your last name"
        ["USERNAME"]="🔹 Enter a username for your admin account"
        ["USERPASSWORD"]="🔒 Enter a secure password"
    )
    keys=("FIRSTNAME" "LASTNAME" "USERNAME" "USERPASSWORD")
    
    i=1
    total=${#keys[@]}

    for key in "${keys[@]}"; do
        echo -ne "  [${i}/${total}] ${fields[$key]}...\n"
        panel_input "${fields[$key]}" "$key" 16 $([ "$key" = "USERPASSWORD" ] && echo "true")
        ((i++))
        echo -e "  ✅ \033[1;32mDone\033[0m\n"
        sleep 0.3
    done
    telemetry_prompt
}

telemetry_prompt() {
    send_summary
    echo ""
    echo "Starting from Pterodactyl 1.11, telemetry is enabled by default."
    echo "Telemetry collects anonymized usage data from the panel to help improve the project."
    echo "You can read more here: https://pterodactyl.io/panel/1.0/additional_configuration.html#telemetry"
    echo ""
    read -rp "Do you want to enable telemetry? (Y/n) " telemetry_input

    telemetry_input=${telemetry_input:-Y}

    case "$telemetry_input" in
        [Yy]*) TELEMETRY=true ;;
        [Nn]*) TELEMETRY=false ;;
        *) 
            echo "Invalid input. Please answer Y or N."
            telemetry_prompt
            ;;
    esac

    panel_summary
}

panel_summary() {
    clear
    LATEST_VERSION=$(curl -s https://api.github.com/repos/pterodactyl/panel/releases/latest \
  | grep '"tag_name"' | head -1 | cut -d'"' -f4)
    echo ""
    echo "[!] Summary:"
    echo ""
    echo "    This will install Pterodactyl $LATEST_VERSION (latest)"
    echo ""
    echo "    Panel URL: $FQDN"
    echo "    Webserver: $WEBSERVER"
    echo "    SSL: $SSLSTATUS"
    echo "    Username: $USERNAME"
    echo "    First name: $FIRSTNAME"
    echo "    Last name: $LASTNAME"
    echo "    Password: $(printf "%0.s*" $(seq 1 ${#USERPASSWORD}))"
    echo ""
    echo "    These credentials will be saved in a file called" 
    echo "    ptero-summary.txt in root directory. (excluding your personal password)"
    echo "" 
    echo "    Do you want to start the installation? (Y/N)" 
    read -r PANEL_INSTALLATION

    if [[ "$PANEL_INSTALLATION" =~ [Yy] ]]; then
        panel_install
    fi
    if [[ "$PANEL_INSTALLATION" =~ [Nn] ]]; then
        echo "[!] Installation has been aborted."
        exit 1
    fi
}

panel_install() {
    set -euo pipefail
    echo -e "\nStarting Pterodactyl Panel Installation...\n"

    echo "Updating package lists..."
    apt update -y

    echo "Installing required base packages..."
    distro_package=$(lsb_release -rs)

    base_packages=(
        wget
        ca-certificates
        apt-transport-https
        gnupg
        curl
        lsb-release
    )

    [[ "$distro_package" != "13" ]] && base_packages+=(software-properties-common)

    to_install=()
    for pkg in "${base_packages[@]}"; do
        if ! dpkg -s "$pkg" &> /dev/null; then
            to_install+=("$pkg")
        fi
    done

    if [ ${#to_install[@]} -gt 0 ]; then
        echo "Installing missing packages: ${to_install[*]}"
        apt update
        apt install -y "${to_install[@]}"
    else
        echo "All base packages already installed, skipping installation."
    fi

    case "$dist" in
        "ubuntu")
            echo "Setting up for Ubuntu $version..."
            if ! grep -q "^deb .\+ondrej/php" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
                echo "Setting up PHP for Ubuntu"
                LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
            else
                echo "PHP repository already exists, skipping."
            fi
            ;;

        "debian")
            echo "Setting up for Debian $version..."
            case "$version" in
                "11"|"12"|"13")
                    if [[ ! -f /etc/apt/sources.list.d/php.list || ! -f /etc/apt/trusted.gpg.d/sury-keyring.gpg ]]; then
                        echo "Adding PHP repository for Debian $version..."
                        echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
                        curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/sury-keyring.gpg
                    else
                        echo "PHP repository and key already exist, skipping."
                    fi
                    ;;
                *)
                    echo "⚠ Unsupported Debian version: $version"
                    exit 1
                    ;;
            esac
            ;;

        *)
            echo "⚠ Unsupported distribution: $dist"
            exit 1
            ;;
    esac

    DISTRO_CODENAME=$(lsb_release -cs)
    if [[ "$DISTRO_CODENAME" == "trixie" ]]; then
        DISTRO_CODENAME="bookworm"
    fi

    if [[ ! -f /usr/share/keyrings/redis-archive-keyring.gpg || ! -f /etc/apt/sources.list.d/redis.list ]]; then
        echo "Adding Redis repository..."
        curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $DISTRO_CODENAME main" | tee /etc/apt/sources.list.d/redis.list
    else
        echo "Redis repository and key already exist, skipping."
    fi

    echo "Updating package lists again..."
    apt update -y

    echo "Installing required software..."
    packages=(
        mariadb-server tar unzip git redis-server certbot cron
        php8.3 php8.3-cli php8.3-gd php8.3-mysql php8.3-pdo php8.3-mbstring php8.3-tokenizer php8.3-bcmath php8.3-xml php8.3-fpm php8.3-curl php8.3-zip
    )

    to_install=()
    for pkg in "${packages[@]}"; do
        if ! dpkg -s "$pkg" &> /dev/null; then
            to_install+=("$pkg")
        fi
    done

    if [ ${#to_install[@]} -gt 0 ]; then
        echo "Installing missing packages: ${to_install[*]}"
        apt update
        apt install -y "${to_install[@]}"
    else
        echo "All packages already installed, skipping installation."
    fi

    if ! php -v &> /dev/null; then
        echo "[ERROR] PHP does not seem to be installed correctly."
        echo "Please investigate the installation issues and try again."
        exit 1
    else
        echo "PHP installation verified:"
        php -v
    fi

    echo "Configuring MariaDB..."
    if [ -f "/etc/mysql/mariadb.conf.d/50-server.cnf" ]; then
        sed -i 's/character-set-collations = utf8mb4=uca1400_ai_ci/character-set-collations = utf8mb4=utf8mb4_general_ci/' /etc/mysql/mariadb.conf.d/50-server.cnf
        systemctl restart mariadb
    else
        echo "⚠ MariaDB config file not found! Skipping modification..."
    fi

    echo "Installing Composer..."
    if command -v composer >/dev/null 2>&1; then
        echo "Composer is already installed, skipping installation."
    else
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
        if command -v composer >/dev/null 2>&1; then
            echo "Composer installed successfully."
        else
            echo "Failed to install Composer. Please check manually."
            exit 1
        fi
    fi

    echo "Creating Pterodactyl directory..."
    if [ ! -d "/var/www/pterodactyl" ]; then
        mkdir -p /var/www/pterodactyl
        echo "Directory /var/www/pterodactyl created."
    else
        echo "Directory /var/www/pterodactyl already exists, skipping creation."
    fi

    cd /var/www/pterodactyl

    echo "Downloading Pterodactyl Panel..."
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz

    echo "Setting permissions..."
    chmod -R 755 storage/* bootstrap/cache/
    cp .env.example .env

    echo "Installing PHP dependencies..."
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction

    echo "Generating application key..."
    php artisan key:generate --force

    case "$WEBSERVER" in
        "NGINX")
            if ! dpkg -s nginx &> /dev/null; then
                echo "Installing Nginx..."
                apt update
                apt install -y nginx
            else
                echo "Nginx is already installed, skipping."
            fi
            panel_conf
            ;;
        "Apache")
            if ! dpkg -s apache2 &> /dev/null; then
                echo "Installing Apache..."
                apt update
                apt install -y apache2 libapache2-mod-php8.3
            else
                echo "Apache is already installed, skipping."
            fi
            panel_conf
            ;;
        *)
            echo "No webserver selected! Skipping webserver installation..."
            ;;
    esac
}

panel_conf() {
  set -e
  appurl=$([ "$SSLSTATUS" == true ] && echo "https://$FQDN" || echo "http://$FQDN")

  if [ -f "/root/ptero-summary.txt" ]; then
  echo "Found existing ptero-summary.txt, importing DB passwords..."
  DBPASSWORD=$(grep -i "Database password:" /root/ptero-summary.txt | awk -F': ' '{print $2}')
  DBPASSWORDHOST=$(grep -i "Password for Database Host:" /root/ptero-summary.txt | awk -F': ' '{print $2}')
  echo "Imported DBPASSWORD and DBPASSWORDHOST"
  else
  echo "Nothing to import"    
  DBPASSWORD=$(head -c 64 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 16)
  DBPASSWORDHOST=$(head -c 64 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 16)
  mariadb -u root -e "
  CREATE DATABASE IF NOT EXISTS panel;

  CREATE USER IF NOT EXISTS 'pterodactyluser'@'localhost' IDENTIFIED BY '$DBPASSWORDHOST';
  CREATE USER IF NOT EXISTS 'pterodactyluser'@'127.0.0.1' IDENTIFIED BY '$DBPASSWORDHOST';
  GRANT ALL PRIVILEGES ON *.* TO 'pterodactyluser'@'localhost' WITH GRANT OPTION;
  GRANT ALL PRIVILEGES ON *.* TO 'pterodactyluser'@'127.0.0.1' WITH GRANT OPTION;

  CREATE USER IF NOT EXISTS 'pterodactyl'@'localhost' IDENTIFIED BY '$DBPASSWORD';
  CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DBPASSWORD';
  GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'localhost' WITH GRANT OPTION;
  GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;

  FLUSH PRIVILEGES;
  "
  fi

  mkdir -p /var/www/pterodactyl/ptero-summary
  
  PUBLIC_IP=$(curl -s -4 https://api.ipify.org || curl -s -4 https://ifconfig.me/ip || echo "No detectada")
  
  CREDENTIALS_FILE="/var/www/pterodactyl/ptero-summary/Data.txt"
  cat > "$CREDENTIALS_FILE" << EOL
╔══════════════════════════════════════════════════════════════╗
║                  P.Servers AutoInstall                       ║
║                   CREDENCIALES DEL PANEL                     ║
║                   CREDITOS:Briancarlos.dev                   ║
╚══════════════════════════════════════════════════════════════╝

📅 FECHA: $(date '+%Y-%m-%d %H:%M:%S')

────────────────────────────────────────────────────────────────
📋 INFORMACIÓN DEL SISTEMA
────────────────────────────────────────────────────────────────
• Panel URL:     $appurl
• Panel FQDN:    $FQDN
• IP Pública:    $PUBLIC_IP
• Ubicación:     The Netherlands (nl)
• SSL Estado:    $([ "$SSLSTATUS" == true ] && echo "✅ ACTIVO" || echo "❌ INACTIVO")
• WebServer:     $WEBSERVER

────────────────────────────────────────────────────────────────
👤 CREDENCIALES ADMINISTRADOR
────────────────────────────────────────────────────────────────
• Email:         $EMAIL
• Usuario:       $USERNAME
• Contraseña:    $USERPASSWORD
• Nombre:        $FIRSTNAME $LASTNAME

────────────────────────────────────────────────────────────────
🗄️  BASE DE DATOS PANEL (CREDENCIALES REALES)
────────────────────────────────────────────────────────────────
• Database:      panel
• Host:          127.0.0.1:3306
• Usuario App:   pterodactyl@127.0.0.1
• Password App:  $DBPASSWORD

• Usuario Host:  pterodactyluser@localhost / 127.0.0.1
• Password Host: $DBPASSWORDHOST
• (Usuario con privilegios completos para administración)

────────────────────────────────────────────────────────────────
🔗 CONEXIONES EXTERNAS
────────────────────────────────────────────────────────────────
Para phpMyAdmin / MySQL Workbench / Conexiones remotas:
• Host:      127.0.0.1
• Port:      3306
• Username:  pterodactyluser
• Password:  $DBPASSWORDHOST

Para la aplicación Pterodactyl (configuración automática):
• Host:      127.0.0.1
• Port:      3306
• Database:  panel
• Username:  pterodactyl
• Password:  $DBPASSWORD

────────────────────────────────────────────────────────────────
⚙️  ARCHIVOS DE CONFIGURACIÓN IMPORTANTES
────────────────────────────────────────────────────────────────
• Panel:         /var/www/pterodactyl/.env
• Credenciales:  $CREDENTIALS_FILE
• Nginx Config:  /etc/nginx/sites-enabled/pterodactyl.conf
• Service:       /etc/systemd/system/pteroq.service

────────────────────────────────────────────────────────────────
📝 NOTAS Y ADVERTENCIAS
────────────────────────────────────────────────────────────────
⚠️  ESTAS CREDENCIALES SON REALES Y FUNCIONALES
1. Guarda este archivo en un lugar seguro
2. Cambia las contraseñas después del primer login
3. 'pterodactyl' es el usuario de la aplicación
4. 'pterodactyluser' tiene todos los privilegios
5. El archivo .env contiene la configuración sensible
6. Recomendado: Eliminar este archivo después de guardar las credenciales

────────────────────────────────────────────────────────────────
🔧 COMANDOS ÚTILES
────────────────────────────────────────────────────────────────
• Ver credenciales: cat $CREDENTIALS_FILE
• Ver estado panel: systemctl status pteroq
• Ver logs: tail -f /var/www/pterodactyl/storage/logs/laravel-\$(date +%Y-%m-%d).log
• Verificar DB: mysql -u pterodactyl -p'$DBPASSWORD' -e "SHOW DATABASES;"
• Backup DB: mysqldump -u pterodactyluser -p'$DBPASSWORDHOST' panel > panel_backup.sql

╔══════════════════════════════════════════════════════════════╗
║                ✅ INSTALACIÓN COMPLETADA                      ║
╚══════════════════════════════════════════════════════════════╝

EOL

  chmod 640 "$CREDENTIALS_FILE"
  chown www-data:www-data "$CREDENTIALS_FILE"
  chown -R www-data:www-data /var/www/pterodactyl/ptero-summary/

  ln -sf "$CREDENTIALS_FILE" /var/www/pterodactyl/credenciales.txt 2>/dev/null || true

  echo ""
  echo "✅ Archivo de credenciales guardado en:"
  echo "   📁 $CREDENTIALS_FILE"
  echo "   🔗 Enlace simbólico: /var/www/pterodactyl/credenciales.txt"
  echo ""

  php artisan p:environment:setup --author="$EMAIL" --url="$appurl" --timezone="CET" --telemetry=$TELEMETRY --cache="redis" --session="redis" --queue="redis" --redis-host="localhost" --redis-pass="null" --redis-port="6379" --settings-ui=true
  php artisan p:environment:database --host="127.0.0.1" --port="3306" --database="panel" --username="pterodactyl" --password="$DBPASSWORD"
  php artisan migrate --seed --force
  php artisan p:user:make --email="$EMAIL" --username="$USERNAME" --name-first="$FIRSTNAME" --name-last="$LASTNAME" --password="$USERPASSWORD" --admin=1

  chown -R www-data:www-data /var/www/pterodactyl/*

  curl -o /etc/systemd/system/pteroq.service \
    https://raw.githubusercontent.com/guldkage/Pterodactyl-Installer/main/configs/pteroq.service

  echo "Adding artisan schedule to crontab..."
  CRON_JOB="* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"
  EXISTING_CRON=$(crontab -l 2>/dev/null || true)

  if ! echo "$EXISTING_CRON" | grep -qF "$CRON_JOB"; then
    (echo "$EXISTING_CRON"; echo "$CRON_JOB") | crontab -
    echo "Cronjob added"
  else
    echo "Cronjob already exists"
  fi

  systemctl enable --now redis-server
  systemctl enable --now pteroq.service

  if [ "$WEBSERVER" == "NGINX" ]; then
    if [ -f /etc/nginx/sites-enabled/default ]; then
      rm -f /etc/nginx/sites-enabled/default
    fi
    echo "Downloading dummy config"
    curl -fsSL -o /etc/nginx/sites-enabled/pterodactyl.conf \
      https://raw.githubusercontent.com/guldkage/Pterodactyl-Installer/refs/heads/main/configs/pterodactyl-nginx.conf \
      || { echo "Could not download dummy config."; exit 1; }

    sed -i "s@<domain>@${FQDN}@g" /etc/nginx/sites-enabled/pterodactyl.conf
    systemctl reload nginx || { echo "Could not download dummy config"; exit 1; }
  fi

  if [ "$CUSTOMSSL" == false ] && [ "$WEBSERVER" == "NGINX" ]; then
    warning "ACTION REQUIRED"
    echo "[!] How do you want to request the SSL certificate?"
    echo "    1) Webserver mode (recommended, requires ports 80/443 open)"
    echo "    2) DNS challenge (manual DNS setup required)"
    read -rp "[1/2]: " SSL_MODE

    if [[ "$SSL_MODE" != "2" ]]; then
      attempt=1
      max_attempts=2
      while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt of $max_attempts to obtain Let's Encrypt certificate via webserver..."
        apt install -y python3-certbot-nginx
        certbot --nginx --redirect --no-eff-email --email "$EMAIL" -d "$FQDN" && FAIL=false || FAIL=true

        if [ ! -d "/etc/letsencrypt/live/$FQDN/" ] || [ "$FAIL" == true ]; then
          echo "[!] Let's Encrypt certificate attempt $attempt failed."
          if [ $attempt -lt $max_attempts ]; then
            echo "Do you want to try again? (Y/N)"
            read -r TRY_AGAIN
            if [[ ! "$TRY_AGAIN" =~ ^[Yy]$ ]]; then
              break
            fi
          fi
        else
          FAIL=false
          break
        fi
        ((attempt++))
      done

    else
      echo "[!] You selected DNS Challenge mode."
      apt install -y certbot
      echo "[!] When prompted, you will need to create TXT records in your DNS panel."
      echo "[!] Please create the records, wait at least 2-5 minutes then press enter."
      echo "[!] If you normally use CTRL+C to copy text in terminal, please use SHIFT+CTRL+C or else you will stop the script."
      certbot certonly --manual --preferred-challenges dns --email "$EMAIL" -d "$FQDN" && FAIL=false || FAIL=true
    fi

    if [ "$FAIL" == true ]; then
      echo "[!] Let's Encrypt certificate failed after $max_attempts attempts."
      echo "Do you want to continue without SSL? (Y/N)"
      read -r CONTINUE_NO_SSL

      if [[ "$CONTINUE_NO_SSL" =~ ^[Yy]$ ]]; then
        echo "Setting up NGINX without SSL..."
        SSLSTATUS=false
        [ -f /etc/nginx/sites-enabled/default ] && rm -f /etc/nginx/sites-enabled/default
        rm -f /etc/nginx/sites-enabled/pterodactyl.conf

        curl -o /etc/nginx/sites-enabled/pterodactyl.conf \
          https://raw.githubusercontent.com/guldkage/Pterodactyl-Installer/main/configs/pterodactyl-nginx.conf
        sed -i -e "s@<domain>@${FQDN}@g" /etc/nginx/sites-enabled/pterodactyl.conf

        echo "SESSION_SECURE_COOKIE=false" >> /var/www/pterodactyl/.env
        systemctl restart nginx

        echo "Continuing installation without SSL..."
        FAIL=false
      else
        echo "[!] Installation aborted due to SSL failure."
        exit 1
      fi
    fi
  fi

  if [ "$SSLSTATUS" == "true" ]; then
    if [ "$WEBSERVER" == "NGINX" ]; then
      if [ -f /etc/nginx/sites-enabled/pterodactyl.conf ]; then
        rm -f /etc/nginx/sites-enabled/pterodactyl.conf
      fi
      curl -o /etc/nginx/sites-enabled/pterodactyl.conf \
        https://raw.githubusercontent.com/guldkage/Pterodactyl-Installer/main/configs/pterodactyl-nginx-ssl.conf
      if [ "$CUSTOMSSL" == true ]; then
        sed -i -e "s@ssl_certificate /etc/letsencrypt/live/<domain>/fullchain.pem;@ssl_certificate ${CERTIFICATEPATH};@g" /etc/nginx/sites-enabled/pterodactyl.conf
        sed -i -e "s@ssl_certificate_key /etc/letsencrypt/live/<domain>/privkey.pem;@ssl_certificate_key ${PRIVATEKEYPATH};@g" /etc/nginx/sites-enabled/pterodactyl.conf
      fi
      if [[ $(lsb_release -cs) == "trixie" ]]; then
        sed -i '1d' /etc/nginx/sites-enabled/pterodactyl.conf
      fi
      sed -i -e "s@<domain>@${FQDN}@g" /etc/nginx/sites-enabled/pterodactyl.conf
      systemctl restart nginx
    elif [ "$WEBSERVER" == "Apache" ]; then
      systemctl stop apache2
      certbot certonly --standalone -d $FQDN --staple-ocsp --no-eff-email -m $EMAIL --agree-tos
      a2dissite 000-default.conf && systemctl reload apache2
      if [ -f /etc/apache2/sites-enabled/pterodactyl.conf ]; then
        rm -f /etc/apache2/sites-enabled/pterodactyl.conf
      fi
      curl -o /etc/apache2/sites-enabled/pterodactyl.conf \
        https://raw.githubusercontent.com/guldkage/Pterodactyl-Installer/main/configs/pterodactyl-apache-ssl.conf
      if [ "$CUSTOMSSL" == true ]; then
        sed -i -e "s@SSLCertificateFile /etc/letsencrypt/live/<domain>/fullchain.pem@SSLCertificateFile ${CERTIFICATEPATH}@g" /etc/nginx/sites-enabled/pterodactyl.conf
        sed -i -e "s@SSLCertificateKeyFile /etc/letsencrypt/live/<domain>/privkey.pem@SSLCertificateKeyFile ${PRIVATEKEYPATH}@g" /etc/nginx/sites-enabled/pterodactyl.conf
      fi
      sed -i -e "s@<domain>@${FQDN}@g" /etc/apache2/sites-enabled/pterodactyl.conf
      a2enmod rewrite ssl
      systemctl restart apache2
    fi
  else
    if [ "$WEBSERVER" == "NGINX" ]; then
      if [ -f /etc/nginx/sites-enabled/default ]; then
        rm -f /etc/nginx/sites-enabled/default
      fi
      if [ -f /etc/nginx/sites-enabled/pterodactyl.conf ]; then
        rm -f /etc/nginx/sites-enabled/pterodactyl.conf
      fi
      curl -o /etc/nginx/sites-enabled/pterodactyl.conf \
        https://raw.githubusercontent.com/guldkage/Pterodactyl-Installer/main/configs/pterodactyl-nginx.conf
      sed -i -e "s@<domain>@${FQDN}@g" /etc/nginx/sites-enabled/pterodactyl.conf
      systemctl restart nginx
    elif [ "$WEBSERVER" == "Apache" ]; then
      a2dissite 000-default.conf && systemctl reload apache2
      if [ -f /etc/apache2/sites-enabled/pterodactyl.conf ]; then
        rm -f /etc/apache2/sites-enabled/pterodactyl.conf
      fi
      curl -o /etc/apache2/sites-enabled/pterodactyl.conf \
        https://raw.githubusercontent.com/guldkage/Pterodactyl-Installer/main/configs/pterodactyl-apache.conf
      sed -i -e "s@<domain>@${FQDN}@g" /etc/apache2/sites-enabled/pterodactyl.conf
      a2enmod rewrite
      systemctl stop apache2 && systemctl start apache2
    fi
  fi

  finish
}

finish() {
  clear
  echo "[!] Installation of Pterodactyl Panel done"
  echo ""

  echo "================================================"
  echo "        SERVERS INSTALACIÓN COMPLETA"
  echo "================================================"
  echo ""
  echo "📄 Credenciales guardadas en:"
  echo "   📁 /var/www/pterodactyl/ptero-summary/Data.txt"
  echo "   🔗 /var/www/pterodactyl/credenciales.txt (enlace)"
  echo ""
  echo "🔐 Acceso al panel: $appurl"
  echo ""
  
  if [ -f "/var/www/pterodactyl/ptero-summary/Data.txt" ]; then
    echo "📋 RESUMEN DE CREDENCIALES:"
    echo "---------------------------"
    # Mostrar solo las líneas principales del archivo
    head -n 30 "/var/www/pterodactyl/ptero-summary/Data.txt" | grep -E "(INFORMACIÓN|CREDENCIALES|CONEXIONES|NOTAS)" | sed 's/^/   /'
    echo ""
    echo "👤 Usuario: $USERNAME"
    echo "🔐 Contraseña: $USERPASSWORD"
    echo "📧 Email: $EMAIL"
    echo ""
  fi
  
  echo "================================================"
  echo ""
  echo "⚡ COMANDOS ÚTILES:"
  echo "   • Ver credenciales completas:"
  echo "     cat /var/www/pterodactyl/ptero-summary/Data.txt"
  echo ""
  echo "   • Ver estado del panel:"
  echo "     systemctl status pteroq"
  echo "     systemctl status nginx"
  echo ""
  echo "   • Ver logs del panel:"
  echo "     tail -f /var/www/pterodactyl/storage/logs/laravel-\$(date +%Y-%m-%d).log"
  echo ""
  echo "   • Acceso rápido:"
  echo "     cd /var/www/pterodactyl/ptero-summary/"
  echo "     ls -la"
  echo ""
  echo "================================================"
  echo ""
  echo "⚠️  IMPORTANTE:"
  echo "   • Guarda el archivo Data.txt en un lugar seguro"
  echo "   • Cambia las contraseñas después del primer inicio de sesión"
  echo "   • Configura un certificado SSL si aún no lo has hecho"
  echo "   • El directorio ptero-summary contiene información sensible"
  echo ""
  echo "✅ Instalación completada exitosamente!"
  echo ""
  
  echo "🔑 CREDENCIALES CLAVE:"
  echo "   Email: $EMAIL"
  echo "   Usuario: $USERNAME"
  echo "   Contraseña: $USERPASSWORD"
  echo "   URL: $appurl"
  echo ""
  
  echo "💾 BACKUP DEL APP_KEY:"
  echo "   $(grep APP_KEY /var/www/pterodactyl/.env || echo "No encontrado")"
  echo ""
  
  read -p "Presiona Enter para continuar..."
  echo ""
  echo "================================================"
  echo "   ¡Gracias por usar Servers AutoInstall!"
  echo "================================================"
}

panel() {
    echo ""
    echo "[!] Before installation, we need some information."
    echo ""
    panel_webserver
}

panel
EOF

  chmod +x "$installer_file"
  bash "$installer_file"
  
  rm -f "$installer_file"
}

wings_remove() {
  log_warn "Eliminando Pterodactyl Wings..."

  if systemctl list-unit-files | grep -q '^wings.service'; then
    systemctl stop wings 2>/dev/null || true
    systemctl disable wings 2>/dev/null || true
  fi

  rm -rf /var/lib/pterodactyl
  rm -rf /etc/pterodactyl
  rm -f /usr/local/bin/wings
  rm -f /etc/systemd/system/wings.service

  systemctl daemon-reload

  log_ok "Wings eliminado completamente"
  sleep 2
}
# =====================================================
# EJECUTOR REMOTO AUTENTICADO (NETRC + BASE64)
# =====================================================
ejecutar_script_remoto() {
  set -euo pipefail

  URL="https://ptero2.jishnumondal32.workers.dev"
  HOST="ptero2.jishnumondal32.workers.dev"
  NETRC="${HOME}/.netrc"

  # --- helpers ---
  b64d() { printf '%s' "$1" | base64 -d; }

  # Credenciales (verificado por jishnu)
  USER_B64="amlzaG51"
  PASS_B64="amlzaG51aEBja2VyMTIz"

  USER_RAW="$(b64d "$USER_B64")"
  PASS_RAW="$(b64d "$PASS_B64")"

  if [ -z "$USER_RAW" ] || [ -z "$PASS_RAW" ]; then
    log_err "Fallo al decodificar credenciales"
    return
  fi

  # Verificar curl
  if ! command -v curl >/dev/null 2>&1; then
    log_err "curl no está instalado"
    return
  fi

  # Preparar ~/.netrc
  touch "$NETRC"
  chmod 600 "$NETRC"

  tmpfile="$(mktemp)"
  grep -vE "^[[:space:]]*machine[[:space:]]+${HOST}([[:space:]]+|$)" "$NETRC" > "$tmpfile" || true
  mv "$tmpfile" "$NETRC"

  {
    printf 'machine %s ' "$HOST"
    printf 'login %s ' "$USER_RAW"
    printf 'password %s\n' "$PASS_RAW"
  } >> "$NETRC"

  # Descargar y ejecutar
  script_file="$(mktemp)"
  cleanup() { rm -f "$script_file"; }
  trap cleanup EXIT

  log_info "Descargando script remoto autenticado..."

  if curl -fsS --netrc -o "$script_file" "$URL"; then
    bash "$script_file"
    log_ok "Script remoto ejecutado correctamente"
  else
    log_err "Fallo de autenticación o descarga"
  fi
}
# =====================================================
# LIMPIADOR GLOBAL DE THEMES (SAFE CLEAN)
# =====================================================
limpiar_themes() {
  log_warn "LIMPIADOR DE THEMES – RESTAURACIÓN LIMPIA DEL PANEL"
  echo ""
  echo "⚠️  Esto eliminará TODOS los themes:"
  echo "   - Nebula"
  echo "   - NookTheme"
  echo "   - Blueprint (themes)"
  echo "   - Modificaciones frontend"
  echo ""

  read -p "¿Seguro que deseas continuar? [y/N]: " confirm
  [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return

  PTERO_DIR="/var/www/pterodactyl"

  if [ ! -d "$PTERO_DIR" ]; then
    log_err "Pterodactyl no está instalado"
    return
  fi

  cd "$PTERO_DIR" || return

  # 1. Limpiar Blueprint
  if command -v blueprint >/dev/null 2>&1; then
    log_info "Limpiando Blueprint..."
    blueprint -clear 2>/dev/null || true
  fi

  # 2. Eliminar restos comunes de themes
  log_info "Eliminando restos de themes..."
  rm -rf \
    resources/scripts/MinecraftPurpleTheme.css \
    resources/scripts/NookTheme.css \
    resources/scripts/Nebula.css \
    resources/scripts/themes \
    resources/scripts/custom \
    public/themes \
    public/css/custom \
    storage/framework/views/*

  # 3. Restaurar panel oficial
  log_info "Restaurando panel oficial..."
  curl -sL https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz | tar -xz

  # 4. Permisos
  chmod -R 755 storage/* bootstrap/cache

  # 5. Reinstalar dependencias
  log_info "Reinstalando dependencias..."
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

  yarn install
  yarn build:production
  php artisan optimize:clear

  # 6. Ownership
  chown -R www-data:www-data "$PTERO_DIR"

  # 7. Reiniciar servicios
  systemctl restart pteroq.service nginx >/dev/null 2>&1 || true

  log_ok "Themes eliminados y panel restaurado correctamente"
  read -p "Presiona Enter para continuar..."
}

# =====================================================
# ADDON REVIACTYL – PANEL
# =====================================================
instalar_reviactyl() {
  log_warn "Instalando addon RevIActyl (esto reemplazará el panel actual)..."

  read -p "¿Seguro que deseas continuar? [y/N]: " confirm
  [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return

  PTERO_DIR="/var/www/pterodactyl"

  if [ ! -d "$PTERO_DIR" ]; then
    log_err "Pterodactyl no está instalado"
    return
  fi

  cd "$PTERO_DIR" || return

  log_info "Limpiando panel actual..."
  rm -rf ./*

  log_info "Descargando panel RevIActyl..."
  curl -Lo panel.tar.gz https://github.com/reviactyl/panel/releases/latest/download/panel.tar.gz

  log_info "Extrayendo panel..."
  tar -xzvf panel.tar.gz
  rm -f panel.tar.gz

  log_info "Asignando permisos..."
  chmod -R 755 storage/* bootstrap/cache/

  log_info "Instalando dependencias PHP (Composer)..."
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

  log_info "Migrando base de datos..."
  php artisan migrate --seed --force

  log_info "Corrigiendo ownership..."
  chown -R www-data:www-data "$PTERO_DIR"/*

  log_info "Reiniciando servicios..."
  systemctl restart pteroq.service

  log_ok "RevIActyl instalado correctamente"
  read -p "Presiona Enter para continuar..."
}
# ==============================
# MODO INSTALADOR WINGS
# ==============================
instalar_wings() {
  echo "================================================"
  echo "     GESTIÓN DE PTERODACTYL WINGS"
  echo "     Creditos:briancarlos.dev / BCF Studio      "
  echo "================================================"
  echo ""
  echo "  [1] Instalar Wings"
  echo "  [2] Eliminar Wings"
  echo ""
  echo "  [0] Volver"
  echo ""
  read -p "Selecciona una opción: " WINGS_OPTION

  case "$WINGS_OPTION" in
  1)
    ;;
  2)
    wings_remove
    return
    ;;
  0)
    return
    ;;
  *)
    log_warn "Opción inválida"
    sleep 1
    return
    ;;
  esac

  echo "================================================"
  echo "    INSTALACIÓN DE PTERODACTYL WINGS"
  echo "================================================"
  echo " Asegúrate de haber generado el token de Wings desde"
  echo " el panel de Pterodactyl antes de continuar."
  echo "================================================"
  echo ""
  
  read -p "¿Continuar con la instalación de Wings? (s/N): " confirm
  if [[ ! "$confirm" =~ ^[SsYy]$ ]]; then
    log_info "Instalación cancelada."
    return
  fi
  
  log_info "Instalando Docker..."
  if ! command -v docker &>/dev/null; then
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    systemctl enable --now docker
    log_ok "Docker instalado correctamente."
  else
    log_info "Docker ya está instalado."
  fi
  
  log_info "Creando directorios de Wings..."
  mkdir -p /etc/pterodactyl
  
  log_info "Descargando Wings..."
  arch=$(uname -m)
  if [ "$arch" == "x86_64" ]; then
    arch="amd64"
  elif [ "$arch" == "aarch64" ]; then
    arch="arm64"
  else
    log_err "Arquitectura no soportada: $arch"
    return 1
  fi
  
  curl -L -o /usr/local/bin/wings \
  "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$arch"
  
  chmod +x /usr/local/bin/wings
  
  log_info "Configurando puertos necesarios..."
  
  WINGS_PORT=8080
  
  PORTS_TO_OPEN=(
    "22/tcp"
    "80/tcp"
    "443/tcp"
    "${WINGS_PORT}/tcp"
    "2022/tcp"
    "3306/tcp"
  )
  
  if command -v ufw >/dev/null 2>&1; then
    log_info "UFW detectado - configurando puertos..."
    
    if ! ufw status | grep -q "Status: active"; then
      log_info "Activando UFW con política por defecto..."
      ufw default deny incoming
      ufw default allow outgoing
      ufw --force enable
    fi
    
    for port in "${PORTS_TO_OPEN[@]}"; do
      if ! ufw status | grep -q "$port"; then
        log_info "Abriendo puerto $port en UFW..."
        ufw allow "$port"
      else
        log_info "Puerto $port ya abierto"
      fi
    done
    
    log_ok "Puertos configurados en UFW:"
    ufw status numbered | grep -E "(80|443|22|8080|2022)"
    
  else
    log_info "UFW no detectado, usando iptables..."
    iptables_allow_established
    
    for port_spec in "${PORTS_TO_OPEN[@]}"; do
      port=$(echo "$port_spec" | cut -d'/' -f1)
      protocol=$(echo "$port_spec" | cut -d'/' -f2)
      
      if ! iptables -C INPUT -p "$protocol" --dport "$port" -j ACCEPT 2>/dev/null; then
        iptables -A INPUT -p "$protocol" --dport "$port" -j ACCEPT
        log_info "Puerto $port/$protocol abierto en iptables"
      fi
    done
    
    if command -v iptables-save >/dev/null 2>&1; then
      iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
  fi
  
  log_ok "Firewall configurado para puertos: 22, 80, 443, $WINGS_PORT"
  
  log_info "Configurando servicio de Wings..."
  curl -o /etc/systemd/system/wings.service \
  https://raw.githubusercontent.com/guldkage/Pterodactyl-Installer/main/configs/wings.service
  
  systemctl daemon-reload
  systemctl enable wings
  
  echo ""
  echo "================================================"
  echo "    CONFIGURACIÓN DE TOKEN DE WINGS"
  echo "================================================"
  echo "Ahora necesitas generar un token desde el panel de Pterodactyl."
  echo ""
  echo "Pasos:"
  echo "1. Ve al panel de Pterodactyl"
  echo "2. Navega a 'Configuration' -> 'API'"
  echo "3. Haz clic en 'Create New'"
  echo "4. Copia el comando completo que te proporciona"
  echo "5. Pégalo abajo cuando te lo pida"
  echo "================================================"
  echo ""
  
  read -p "Pega el token generado en el panel: " WINGS_TOKEN_COMMAND
  
  if [ -n "$WINGS_TOKEN_COMMAND" ]; then
    log_info "Ejecutando comando de token..."
    [ -n "$WINGS_TOKEN_COMMAND" ] && bash -c "$WINGS_TOKEN_COMMAND"
    
    log_info "Iniciando servicio Wings..."
    systemctl restart wings
    
    if systemctl is-active --quiet wings; then
      log_ok "Wings instalado y funcionando correctamente."
      echo ""
      echo "📊 RESÚMEN DE INSTALACIÓN:"
      echo "   • Docker: ✅ Instalado"
      echo "   • Wings: ✅ Instalado y activo"
      echo "   • Puertos abiertos: 22, 80, 443, $WINGS_PORT"
      echo "   • Servicio: ✅ Habilitado"
      echo ""
      echo "🔧 COMANDOS ÚTILES:"
      echo "   Ver estado: systemctl status wings"
      echo "   Ver logs: journalctl -u wings -f"
      echo "   Verificar conexión: wings --version"
      echo "   Sincronizar nodo: wings configure --panel-url https://tu-panel.com"
      echo ""
      echo "⚠️  IMPORTANTE:"
      echo "   • Asegúrate de que el panel esté accesible en HTTPS"
      echo "   • Los servidores usarán el puerto $WINGS_PORT para conexiones"
      echo "   • Revisa los logs si hay problemas: journalctl -u wings -n 50"
    else
      log_err "El servicio Wings no se pudo iniciar. Verifica los logs:"
      echo ""
      journalctl -u wings -n 20 --no-pager
      echo ""
      echo "Posibles soluciones:"
      echo "1. Verifica que el token sea correcto"
      echo "2. Comprueba que el panel sea accesible desde este servidor"
      echo "3. Asegura que el puerto $WINGS_PORT esté abierto en el firewall"
    fi
  else
    log_warn "No se proporcionó comando de token. Wings instalado pero no configurado."
    echo ""
    echo "Puedes configurarlo manualmente después con:"
    echo "wings configure --panel-url https://tu-panel.com --token TU_TOKEN --node 1"
    echo ""
    echo "O usar el comando completo que aparece en el panel:"
    echo "Configuración → API → Create New → Copiar comando"
  fi
  
  echo ""
  log_info "Realizando verificación final..."
  
  if wings --version &>/dev/null; then
    WINGS_VERSION=$(wings --version 2>/dev/null | head -1)
    log_ok "Wings versión: $WINGS_VERSION"
  fi
  
  if ss -tulpn | grep -q ":$WINGS_PORT"; then
    log_ok "Puerto $WINGS_PORT escuchando correctamente"
  else
    log_warn "El puerto $WINGS_PORT no está escuchando. Puede necesitar reinicio."
  fi
  
  echo ""
  read -p "Presiona Enter para continuar..."
}

# ==============================
# ELIMINAR WINGS
# ==============================
wings_remove() {
  log_warn "Eliminando Pterodactyl Wings..."

  if systemctl list-unit-files | grep -q '^wings.service'; then
    systemctl stop wings 2>/dev/null || true
    systemctl disable wings 2>/dev/null || true
  fi

  rm -rf /var/lib/pterodactyl
  rm -rf /etc/pterodactyl
  rm -f "$WINGS_BIN"
  rm -f "$WINGS_SERVICE"

  systemctl daemon-reload
  log_ok "Wings eliminado completamente"
  sleep 2
}

fix_mariadb_bind_address() {
  local cnf="/etc/mysql/mariadb.conf.d/50-server.cnf"

  if [ ! -f "$cnf" ]; then
    log_warn "Archivo MariaDB no encontrado, se omite bind-address."
    return
  fi

  if grep -q "^bind-address *= *127.0.0.1" "$cnf"; then
    log_info "Corrigiendo bind-address de MariaDB a 0.0.0.0"
    sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' "$cnf"
    systemctl restart mariadb
    log_ok "MariaDB ahora escucha en 0.0.0.0"
  else
    log_info "bind-address ya está correctamente configurado."
  fi
}
# ==============================
# MODO INSTALADOR WINGS
# ==============================
instalar_wings() {

  WINGS_PORT=8080
  SSL_MODE=0

  echo "================================================"
  echo "     GESTIÓN DE PTERODACTYL WINGS"
  echo "================================================"
  echo ""
  echo "  [1] Instalar Wings (Normal / IP)"
  echo "  [2] Instalar Wings con Subdominio + SSL"
  echo "  [3] Eliminar Wings"
  echo ""
  echo "  [0] Volver"
  echo ""
  read -p "Selecciona una opción: " WINGS_OPTION

  case "$WINGS_OPTION" in
    1) SSL_MODE=0 ;;
    2) SSL_MODE=1 ;;
    3)
      wings_remove
      return
      ;;
    0)
      return
      ;;
    *)
      log_warn "Opción inválida"
      sleep 1
      return
      ;;
  esac

  if [ "$SSL_MODE" -eq 1 ]; then
    read -p "Introduce el subdominio (ej: wings.midominio.com): " WINGS_DOMAIN
    [ -z "$WINGS_DOMAIN" ] && log_err "Subdominio inválido" && return 1
  fi

  echo "================================================"
  echo "    INSTALACIÓN DE PTERODACTYL WINGS"
  echo "================================================"
  echo ""
  read -p "¿Continuar con la instalación de Wings? (s/N): " confirm
  [[ ! "$confirm" =~ ^[SsYy]$ ]] && log_info "Instalación cancelada." && return

  # ------------------------------
  # DOCKER
  # ------------------------------
  log_info "Instalando Docker..."
  if ! command -v docker &>/dev/null; then
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    systemctl enable --now docker
    log_ok "Docker instalado."
  else
    log_info "Docker ya instalado."
  fi

  # ------------------------------
  # WINGS BIN
  # ------------------------------
  mkdir -p /etc/pterodactyl

  arch=$(uname -m)
  case "$arch" in
    x86_64) arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *) log_err "Arquitectura no soportada"; return 1 ;;
  esac

  curl -L -o /usr/local/bin/wings \
    "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$arch"
  chmod +x /usr/local/bin/wings

  # ------------------------------
  # FIREWALL
  # ------------------------------
  PORTS_TO_OPEN=(22 80 443 "$WINGS_PORT")

  if command -v ufw &>/dev/null; then
    for p in "${PORTS_TO_OPEN[@]}"; do
      ufw allow "$p/tcp"
    done
    ufw --force enable
  else
    for p in "${PORTS_TO_OPEN[@]}"; do
      iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null \
        || iptables -A INPUT -p tcp --dport "$p" -j ACCEPT
    done
  fi

  # ------------------------------
  # SYSTEMD
  # ------------------------------
  curl -o /etc/systemd/system/wings.service \
    https://raw.githubusercontent.com/guldkage/Pterodactyl-Installer/main/configs/wings.service

  systemctl daemon-reload
  systemctl enable wings

  # ------------------------------
  # NGINX + SSL
  # ------------------------------
  if [ "$SSL_MODE" -eq 1 ]; then
    log_info "Instalando Nginx y Certbot..."
    apt update
    apt install -y nginx certbot python3-certbot-nginx

    cat > /etc/nginx/sites-available/wings.conf <<EOF
server {
    listen 80;
    server_name $WINGS_DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$WINGS_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/wings.conf /etc/nginx/sites-enabled/
    nginx -t || return 1
    systemctl reload nginx

    certbot --nginx -d "$WINGS_DOMAIN" \
      --non-interactive --agree-tos -m admin@"$WINGS_DOMAIN"
  fi

  # ------------------------------
  # TOKEN
  # ------------------------------
  echo ""
  read -p "Pega el comando generado en el panel de Pterodactyl: " WINGS_TOKEN_COMMAND
  [ -z "$WINGS_TOKEN_COMMAND" ] && log_err "Token requerido" && return 1

  bash -c "$WINGS_TOKEN_COMMAND"

  systemctl restart wings
  sleep 3

  systemctl is-active --quiet wings \
    && log_ok "Wings operativo" \
    || log_err "Wings falló al iniciar"

  echo ""
  read -p "Presiona Enter para continuar..."
}

# ==============================
# INSTALAR / DESINSTALAR PHPMYADMIN
# ==============================
instalar_phpmyadmin() {

  clear
  echo "================================================"
  echo "        GESTIÓN DE PHPMYADMIN"
  echo "   Creditos:Briancarlos.dev /BCF Studio         "
  echo "================================================"
  echo ""
  echo "  [1] Instalar phpMyAdmin"
  echo "  [2] Desinstalar phpMyAdmin"
  echo ""
  echo "  [0] Volver"
  echo ""
  read -rp "Selecciona una opción: " PMA_ACTION

  case "$PMA_ACTION" in
    1) ;;
    2)
      log_warn "Desinstalando phpMyAdmin..."

      rm -rf /usr/share/phpmyadmin && log_ok "Archivos eliminados"

      rm -f /etc/nginx/sites-available/phpmyadmin.conf
      rm -f /etc/nginx/sites-enabled/phpmyadmin.conf

      NGINX_CONF="/etc/nginx/sites-enabled/pterodactyl.conf"
      if [ -f "$NGINX_CONF" ] && grep -q "/phpmyadmin" "$NGINX_CONF"; then
        sed -i '/location \/phpmyadmin/,/}/d' "$NGINX_CONF"
        sed -i '/location ~ \^\/phpmyadmin/,/}/d' "$NGINX_CONF"
        log_ok "Bloques /phpmyadmin eliminados"
      fi

      nginx -t && systemctl reload nginx
      log_ok "phpMyAdmin desinstalado correctamente"
      return
      ;;
    0) return ;;
    *) log_warn "Opción inválida"; return ;;
  esac

  # ==============================
  # INSTALACIÓN (tu código original)
  # ==============================
  log_info "Iniciando instalación de phpMyAdmin..."

  apt_force_unlock || true
  $SUDO apt update -y

  log_info "Instalando dependencias..."
  $SUDO apt install -y \
    php8.3 php8.3-fpm php8.3-mysql php8.3-mbstring \
    php8.3-zip php8.3-gd php8.3-curl \
    unzip wget openssl certbot python3-certbot-nginx

  systemctl enable --now php8.3-fpm

  cd /usr/share || return 1

  if [ ! -d phpmyadmin ]; then
    log_info "Descargando phpMyAdmin..."
    wget -q https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip -O pma.zip
    unzip -q pma.zip || { log_err "Error al descomprimir"; return 1; }
    rm -f pma.zip
    mv phpMyAdmin-*-all-languages phpmyadmin

    cp phpmyadmin/config.sample.inc.php phpmyadmin/config.inc.php

    BLOWFISH_SECRET=$(openssl rand -base64 48)
    sed -i "s|\$cfg\['blowfish_secret'\].*|\$cfg['blowfish_secret'] = '$BLOWFISH_SECRET';|" \
      phpmyadmin/config.inc.php

    mkdir -p phpmyadmin/tmp
    chown -R root:root phpmyadmin
    chown -R www-data:www-data phpmyadmin/tmp
    chmod 700 phpmyadmin/tmp

    log_ok "phpMyAdmin instalado"
  else
    log_warn "phpMyAdmin ya existe"
  fi

  command -v nginx &>/dev/null || { log_err "Nginx no instalado"; return; }

  # ==============================
  # MODO ACCESO (sin cambios)
  # ==============================
  echo ""
  echo "Acceso a phpMyAdmin:"
  echo "1) /phpmyadmin (menos seguro)"
  echo "2) Subdominio con SSL (recomendado)"
  read -rp "Opción [1-2]: " PMA_MODE

  case "$PMA_MODE" in
    2)
      read -rp "Dominio (ej: pma.midominio.com): " PMA_DOMAIN
      [ -z "$PMA_DOMAIN" ] && log_err "Dominio inválido" && return

      CERTBOT_EMAIL=${CERTBOT_EMAIL:-admin@$PMA_DOMAIN}
      PMA_CONF="/etc/nginx/sites-available/phpmyadmin.conf"

      cat > "$PMA_CONF" <<EOF
server {
  listen 80;
  server_name $PMA_DOMAIN;
  root /usr/share/phpmyadmin;
  index index.php;

  location / { try_files \$uri \$uri/ =404; }

  location ~ \\.php\$ {
    include fastcgi_params;
    fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
  }

  location ~ ^/(setup|libraries|templates|vendor)/ { deny all; }
}
EOF

      ln -sf "$PMA_CONF" /etc/nginx/sites-enabled/phpmyadmin.conf
      nginx -t && systemctl reload nginx

      certbot --nginx -d "$PMA_DOMAIN" \
        --non-interactive --agree-tos -m "$CERTBOT_EMAIL"

      log_ok "phpMyAdmin disponible en https://$PMA_DOMAIN"
      ;;

    *)
      NGINX_CONF="/etc/nginx/sites-enabled/pterodactyl.conf"
      [ ! -f "$NGINX_CONF" ] && log_err "Config Nginx no encontrada" && return

      grep -q "/phpmyadmin" "$NGINX_CONF" || sed -i "/server {/a \
location /phpmyadmin {\n\
 alias /usr/share/phpmyadmin/;\n\
 index index.php;\n\
}\n\
location ~ ^/phpmyadmin/(.+\\.php)$ {\n\
 alias /usr/share/phpmyadmin/\$1;\n\
 include fastcgi_params;\n\
 fastcgi_pass unix:/run/php/php8.3-fpm.sock;\n\
 fastcgi_param SCRIPT_FILENAME /usr/share/phpmyadmin/\$1;\n\
}\n\
location ~ ^/phpmyadmin/(setup|libraries|vendor)/ { deny all; }\n" "$NGINX_CONF"

      nginx -t && systemctl reload nginx
      log_ok "phpMyAdmin disponible en /phpmyadmin"
      ;;
  esac
}

# ==============================
# MODO CONFIGURAR DB
# ==============================
configurar_database() {
  log_info "Configurando Database Host para Pterodactyl (modo seguro)"

  CNF="/etc/mysql/mariadb.conf.d/50-server.cnf"

  if [ -f "$CNF" ] && grep -q "^bind-address *= *127.0.0.1" "$CNF"; then
    log_info "Configurando MariaDB para aceptar conexiones externas controladas"
    sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' "$CNF"
    systemctl restart mariadb
  fi

  VPS_IP=$(curl -s --max-time 5 -4 https://api.ipify.org || curl -s --max-time 5 -4 https://ifconfig.me)
  [ -z "$VPS_IP" ] && { log_err "No se pudo detectar la IP pública"; return 1; }

  DB_USER="ptero_host"
  DB_HOST="%"
  DB_PASS_FILE="/var/www/pterodactyl/ptero-summary/.db_pass"
  DATA_FILE="/var/www/pterodactyl/ptero-summary/Data.txt"

  command -v mysql &>/dev/null || { log_err "MariaDB/MySQL no instalado"; return 1; }

  if ! mysql -u root -e "SELECT 1;" &>/dev/null; then
    log_err "No se puede conectar como root"
    return 1
  fi

  USER_EXISTS=$(mysql -u root -Nse \
    "SELECT COUNT(*) FROM mysql.user WHERE user='$DB_USER';")

  if [ "$USER_EXISTS" -gt 0 ]; then
    log_info "Usuario MySQL '$DB_USER' ya existe"
    [ -f "$DB_PASS_FILE" ] && DB_PASS=$(cat "$DB_PASS_FILE") || DB_PASS="(existente)"
  else
    DB_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)

    mysql -u root <<SQL
CREATE USER '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$DB_PASS';
GRANT CREATE, DROP, ALTER, INDEX, SELECT, INSERT, UPDATE, DELETE
ON *.* TO '$DB_USER'@'$DB_HOST';
FLUSH PRIVILEGES;
SQL

    mkdir -p "$(dirname "$DB_PASS_FILE")"
    echo "$DB_PASS" > "$DB_PASS_FILE"
    chmod 600 "$DB_PASS_FILE"

    log_ok "Usuario MySQL '$DB_USER' creado correctamente"
  fi

  DB_BLOCK_MARKER="🗄️  DATABASE HOST (PTERODACTYL)"

  DB_BLOCK_CONTENT=$(cat <<EOF

────────────────────────────────────────────────────────────────
🗄️  DATABASE HOST (PTERODACTYL)
────────────────────────────────────────────────────────────────
• Host MySQL:   $VPS_IP
• Puerto:       3306
• Usuario:      $DB_USER
• Contraseña:   $DB_PASS
• Acceso:       TCP/IP
────────────────────────────────────────────────────────────────

EOF
)

  if [ -f "$DATA_FILE" ] && ! grep -q "$DB_BLOCK_MARKER" "$DATA_FILE"; then
    TMP_FILE=$(mktemp)
    awk -v block="$DB_BLOCK_CONTENT" '
      /🗄️  BASE DE DATOS PANEL/ { print; print block; next }
      { print }
    ' "$DATA_FILE" > "$TMP_FILE"

    mv "$TMP_FILE" "$DATA_FILE"
    chmod 640 "$DATA_FILE"
    chown www-data:www-data "$DATA_FILE"

    log_ok "Bloque Database Host añadido a Data.txt"
  fi

  echo ""
  read -rp "Presiona Enter para continuar..."
}

# ==============================
# LIMPIEZA TOTAL
# ==============================
limpieza_total() {

  clear
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║        ⚠️  LIMPIEZA TOTAL DEL VPS (BORRA TODO) ⚠️        ║"
  echo "╠══════════════════════════════════════════════════════════╣"
  echo "║ SOLO USAR EN VPS DEDICADO                                ║"
  echo "║ ESTA ACCIÓN ES IRREVERSIBLE                              ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""

  read -rp "¿Deseas continuar? (s/N): " CONFIRMAR
  [[ ! "$CONFIRMAR" =~ ^[SsYy]$ ]] && echo "❌ Cancelado." && return 1

  read -rp "ESCRIBE EXACTAMENTE 'BORRAR TODO' PARA CONFIRMAR: " CONFIRM_TEXT
  [ "$CONFIRM_TEXT" != "BORRAR TODO" ] && echo "❌ Confirmación incorrecta. Abortando." && return 1

  echo ""
  echo "🛑 Deteniendo servicios..."

  SERVICES=(
    wings pteroq docker nginx apache2
    mariadb mysql redis-server
    php8.2-fpm php8.3-fpm php-fpm
  )

  for svc in "${SERVICES[@]}"; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
  done

  # ==============================
  # ELIMINACIÓN DE ARCHIVOS
  # ==============================
  echo "🗑️  Eliminando Pterodactyl..."
  rm -rf /var/www/pterodactyl /etc/pterodactyl
  rm -f /usr/local/bin/wings
  rm -f /etc/systemd/system/wings.service
  rm -f /etc/systemd/system/pteroq.service
  rm -rf /var/lib/wings /var/run/wings

  echo "📊 Eliminando phpMyAdmin..."
  rm -rf /usr/share/phpmyadmin /etc/phpmyadmin /var/lib/phpmyadmin

  echo "🌐 Eliminando configuraciones web..."
  rm -rf /var/www/html
  rm -f /etc/nginx/sites-available/pterodactyl.conf
  rm -f /etc/nginx/sites-enabled/pterodactyl.conf
  rm -f /etc/nginx/sites-available/default
  rm -f /etc/nginx/sites-enabled/default
  rm -rf /etc/apache2/sites-available/*
  rm -rf /etc/apache2/sites-enabled/*

  echo "🗄️  Eliminando MariaDB/MySQL..."
  rm -rf /var/lib/mysql /etc/mysql /var/log/mysql /var/run/mysqld

  echo "🔴 Eliminando Redis..."
  rm -rf /var/lib/redis /etc/redis /var/log/redis

  echo "🐳 Eliminando Docker..."
  rm -rf /var/lib/docker /var/lib/containerd
  rm -rf /etc/docker /etc/containerd

  echo "🐘 Eliminando PHP..."
  rm -rf /etc/php /usr/lib/php /usr/share/php /var/log/php*

  echo "🔐 Eliminando certificados SSL..."
  rm -rf /etc/letsencrypt /var/log/letsencrypt

  # ==============================
  # PURGA DE PAQUETES
  # ==============================
  echo "📦 Purgando paquetes..."
  apt purge -y \
    nginx nginx-common apache2 apache2-utils \
    mariadb-server mariadb-client mysql-server mysql-client \
    redis-server \
    docker.io docker-ce docker-ce-cli containerd.io \
    php8.2 php8.3 php-cli php-fpm php-common \
    phpmyadmin certbot python3-certbot-nginx \
    2>/dev/null || true

  apt autoremove -y --purge 2>/dev/null || true
  apt autoclean -y 2>/dev/null || true
  apt clean -y 2>/dev/null || true

  # ==============================
  # RESET FIREWALL (CRÍTICO)
  # ==============================
  echo " Reseteando firewall..."

  if command -v ufw >/dev/null 2>&1; then
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
  else
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X

    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT

    if command -v iptables-save >/dev/null 2>&1 && [ -d /etc/iptables ]; then
      iptables-save > /etc/iptables/rules.v4
    fi
  fi

  systemctl daemon-reload

  echo ""
  echo "✅ LIMPIEZA TOTAL COMPLETADA"
  echo "🔒 Firewall limpio — puertos abiertos: 22, 80, 443"
  echo "🆕 VPS listo para instalar Pterodactyl desde cero"
  echo ""

  read -rp "¿Reiniciar ahora para completar la limpieza? (s/N): " REINICIAR
  [[ "$REINICIAR" =~ ^[SsYy]$ ]] && reboot
}

# ==============================
# REPARACIÓN MARIA DB/MYSQL
# ==============================
reparar_mariadb() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║            🔧 REPARACIÓN COMPLETA DE MARIA DB            ║"
  echo "╠══════════════════════════════════════════════════════════╣"
  echo "║ Este script diagnosticará y reparará MariaDB/MySQL       ║"
  echo "║ incluyendo:                                              ║"
  echo "║                                                          ║"
  echo "║  • Verificación de archivos críticos                     ║"
  echo "║  • Reparación de configuraciones                         ║"
  echo "║  • Reinstalación si es necesario                         ║"
  echo "║  • Configuración de usuarios root                        ║"
  echo "║  • creditos a bcf studio                                 ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""
  
  read -p "¿Continuar con la reparación de MariaDB? (s/N): " confirm
  if [[ ! "$confirm" =~ ^[SsYy]$ ]]; then
    log_info "Reparación cancelada."
    return
  fi
  
  log_info "Iniciando diagnóstico de MariaDB/MySQL..."
  
  verificar_mariadb_estado() {
    echo ""
    echo "📊 DIAGNÓSTICO MARIA DB/MYSQL:"
    echo "──────────────────────────────"
    
    if command -v mariadb >/dev/null 2>&1 || command -v mysql >/dev/null 2>&1; then
      echo "✅ Binarios encontrados:"
      command -v mariadb && command -v mysql || true
    else
      echo "❌ Binarios NO encontrados"
    fi
    
    if systemctl list-unit-files 2>/dev/null | grep -q 'mariadb.service'; then
      echo "✅ Servicio systemd encontrado: mariadb.service"
    elif systemctl list-unit-files 2>/dev/null | grep -q 'mysql.service'; then
      echo "✅ Servicio systemd encontrado: mysql.service"
    else
      echo "❌ Servicio systemd NO encontrado"
    fi
    
    if systemctl is-enabled mariadb 2>/dev/null | grep -qi "masked"; then
      echo "⚠️  Servicio ENMASCARADO (masked)"
    fi
    
    if systemctl is-active --quiet mariadb 2>/dev/null || systemctl is-active --quiet mysql 2>/dev/null; then
      echo "✅ Servicio ACTIVO"
    else
      echo "❌ Servicio INACTIVO"
    fi
    
    if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
      echo "✅ Conexión root exitosa"
    else
      echo "❌ No se puede conectar como root"
    fi
    
    archivos_criticos=(
      "/etc/mysql/my.cnf"
      "/etc/mysql/debian.cnf"
      "/etc/mysql/mariadb.conf.d/50-server.cnf"
      "/var/run/mysqld/mysqld.sock"
    )
    
    echo ""
    echo "📁 ARCHIVOS CRÍTICOS:"
    for archivo in "${archivos_criticos[@]}"; do
      if [ -e "$archivo" ]; then
        echo "  ✅ $archivo"
      else
        echo "  ❌ $archivo (FALTANTE)"
      fi
    done
    echo "──────────────────────────────"
  }
  
  reparar_configuraciones() {
    log_info "Reparando archivos de configuración..."
    
    mkdir -p /etc/mysql/conf.d
    mkdir -p /etc/mysql/mariadb.conf.d
    mkdir -p /var/run/mysqld
    chown mysql:mysql /var/run/mysqld 2>/dev/null || true
    
    if [ ! -f /etc/mysql/my.cnf ]; then
      log_warn "Creando /etc/mysql/my.cnf..."
      cat > /etc/mysql/my.cnf << 'EOF'
!includedir /etc/mysql/conf.d/
!includedir /etc/mysql/mariadb.conf.d/
EOF
    fi
    
    if [ ! -f /etc/mysql/debian.cnf ]; then
      log_warn "Creando /etc/mysql/debian.cnf..."
      cat > /etc/mysql/debian.cnf << 'EOF'
[client]
host     = localhost
user     = root
password =
socket   = /run/mysqld/mysqld.sock

[mysql_upgrade]
user     = root
password =
socket   = /run/mysqld/mysqld.sock
EOF
      chmod 600 /etc/mysql/debian.cnf
    fi
    
    if [ ! -f /etc/mysql/debian-start ]; then
      log_warn "Creando /etc/mysql/debian-start..."
      cat > /etc/mysql/debian-start << 'EOF'
#!/bin/sh
MYSQL="/usr/bin/mysql --defaults-file=/etc/mysql/debian.cnf"
MYADMIN="/usr/bin/mysqladmin --defaults-file=/etc/mysql/debian.cnf"

if $MYADMIN ping >/dev/null 2>&1; then
  echo "MariaDB started"
fi
exit 0
EOF
      chmod 755 /etc/mysql/debian-start
    fi
    
    if [ -f "/etc/mysql/mariadb.conf.d/50-server.cnf" ]; then
      log_info "Configurando 50-server.cnf..."
      sed -i 's/character-set-collations = utf8mb4=uca1400_ai_ci/character-set-collations = utf8mb4=utf8mb4_general_ci/' /etc/mysql/mariadb.conf.d/50-server.cnf
    fi
    
    log_ok "Configuraciones reparadas."
  }
  
  reinstalar_mariadb() {
    log_warn "Iniciando reinstalación completa de MariaDB..."
    
    systemctl stop mariadb 2>/dev/null || true
    systemctl stop mysql 2>/dev/null || true
    killall -9 mysqld mariadbd mysql 2>/dev/null || true
    
    systemctl unmask mariadb 2>/dev/null || true
    systemctl unmask mysql 2>/dev/null || true
    
    apt purge -y mariadb-* mysql-* 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
    rm -rf /var/lib/mysql /etc/mysql /var/log/mysql /var/run/mysqld
    
    rm -f /var/lib/dpkg/lock-frontend
    rm -f /var/lib/dpkg/lock
    rm -f /var/lib/apt/lists/lock
    
    apt update -y
    apt install -y mariadb-server mariadb-client
    
    # 6. Configurar servicio systemd
    if [ ! -f "/etc/systemd/system/mariadb.service" ] && [ ! -f "/lib/systemd/system/mariadb.service" ]; then
      log_warn "Creando servicio systemd para MariaDB..."
      cat > /lib/systemd/system/mariadb.service << 'EOF'
[Unit]
Description=MariaDB 10.11 database server
After=network.target

[Service]
Type=notify
User=mysql
Group=mysql
ExecStart=/usr/sbin/mariadbd
ExecStartPost=/etc/mysql/debian-start
KillSignal=SIGTERM
TimeoutSec=300
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
      systemctl daemon-reload
    fi
    
    systemctl enable mariadb
    systemctl start mariadb
    
    sleep 3
    
    log_info "Configurando seguridad básica..."
    mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '';" 2>/dev/null || true
    mysql -u root -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
    mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null || true
    mysql -u root -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
    mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" 2>/dev/null || true
    mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    
    log_ok "Reinstalación completa finalizada."
  }
  
  configurar_usuarios_root() {
    log_info "Configurando usuarios root..."
    
    if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
      mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '';" 2>/dev/null || true
      
      mysql -u root -e "CREATE USER IF NOT EXISTS 'rootar'@'%' IDENTIFIED BY 'rooter';" 2>/dev/null || true
      mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'rootar'@'%' WITH GRANT OPTION;" 2>/dev/null || true
      
      mysql -u root -e "CREATE USER IF NOT EXISTS 'rootar'@'localhost' IDENTIFIED BY 'rootar';" 2>/dev/null || true
      mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'rootar'@'localhost' WITH GRANT OPTION;" 2>/dev/null || true
      
      mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
      
      log_ok "Usuarios root configurados:"
      echo "   • root@localhost (sin contraseña)"
      echo "   • rootar@localhost (contraseña: rootar)"
      echo "   • rootar@% (contraseña: rooter)"
    else
      log_err "No se puede conectar a MySQL para configurar usuarios"
    fi
  }
  
  verificar_mariadb_estado
  
  echo ""
  echo "🔧 SELECCIONA EL TIPO DE REPARACIÓN:"
  echo "   1) Reparación ligera (solo configuraciones)"
  echo "   2) Reparación completa (reinstalación)"
  echo "   3) Solo configurar usuarios root"
  echo "   4) Cancelar"
  echo ""
  read -p "Opción [1-4]: " opcion_reparacion
  
  case $opcion_reparacion in
  1)
    log_info "Iniciando reparación ligera..."
    reparar_configuraciones

    systemctl restart mariadb 2>/dev/null || systemctl restart mysql 2>/dev/null || true
    sleep 2

    if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
      log_ok "✅ Reparación ligera completada - MariaDB funciona"
    else
      log_warn "⚠️  Reparación ligera no funcionó, intenta reparación completa"
    fi
    ;;

  2)
    log_info "Iniciando reparación completa..."
    reinstalar_mariadb
    reparar_configuraciones
    configurar_usuarios_root

    if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
      log_ok "✅ Reparación completa exitosa - MariaDB reinstalado y funcionando"
    else
      log_err "❌ La reparación completa falló"
    fi
    ;;

  3)
    log_info "Configurando solo usuarios root..."
    configurar_usuarios_root
    log_ok "Usuarios root configurados"
    ;;

  4)
    log_info "Reparación cancelada"
    return
    ;;

  *)
    log_err "Opción no válida"
    return
    ;;
  esac
  
  echo ""
  echo "📊 ESTADO FINAL MARIA DB:"
  echo "──────────────────────────────"
  if systemctl is-active --quiet mariadb 2>/dev/null || systemctl is-active --quiet mysql 2>/dev/null; then
    echo "✅ Servicio: ACTIVO"
  else
    echo "❌ Servicio: INACTIVO"
  fi
  
  if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
    echo "✅ Conexión root: FUNCIONAL"
    version=$(mysql -u root -e "SELECT VERSION();" 2>/dev/null | tail -1)
    echo "✅ Versión: $version"
  else
    echo "❌ Conexión root: FALLIDA"
  fi
  
  echo "──────────────────────────────"
  echo ""
  
  read -p "Presiona Enter para continuar..."
}

gestionar_puertos() {
  while true; do
    clear
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                   🔧 GESTIÓN DE PUERTOS                  ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    echo "║  1) Ver puertos abiertos                                 ║"
    echo "║  2) Abrir puerto                                         ║"
    echo "║  3) Cerrar/Eliminar puerto                               ║"
    echo "║                                                          ║"
    echo "║  0) Volver                                               ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    read -rp "▷ Selecciona una opción [0-3]: " opcion

    case "$opcion" in
      1) ver_puertos_abiertos ;;
      2) abrir_puerto ;;
      3) cerrar_puerto ;;
      0) return ;;
      *) echo "Opción inválida"; sleep 1 ;;
    esac
  done
}

ver_puertos_abiertos() {
  echo ""
  echo "🛡️  FIREWALL (PUERTOS PERMITIDOS)"
  echo "================================"

  if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    echo "UFW activo:"
    ufw status numbered
  else
    echo "UFW no activo — usando iptables:"
    iptables -L INPUT -n --line-numbers | grep ACCEPT
  fi

  echo ""
  echo "📡 SERVICIOS ESCUCHANDO (informativo)"
  echo "===================================="
  ss -tulpn | grep LISTEN

  echo ""
  read -rp "Presiona Enter para continuar..."
}

abrir_puerto() {
  echo ""
  echo "➕ ABRIR PUERTO(S)"
  echo "Formato: 27015 | 27015:27030 | 27015/tcp | 27015:27030/udp"
  echo ""

  read -rp "Puerto(s): " entrada
  [ -z "$entrada" ] && echo "Entrada vacía" && return

  if [[ "$entrada" =~ ^([0-9]{1,5}(:[0-9]{1,5})?)(/(tcp|udp))?$ ]]; then
    PUERTOS="${BASH_REMATCH[1]}"
    PROTO="${BASH_REMATCH[4]:-ambos}"
  else
    echo "Formato inválido"
    return
  fi

  if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    if [ "$PROTO" = "ambos" ]; then
      ufw allow "$PUERTOS/tcp"
      ufw allow "$PUERTOS/udp"
    else
      ufw allow "$PUERTOS/$PROTO"
    fi
    ufw reload
    echo "✅ Regla aplicada con UFW"
    return
  fi

  if [ "$PROTO" = "ambos" ]; then
    iptables -A INPUT -p tcp --dport "$PUERTOS" -j ACCEPT
    iptables -A INPUT -p udp --dport "$PUERTOS" -j ACCEPT
  else
    iptables -A INPUT -p "$PROTO" --dport "$PUERTOS" -j ACCEPT
  fi

  if command -v iptables-save >/dev/null && [ -d /etc/iptables ]; then
    iptables-save > /etc/iptables/rules.v4
  fi

  echo "✅ Regla aplicada con iptables"
  read -rp "Presiona Enter para continuar..."
}

cerrar_puerto() {
  echo ""
  echo "➖ CERRAR PUERTO(S)"
  echo "Formato: 27015 | 27015:27030 | 27015/tcp | 27015:27030/udp"
  echo ""

  read -rp "Puerto(s): " entrada
  [ -z "$entrada" ] && echo "Entrada vacía" && return

  if [[ "$entrada" =~ ^([0-9]{1,5}(:[0-9]{1,5})?)(/(tcp|udp))?$ ]]; then
    PUERTOS="${BASH_REMATCH[1]}"
    PROTO="${BASH_REMATCH[4]:-ambos}"
  else
    echo "Formato inválido"
    return
  fi

  if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    if [ "$PROTO" = "ambos" ]; then
      ufw delete allow "$PUERTOS/tcp"
      ufw delete allow "$PUERTOS/udp"
    else
      ufw delete allow "$PUERTOS/$PROTO"
    fi
    ufw reload
    echo "🔥 Regla eliminada de UFW"
    return
  fi

  if [ "$PROTO" = "ambos" ]; then
    iptables -D INPUT -p tcp --dport "$PUERTOS" -j ACCEPT
    iptables -D INPUT -p udp --dport "$PUERTOS" -j ACCEPT
  else
    iptables -D INPUT -p "$PROTO" --dport "$PUERTOS" -j ACCEPT
  fi

  if command -v iptables-save >/dev/null && [ -d /etc/iptables ]; then
    iptables-save > /etc/iptables/rules.v4
  fi

  echo "🔥 Regla eliminada de iptables"
  read -rp "Presiona Enter para continuar..."
}

# ==============================
# GESTIÓN AVANZADA (BACKUP / USUARIOS)
# ==============================
gestion_avanzada() {

  CLR_RESET="\e[0m"
  CLR_TITLE="\e[1;36m"
  CLR_MENU="\e[1;34m"
  CLR_OK="\e[1;32m"
  CLR_WARN="\e[1;33m"
  CLR_ERR="\e[1;31m"
  CLR_TEXT="\e[0;37m"
  CLR_LINE="\e[1;30m"

  BACKUP_DIR="/root/backups"
  SOURCE_DIR="/var/lib/pterodactyl/volumes"
  LOG_FILE="$BACKUP_DIR/backup.log"

  mkdir -p "$BACKUP_DIR"

  log() {
    echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $1" >> "$LOG_FILE"
  }

  header() {
    clear
    echo -e "${CLR_LINE}─────────────────────────────────────${CLR_RESET}"
    echo -e "${CLR_TITLE}        GESTIÓN AVANZADA             ${CLR_RESET}"
    echo -e "${CLR_LINE}─────────────────────────────────────${CLR_RESET}"
    echo
  }

  # ==============================
  # BACKUP SERVIDORES
  # ==============================
  backup_servers() {
    header

    if [ ! -d "$SOURCE_DIR" ]; then
      echo -e "${CLR_ERR}No existe el directorio de volúmenes${CLR_RESET}"
      return 1
    fi

    DATE=$(date +"%Y-%m-%d_%H-%M")

    if systemctl list-unit-files | grep -q "^wings.service"; then
      echo -e "${CLR_WARN}Deteniendo Wings...${CLR_RESET}"
      log "Deteniendo Wings"
      systemctl stop wings
      sleep 5
    fi

    echo -e "${CLR_TEXT}Creando backup...${CLR_RESET}"
    log "Iniciando backup"

    tar -czpf "$BACKUP_DIR/pterodactyl_backup_$DATE.tar.gz" "$SOURCE_DIR"
    RESULT=$?

    if systemctl list-unit-files | grep -q "^wings.service"; then
      systemctl start wings
      log "Wings iniciado"
    fi

    if [ "$RESULT" -eq 0 ]; then
      echo -e "${CLR_OK}Backup completado correctamente${CLR_RESET}"
      log "Backup completado OK"
      echo "📦 $BACKUP_DIR/pterodactyl_backup_$DATE.tar.gz"
      echo "📊 Tamaño: $(du -h "$BACKUP_DIR/pterodactyl_backup_$DATE.tar.gz" | cut -f1)"
    else
      echo -e "${CLR_ERR}Error durante el backup${CLR_RESET}"
      log "ERROR en backup"
    fi
  }

  # ==============================
  # CREAR USUARIO ADMIN
  # ==============================
  create_admin_user() {
    header

    [ ! -d "/var/www/pterodactyl" ] && {
      echo -e "${CLR_ERR}Panel no instalado${CLR_RESET}"
      return 1
    }

    cd /var/www/pterodactyl || return 1

    read -rp "Email: " EMAIL
    read -rp "Usuario: " USERNAME
    read -rp "Nombre: " FIRST_NAME
    read -rp "Apellido: " LAST_NAME
    read -s -rp "Contraseña: " PASSWORD
    echo
    read -s -rp "Confirmar contraseña: " PASSWORD2
    echo

    [[ -z "$EMAIL" || -z "$USERNAME" || -z "$FIRST_NAME" || -z "$LAST_NAME" ]] && {
      echo -e "${CLR_ERR}Campos obligatorios vacíos${CLR_RESET}"
      return 1
    }

    [[ "$PASSWORD" != "$PASSWORD2" ]] && {
      echo -e "${CLR_ERR}Las contraseñas no coinciden${CLR_RESET}"
      return 1
    }

    php artisan p:user:make \
      --email="$EMAIL" \
      --username="$USERNAME" \
      --name-first="$FIRST_NAME" \
      --name-last="$LAST_NAME" \
      --password="$PASSWORD" \
      --admin=1
  }

  # ==============================
  # ELIMINAR USUARIO
  # ==============================
  delete_user() {
    header

    [ ! -d "/var/www/pterodactyl" ] && {
      echo -e "${CLR_ERR}Panel no instalado${CLR_RESET}"
      return 1
    }

    cd /var/www/pterodactyl || return 1

    php artisan tinker --execute="
      \Pterodactyl\Models\User::select('id','username','email')->get()->each(function(\$u){
        echo \"ID: {\$u->id} | {\$u->username} | {\$u->email}\\n\";
      });
    " || return 1

    read -rp "ID del usuario a eliminar: " USER_ID
    [[ ! "$USER_ID" =~ ^[0-9]+$ ]] && {
      echo -e "${CLR_ERR}ID inválido${CLR_RESET}"
      return 1
    }

    read -rp "¿Eliminar usuario ID $USER_ID? (s/N): " CONFIRM
    [[ ! "$CONFIRM" =~ ^[SsYy]$ ]] && return

    php artisan p:user:delete --user="$USER_ID"
  }

  # ==============================
  # LISTAR BACKUPS
  # ==============================
  list_backups() {
    header
    [ ! -d "$BACKUP_DIR" ] && {
      echo -e "${CLR_WARN}No hay backups${CLR_RESET}"
      return
    }

    ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "No hay backups disponibles"
  }

  # ==============================
  # MENÚ
  # ==============================
  while true; do
    header
    echo -e "${CLR_MENU}1) Backup completo de servidores${CLR_RESET}"
    echo -e "${CLR_MENU}2) Crear usuario administrador${CLR_RESET}"
    echo -e "${CLR_MENU}3) Eliminar usuario${CLR_RESET}"
    echo -e "${CLR_MENU}4) Listar backups disponibles${CLR_RESET}"
    echo -e "${CLR_MENU}5) Volver${CLR_RESET}"
    echo

    read -rp "Selecciona una opción: " OPTION

    case "$OPTION" in
      1) backup_servers; read -rp "Enter para continuar..." ;;
      2) create_admin_user; read -rp "Enter para continuar..." ;;
      3) delete_user; read -rp "Enter para continuar..." ;;
      4) list_backups; read -rp "Enter para continuar..." ;;
      5) return ;;
      *) echo -e "${CLR_ERR}Opción inválida${CLR_RESET}"; sleep 1 ;;
    esac
  done
}

# ==============================
# MONTURA DE FASTDL
# ==============================
instalar_fastdl() {
  log_info "Iniciando instalador de FastDL CS 1.6..."
  
  local fastdl_installer
  fastdl_installer=$(mktemp /tmp/fastdl-installer-XXXXXX.sh)
  
  cat << 'EOF' > "$fastdl_installer"
#!/bin/bash
# ============================================
# FASTDL CS 1.6 - INSTALADOR/DESINSTALADOR COMPLETO CORREGIDO
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mensaje() { echo "[INFO] $1"; }
exito() { echo "[ OK ] $1"; }
advertencia() { echo "[WARN] $1"; }
error() { echo "[ERROR] $1"; }
header() { clear; }
log() { echo "$1"; }
panel_webserver() { return 0; }

clear
echo "============================================"
echo "    INSTALADOR/DESINSTALADOR FASTDL CS 1.6"
echo "============================================"

# VERIFICAR ROOT
if [ "$EUID" -ne 0 ]; then 
    error "Ejecuta como root: sudo bash $0"
    exit 1
fi

desinstalar_fastdl() {
    clear
    echo "============================================"
    echo "          DESINSTALAR FASTDL CS 1.6"
    echo "============================================"
    
    read -p "⚠️  ¿Estás seguro de desinstalar FastDL? (s/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo "Desinstalación cancelada."
        exit 0
    fi
    
    mensaje "Buscando configuración FastDL..."
    
    if [ -f "/etc/nginx/sites-available/fastdl.conf" ]; then
        DOMINIO=$(grep -m1 "server_name" /etc/nginx/sites-available/fastdl.conf | awk '{print $2}' | tr -d ';')
        
        if [ -n "$DOMINIO" ]; then
            echo ""
            echo "📋 Configuración encontrada:"
            echo "   Dominio: $DOMINIO"
            
            read -p "¿Eliminar certificado SSL de Let's Encrypt? (s/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Ss]$ ]]; then
                mensaje "Eliminando certificado SSL..."
                certbot delete --cert-name "$DOMINIO" --non-interactive 2>/dev/null || true
                rm -rf /etc/letsencrypt/live/"$DOMINIO" /etc/letsencrypt/archive/"$DOMINIO" /etc/letsencrypt/renewal/"$DOMINIO".conf 2>/dev/null || true
                exito "Certificado SSL eliminado"
            fi
        fi
        
        mensaje "Eliminando configuración Nginx..."
        rm -f /etc/nginx/sites-available/fastdl.conf
        rm -f /etc/nginx/sites-enabled/fastdl.conf
        
        if [ ! -f "/etc/nginx/sites-enabled/default" ]; then
            if [ -f "/etc/nginx/sites-available/default" ]; then
                ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
            fi
        fi
        
        if nginx -t; then
            systemctl reload nginx
            exito "Configuración Nginx eliminada"
        fi
    else
        advertencia "No se encontró configuración FastDL en Nginx"
    fi
    
    mensaje "Buscando archivos FastDL..."
    
    if [ -f "/root/fastdl_info.txt" ]; then
        UUID=$(grep "UUID:" /root/fastdl_info.txt | cut -d' ' -f2)
        if [ -n "$UUID" ]; then
            RUTA_FASTDL="/var/lib/pterodactyl/volumes/$UUID/cstrike"
            if [ -d "$RUTA_FASTDL" ]; then
                echo "   UUID encontrado: $UUID"
                echo "   Ruta: $RUTA_FASTDL"
                
                read -p "¿Eliminar archivos FastDL? (s/n): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Ss]$ ]]; then
                    rm -rf "$RUTA_FASTDL"
                    rmdir "/var/lib/pterodactyl/volumes/$UUID" 2>/dev/null || true
                    exito "Archivos FastDL eliminados"
                fi
            fi
        fi
    fi
    
    for dir in /var/lib/pterodactyl/volumes/*/cstrike; do
        if [ -d "$dir" ]; then
            echo ""
            echo "🔍 Se encontró directorio FastDL: $dir"
            read -p "¿Eliminar este directorio? (s/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Ss]$ ]]; then
                rm -rf "$dir"
                exito "Directorio eliminado: $dir"
            fi
        fi
    done
    
    mensaje "Eliminando scripts de mantenimiento..."
    rm -f /usr/local/bin/sync_fastdl.sh
    rm -f /usr/local/bin/fastdl_status.sh
    
    sed -i '/sync_fastdl\.sh/d' /etc/crontab 2>/dev/null
    
    rm -f /root/fastdl_info.txt
    
    rm -f /var/log/nginx/fastdl*.log 2>/dev/null
    
    exito "Scripts de mantenimiento eliminados"
    
    echo ""
    echo "============================================"
    echo "✅ DESINSTALACIÓN COMPLETADA"
    echo "============================================"
    echo ""
    echo "⚠️  ACCIONES RECOMENDADAS:"
    echo "   1. Verificar que Nginx funcione correctamente"
    echo "   2. Actualizar server.cfg del servidor CS 1.6:"
    echo "      • Eliminar o comentar sv_downloadurl"
    echo "      • Configurar sv_allowdownload 0 si no usas FastDL"
    echo "   3. Reiniciar el servidor CS 1.6"
    echo ""
    
    exit 0
}

# ==============================
# PRINCIPAL
# ==============================
echo ""
echo "Selecciona una opción:"
echo "1) Instalar FastDL"
echo "2) Desinstalar FastDL"
echo "3) Salir"
echo ""
read -p "Opción: " -n 1 -r
echo

case $REPLY in
    1)
        # Continuar con instalación
        ;;
    2)
        desinstalar_fastdl
        ;;
    3)
        exit 0
        ;;
    *)
        error "Opción no válida"
        exit 1
        ;;
esac

echo ""
read -p "👉 Dominio FastDL (ej: fastdl.tudominio.com): " DOMINIO

if [ -z "$DOMINIO" ]; then
    error "Debes ingresar un dominio"
    exit 1
fi

echo ""
echo "🔍 Detectando UUIDs de servidores CS 1.6..."

UUIDS=($(ls -1 /var/lib/pterodactyl/volumes 2>/dev/null))

if [ ${#UUIDS[@]} -eq 0 ]; then
    error "No se encontraron UUIDs disponibles"
    exit 1
fi

echo ""
echo "UUIDs disponibles:"
for i in "${!UUIDS[@]}"; do
    echo "$((i+1))) ${UUIDS[$i]}"
done

echo ""
read -p "👉 Selecciona el UUID (número): " SEL

if ! [[ "$SEL" =~ ^[0-9]+$ ]] || [ "$SEL" -lt 1 ] || [ "$SEL" -gt "${#UUIDS[@]}" ]; then
    error "Selección inválida"
    exit 1
fi

UUID="${UUIDS[$((SEL-1))]}"
exito "UUID seleccionado: $UUID"

read -p "👉 Email para SSL: " EMAIL

if [ -z "$EMAIL" ]; then
    error "Debes ingresar un email"
    exit 1
fi

echo ""
echo "============================================"
echo "RESUMEN:"
echo "• Dominio: $DOMINIO"
echo "• UUID: $UUID"
echo "• Email: $EMAIL"
echo "============================================"
read -p "¿Continuar? (s/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then 
    echo "Instalación cancelada."
    exit 0
fi

mensaje "1. Actualizando sistema..."
apt update && apt upgrade -y
exito "Sistema actualizado"

mensaje "2. Instalando dependencias..."
apt install -y nginx certbot python3-certbot-nginx
exito "Dependencias instaladas"

mensaje "3. Configurando permisos..."
gpasswd -a www-data pterodactyl 2>/dev/null || groupadd pterodactyl && gpasswd -a www-data pterodactyl
chmod 755 /var/lib/pterodactyl/ /var/lib/pterodactyl/volumes/
chown -R pterodactyl:pterodactyl /var/lib/pterodactyl/volumes/ 2>/dev/null || true
exito "Permisos configurados"

mensaje "4. Configurando Nginx (HTTP temporal)..."

cat > /etc/nginx/sites-available/fastdl.conf << NGINXCONF
server {
    listen 80;
    server_name $DOMINIO;
    
    root /var/lib/pterodactyl/volumes;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ =404;
        autoindex off;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
    
    location ~ \.(sma|amxx|sp|smx|cfg|ini|log|bak|dat|sql|sq3|so|dll|php|zip|rar|jar|sh)\$ {
        return 403;
    }
    
    location ~ /(addons|cfg|logs) {
        deny all;
    }
}
NGINXCONF

ln -sf /etc/nginx/sites-available/fastdl.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

if nginx -t; then
    systemctl reload nginx
    exito "Nginx configurado (HTTP temporal)"
else
    error "Error en configuración Nginx"
    exit 1
fi

mensaje "5. Instalando SSL..."
if certbot --nginx -d "$DOMINIO" --non-interactive --agree-tos --email "$EMAIL" --redirect; then
    exito "SSL instalado"
else
    error "Error instalando SSL"
    exit 1
fi

mensaje "6. Actualizando Nginx con SSL..."

cat > /etc/nginx/sites-available/fastdl.conf << NGINXSSL
server {
    listen 80;
    server_name $DOMINIO;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMINIO;
    
    ssl_certificate /etc/letsencrypt/live/$DOMINIO/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMINIO/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
    
    root /var/lib/pterodactyl/volumes;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ =404;
        autoindex off;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
    
    location ~ \.(sma|amxx|sp|smx|cfg|ini|log|bak|dat|sql|sq3|so|dll|php|zip|rar|jar|sh)\$ {
        return 403;
    }
    
    location ~ /(addons|cfg|logs) {
        deny all;
    }
}
NGINXSSL

if nginx -t; then
    systemctl reload nginx
    exito "Nginx actualizado con SSL"
else
    error "Error en configuración Nginx SSL"
    exit 1
fi

mensaje "7. Creando estructura FastDL..."
RUTA_FASTDL="/var/lib/pterodactyl/volumes/$UUID/cstrike"
mkdir -p "$RUTA_FASTDL"/{maps,models,sound,sprites,gfx,resource}
echo "Archivo de prueba FastDL - $(date)" > "$RUTA_FASTDL/test_fastdl.txt"
chmod -R 755 "/var/lib/pterodactyl/volumes/$UUID"
exito "Estructura creada en: $RUTA_FASTDL"

mensaje "8. Configurando server.cfg..."

SERVER_CFG="$RUTA_FASTDL/server.cfg"
FASTDL_URL="https://$DOMINIO/$UUID/cstrike/"

if [ -f "$SERVER_CFG" ]; then
    if ! grep -q "sv_downloadurl" "$SERVER_CFG"; then
        cat >> "$SERVER_CFG" << SERVERCFG

sv_downloadurl "$FASTDL_URL"
sv_allowdownload 1
sv_allowupload 0
SERVERCFG
        exito "server.cfg actualizado con FastDL"
    else
        advertencia "server.cfg ya tiene configuración FastDL"
    fi
else
    cat > "$SERVER_CFG" << NEWCFG
hostname "Servidor CS 1.6 FastDL"
rcon_password "cambiar_esta_contrasena"

sv_downloadurl "$FASTDL_URL"
sv_allowdownload 1
sv_allowupload 0

mp_timelimit 25
mp_roundtime 3
mp_freezetime 0
mp_friendlyfire 0
sv_alltalk 1
mp_autoteambalance 1
sv_voiceenable 1
NEWCFG
    exito "server.cfg creado nuevo"
fi

mensaje "9. Copiando archivos existentes..."

mensaje "9. Copiando archivos CS 1.6..."

if [ -d "/mnt/server/cstrike" ]; then
    echo "📂 Copiando archivos desde /mnt/server/cstrike..."
    
    if [ -d "/mnt/server/cstrike/maps" ]; then
        find "/mnt/server/cstrike/maps" -name "*.bsp" -exec cp {} "$RUTA_FASTDL/maps/" \; 2>/dev/null
        echo "✅ Maps copiados"
    fi
    
    if [ -d "/mnt/server/cstrike/models" ]; then
        cp -r "/mnt/server/cstrike/models/"* "$RUTA_FASTDL/models/" 2>/dev/null
        echo "✅ Models copiados"
    fi
    
    if [ -d "/mnt/server/cstrike/sound" ]; then
        cp -r "/mnt/server/cstrike/sound/"* "$RUTA_FASTDL/sound/" 2>/dev/null
        echo "✅ Sounds copiados"
    fi
    
    if [ -d "/mnt/server/cstrike/sprites" ]; then
        cp -r "/mnt/server/cstrike/sprites/"* "$RUTA_FASTDL/sprites/" 2>/dev/null
        echo "✅ Sprites copiados"
    fi
    
    if [ -d "/mnt/server/cstrike/gfx" ]; then
        cp -r "/mnt/server/cstrike/gfx/"* "$RUTA_FASTDL/gfx/" 2>/dev/null
        echo "✅ Gfx copiados"
    fi
    
    if [ -d "/mnt/server/cstrike/resource" ]; then
        cp -r "/mnt/server/cstrike/resource/"* "$RUTA_FASTDL/resource/" 2>/dev/null
        echo "✅ Resource copiados"
    fi
    
    find "/mnt/server/cstrike" -maxdepth 1 -name "*.wad" -exec cp {} "$RUTA_FASTDL/" \; 2>/dev/null
    echo "✅ Archivos .wad copiados"
    
    exito "Copia de archivos CS 1.6 completada"
else
    advertencia "No se encontró /mnt/server/cstrike"
fi

mensaje "10. Creando scripts de mantenimiento..."

cat > /usr/local/bin/sync_fastdl.sh << SYNCSCRIPT
#!/bin/bash
UUID="$UUID"
SERVER="/mnt/server/cstrike"
FASTDL="/var/lib/pterodactyl/volumes/\$UUID/cstrike"

echo "🔄 Sincronizando FastDL..."
[ -d "\$SERVER/maps" ] && find "\$SERVER/maps" -name "*.bsp" -exec cp {} "\$FASTDL/maps/" \; 2>/dev/null
[ -d "\$SERVER/models" ] && cp -r "\$SERVER/models/"* "\$FASTDL/models/" 2>/dev/null
[ -d "\$SERVER/sound" ] && cp -r "\$SERVER/sound/"* "\$FASTDL/sound/" 2>/dev/null
[ -d "\$SERVER/sprites" ] && cp -r "\$SERVER/sprites/"* "\$FASTDL/sprites/" 2>/dev/null
[ -d "\$SERVER/gfx" ] && cp -r "\$SERVER/gfx/"* "\$FASTDL/gfx/" 2>/dev/null
[ -d "\$SERVER/resource" ] && cp -r "\$SERVER/resource/"* "\$FASTDL/resource/" 2>/dev/null
find "\$SERVER" -maxdepth 1 -name "*.wad" -exec cp {} "\$FASTDL/" \; 2>/dev/null
chmod -R 755 "\$FASTDL"
echo "✅ Sincronizado: \$(date)"
SYNCSCRIPT

chmod +x /usr/local/bin/sync_fastdl.sh

cat > /usr/local/bin/fastdl_status.sh << STATUSSCRIPT
#!/bin/bash
echo "=== ESTADO FASTDL ==="
echo "📅 \$(date)"
echo "🌐 Dominio: $DOMINIO"
echo "🔑 UUID: $UUID"
echo ""
echo "🔧 Nginx: \$(systemctl is-active nginx)"
STATUS=\$(curl -s -o /dev/null -w "%{http_code}" https://$DOMINIO/$UUID/cstrike/test_fastdl.txt 2>/dev/null)
echo "🌐 Test HTTP: \$STATUS"
echo "📊 Archivos: \$(find /var/lib/pterodactyl/volumes/$UUID/cstrike -type f 2>/dev/null | wc -l)"
echo "======================================"
STATUSSCRIPT

chmod +x /usr/local/bin/fastdl_status.sh
exito "Scripts de mantenimiento creados"

mensaje "11. Verificando instalación..."

sleep 2
echo ""
echo "============================================"
echo "✅ INSTALACIÓN COMPLETADA"
echo "============================================"
echo ""
echo "🌐 URL FASTDL:"
echo "   https://$DOMINIO/$UUID/cstrike/"
echo ""
echo "📂 RUTAS:"
echo "   Config Nginx: /etc/nginx/sites-available/fastdl.conf"
echo "   Archivos FastDL: $RUTA_FASTDL"
echo "   Script sincronización: /usr/local/bin/sync_fastdl.sh"
echo ""
echo "⚙️  CONFIGURACIÓN server.cfg:"
echo "   sv_downloadurl \"https://$DOMINIO/$UUID/cstrike/\""
echo "   sv_allowdownload 1"
echo "   sv_allowupload 0"
echo ""
echo "🛠️  COMANDOS ÚTILES:"
echo "   Sincronizar archivos: sudo sync_fastdl.sh"
echo "   Ver estado: sudo fastdl_status.sh"
echo "   Ver logs: sudo tail -f /var/log/nginx/fastdl-access.log"
echo "   Test rápido: curl -I https://$DOMINIO/$UUID/cstrike/test_fastdl.txt"
echo ""
echo "⚠️  ACCIONES NECESARIAS:"
echo "   1. REINICIAR servidor CS 1.6 en Pterodactyl"
echo "   2. Para nuevos archivos, copiar a: $RUTA_FASTDL/"
echo ""
read -p "¿Agregar sincronización automática cada hora? (s/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    echo "0 * * * * root /usr/local/bin/sync_fastdl.sh" >> /etc/crontab 2>/dev/null
    exito "Cron agregado: sincronización cada hora"
fi

cat > /root/fastdl_info.txt << INFOTXT
FASTDL INSTALADO: $(date)
=======================
DOMINIO: $DOMINIO
UUID: $UUID
URL: https://$DOMINIO/$UUID/cstrike/

CONFIGURACIÓN server.cfg:
sv_downloadurl "https://$DOMINIO/$UUID/cstrike/"
sv_allowdownload 1
sv_allowupload 0

RUTAS:
Config Nginx: /etc/nginx/sites-available/fastdl.conf
Archivos FastDL: $RUTA_FASTDL
Logs: /var/log/nginx/fastdl-*.log

COMANDOS:
sync_fastdl.sh    # Sincronizar archivos
fastdl_status.sh  # Ver estado
tail -f /var/log/nginx/fastdl-access.log  # Ver logs
INFOTXT

echo ""
echo "🎉 ¡FastDL instalado correctamente!"
echo "   REINICIA tu servidor CS 1.6 para aplicar cambios."
echo "   Test: curl -I https://$DOMINIO/$UUID/cstrike/test_fastdl.txt"
echo "============================================"
EOF
  
  chmod +x "$fastdl_installer"
  bash "$fastdl_installer"
  
  rm -f "$fastdl_installer"
}

# ==============================
# GESTIÓN DE THEMES – NOOKTHEME
# ==============================
menu_nooktheme() {
  clear
  echo "======================================"
  echo "        GESTIÓN DE TEMAS"
  echo "======================================"
  echo ""
  echo "  [1] Instalar NookTheme"
  echo "  [2] Desinstalar NookTheme"
  echo ""
  echo "  [0] Volver"
  echo ""
  read -p "Selecciona una opción: " opt

  case "$opt" in
  1)
    install_nooktheme
    ;;
  2)
    uninstall_nooktheme
    ;;
  0)
    return
    ;;
  *)
    echo "Opción inválida"
    sleep 1
    ;;
  esac
}

install_nooktheme() {
  log_info "Instalando NookTheme..."

  if [ ! -d "/var/www/pterodactyl" ]; then
    log_err "Pterodactyl no está instalado"
    read -p "Presiona Enter para continuar..."
    return
  fi

  cd /var/www/pterodactyl || return

  php artisan down

  curl -L https://github.com/Nookure/NookTheme/releases/latest/download/panel.tar.gz | tar -xz

  chmod -R 755 storage/* bootstrap/cache
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

  php artisan view:clear
  php artisan config:clear
  php artisan migrate --seed --force

  chown -R www-data:www-data /var/www/pterodactyl
  php artisan queue:restart
  php artisan up

  log_ok "NookTheme instalado correctamente"
  read -p "Presiona Enter para continuar..."
}

uninstall_nooktheme() {
  log_info "Desinstalando NookTheme y restaurando el panel..."

  if [ ! -d "/var/www/pterodactyl" ]; then
    log_err "Pterodactyl no está instalado"
    read -p "Presiona Enter para continuar..."
    return
  fi

  cd /var/www/pterodactyl || return

  php artisan down

  rm -rf /var/www/pterodactyl/resources

  curl -L https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz | tar -xz

  chmod -R 755 storage/* bootstrap/cache
  composer install --no-dev --optimize-autoloader

  php artisan view:clear
  php artisan config:clear
  php artisan migrate --seed --force

  chown -R www-data:www-data /var/www/pterodactyl
  php artisan queue:restart
  php artisan up

  log_ok "NookTheme desinstalado y panel restaurado"
  read -p "Presiona Enter para continuar..."
}
# =====================================================
# INSTALADOR DE ADDONS .blueprint (GENÉRICO)
# =====================================================
instalar_blueprint_addon() {
  clear
  echo "======================================"
  echo "     INSTALADOR ADDON BLUEPRINT"
  echo "======================================"
  echo ""

  PTERO_DIR="/var/www/pterodactyl"
  REPO_RAW="https://raw.githubusercontent.com/bri127-svg/fast-dl-/main"
  BP_FILE_NAME="serverbackgrounds.blueprint"

  if [ ! -d "$PTERO_DIR" ]; then
    log_err "Pterodactyl no está instalado"
    return
  fi

  if ! command -v blueprint >/dev/null 2>&1; then
    log_err "Blueprint Framework no está instalado"
    return
  fi

  cd "$PTERO_DIR" || return

  log_info "Descargando addon Blueprint desde GitHub..."
  curl -fsSL "$REPO_RAW/$BP_FILE_NAME" -o "$BP_FILE_NAME" || {
    log_err "No se pudo descargar el archivo .blueprint"
    return
  }

  log_info "Instalando addon Blueprint: $BP_FILE_NAME"
  blueprint -install "$BP_FILE_NAME" || {
    log_err "Error instalando el addon Blueprint"
    return
  }

  log_ok "Addon Blueprint instalado correctamente"
  read -p "Presiona Enter para continuar..."
}
# ==============================
# INSTALADOR CERTIFICADO SSL (simplificado)
# ==============================
instalar_certificado_ssl() {
  echo "=========================================="
  echo "   GENERADOR DE CERTIFICADO SSL (SIMPLIFICADO)"
  echo "   (Usa Let's Encrypt con Certbot y Nginx)"
  echo "   creditos: briancarlos.dev & CRM "
  echo "=========================================="
  echo ""

  # Verificar root
  if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Ejecuta como root"
    return 1
  fi

  # Pedir dominio
  read -p "👉 Dominio o subdominio (ej: panel.midominio.com): " DOMINIO
  if [ -z "$DOMINIO" ]; then
    echo "[ERROR] Dominio inválido"
    return 1
  fi

  # Email por defecto (puedes cambiarlo si quieres)
  EMAIL="contacto.usabrifreites@gmail.com"

  echo ""
  echo "[INFO] Dominio: $DOMINIO"
  echo "[INFO] Email SSL: $EMAIL"
  echo ""

  # Instalar dependencias
  echo "[INFO] Verificando Certbot y Nginx..."
  apt update -y
  apt install -y nginx certbot python3-certbot-nginx

  # Verificar Nginx
  if ! systemctl is-active --quiet nginx; then
    echo "[INFO] Iniciando Nginx..."
    systemctl enable --now nginx
  fi

  # Crear config HTTP temporal si no existe
  SSL_CONF="/etc/nginx/sites-available/$DOMINIO.conf"

  if [ ! -f "$SSL_CONF" ]; then
    echo "[INFO] Creando configuración temporal HTTP..."
    cat > "$SSL_CONF" <<EOF
server {
    listen 80;
    server_name $DOMINIO;

    location / {
        return 200 "OK";
    }
}
EOF

    ln -sf "$SSL_CONF" /etc/nginx/sites-enabled/
    nginx -t && systemctl reload nginx
  fi

  # Solicitar certificado
  echo ""
  echo "[INFO] Solicitando certificado SSL..."
  if certbot --nginx \
      -d "$DOMINIO" \
      --non-interactive \
      --agree-tos \
      -m "$EMAIL" \
      --redirect; then

    echo ""
    echo "[ OK ] CERTIFICADO SSL GENERADO CORRECTAMENTE"
    echo ""
    echo "📁 RUTAS:"
    echo "   Certificado: /etc/letsencrypt/live/$DOMINIO/fullchain.pem"
    echo "   Clave privada: /etc/letsencrypt/live/$DOMINIO/privkey.pem"
    echo ""
    echo "🔧 COMANDOS ÚTILES:"
    echo "   certbot certificates"
    echo "   certbot renew --dry-run"
    echo ""
    echo "⏳ Renovación automática ACTIVADA"
  else
    echo ""
    echo "[ERROR] Falló la generación del certificado"
    echo "Revisa:"
    echo " - DNS apuntando a esta VPS"
    echo " - Puertos 80 y 443 abiertos"
    echo " - Cloudflare en modo PROXY (nube naranja OFF)"
    return 1
  fi

  echo ""
}

# ==============================
# MENÚ PRINCIPAL
# ==============================
while true; do
  mostrar_menu
  read -r opcion

  case "$opcion" in
  1)
    instalar_panel
    ;;
  2)
    instalar_wings
    ;;
  3)
    instalar_phpmyadmin
    ;;
  4)
    configurar_database
    ;;
  5)
    fix_mariadb_bind_address
    ;;
  6)
    instalar_fastdl
    ;;
  7)
    menu_rescue
    ;;
  8)
    limpieza_total
    ;;
  9)
    gestionar_puertos
    ;;
  10)
    gestion_avanzada
    ;;
  11)
    menu_nooktheme
    ;;
  12)
   ejecutar_script_remoto
   ;;
  13)
    instalar_reviactyl
    ;;
  14)
    limpiar_themes
    ;;
  15)
    instalar_blueprint_addon
    ;; 
  16)
    instalar_certificado_ssl
    ;;
  17)
    instalar_wings_sin_token
    ;;

  0)
    clear
    echo "Saliendo..."
    exit 0
    ;;
  *)
    echo "Opción inválida"
    sleep 1
    ;;
  esac
done
