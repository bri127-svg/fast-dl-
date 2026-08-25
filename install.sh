  echo -e "  \e[1;35m› [12]\e[0m Ejecutar Comandos para intalacion de el nebula"
  echo -e "  \e[1;35m› [13]\e[0m Instalar Addon RevIActyl"
  echo -e "  \e[1;35m› [14]\e[0m Limpiador de Themes (Restaurar Panel)"
  echo -e "  \e[1;35m› [15]\e[0m Instalar Addon Blueprint (FONDO DE SERVIDOR

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
