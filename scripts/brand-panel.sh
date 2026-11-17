#!/bin/bash

######################################################################################
#  Nothing X Panel — Web UI Customizer & Brand Application Script                    #
#  Rebrands the web interface to Nothing Panel / Nothing X aesthetics                #
######################################################################################

set -e

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Must run as root"
  exit 1
fi

PANEL_DIR="/var/www/pterodactyl"

if [ ! -d "$PANEL_DIR" ]; then
  echo "ERROR: Panel directory not found at $PANEL_DIR"
  exit 1
fi

echo "Applying Nothing Panel custom branding..."

# 1. Update APP_NAME in .env
sed -i '/^APP_NAME=/d' "$PANEL_DIR/.env"
sed -i '1i APP_NAME="Nothing Panel"' "$PANEL_DIR/.env"

# 2. Deploy Nothing X Logo SVG
cat << 'EOF' > "$PANEL_DIR/public/assets/svgs/pterodactyl.svg"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 300" width="300" height="300">
  <defs>
    <linearGradient id="cyanGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#00f2fe" />
      <stop offset="100%" stop-color="#4facfe" />
    </linearGradient>
    <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="6" result="blur" />
      <feMerge>
        <feMergeNode in="blur" />
        <feMergeNode in="SourceGraphic" />
      </feMerge>
    </filter>
  </defs>
  
  <rect x="20" y="20" width="260" height="260" rx="36" fill="#0d1117" stroke="url(#cyanGrad)" stroke-width="2.5" filter="url(#glow)" />
  <rect x="28" y="28" width="244" height="244" rx="28" fill="#101522" stroke="#1c2538" stroke-width="1.5" />
  
  <g transform="translate(150, 115)">
    <path d="M -40,42 L -40,-42 L -20,-42 L 20,20 L 20,-42 L 40,-42 L 40,42 L 20,42 L -20,-20 L -20,42 Z" 
          fill="url(#cyanGrad)" filter="url(#glow)" />
    <circle cx="-52" cy="-42" r="3" fill="#00f2fe" />
    <circle cx="-52" cy="0" r="3" fill="#00f2fe" opacity="0.6" />
    <circle cx="-52" cy="42" r="3" fill="#00f2fe" />
    <circle cx="52" cy="-42" r="3" fill="#4facfe" />
    <circle cx="52" cy="0" r="3" fill="#4facfe" opacity="0.6" />
    <circle cx="52" cy="42" r="3" fill="#4facfe" />
  </g>
  
  <text x="150" y="200" font-family="'Courier New', Courier, monospace, sans-serif" 
        font-size="20" font-weight="900" fill="#ffffff" letter-spacing="8" text-anchor="middle">
    NOTHING
  </text>
  <text x="150" y="224" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" 
        font-size="11" font-weight="800" fill="#00f2fe" letter-spacing="5" text-anchor="middle">
    X  P A N E L
  </text>
  
  <line x1="60" y1="240" x2="240" y2="240" stroke="url(#cyanGrad)" stroke-width="1" opacity="0.5" />
  <circle cx="150" cy="240" r="3" fill="#00f2fe" />
</svg>
EOF
chmod 644 "$PANEL_DIR/public/assets/svgs/pterodactyl.svg"
chown www-data:www-data "$PANEL_DIR/public/assets/svgs/pterodactyl.svg"

# 3. Inject Custom Nothing UI Styling into wrapper.blade.php
WRAPPER="$PANEL_DIR/resources/views/templates/wrapper.blade.php"
if [ -f "$WRAPPER" ]; then
  sed -i "s@<title>{{ config('app.name', 'Pterodactyl') }}</title>@<title>Nothing Panel</title>@g" "$WRAPPER"
  
  if ! grep -q "Nothing Panel Custom UI" "$WRAPPER"; then
    TMP_STYLE=$(mktemp)
    cat << 'EOF' > "$TMP_STYLE"
        <!-- Nothing Panel Custom UI & Branding -->
        <style>
            :root {
                --np-cyan: #00f2fe;
                --np-blue: #4facfe;
            }
            body {
                background: #080a0f !important;
                background-image: radial-gradient(circle at 50% 15%, rgba(0, 242, 254, 0.07) 0%, transparent 60%) !important;
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif !important;
            }
            div[class*="LoginFormContainer___StyledDiv3"],
            div[class*="LoginFormContainer___StyledDiv "] {
                color: #f1f5f9 !important;
            }
            div[style*="background-color: rgb(255, 255, 255)"],
            div[class*="LoginFormContainer___StyledDiv"] {
                background-color: #111522 !important;
                border: 1px solid rgba(0, 242, 254, 0.22) !important;
                box-shadow: 0 20px 50px rgba(0, 0, 0, 0.8), 0 0 30px rgba(0, 242, 254, 0.1) !important;
                border-radius: 12px !important;
            }
            input[type="text"], input[type="password"], input[type="email"] {
                background-color: #0b0e17 !important;
                border: 1px solid #20293d !important;
                color: #ffffff !important;
                border-radius: 8px !important;
                transition: all 0.25s ease !important;
            }
            input[type="text"]:focus, input[type="password"]:focus, input[type="email"]:focus {
                border-color: #00f2fe !important;
                box-shadow: 0 0 12px rgba(0, 242, 254, 0.35) !important;
                background-color: #0f1422 !important;
            }
            label {
                color: #94a3b8 !important;
                font-weight: 600 !important;
                font-size: 0.75rem !important;
                letter-spacing: 0.5px !important;
            }
            button[type="submit"] {
                background: linear-gradient(135deg, #00f2fe 0%, #4facfe 100%) !important;
                color: #060c18 !important;
                font-weight: 800 !important;
                letter-spacing: 1px !important;
                border-radius: 8px !important;
                box-shadow: 0 4px 18px rgba(0, 242, 254, 0.4) !important;
                transition: all 0.2s ease !important;
            }
            button[type="submit"]:hover {
                transform: translateY(-2px) !important;
                box-shadow: 0 6px 25px rgba(0, 242, 254, 0.65) !important;
            }
            a {
                color: #00f2fe !important;
            }
            div[class*="LoginFormContainer___StyledDiv2"] {
                background: transparent !important;
            }
        </style>
    </head>
EOF
    sed -i '/<\/head>/e cat '"$TMP_STYLE" "$WRAPPER"
    rm -f "$TMP_STYLE"
  fi
fi

# 4. Rebrand Admin Views
ADMIN_BLADE="$PANEL_DIR/resources/views/layouts/admin.blade.php"
if [ -f "$ADMIN_BLADE" ]; then
  sed -i 's@https://pterodactyl\.io/@https://panel.fayas.nx.kg@g' "$ADMIN_BLADE"
  sed -i 's@https://pterodactyl\.io@https://panel.fayas.nx.kg@g' "$ADMIN_BLADE"
  sed -i 's@Pterodactyl Software@Nothing Panel@g' "$ADMIN_BLADE"
  sed -i 's@<b>Pterodactyl</b>@<b>Nothing</b> Panel@g' "$ADMIN_BLADE"
  sed -i "s@<span>{{ config('app.name', 'Pterodactyl') }}</span>@<span>Nothing Panel</span>@g" "$ADMIN_BLADE"
fi

ADMIN_INDEX="$PANEL_DIR/resources/views/admin/index.blade.php"
if [ -f "$ADMIN_INDEX" ]; then
  sed -i 's@https://github\.com/pterodactyl/panel@https://github.com/nothingxdev-top/nothing-x-panel@g' "$ADMIN_INDEX"
  sed -i 's@https://pterodactyl\.io@https://panel.fayas.nx.kg@g' "$ADMIN_INDEX"
  sed -i 's@https://discord\.gg/pterodactyl@#@g' "$ADMIN_INDEX"
  sed -i 's@https://github\.com/sponsors/pterodactyl@https://github.com/nothingxdev-top@g' "$ADMIN_INDEX"
fi

# 5. Patch Built JS Assets via Python
python3 - << 'PYEOF'
import glob, os

for f in glob.glob('/var/www/pterodactyl/public/assets/*.js'):
    with open(f, 'rb') as fp:
        raw = fp.read()
    
    replacements = [
        (b'Pterodactyl\xc2\xae', b'Nothing Panel\xc2\xae'),
        (b'Pterodactyl\xe2\x84\xa2', b'Nothing Panel\xe2\x84\xa2'),
        (b'Pterodactyl Software', b'Nothing Panel'),
        (b'https://pterodactyl.io', b'https://panel.fayas.nx.kg'),
        (b'\xc2\xa9 2015 - ', b'\xc2\xa9 '),
        (b'\xc2\xa9 2026 2026', b'\xc2\xa9 2026'),
        (b'\xc2\xa9 2026 ', b'\xc2\xa9 '),
        (b'"Pterodactyl"', b'"Nothing Panel"'),
        (b'>Pterodactyl<', b'>Nothing Panel<'),
    ]
    
    modified = False
    for old, new in replacements:
        if old in raw:
            raw = raw.replace(old, new)
            modified = True
            
    # Protect required JS internal object
    if b'Nothing PanelUser' in raw:
        raw = raw.replace(b'Nothing PanelUser', b'PterodactylUser')
        modified = True
        
    if modified:
        with open(f, 'wb') as fp:
            fp.write(raw)
        print(f"  ✔ Rebranded asset: {os.path.basename(f)}")
PYEOF

# 6. Ensure Permissions & Clear Caches
chown -R www-data:www-data "$PANEL_DIR"
chmod -R 755 "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"

cd "$PANEL_DIR"
php artisan view:clear >/dev/null 2>&1 || true
php artisan config:clear >/dev/null 2>&1 || true
php artisan cache:clear >/dev/null 2>&1 || true

systemctl restart php8.3-fpm nginx 2>/dev/null || true

echo "Nothing Panel custom branding applied successfully!"
