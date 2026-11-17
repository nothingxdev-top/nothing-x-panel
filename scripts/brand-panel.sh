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

# 1. Update APP_NAME & read PANEL_URL from .env
sed -i '/^APP_NAME=/d' "$PANEL_DIR/.env"
sed -i '1i APP_NAME="Nothing Panel"' "$PANEL_DIR/.env"

APP_URL_LINE=$(grep '^APP_URL=' "$PANEL_DIR/.env" | head -1 || true)
PANEL_URL=$(echo "$APP_URL_LINE" | cut -d '=' -f2 | tr -d '"' | tr -d "'" | tr -d ' ' || true)
if [ -z "$PANEL_URL" ]; then
  PANEL_URL="https://panel.fayas.nx.kg"
fi
export PANEL_URL

# 2. Deploy Nothing X Logo SVG with #C268F2 Theme
cat << 'EOF' > "$PANEL_DIR/public/assets/svgs/pterodactyl.svg"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 300" width="300" height="300">
  <defs>
    <linearGradient id="purpleGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#C268F2" />
      <stop offset="100%" stop-color="#8A2BE2" />
    </linearGradient>
    <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="6" result="blur" />
      <feMerge>
        <feMergeNode in="blur" />
        <feMergeNode in="SourceGraphic" />
      </feMerge>
    </filter>
  </defs>
  
  <rect x="20" y="20" width="260" height="260" rx="36" fill="#0d0a17" stroke="url(#purpleGrad)" stroke-width="2.5" filter="url(#glow)" />
  <rect x="28" y="28" width="244" height="244" rx="28" fill="#140f24" stroke="#251a3d" stroke-width="1.5" />
  
  <g transform="translate(150, 115)">
    <path d="M -40,42 L -40,-42 L -20,-42 L 20,20 L 20,-42 L 40,-42 L 40,42 L 20,42 L -20,-20 L -20,42 Z" 
          fill="url(#purpleGrad)" filter="url(#glow)" />
    <circle cx="-52" cy="-42" r="3" fill="#C268F2" />
    <circle cx="-52" cy="0" r="3" fill="#C268F2" opacity="0.6" />
    <circle cx="-52" cy="42" r="3" fill="#C268F2" />
    <circle cx="52" cy="-42" r="3" fill="#8A2BE2" />
    <circle cx="52" cy="0" r="3" fill="#8A2BE2" opacity="0.6" />
    <circle cx="52" cy="42" r="3" fill="#8A2BE2" />
  </g>
  
  <text x="150" y="200" font-family="'Courier New', Courier, monospace, sans-serif" 
        font-size="20" font-weight="900" fill="#ffffff" letter-spacing="8" text-anchor="middle">
    NOTHING
  </text>
  <text x="150" y="224" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" 
        font-size="11" font-weight="800" fill="#C268F2" letter-spacing="5" text-anchor="middle">
    X  P A N E L
  </text>
  
  <line x1="60" y1="240" x2="240" y2="240" stroke="url(#purpleGrad)" stroke-width="1" opacity="0.5" />
  <circle cx="150" cy="240" r="3" fill="#C268F2" />
</svg>
EOF
chmod 644 "$PANEL_DIR/public/assets/svgs/pterodactyl.svg"
chown www-data:www-data "$PANEL_DIR/public/assets/svgs/pterodactyl.svg"

# 3. Inject Custom Nothing UI Styling into wrapper.blade.php
WRAPPER="$PANEL_DIR/resources/views/templates/wrapper.blade.php"
if [ -f "$WRAPPER" ]; then
  sed -i "s@<title>{{ config('app.name', 'Pterodactyl') }}</title>@<title>Nothing Panel</title>@g" "$WRAPPER"
  
  # Remove previous injection if present to allow re-applying cleanly
  sed -i '/<!-- Nothing Panel Custom UI/,/<\/style>/d' "$WRAPPER"
  
  TMP_STYLE=$(mktemp)
  cat << 'EOF' > "$TMP_STYLE"
        <!-- Nothing Panel Custom UI & Branding -->
        <style>
            :root {
                --np-primary: #C268F2;
                --np-secondary: #8A2BE2;
                --np-accent: #DA70D6;
                --np-dark: #090810;
                --np-card: #151124;
            }
            body {
                background: #090810 !important;
                background-image: radial-gradient(circle at 50% 15%, rgba(194, 104, 242, 0.12) 0%, transparent 65%) !important;
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif !important;
            }
            /* REMOVE THE MASCOT IMAGE & CONTAINER COMPLETELY */
            div[class*="LoginFormContainer___StyledDiv2"],
            img[src*="pterodactyl.svg"],
            img[alt*="pterodactyl"] {
                display: none !important;
            }
            /* CENTER AND STYLE THE LOGIN CARD PROPERLY */
            div[class*="LoginFormContainer___StyledDiv"] {
                max-width: 440px !important;
                margin: 2.5rem auto !important;
                background-color: rgba(21, 17, 36, 0.96) !important;
                border: 1px solid rgba(194, 104, 242, 0.35) !important;
                box-shadow: 0 25px 65px rgba(0, 0, 0, 0.85), 0 0 35px rgba(194, 104, 242, 0.2) !important;
                border-radius: 16px !important;
                padding: 2.5rem 2rem !important;
                display: block !important;
            }
            div[class*="LoginFormContainer___StyledDiv3"] {
                width: 100% !important;
                flex: none !important;
                color: #f1f5f9 !important;
            }
            /* H2 Login Title */
            h2[class*="LoginFormContainer"] {
                color: #ffffff !important;
                font-weight: 800 !important;
                letter-spacing: 0.5px !important;
                text-align: center !important;
                font-size: 1.75rem !important;
            }
            /* Inputs */
            input[type="text"], input[type="password"], input[type="email"] {
                background-color: #0e0b1a !important;
                border: 1px solid #2d2447 !important;
                color: #ffffff !important;
                border-radius: 10px !important;
                padding: 0.85rem 1rem !important;
                transition: all 0.25s ease !important;
            }
            input[type="text"]:focus, input[type="password"]:focus, input[type="email"]:focus {
                border-color: #C268F2 !important;
                box-shadow: 0 0 16px rgba(194, 104, 242, 0.45) !important;
                background-color: #130f24 !important;
                outline: none !important;
            }
            label {
                color: #bfa8db !important;
                font-weight: 700 !important;
                font-size: 0.75rem !important;
                letter-spacing: 0.8px !important;
                text-transform: uppercase !important;
            }
            /* Submit Button with #C268F2 Gradient */
            button[type="submit"] {
                background: linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%) !important;
                color: #ffffff !important;
                font-weight: 800 !important;
                letter-spacing: 1.2px !important;
                border-radius: 10px !important;
                box-shadow: 0 4px 20px rgba(194, 104, 242, 0.5) !important;
                transition: all 0.2s ease !important;
                text-transform: uppercase !important;
                border: none !important;
                padding: 0.85rem !important;
            }
            button[type="submit"]:hover {
                transform: translateY(-2px) !important;
                box-shadow: 0 6px 28px rgba(194, 104, 242, 0.75) !important;
                filter: brightness(1.1) !important;
            }
            /* Links & Footer */
            a {
                color: #C268F2 !important;
                transition: all 0.2s ease !important;
            }
            a:hover {
                color: #e29eff !important;
                text-shadow: 0 0 8px rgba(194, 104, 242, 0.6) !important;
            }
            p[class*="LoginFormContainer___StyledP"] {
                color: #8c76ab !important;
            }
            p[class*="LoginFormContainer___StyledP"] a {
                color: #C268F2 !important;
            }
            /* Admin Layout Navbar & Theme */
            .skin-blue .main-header .navbar,
            .skin-blue .main-header .logo {
                background-color: #120e22 !important;
                border-bottom: 2px solid #C268F2 !important;
            }
            .skin-blue .main-sidebar {
                background-color: #0c0916 !important;
            }
            .content-wrapper {
                background-color: #08060f !important;
            }
            .btn-primary {
                background-color: #C268F2 !important;
                border-color: #9B42DA !important;
            }
            .btn-primary:hover {
                background-color: #d182fc !important;
            }
            .box.box-primary {
                border-top-color: #C268F2 !important;
            }
            .box {
                background: #141024 !important;
                border: 1px solid rgba(194, 104, 242, 0.2) !important;
                color: #e2d9f3 !important;
            }
        </style>
    </head>
EOF
  sed -i '/<\/head>/e cat '"$TMP_STYLE" "$WRAPPER"
  rm -f "$TMP_STYLE"
fi

# 4. Rebrand Admin Views
ADMIN_BLADE="$PANEL_DIR/resources/views/layouts/admin.blade.php"
if [ -f "$ADMIN_BLADE" ]; then
  sed -i 's@https://pterodactyl\.io/@#@g' "$ADMIN_BLADE"
  sed -i 's@https://pterodactyl\.io@#@g' "$ADMIN_BLADE"
  sed -i 's@Pterodactyl Software@Nothing Panel@g' "$ADMIN_BLADE"
  sed -i 's@<b>Pterodactyl</b>@<b>Nothing</b> Panel@g' "$ADMIN_BLADE"
  sed -i "s@<span>{{ config('app.name', 'Pterodactyl') }}</span>@<span>Nothing Panel</span>@g" "$ADMIN_BLADE"
  sed -i "s@Copyright &copy; 2015 - {{ date('Y') }}@Copyright &copy; {{ date('Y') }}@g" "$ADMIN_BLADE"
fi

ADMIN_INDEX="$PANEL_DIR/resources/views/admin/index.blade.php"
if [ -f "$ADMIN_INDEX" ]; then
  sed -i 's@Pterodactyl Panel@Nothing Panel@g' "$ADMIN_INDEX"
  sed -i 's@Pterodactyl@Nothing@g' "$ADMIN_INDEX"
  sed -i 's@https://github\.com/pterodactyl/panel@https://github.com/nothingxdev-top/nothing-x-panel@g' "$ADMIN_INDEX"
  sed -i 's@https://pterodactyl\.io@#@g' "$ADMIN_INDEX"
  sed -i 's@https://discord\.gg/pterodactyl@#@g' "$ADMIN_INDEX"
  sed -i 's@https://github\.com/sponsors/pterodactyl@https://github.com/nothingxdev-top@g' "$ADMIN_INDEX"
fi

# 5. Patch Built JS Assets via Python
python3 - << 'PYEOF'
import glob, os

panel_url = os.environ.get('PANEL_URL', 'https://panel.fayas.nx.kg').encode('utf-8')

for f in glob.glob('/var/www/pterodactyl/public/assets/*.js'):
    with open(f, 'rb') as fp:
        raw = fp.read()
    
    replacements = [
        (b'Pterodactyl\xc2\xae', b'Nothing Panel\xc2\xae'),
        (b'Pterodactyl\xe2\x84\xa2', b'Nothing Panel\xe2\x84\xa2'),
        (b'Pterodactyl Software', b'Nothing Panel'),
        (b'https://pterodactyl.io', panel_url),
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
