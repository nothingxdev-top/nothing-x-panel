#!/bin/bash

######################################################################################
#  Nothing X Panel — Auto Installer                                                  #
#  Pre-configured, non-interactive installation                                      #
######################################################################################

set -e -o pipefail

# ── Re-exec from file if piped ──
if [ ! -t 0 ] && [ -z "$NP_REEXEC" ]; then
  TMPFILE=$(mktemp /tmp/np-auto.XXXXXX.sh)
  trap 'rm -f "$TMPFILE"' EXIT
  curl -fsSL "https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/scripts/auto-install.sh" -o "$TMPFILE"
  chmod +x "$TMPFILE"
  NP_REEXEC=1 exec bash "$TMPFILE"
fi

# ── Root check ──
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Run as root: sudo bash <(curl -fsSL ...)"
  exit 1
fi

export GITHUB_SOURCE="master"
export GITHUB_BASE_URL="https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel"
export GITHUB_URL="$GITHUB_BASE_URL/$GITHUB_SOURCE"

# ═══════════════════════════════════════════
# ██  PRE-CONFIGURED SETTINGS  ██
# ═══════════════════════════════════════════

# Panel domain
export FQDN="panel.fayas.nx.kg"

# MySQL credentials
export MYSQL_DB="nothing_panel"
export MYSQL_USER="nothing_panel_user"
export MYSQL_PASSWORD="Np@$(openssl rand -hex 12)"

# Timezone
export timezone="Asia/Kolkata"

# Email (Let's Encrypt + panel)
export email="fayasshameem3@gmail.com"

# Admin account
export user_email="fayasshameem3@gmail.com"
export user_username="admin"
export user_firstname="Admin"
export user_lastname="User"
export user_password="admin1234"

# SSL + Firewall
export CONFIGURE_LETSENCRYPT="true"
export CONFIGURE_FIREWALL="true"
export ASSUME_SSL="false"

# Panel version (1 = stable)
export PANEL_MAJOR_VERSION="1"

# Telemetry off
export telemetry="false"

# ═══════════════════════════════════════════
# Download lib and run installer
# ═══════════════════════════════════════════

echo ""
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║         Nothing X Panel — Auto Installer                    ║"
echo "  ╠══════════════════════════════════════════════════════════════╣"
echo "  ║  Domain   : $FQDN"
echo "  ║  Email    : $email"
echo "  ║  Username : $user_username"
echo "  ║  SSL      : Let's Encrypt (auto)"
echo "  ║  Firewall : auto"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Starting installation in 3 seconds..."
sleep 3

# Download lib.sh
[ -f /tmp/lib.sh ] && rm -f /tmp/lib.sh
curl -fsSL -o /tmp/lib.sh "$GITHUB_URL/lib/lib.sh"
source /tmp/lib.sh

# Run panel installer directly (non-interactive)
echo ""
output "Running Nothing X Panel installer..."

script=$(curl -fsSL "$GITHUB_URL/installers/panel.sh") || { echo "Failed to download panel installer"; exit 1; }
bash -e -o pipefail -c "$script"

# Update password to admin as requested
if [ -d /var/www/pterodactyl ]; then
  cd /var/www/pterodactyl
  php artisan tinker --execute="\$u = \App\Models\User::where('username', '$user_username')->first(); if(\$u){ \$u->password = Hash::make('admin'); \$u->save(); }" 2>/dev/null || true
fi

echo ""
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║  ✔  Nothing X Panel Installation Complete!                  ║"
echo "  ╠══════════════════════════════════════════════════════════════╣"
echo "  ║  URL      : https://$FQDN"
echo "  ║  Username : $user_username"
echo "  ║  Password : admin"
echo "  ║  Email    : $user_email"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo ""

rm -f /tmp/lib.sh
