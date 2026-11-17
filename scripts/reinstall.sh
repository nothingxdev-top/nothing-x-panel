#!/bin/bash

######################################################################################
#  Nothing X Panel — Check & Reinstall Script                                        #
#  Removes existing installation and does a clean fresh install                      #
######################################################################################

set -e -o pipefail

# ── Re-exec from file if piped ──
if [ ! -t 0 ] && [ -z "$NP_REEXEC" ]; then
  TMPFILE=$(mktemp /tmp/np-reinstall.XXXXXX.sh)
  trap 'rm -f "$TMPFILE"' EXIT
  curl -fsSL "https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/scripts/reinstall.sh" -o "$TMPFILE"
  chmod +x "$TMPFILE"
  NP_REEXEC=1 exec bash "$TMPFILE"
fi

# ── Root check ──
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Run as root: curl ... | sudo bash"
  exit 1
fi

# Colors
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[38;2;194;104;242m'
WHITE=$'\033[1;37m'
NC=$'\033[0m'

export GITHUB_SOURCE="master"
export GITHUB_BASE_URL="https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel"
export GITHUB_URL="$GITHUB_BASE_URL/$GITHUB_SOURCE"
export DEBIAN_FRONTEND="noninteractive"
export NEEDRESTART_MODE="a"

# ═══════════════════════════════════════════
# PRE-CONFIGURED SETTINGS
# ═══════════════════════════════════════════
export FQDN="panel.fayas.nx.kg"
export MYSQL_DB="nothing_panel"
export MYSQL_USER="nothing_panel_user"
export MYSQL_PASSWORD="NpSecure@2026$(openssl rand -hex 6)"
export timezone="Asia/Kolkata"
export email="fayasshameem3@gmail.com"
export user_email="fayasshameem3@gmail.com"
export user_username="admin"
export user_firstname="Admin"
export user_lastname="User"
export user_password="admin1234"
export CONFIGURE_LETSENCRYPT="true"
export CONFIGURE_FIREWALL="true"
export ASSUME_SSL="false"
export PANEL_MAJOR_VERSION="1"
export telemetry="false"

echo ""
echo -e "  ${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "  ${CYAN}║${NC}  ${WHITE}Nothing X Panel — Check & Reinstall${NC}                       ${CYAN}║${NC}"
echo -e "  ${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ═══════════════════════════════════════════
# STEP 1: SYSTEM CHECK
# ═══════════════════════════════════════════
echo -e "  ${CYAN}[ STEP 1 ]${NC} System Check..."
echo ""

# OS check
source /etc/os-release 2>/dev/null || true
echo -e "  ${GREEN}✔${NC} OS: $PRETTY_NAME"

# Disable needrestart prompts
mkdir -p /etc/needrestart/conf.d 2>/dev/null || true
echo '$nrconf{restart} = "a";' > /etc/needrestart/conf.d/autorestart.conf 2>/dev/null || true
echo '$nrconf{kernelhints} = 0;' >> /etc/needrestart/conf.d/autorestart.conf 2>/dev/null || true

# Check DNS for domain
echo -n "  Checking DNS for $FQDN ... "
RESOLVED=$(dig +short "$FQDN" 2>/dev/null || nslookup "$FQDN" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | tail -1 || echo "")
SERVER_IP=$(curl -fsSL ifconfig.me 2>/dev/null || curl -fsSL api.ipify.org 2>/dev/null || echo "unknown")
if [ "$RESOLVED" == "$SERVER_IP" ]; then
  echo -e "${GREEN}✔ DNS OK ($RESOLVED → this server)${NC}"
elif [ -z "$RESOLVED" ]; then
  echo -e "${YELLOW}⚠ DNS not resolved yet. SSL may fail!${NC}"
  echo -e "  ${YELLOW}  Add DNS A record: $FQDN → $SERVER_IP${NC}"
else
  echo -e "${YELLOW}⚠ DNS points to $RESOLVED but server is $SERVER_IP${NC}"
fi

echo ""

# ═══════════════════════════════════════════
# STEP 2: CLEAN EXISTING INSTALLATION
# ═══════════════════════════════════════════
echo -e "  ${CYAN}[ STEP 2 ]${NC} Cleaning existing installation..."
echo ""

CLEANED=false

# Remove panel files
if [ -d "/var/www/pterodactyl" ]; then
  echo -n "  Removing panel files ... "
  rm -rf /var/www/pterodactyl
  echo -e "${GREEN}✔${NC}"
  CLEANED=true
fi

# Remove wings config
if [ -d "/etc/pterodactyl" ]; then
  echo -n "  Removing wings config ... "
  rm -rf /etc/pterodactyl
  echo -e "${GREEN}✔${NC}"
  CLEANED=true
fi

# Stop and remove services
for svc in pteroq wings nginx php8.3-fpm; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    echo -n "  Stopping $svc ... "
    systemctl stop "$svc" 2>/dev/null || true
    echo -e "${GREEN}✔${NC}"
  fi
done

# Remove nginx panel config
if [ -f "/etc/nginx/sites-enabled/pterodactyl.conf" ]; then
  echo -n "  Removing nginx panel config ... "
  rm -f /etc/nginx/sites-enabled/pterodactyl.conf
  rm -f /etc/nginx/sites-available/pterodactyl.conf
  echo -e "${GREEN}✔${NC}"
  CLEANED=true
fi

# Remove old certbot cert
if [ -d "/etc/letsencrypt/live/$FQDN" ]; then
  echo -n "  Removing old SSL cert for $FQDN ... "
  certbot delete --cert-name "$FQDN" --non-interactive 2>/dev/null || true
  echo -e "${GREEN}✔${NC}"
fi

# Drop old database
if command -v mariadb >/dev/null 2>&1 || command -v mysql >/dev/null 2>&1; then
  DB_CMD=$(command -v mariadb 2>/dev/null || command -v mysql)
  echo -n "  Dropping old database ... "
  $DB_CMD -u root -e "DROP DATABASE IF EXISTS \`$MYSQL_DB\`;" 2>/dev/null || true
  $DB_CMD -u root -e "DROP USER IF EXISTS '$MYSQL_USER'@'127.0.0.1';" 2>/dev/null || true
  $DB_CMD -u root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
  echo -e "${GREEN}✔${NC}"
fi

# Remove cron job
if crontab -l 2>/dev/null | grep -q "pterodactyl"; then
  echo -n "  Removing old cron job ... "
  crontab -l 2>/dev/null | grep -v "pterodactyl" | crontab - 2>/dev/null || true
  echo -e "${GREEN}✔${NC}"
fi

# Remove systemd service
if [ -f "/etc/systemd/system/pteroq.service" ]; then
  echo -n "  Removing pteroq service ... "
  systemctl disable pteroq 2>/dev/null || true
  rm -f /etc/systemd/system/pteroq.service
  systemctl daemon-reload 2>/dev/null || true
  echo -e "${GREEN}✔${NC}"
fi

if [ "$CLEANED" == true ]; then
  echo -e "\n  ${GREEN}✔ Cleanup complete!${NC}"
else
  echo -e "  ${GREEN}✔ No existing installation found — fresh install!${NC}"
fi

echo ""
sleep 2

# ═══════════════════════════════════════════
# STEP 3: FRESH INSTALLATION
# ═══════════════════════════════════════════
echo -e "  ${CYAN}[ STEP 3 ]${NC} Installing Nothing X Panel..."
echo ""
echo -e "  ${WHITE}Settings:${NC}"
echo -e "  Domain   : ${GREEN}$FQDN${NC}"
echo -e "  Email    : ${GREEN}$email${NC}"
echo -e "  Username : ${GREEN}$user_username${NC}"
echo -e "  SSL      : ${GREEN}Let's Encrypt (auto)${NC}"
echo -e "  Firewall : ${GREEN}UFW (auto)${NC}"
echo ""
sleep 2

# Download lib.sh
[ -f /tmp/lib.sh ] && rm -f /tmp/lib.sh
curl -fsSL -o /tmp/lib.sh "$GITHUB_URL/lib/lib.sh"
# shellcheck source=lib/lib.sh
source /tmp/lib.sh

# Run panel installer
echo ""
echo -e "  ${CYAN}Starting panel installation (this takes 5-10 minutes)...${NC}"
echo ""

script=$(curl -fsSL "$GITHUB_URL/installers/panel.sh") || {
  echo -e "  ${RED}✖ Failed to download panel installer${NC}"
  exit 1
}
bash -e -o pipefail -c "$script"

# Update password to admin as requested
if [ -d /var/www/pterodactyl ]; then
  cd /var/www/pterodactyl
  php artisan tinker --execute="\$u = \Pterodactyl\Models\User::where('username', '$user_username')->first(); if(\$u){ \$u->password = \Illuminate\Support\Facades\Hash::make('admin'); \$u->save(); }" 2>/dev/null || true
  
  # Apply Nothing Panel UI custom branding
  curl -fsSL "$GITHUB_URL/scripts/brand-panel.sh" | bash || true
  
  # Ensure clean nginx start without port collisions
  killall -9 nginx 2>/dev/null || true
  sleep 1
  systemctl restart nginx php8.3-fpm 2>/dev/null || true
fi

# ═══════════════════════════════════════════
# STEP 4: DONE
# ═══════════════════════════════════════════
echo ""
echo -e "  ${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "  ${CYAN}║${NC}  ${GREEN}✔ Nothing X Panel Successfully Installed!${NC}               ${CYAN}║${NC}"
echo -e "  ${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
printf   "  ${CYAN}║${NC}  %-20s : %-36s${CYAN}║${NC}\n" "Panel URL"  "https://$FQDN"
printf   "  ${CYAN}║${NC}  %-20s : %-36s${CYAN}║${NC}\n" "Username"   "$user_username"
printf   "  ${CYAN}║${NC}  %-20s : %-36s${CYAN}║${NC}\n" "Password"   "admin"
printf   "  ${CYAN}║${NC}  %-20s : %-36s${CYAN}║${NC}\n" "Email"      "$user_email"
echo -e "  ${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "  ${CYAN}║${NC}  Next: Install Wings on game server nodes                     ${CYAN}║${NC}"
echo -e "  ${CYAN}║${NC}  Domain Manager: sudo np-domain                              ${CYAN}║${NC}"
echo -e "  ${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

rm -f /tmp/lib.sh
