#!/bin/bash

set -e -o pipefail

######################################################################################
#                                                                                    #
# Project 'nothing-panel-installer'                                                  #
#                                                                                    #
# Copyright (C) 2018 - 2026, Nothing Panel                                           #
#                                                                                    #
#   This program is free software: you can redistribute it and/or modify             #
#   it under the terms of the GNU General Public License as published by             #
#   the Free Software Foundation, either version 3 of the License, or                #
#   (at your option) any later version.                                              #
#                                                                                    #
######################################################################################

# Check if script is loaded, load if not or fail otherwise.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh || source <(curl -sSL "$GITHUB_BASE_URL/$GITHUB_SOURCE"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* ERROR: Could not load lib script" && exit 1
fi

# ------------------ Variables ----------------- #

# Domain name / IP
FQDN="${FQDN:-localhost}"

# Default MySQL credentials
MYSQL_DB="${MYSQL_DB:-panel}"
MYSQL_USER="${MYSQL_USER:-nothing_user}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-$(gen_passwd 64)}"

# Environment
timezone="${timezone:-Europe/Stockholm}"
telemetry="${telemetry:-true}"

# Assume SSL, will fetch different config if true
ASSUME_SSL="${ASSUME_SSL:-false}"
CONFIGURE_LETSENCRYPT="${CONFIGURE_LETSENCRYPT:-false}"

# Cloudflare Tunnel for NAT VPS / IPv6 / Non-Dedicated
USE_CLOUDFLARE_TUNNEL="${USE_CLOUDFLARE_TUNNEL:-false}"
CF_TUNNEL_MODE="${CF_TUNNEL_MODE:-token}"
CF_TUNNEL_TOKEN="${CF_TUNNEL_TOKEN:-}"

# Firewall
CONFIGURE_FIREWALL="${CONFIGURE_FIREWALL:-false}"

# Must be assigned to work, no default values
email="${email:-}"
user_email="${user_email:-}"
user_username="${user_username:-}"
user_firstname="${user_firstname:-}"
user_lastname="${user_lastname:-}"
user_password="${user_password:-}"

missing=()

for var in email user_email user_username user_firstname user_lastname user_password; do
  if [[ -z "${!var}" ]]; then
    missing+=("$var")
  fi
done

if (( ${#missing[@]} > 0 )); then
  for m in "${missing[@]}"; do
    error "${m} is required"
  done
  exit 1
fi

validate_panel_version
valid_database_identifier "$MYSQL_DB"
valid_database_identifier "$MYSQL_USER"
valid_panel_database_password "$MYSQL_PASSWORD"
valid_admin_username "$user_username"
valid_admin_name "$user_firstname"
valid_admin_name "$user_lastname"
valid_admin_password "$user_password"
valid_hostname "$FQDN"
if [ -d /var/www/nothing ]; then
  error "An existing Nothing Panel installation was detected. This script only supports fresh installations."
  exit 1
fi
get_latest_versions panel

# --------- Main installation functions -------- #

install_composer() {
  output "Installing composer.."
  curl -fsSL https://getcomposer.org/installer | "$PHP_BIN" -- --2 --install-dir=/usr/local/bin --filename=composer
  success "Composer installed!"
}

ptdl_dl() {
  output "Downloading Nothing Panel files..."
  mkdir -p /var/www/nothing
  cd /var/www/nothing || exit

  output "Installing Nothing Panel engine $PTERODACTYL_PANEL_VERSION"
  curl -fLo panel.tar.gz "$PANEL_DL_URL"
  if [ "$PANEL_MAJOR_VERSION" == "2" ]; then
    tar -xzvf panel.tar.gz --strip-components=1
  else
    tar -xzvf panel.tar.gz
  fi
  chmod -R 755 storage/* bootstrap/cache/

  cp .env.example .env

  # Maintain backwards compatibility symlink
  ln -sfn /var/www/nothing /var/www/pterodactyl

  success "Downloaded Nothing Panel files!"
}

install_composer_deps() {
  output "Installing composer dependencies.."
  export COMPOSER_ALLOW_SUPERUSER=1
  "$PHP_BIN" /usr/local/bin/composer install --no-dev --optimize-autoloader
  "$PHP_BIN" /usr/local/bin/composer check-platform-reqs --no-dev
  success "Installed composer dependencies!"

  if [ "$PANEL_MAJOR_VERSION" == "2" ]; then
    output "Building Panel v2 frontend.."
    npm ci --include=dev
    npm run build:production
    success "Built Panel frontend!"
  fi
}

# Configure environment
configure() {
  output "Configuring environment.."

  local app_url="http://$FQDN"
  [ "$ASSUME_SSL" == true ] && app_url="https://$FQDN"
  [ "$CONFIGURE_LETSENCRYPT" == true ] && app_url="https://$FQDN"

  # Generate encryption key
  "$PHP_BIN" artisan key:generate --force

  # Fill in environment:setup automatically
  "$PHP_BIN" artisan p:environment:setup \
    --author="$email" \
    --url="$app_url" \
    --timezone="$timezone" \
    --cache="redis" \
    --session="redis" \
    --queue="redis" \
    --redis-host="localhost" \
    --redis-pass="null" \
    --redis-port="6379" \
    --telemetry="$telemetry" \
    --settings-ui=true

  # Fill in environment:database credentials automatically
  "$PHP_BIN" artisan p:environment:database \
    --host="127.0.0.1" \
    --port="3306" \
    --database="$MYSQL_DB" \
    --username="$MYSQL_USER" \
    --password="$MYSQL_PASSWORD"

  # configures database
  "$PHP_BIN" artisan migrate --seed --force

  # Create user account
  local make_pass="$user_password"
  if [ ${#make_pass} -lt 8 ]; then
    make_pass="SecurePassword123!"
  fi
  "$PHP_BIN" artisan p:user:make \
    --email="$user_email" \
    --username="$user_username" \
    --name-first="$user_firstname" \
    --name-last="$user_lastname" \
    --password="$make_pass" \
    --admin=1 || true

  # Set exact requested password (supports short passwords like 'admin')
  "$PHP_BIN" artisan tinker --execute="\$u = \Pterodactyl\Models\User::where('username', '$user_username')->orWhere('email', '$user_email')->first(); if(\$u) { \$u->password = \Illuminate\Support\Facades\Hash::make('$user_password'); \$u->save(); }" >/dev/null 2>&1 || true

  # Disable reCAPTCHA to prevent verification failures on custom domains
  if grep -q '^RECAPTCHA_ENABLED=' .env; then
    sed -i 's/^RECAPTCHA_ENABLED=.*/RECAPTCHA_ENABLED=false/' .env
  else
    echo "" >> .env
    echo "RECAPTCHA_ENABLED=false" >> .env
  fi
  if [ -f "config/recaptcha.php" ]; then
    sed -i "s/'enabled' => env('RECAPTCHA_ENABLED', true)/'enabled' => false/g" config/recaptcha.php
  fi

  success "Configured environment!"
}

# set the correct folder permissions depending on OS and webserver
set_folder_permissions() {
  # if os is ubuntu or debian, we do this
  case "$OS" in
  debian | ubuntu)
    chown -R www-data:www-data ./*
    ;;
  rocky | almalinux)
    chown -R nginx:nginx ./*
    ;;
  esac
}

insert_cronjob() {
  output "Installing cronjob.. "

  {
    crontab -l 2>/dev/null || true
    echo "* * * * * $PHP_BIN /var/www/nothing/artisan schedule:run >> /dev/null 2>&1"
  } | crontab -
  case "$OS" in
  ubuntu | debian)
    systemctl enable --now cron
    ;;
  rocky | almalinux)
    systemctl enable --now crond
    ;;
  esac

  success "Cronjob installed!"
}

install_pteroq() {
  output "Installing Nothing Panel queue worker service.."

  curl -fsSL -o /etc/systemd/system/nothingq.service "$GITHUB_URL"/configs/nothingq.service
  sed -i -e "s@redis-server.service@${CACHE_SERVICE}.service@g" -e "s@/usr/bin/php @$PHP_BIN @g" /etc/systemd/system/nothingq.service

  case "$OS" in
  debian | ubuntu)
    sed -i -e "s@<user>@www-data@g" /etc/systemd/system/nothingq.service
    ;;
  rocky | almalinux)
    sed -i -e "s@<user>@nginx@g" /etc/systemd/system/nothingq.service
    ;;
  esac

  ln -sf /etc/systemd/system/nothingq.service /etc/systemd/system/pteroq.service 2>/dev/null || true

  systemctl daemon-reload
  systemctl enable nothingq.service
  systemctl start nothingq
  systemctl enable pteroq.service 2>/dev/null || true

  success "Installed queue worker service!"
}

# -------- OS specific install functions ------- #

enable_services() {
  systemctl enable --now "$CACHE_SERVICE"
  case "$OS" in
  ubuntu | debian)
    systemctl enable --now php8.3-fpm
    ;;
  esac
  systemctl enable nginx
  systemctl enable mariadb
  systemctl start mariadb
}

selinux_allow() {
  setsebool -P httpd_can_network_connect 1 || true # these commands can fail OK
  setsebool -P httpd_execmem 1 || true
  setsebool -P httpd_unified 1 || true
}

php_fpm_conf() {
  curl -fsSL -o /etc/php-fpm.d/www-nothing.conf "$GITHUB_URL"/configs/www-nothing.conf

  systemctl enable php-fpm
  systemctl start php-fpm
}

ubuntu_dep() {
  # Install deps for adding repos
  install_packages "software-properties-common apt-transport-https ca-certificates gnupg"

  # Add Ubuntu universe repo
  add-apt-repository universe -y
  case "$OS_VER_MAJOR" in
  22)
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    ;;
  26)
    debian_dep # Sury also provides PHP 8.3 packages for Ubuntu 26.04.
    ;;
  esac
}

debian_dep() {
  # Install deps for adding repos
  install_packages "dirmngr ca-certificates apt-transport-https lsb-release gnupg"

  # Install PHP 8.3 using sury's repo
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor --yes -o /etc/apt/keyrings/php.gpg
  echo "deb [signed-by=/etc/apt/keyrings/php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
}

alma_rocky_dep() {
  # SELinux tools
  install_packages "policycoreutils selinux-policy selinux-policy-targeted epel-release"

  # add remi repo (php8.3)
  if [ "$OS_VER_MAJOR" != "10" ]; then
    install_packages "https://rpms.remirepo.net/enterprise/remi-release-$OS_VER_MAJOR.rpm"
    dnf module enable -y php:remi-8.3
    if ! command -v mariadbd >/dev/null 2>&1; then
      dnf module enable -y mariadb:10.11
    fi
  fi
}

dep_install() {
  output "Installing dependencies for $OS $OS_VER..."

  # Update repos before installing
  update_repos

  [ "$CONFIGURE_FIREWALL" == true ] && install_firewall && firewall_ports

  case "$OS" in
  ubuntu | debian)
    if [ "$OS" == "ubuntu" ]; then
      ubuntu_dep
      if [ "$OS_VER_MAJOR" == "22" ] && ! command -v mariadbd >/dev/null 2>&1; then
        curl -fsSL "$MARIADB_URL" | bash -s -- --mariadb-server-version=mariadb-10.11 --skip-maxscale --skip-tools
      fi
    else
      debian_dep
    fi

    update_repos

    # Install dependencies
    install_packages "php8.3 php8.3-{cli,common,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip,intl} \
      mariadb-common mariadb-server mariadb-client \
      nginx \
      redis-server \
      zip unzip tar \
      git cron"

    [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "certbot python3-certbot-nginx"

    ;;
  rocky | almalinux)
    alma_rocky_dep

    # Install dependencies
    install_packages "php php-{common,fpm,cli,mysqlnd,gd,mbstring,pdo,zip,bcmath,xml,opcache,process,sodium,intl} \
      mariadb mariadb-server \
      nginx \
      $CACHE_SERVICE \
      zip unzip tar \
      git cronie"

    [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "certbot python3-certbot-nginx"

    # Allow nginx
    selinux_allow

    # Create config for php fpm
    php_fpm_conf
    ;;
  esac

  local setup_url
  if [ "$PANEL_MAJOR_VERSION" == "2" ]; then
    case "$OS" in
    ubuntu | debian)
      setup_url="https://deb.nodesource.com/setup_22.x"
      ;;
    rocky | almalinux)
      setup_url="https://rpm.nodesource.com/setup_22.x"
      ;;
    esac
    curl -fsSL "$setup_url" | bash -
    install_packages "nodejs"
  fi
  enable_services

  success "Dependencies installed!"
}

# --------------- Other functions -------------- #

firewall_ports() {
  output "Opening ports: 22 (SSH), 80 (HTTP) and 443 (HTTPS)"

  firewall_allow_ports "22 80 443"

  success "Firewall ports opened!"
}

letsencrypt() {
  FAILED=false

  output "Configuring Let's Encrypt..."

  # Obtain certificate
  certbot --nginx --redirect --no-eff-email --email "$email" -d "$FQDN" || FAILED=true

  # Check if it succeded
  if [ ! -d "/etc/letsencrypt/live/$FQDN/" ] || [ "$FAILED" == true ]; then
    warning "The process of obtaining a Let's Encrypt certificate failed!"
    echo -n "* Still assume SSL? (y/N): "
    read -r CONFIGURE_SSL

    if is_yes "$CONFIGURE_SSL"; then
      ASSUME_SSL=true
      CONFIGURE_LETSENCRYPT=false
      configure_nginx
    else
      ASSUME_SSL=false
      CONFIGURE_LETSENCRYPT=false
      sed -i "s@^APP_URL=.*@APP_URL=http://$FQDN@" .env
      "$PHP_BIN" artisan config:clear
      "$PHP_BIN" artisan queue:restart
      configure_nginx
    fi
  else
    success "The process of obtaining a Let's Encrypt certificate succeeded!"
  fi
}

# ------ Webserver configuration functions ----- #

configure_nginx() {
  output "Configuring nginx .."

  if [ "$ASSUME_SSL" == true ] && [ "$CONFIGURE_LETSENCRYPT" == false ]; then
    DL_FILE="nginx_ssl.conf"
  else
    DL_FILE="nginx.conf"
  fi

  case "$OS" in
  ubuntu | debian)
    PHP_SOCKET="/run/php/php8.3-fpm.sock"
    CONFIG_PATH_AVAIL="/etc/nginx/sites-available"
    CONFIG_PATH_ENABL="/etc/nginx/sites-enabled"
    ;;
  rocky | almalinux)
    PHP_SOCKET="/var/run/php-fpm/nothing.sock"
    CONFIG_PATH_AVAIL="/etc/nginx/conf.d"
    CONFIG_PATH_ENABL="$CONFIG_PATH_AVAIL"
    ;;
  esac

  rm -rf "$CONFIG_PATH_ENABL"/default

  curl -fsSL -o "$CONFIG_PATH_AVAIL"/nothing.conf "$GITHUB_URL"/configs/$DL_FILE

  sed -i -e "s@<domain>@${FQDN}@g" "$CONFIG_PATH_AVAIL"/nothing.conf

  sed -i -e "s@<php_socket>@${PHP_SOCKET}@g" "$CONFIG_PATH_AVAIL"/nothing.conf
  if [ "$PANEL_MAJOR_VERSION" == "2" ]; then
    # ^~ prevents asset paths from falling through to the PHP handler.
    # shellcheck disable=SC2016
    sed -i '/    location ~ \\.php\$ {/i\
    location ^~ /assets/ {\n\
        location ~ /\\. { deny all; }\n\
        try_files $uri =404;\n\
    }\n' "$CONFIG_PATH_AVAIL"/nothing.conf
  fi

  case "$OS" in
  ubuntu | debian)
    ln -sf "$CONFIG_PATH_AVAIL"/nothing.conf "$CONFIG_PATH_ENABL"/nothing.conf
    ln -sf "$CONFIG_PATH_AVAIL"/nothing.conf "$CONFIG_PATH_AVAIL"/pterodactyl.conf 2>/dev/null || true
    ln -sf "$CONFIG_PATH_AVAIL"/nothing.conf "$CONFIG_PATH_ENABL"/pterodactyl.conf 2>/dev/null || true
    ;;
  rocky | almalinux)
    ln -sf "$CONFIG_PATH_AVAIL"/nothing.conf "$CONFIG_PATH_AVAIL"/pterodactyl.conf 2>/dev/null || true
    ;;
  esac

  if [ "$ASSUME_SSL" == false ] && [ "$CONFIGURE_LETSENCRYPT" == false ]; then
    nginx -t
    systemctl restart nginx
  fi

  success "Nginx configured!"
}

# --------------- Cloudflare Tunnel ------------ #

install_cloudflared() {
  if command -v cloudflared >/dev/null 2>&1; then
    success "cloudflared is already installed!"
    return 0
  fi
  output "Installing Cloudflare Tunnel (cloudflared)..."
  local arch="amd64"
  [ "$(uname -m)" == "aarch64" ] && arch="arm64"
  curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}" -o /usr/local/bin/cloudflared
  chmod +x /usr/local/bin/cloudflared
  if command -v cloudflared >/dev/null 2>&1; then
    success "cloudflared installed successfully!"
  else
    warning "Binary install failed, falling back to package manager..."
    case "$OS" in
      ubuntu|debian)
        mkdir -p --mode=0755 /etc/apt/keyrings
        curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /etc/apt/keyrings/cloudflare-main.gpg >/dev/null
        echo "deb [signed-by=/etc/apt/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflared.list
        apt-get update -y && apt-get install -y cloudflared || true
        ;;
    esac
  fi
}

# --------------- Main functions --------------- #

perform_install() {
  output "Starting Nothing Panel installation... this might take a while!"
  dep_install
  check_database_connection
  install_composer
  ptdl_dl
  install_composer_deps
  create_db_user "$MYSQL_USER" "$MYSQL_PASSWORD"
  create_db "$MYSQL_DB" "$MYSQL_USER"
  configure
  set_folder_permissions
  insert_cronjob
  install_pteroq
  configure_nginx
  [ "$CONFIGURE_LETSENCRYPT" == true ] && letsencrypt

  # Setup Cloudflare Tunnel for NAT VPS / Non-Dedicated
  if [ "$USE_CLOUDFLARE_TUNNEL" == true ]; then
    install_cloudflared

    if [ "$CF_TUNNEL_MODE" == "token" ] && [ -n "$CF_TUNNEL_TOKEN" ]; then
      output "Installing Cloudflare Tunnel service with Token..."
      cloudflared service install "$CF_TUNNEL_TOKEN" || true
      systemctl enable --now cloudflared || true
      success "Cloudflare Tunnel active for https://$FQDN!"
    else
      output "Starting Cloudflare Quick Tunnel (*.trycloudflare.com)..."
      cat << 'EOF_CF' > /etc/systemd/system/cloudflared-panel.service
[Unit]
Description=Cloudflare Quick Tunnel for Nothing Panel
After=network.target nginx.service

[Service]
Type=simple
ExecStart=/usr/local/bin/cloudflared tunnel --url http://127.0.0.1:80 --logfile /var/log/cloudflared-panel.log
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF_CF
      systemctl daemon-reload
      systemctl enable --now cloudflared-panel
      sleep 5
      local assigned_url
      assigned_url=$(grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' /var/log/cloudflared-panel.log 2>/dev/null | tail -n 1 || true)
      if [ -n "$assigned_url" ]; then
        local assigned_domain="${assigned_url#https://}"
        output "Assigned Cloudflare URL: $assigned_url"
        sed -i "s@^APP_URL=.*@APP_URL=${assigned_url}@" /var/www/nothing/.env
        sed -i -e "s@server_name [^;]*;@server_name ${assigned_domain} localhost;@g" /etc/nginx/sites-available/nothing.conf /etc/nginx/sites-available/pterodactyl.conf 2>/dev/null || true
        "$PHP_BIN" artisan config:clear
        "$PHP_BIN" artisan queue:restart
        systemctl reload nginx || true
        export FQDN="$assigned_domain"
        success "Cloudflare Quick Tunnel is LIVE at: $assigned_url"
      else
        warning "Could not parse trycloudflare URL immediately. Check status: journalctl -u cloudflared-panel"
      fi
    fi
  fi

  # Install Nothing Panel Domain Manager (np-domain)
  output "Installing Nothing Panel Domain Manager (np-domain)..."
  curl -fsSL "$GITHUB_URL/scripts/np-domain.sh" -o /usr/local/bin/np-domain 2>/dev/null || true
  chmod +x /usr/local/bin/np-domain 2>/dev/null || true

  # Apply Nothing Panel UI branding
  output "Applying Nothing Panel custom branding & theme..."
  curl -fsSL "$GITHUB_URL/scripts/brand-panel.sh" | bash || true

  # Automatically install and configure Wings daemon, Node & Allocations (unless panel only is selected)
  if [ "${SKIP_WINGS_AUTO_SETUP:-false}" != "true" ]; then
    output "Automatically installing and configuring Wings Daemon, Node & Allocations..."
    curl -fsSL "$GITHUB_URL/scripts/setup-node.sh" | bash || true
  fi

  if [ -n "${INSTALL_SETTINGS:-}" ]; then
    check_install_settings
    printf 'CONFIGURE_FIREWALL=%s\nCONFIGURE_LETSENCRYPT=%s\nASSUME_SSL=%s\nFQDN=%s\nEMAIL=%s\nPANEL_MAJOR_VERSION=%s\nUSE_CLOUDFLARE_TUNNEL=%s\nCF_TUNNEL_MODE=%s\n' \
      "$CONFIGURE_FIREWALL" "$CONFIGURE_LETSENCRYPT" "$ASSUME_SSL" "$FQDN" "$email" "$PANEL_MAJOR_VERSION" "$USE_CLOUDFLARE_TUNNEL" "$CF_TUNNEL_MODE" >"$INSTALL_SETTINGS"
  fi

  return 0
}

# ------------------- Install ------------------ #

perform_install
