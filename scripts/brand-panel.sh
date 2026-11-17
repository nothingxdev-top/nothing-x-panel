#!/bin/bash

######################################################################################
#  Nothing X Panel — Web UI Customizer & Brand Application Script                    #
#  Rebrands the web interface to Nothing Panel / Nothing X aesthetics (#C268F2)     #
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

echo "Applying Nothing Panel custom branding (#C268F2)..."

# 1. Update APP_NAME & ensure RECAPTCHA is disabled in .env
sed -i '/^APP_NAME=/d' "$PANEL_DIR/.env"
sed -i '1i APP_NAME="Nothing Panel"' "$PANEL_DIR/.env"

if grep -q '^RECAPTCHA_ENABLED=' "$PANEL_DIR/.env"; then
  sed -i 's/^RECAPTCHA_ENABLED=.*/RECAPTCHA_ENABLED=false/' "$PANEL_DIR/.env"
else
  echo "" >> "$PANEL_DIR/.env"
  echo "RECAPTCHA_ENABLED=false" >> "$PANEL_DIR/.env"
fi

if [ -f "$PANEL_DIR/config/recaptcha.php" ]; then
  sed -i "s/'enabled' => env('RECAPTCHA_ENABLED', true)/'enabled' => false/g" "$PANEL_DIR/config/recaptcha.php"
fi

APP_URL_LINE=$(grep '^APP_URL=' "$PANEL_DIR/.env" | head -1 || true)
PANEL_URL=$(echo "$APP_URL_LINE" | cut -d '=' -f2 | tr -d '"' | tr -d "'" | tr -d ' ' || true)
if [ -z "$PANEL_URL" ]; then
  PANEL_URL="https://panel.fayas.nx.kg"
fi
export PANEL_URL

# 2. Neutralize the dinosaur SVG (1x1 transparent)
mkdir -p "$PANEL_DIR/public/assets/svgs"
cat << 'EOF' > "$PANEL_DIR/public/assets/svgs/pterodactyl.svg"
<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1" viewBox="0 0 1 1"></svg>
EOF
chmod 644 "$PANEL_DIR/public/assets/svgs/pterodactyl.svg"
chown www-data:www-data "$PANEL_DIR/public/assets/svgs/pterodactyl.svg"

# 3. Patch Built React / JS Bundles (Remove Mascot & Footer Elements, Protect PterodactylUser)
python3 - << 'PYEOF'
import glob, os

panel_url = os.environ.get('PANEL_URL', 'https://panel.fayas.nx.kg')

for path in glob.glob('/var/www/pterodactyl/public/assets/*.js'):
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    changed = False

    # Remove mascot element from createElement in auth bundle
    target_mascot = 'o.createElement(f,{$_css4:{flex:"none",userSelect:"none",marginBottom:"1.5rem",alignSelf:"center","@media (min-width: 768px)":{marginBottom:"0px"}}},o.createElement(b,{src:"/assets/svgs/pterodactyl.svg",$_css5:{display:"block",width:"12rem",marginLeft:"auto",marginRight:"auto","@media (min-width: 768px)":{width:"16rem"}}})),'
    if target_mascot in content:
        content = content.replace(target_mascot, 'null,')
        changed = True

    # Remove footer element from createElement in auth bundle
    target_footer = 'o.createElement(x,{$_css7:{textAlign:"center"'
    if target_footer in content:
        content = content.replace(target_footer, 'null && o.createElement(x,{$_css7:{textAlign:"center"')
        changed = True

    for old, new in [
        ('Pterodactyl Software', 'Nothing Panel'),
        ('https://pterodactyl.io', panel_url),
        ('"Pterodactyl"', '"Nothing Panel"'),
        ('>Pterodactyl<', '>Nothing Panel<'),
    ]:
        if old in content:
            content = content.replace(old, new)
            changed = True

    # Protect internal JS state object
    if 'Nothing PanelUser' in content:
        content = content.replace('Nothing PanelUser', 'PterodactylUser')
        changed = True

    if changed:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"  ✔ Patched bundle: {os.path.basename(path)}")
PYEOF

# 4. Inject Modern Custom Theme into wrapper.blade.php
WRAPPER="$PANEL_DIR/resources/views/templates/wrapper.blade.php"
if [ -f "$WRAPPER" ]; then
  python3 - << 'PYEOF'
import re

wrapper_path = "/var/www/pterodactyl/resources/views/templates/wrapper.blade.php"
with open(wrapper_path, "r", encoding="utf-8") as f:
    wrapper = f.read()

wrapper = re.sub(r"<!-- Nothing Panel Custom UI.*?<\/style>", "", wrapper, flags=re.DOTALL)
wrapper = re.sub(r"</head>\s*</head>", "</head>", wrapper)

custom_css = """<!-- Nothing Panel Custom UI & Branding -->
        <style>
            :root {
                --np-primary: #C268F2;
                --np-secondary: #8A2BE2;
                --np-accent: #DA70D6;
                --np-dark: #08060f;
                --np-card: #120e22;
            }
            body {
                background: #08060f !important;
                background-image: radial-gradient(circle at 50% 10%, rgba(194, 104, 242, 0.16) 0%, transparent 60%) !important;
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif !important;
            }
            /* MASCOT AND FOOTER REMOVAL */
            div[class*="LoginFormContainer___StyledDiv2"],
            img[src*="pterodactyl"],
            img[alt*="pterodactyl"],
            p[class*="LoginFormContainer___StyledP"],
            a[href*="pterodactyl.io"] {
                display: none !important;
                visibility: hidden !important;
                height: 0 !important;
                width: 0 !important;
                opacity: 0 !important;
            }
            /* CENTER AND STYLE THE LOGIN CARD */
            div[class*="LoginFormContainer___StyledDiv"] {
                max-width: 440px !important;
                margin: 4rem auto 2rem auto !important;
                background-color: #120e22 !important;
                border: 1px solid rgba(194, 104, 242, 0.4) !important;
                box-shadow: 0 25px 70px rgba(0, 0, 0, 0.85), 0 0 35px rgba(194, 104, 242, 0.25) !important;
                border-radius: 16px !important;
                padding: 2.5rem 2rem !important;
                display: block !important;
            }
            div[class*="LoginFormContainer___StyledDiv3"] {
                width: 100% !important;
                flex: none !important;
                color: #f1f5f9 !important;
            }
            /* Login Title */
            h2[class*="LoginFormContainer"], h2 {
                color: #ffffff !important;
                font-weight: 800 !important;
                letter-spacing: -0.5px !important;
                text-align: center !important;
                font-size: 1.85rem !important;
                margin-bottom: 1.5rem !important;
            }
            /* Form Labels */
            label {
                color: #d1b8eb !important;
                font-weight: 700 !important;
                font-size: 0.75rem !important;
                letter-spacing: 0.8px !important;
                text-transform: uppercase !important;
                margin-bottom: 0.4rem !important;
            }
            /* Inputs */
            input[type="text"], input[type="password"], input[type="email"] {
                background-color: #0b0817 !important;
                border: 1.5px solid #281f3d !important;
                color: #ffffff !important;
                border-radius: 10px !important;
                padding: 0.85rem 1rem !important;
                transition: all 0.2s ease !important;
                font-size: 0.95rem !important;
            }
            input[type="text"]:focus, input[type="password"]:focus, input[type="email"]:focus {
                border-color: #C268F2 !important;
                box-shadow: 0 0 16px rgba(194, 104, 242, 0.5) !important;
                background-color: #0f0b20 !important;
                outline: none !important;
            }
            /* Buttons */
            button, button[type="submit"], .btn-primary, [class*="Button___StyledButton"] {
                background: linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%) !important;
                background-color: #C268F2 !important;
                color: #ffffff !important;
                font-weight: 800 !important;
                letter-spacing: 1px !important;
                border-radius: 10px !important;
                box-shadow: 0 4px 20px rgba(194, 104, 242, 0.5) !important;
                transition: all 0.2s ease !important;
                text-transform: uppercase !important;
                border: none !important;
                padding: 0.85rem !important;
                cursor: pointer !important;
            }
            button:hover, button[type="submit"]:hover, .btn-primary:hover, [class*="Button___StyledButton"]:hover {
                transform: translateY(-2px) !important;
                box-shadow: 0 6px 30px rgba(194, 104, 242, 0.8) !important;
                filter: brightness(1.1) !important;
            }
            /* Select menus */
            select {
                background-color: #0b0817 !important;
                border: 1.5px solid #281f3d !important;
                color: #ffffff !important;
                border-radius: 10px !important;
            }
            select:focus {
                border-color: #C268F2 !important;
                box-shadow: 0 0 16px rgba(194, 104, 242, 0.5) !important;
            }
            /* Links */
            a {
                color: #C268F2 !important;
                transition: all 0.2s ease !important;
            }
            a:hover {
                color: #e29eff !important;
                text-shadow: 0 0 8px rgba(194, 104, 242, 0.6) !important;
            }
            /* Flash & Error boxes */
            div[class*="FlashMessageRender"] {
                border-radius: 10px !important;
            }
        </style>
    </head>"""

wrapper = wrapper.replace("</head>", custom_css, 1)
with open(wrapper_path, "w", encoding="utf-8") as f:
    f.write(wrapper)
PYEOF
fi

# 5. Rebrand Admin Views & Inject Admin UI Theme
ADMIN_BLADE="$PANEL_DIR/resources/views/layouts/admin.blade.php"
if [ -f "$ADMIN_BLADE" ]; then
  sed -i 's@https://pterodactyl\.io/@#@g' "$ADMIN_BLADE"
  sed -i 's@https://pterodactyl\.io@#@g' "$ADMIN_BLADE"
  sed -i 's@Pterodactyl Software@Nothing Panel@g' "$ADMIN_BLADE"
  sed -i 's@<b>Pterodactyl</b>@<b>Nothing</b> Panel@g' "$ADMIN_BLADE"
  sed -i "s@<span>{{ config('app.name', 'Pterodactyl') }}</span>@<span>Nothing Panel</span>@g" "$ADMIN_BLADE"
  sed -i "s@Copyright &copy; 2015 - {{ date('Y') }}@Copyright &copy; {{ date('Y') }}@g" "$ADMIN_BLADE"

  python3 - << 'PYEOF'
import re

admin_blade = "/var/www/pterodactyl/resources/views/layouts/admin.blade.php"
with open(admin_blade, "r", encoding="utf-8") as f:
    admin_content = f.read()

admin_content = re.sub(r"<!-- Nothing Admin Theme.*?<\/style>", "", admin_content, flags=re.DOTALL)
admin_css = """<!-- Nothing Admin Theme -->
        <style>
            :root {
                --np-primary: #C268F2;
                --np-secondary: #8A2BE2;
            }
            .skin-blue .main-header .navbar {
                background: #0f0b1e !important;
                border-bottom: 2px solid #C268F2 !important;
            }
            .skin-blue .main-header .logo {
                background: #0a0715 !important;
                border-bottom: 2px solid #C268F2 !important;
                border-right: 1px solid rgba(194, 104, 242, 0.25) !important;
                color: #C268F2 !important;
                font-weight: 800 !important;
            }
            .skin-blue .main-sidebar {
                background-color: #0a0715 !important;
                border-right: 1px solid rgba(194, 104, 242, 0.15) !important;
            }
            .skin-blue .sidebar-menu > li.header {
                color: #8c76ab !important;
                background: #06040d !important;
                font-weight: 700 !important;
                letter-spacing: 0.8px !important;
            }
            .skin-blue .sidebar-menu > li.active > a,
            .skin-blue .sidebar-menu > li:hover > a {
                color: #ffffff !important;
                background: rgba(194, 104, 242, 0.18) !important;
                border-left-color: #C268F2 !important;
            }
            .skin-blue .sidebar-menu > li > a {
                color: #b5a4d4 !important;
            }
            .content-wrapper {
                background-color: #06040e !important;
            }
            .content-header > h1 {
                color: #ffffff !important;
                font-weight: 700 !important;
            }
            .content-header > h1 > small {
                color: #C268F2 !important;
            }
            .box {
                background: #110d22 !important;
                border: 1px solid rgba(194, 104, 242, 0.25) !important;
                border-radius: 10px !important;
                box-shadow: 0 4px 15px rgba(0, 0, 0, 0.4) !important;
                color: #e2d9f3 !important;
            }
            .box-header {
                color: #ffffff !important;
                border-bottom: 1px solid rgba(194, 104, 242, 0.2) !important;
            }
            .box.box-success, .box.box-primary, .box.box-info, .box.box-warning {
                border-top: 3px solid #C268F2 !important;
            }
            .btn-primary, .btn-success, .btn-warning, .btn-info {
                background: linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%) !important;
                border: 1px solid #C268F2 !important;
                color: #ffffff !important;
                border-radius: 8px !important;
                font-weight: 600 !important;
                box-shadow: 0 3px 12px rgba(194, 104, 242, 0.35) !important;
                transition: all 0.2s ease !important;
            }
            .btn-primary:hover, .btn-success:hover, .btn-warning:hover, .btn-info:hover {
                box-shadow: 0 5px 20px rgba(194, 104, 242, 0.7) !important;
                transform: translateY(-1px) !important;
                filter: brightness(1.15) !important;
            }
            .form-control, .select2-selection {
                background-color: #0b0817 !important;
                border: 1px solid #281f3d !important;
                color: #ffffff !important;
                border-radius: 8px !important;
            }
            .form-control:focus {
                border-color: #C268F2 !important;
                box-shadow: 0 0 10px rgba(194, 104, 242, 0.4) !important;
            }
            .main-footer {
                background: #0a0715 !important;
                border-top: 1px solid rgba(194, 104, 242, 0.2) !important;
                color: #8c76ab !important;
            }
            .main-footer a {
                color: #C268F2 !important;
            }
        </style>
    </head>"""

admin_content = admin_content.replace("</head>", admin_css, 1)
with open(admin_blade, "w", encoding="utf-8") as f:
    f.write(admin_content)
PYEOF
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

# 6. Configure Nginx Cache-Control (Force Fresh Bundles)
python3 - << 'PYEOF'
nginx_file = "/etc/nginx/sites-available/pterodactyl.conf"
if os.path.exists(nginx_file):
    with open(nginx_file, "r") as f:
        conf = f.read()

    cache_block = """
    location ~* \.(css|js|svg|png|jpg|jpeg|gif|ico|woff|woff2|ttf)$ {
        expires -1;
        add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0";
        try_files $uri $uri/ /index.php?$query_string;
    }
"""
    if "no-store, no-cache" not in conf:
        conf = conf.replace("location ~ \\.php$", cache_block + "\n    location ~ \\.php$")
        with open(nginx_file, "w") as f:
            f.write(conf)
PYEOF

# 7. Ensure Permissions & Flush Caches
chown -R www-data:www-data "$PANEL_DIR"
chmod -R 755 "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"

cd "$PANEL_DIR"
php artisan view:clear >/dev/null 2>&1 || true
php artisan config:clear >/dev/null 2>&1 || true
php artisan cache:clear >/dev/null 2>&1 || true

systemctl reload nginx 2>/dev/null || true
systemctl restart php8.3-fpm 2>/dev/null || true

echo "Nothing Panel custom branding applied successfully!"
