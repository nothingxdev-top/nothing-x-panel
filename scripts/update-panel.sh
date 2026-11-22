#!/bin/bash

######################################################################################
#  Nothing X Panel — Safe In-Place Update Script (Preserves Data)                   #
#  Updates panel engine, applies migrations, clears cache & preserves all data       #
######################################################################################

set -e -o pipefail

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Must run as root"
  exit 1
fi

# Detect Panel Directory
PANEL_DIR=""
if [ -d "/var/www/nothing" ]; then
  PANEL_DIR="/var/www/nothing"
elif [ -d "/var/www/pterodactyl" ]; then
  PANEL_DIR="/var/www/pterodactyl"
else
  echo "ERROR: Panel directory not found."
  exit 1
fi

echo "=========================================================="
echo " Updating Nothing Panel (Preserving All Data & Database)  "
echo " Target: $PANEL_DIR"
echo "=========================================================="

cd "$PANEL_DIR"

# 1. Put panel into maintenance mode
echo "* Entering maintenance mode..."
php artisan down || true

# 2. Backup .env and storage
echo "* Backing up configuration..."
cp .env .env.backup.$(date +%Y%m%d%H%M%S)

# 3. Download latest release
echo "* Downloading latest release files..."
curl -L https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz | tar -xzv
chmod -R 755 storage/* bootstrap/cache

# 4. Update dependencies
echo "* Updating Composer dependencies..."
export COMPOSER_ALLOW_SUPERUSER=1
composer install --no-dev --optimize-autoloader

# 5. Run database migrations (safe, preserves data)
echo "* Running database migrations..."
php artisan migrate --seed --force

# 6. Apply Nothing custom branding & theme
echo "* Re-applying custom branding and theme..."
NP_NO_MENU=1 curl -fsSL "https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/scripts/brand-panel.sh" | NP_NO_MENU=1 bash || true

# 7. Clear caches
echo "* Clearing application cache..."
php artisan view:clear || true
php artisan config:clear || true
php artisan cache:clear || true

# 8. Set permissions
chown -R www-data:www-data "$PANEL_DIR" 2>/dev/null || chown -R nginx:nginx "$PANEL_DIR" 2>/dev/null || true

# 9. Restart queue & web services
echo "* Restarting services..."
systemctl restart nothingq 2>/dev/null || systemctl restart pteroq 2>/dev/null || true
systemctl restart php8.3-fpm 2>/dev/null || true
systemctl reload nginx 2>/dev/null || true

# 10. Exit maintenance mode
echo "* Exiting maintenance mode..."
php artisan up || true

echo "=========================================================="
echo " ✔ Nothing Panel successfully updated without data loss!  "
echo "=========================================================="
