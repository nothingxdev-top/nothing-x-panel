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

PANEL_DIR=""
if [ -d "/var/www/nothing" ]; then
  PANEL_DIR="/var/www/nothing"
elif [ -d "/var/www/pterodactyl" ]; then
  PANEL_DIR="/var/www/pterodactyl"
else
  echo "ERROR: Panel directory not found"
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
export PANEL_DIR

# Ensure cloudflared is installed for NAT VPS / IPv6 / Port routing without port-forwarding
if ! command -v cloudflared &>/dev/null; then
  echo "Installing Cloudflare Tunnel (cloudflared)..."
  curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /tmp/cloudflared 2>/dev/null || true
  if [ -f /tmp/cloudflared ]; then
    mv -f /tmp/cloudflared /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
  fi
fi

# 2. Deploy Brand Logo, Favicons & Neutralize dinosaur SVG (Only Using User Favicon/Logo)
mkdir -p "$PANEL_DIR/public/assets" "$PANEL_DIR/public/favicons" "$PANEL_DIR/public/assets/svgs"

# Clean up all legacy / another logo variants
rm -f "$PANEL_DIR/public/assets/logo.png.bak" "$PANEL_DIR/public/assets/logo.svg.bak" 2>/dev/null || true

# Deploy custom favicon.ico (binary decoded from base64)
python3 - << 'PYEOF'
import base64, os

panel_dir = os.environ.get('PANEL_DIR', '/var/www/nothing')
ico_b64 = "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"
png_b64 = "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"

ico_data = base64.b64decode(ico_b64)
png_data = base64.b64decode(png_b64)

# Write favicon.ico
for p in [f'{panel_dir}/public/favicons/favicon.ico', f'{panel_dir}/public/favicon.ico']:
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'wb') as f:
        f.write(ico_data)

# Write logo.png and ALL png favicons (wipe every old Pterodactyl icon completely)
fav_icons = [
    'android-chrome-192x192.png', 'android-chrome-512x512.png',
    'android-icon-144x144.png', 'android-icon-192x192.png', 'android-icon-36x36.png',
    'android-icon-48x48.png', 'android-icon-72x72.png', 'android-icon-96x96.png',
    'apple-icon-114x114.png', 'apple-icon-120x120.png', 'apple-icon-144x144.png',
    'apple-icon-152x152.png', 'apple-icon-180x180.png', 'apple-icon-57x57.png',
    'apple-icon-60x60.png', 'apple-icon-72x72.png', 'apple-icon-76x76.png',
    'apple-icon.png', 'apple-icon-precomposed.png', 'apple-touch-icon.png',
    'favicon-16x16.png', 'favicon-32x32.png', 'favicon-96x96.png',
    'ms-icon-144x144.png', 'ms-icon-150x150.png', 'ms-icon-310x310.png',
    'ms-icon-70x70.png', 'mstile-150x150.png'
]
for f_name in fav_icons:
    p = f'{panel_dir}/public/favicons/{f_name}'
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'wb') as f:
        f.write(png_data)

with open(f'{panel_dir}/public/assets/logo.png', 'wb') as f:
    f.write(png_data)

# Remove legacy zip archive if present
try:
    os.remove(f'{panel_dir}/public/favicons/df4b367461890fa5fd0d9339d3c3f9c6.ico.zip')
except OSError:
    pass

# Generate logo.svg embedding the exact logo image
svg_content = f"""<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 64 64" width="64" height="64">
  <image width="64" height="64" xlink:href="data:image/png;base64,{png_b64}"/>
</svg>"""

with open(f'{panel_dir}/public/assets/logo.svg', 'w', encoding='utf-8') as f:
    f.write(svg_content)
with open(f'{panel_dir}/public/favicons/safari-pinned-tab.svg', 'w', encoding='utf-8') as f:
    f.write(svg_content)

# Neutralize mascot svgs with user logo
for svg_path in [
    f'{panel_dir}/public/assets/svgs/pterodactyl.svg',
    f'{panel_dir}/public/assets/svgs/not_found.svg',
    f'{panel_dir}/public/assets/svgs/server_error.svg',
    f'{panel_dir}/public/assets/svgs/server_installing.svg',
    f'{panel_dir}/resources/scripts/assets/images/pterodactyl.svg',
    f'{panel_dir}/resources/scripts/assets/images/not_found.svg',
    f'{panel_dir}/resources/scripts/assets/images/server_error.svg',
    f'{panel_dir}/resources/scripts/assets/images/server_installing.svg',
]:
    if os.path.exists(svg_path) or os.path.exists(os.path.dirname(svg_path)):
        os.makedirs(os.path.dirname(svg_path), exist_ok=True)
        with open(svg_path, 'w', encoding='utf-8') as f:
            f.write(svg_content)
PYEOF
chmod 644 "$PANEL_DIR/public/assets/logo.svg" "$PANEL_DIR/public/assets/logo.png" "$PANEL_DIR/public/favicons/favicon.ico" 2>/dev/null || true
chmod 644 "$PANEL_DIR/public/favicons/apple-touch-icon.png" "$PANEL_DIR/public/favicons/favicon-32x32.png" 2>/dev/null || true
chown -R www-data:www-data "$PANEL_DIR/public/favicons" "$PANEL_DIR/public/assets" 2>/dev/null || true

# 3. Patch Built React / JS Bundles (Remove Mascot & Footer Elements, Protect PterodactylUser)
python3 - << 'PYEOF'
import glob, os

panel_url = os.environ.get('PANEL_URL', 'https://panel.fayas.nx.kg')
panel_dir = os.environ.get('PANEL_DIR', '/var/www/nothing')

for path in glob.glob(f'{panel_dir}/public/assets/*.js'):
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

    # Restore text-gray-400 to bright white
    if True:
        # Restore any dark text on dark background in bundle to bright white
        content = content.replace('color: rgba(11, 7, 23, 1)', 'color: rgba(255, 255, 255, 1)')
        content = content.replace('color: rgba(11, 7, 23, var(--tw-text-opacity', 'color: rgba(255, 255, 255, var(--tw-text-opacity')
        content = content.replace('color:rgba(11,7,23,1)', 'color:rgba(255,255,255,1)')
        content = content.replace('color:rgba(11,7,23,var(--tw-text-opacity', 'color:rgba(255,255,255,var(--tw-text-opacity')
        # Eliminate Pterodactyl blue buttons
        content = content.replace('bg-primary-500', 'bg-primary-500 np-btn-purple')
        content = content.replace('bg-blue-600', 'bg-blue-600 np-btn-purple')
        changed = True

    if '.text-gray-400' in content:
        content = content.replace('color: rgba(11, 7, 23, 1)', 'color: rgba(255, 255, 255, 1)')
        content = content.replace('color: rgba(11, 7, 23, var(--tw-text-opacity', 'color: rgba(255, 255, 255, var(--tw-text-opacity')
        changed = True

    # Force dark card background in auth bundle inline style
    if 'backgroundColor:"rgba(255, 255, 255, var(--tw-bg-opacity))"' in content:
        content = content.replace('backgroundColor:"rgba(255, 255, 255, var(--tw-bg-opacity))"', 'backgroundColor:"rgba(18, 14, 34, 1)"')
        changed = True

    for old, new in [
        ('Configure Pterodactyl to your liking.', 'Configure Nothing Panel to your liking.'),
        ('Configure Pterodactyl to your liking', 'Configure Nothing Panel to your liking'),
        ('Configure Pterodactyl', 'Configure Nothing Panel'),
        ('Pterodactyl Software', 'Nothing Panel'),
        ('Pterodactyl Panel', 'Nothing Panel'),
        ('Pterodactyl Wings', 'Nothing Wings'),
        ('https://pterodactyl.io', panel_url),
        ('http://pterodactyl.io', panel_url),
        ('pterodactyl.io', 'nothingx.top'),
        ('"Pterodactyl®"', '""'),
        ('Pterodactyl®', 'Nothing Panel'),
        ('Pterodactyl&reg;', 'Nothing Panel'),
        ('"Pterodactyl"', '"Nothing Panel"'),
        ('>Pterodactyl<', '>Nothing Panel<'),
        ('>Pterodactyl ', '>Nothing Panel '),
        (' Pterodactyl<', ' Nothing Panel<'),
        ('© 2015 - ', '© '),
        ('"© 2015 - "', '""'),
        ('hsla(209, 18%, 30%, 1)', 'rgba(18, 14, 36, 1)'),
        ('hsla(209, 18%, 30%', 'rgba(18, 14, 36'),
        ('hsla(211, 12%, 43%', 'rgba(18, 14, 36'),
        ('hsla(211, 10%, 53%', 'rgba(18, 14, 36'),
        ('backgroundColor:"rgba(209, 184, 235', 'backgroundColor:"rgba(11, 7, 23'),
        ('rgba(209, 184, 235, var(--tw-bg-opacity))', 'rgba(11, 7, 23, var(--tw-bg-opacity))'),
        ('rgba(209, 184, 235', 'rgba(235, 218, 252'),
        ('container@pterodactyl~', 'container@nothing~'),
        ('[Pterodactyl Daemon]:', '[Nothing Daemon]:'),
        ('Pterodactyl Daemon', 'Nothing Daemon'),
        ('Pterodactyl', 'Nothing Panel'),
    ]:
        if old in content:
            content = content.replace(old, new)
            changed = True

    # Protect internal JS state object
    if 'Nothing PanelUser' in content:
        content = content.replace('Nothing PanelUser', 'PterodactylUser')
        changed = True

    # Register dedicated /domains tab in server navigation and router
    target_route = 'r.createElement(o.A,{action:"settings.reinstall"},r.createElement(Ii,null)))))}},{path:"/activity"'
    domains_route = 'r.createElement(o.A,{action:"settings.reinstall"},r.createElement(Ii,null)))))}},{path:"/domains",permission:null,name:"Domains",component:()=>{return r.createElement("div",{id:"np-domains-view-mount",style:{width:"100%",minHeight:"400px",padding:"24px 0",boxSizing:"border-box"}})}},{path:"/activity"'
    if target_route in content:
        content = content.replace(target_route, domains_route)
        changed = True

    # Fix any previously injected bundle that used undefined component 'c'
    if 'r.createElement(c,{title:"Domains"}' in content:
        content = content.replace('r.createElement(c,{title:"Domains"},r.createElement("div",{id:"np-domains-view-mount"}))', 'r.createElement("div",{id:"np-domains-view-mount",style:{width:"100%",minHeight:"400px",padding:"24px 0",boxSizing:"border-box"}})')
        changed = True

    # Restore Server Console grid layout if previously converted to flex-col
    if 'flex flex-col gap-6' in content and 'ServerConsole' in content:
        content = content.replace('flex flex-col gap-6', 'grid-cols-1 md:grid-cols-4 gap-4')
        changed = True
    elif 'flex flex-col gap-6' in content:
        content = content.replace('flex flex-col gap-6', 'grid-cols-1 md:grid-cols-4 gap-4')
        changed = True

    # Verify StartupContainer grid target in bundles (layout is styled via CSS)
    if 'StartupContainer' in content or 'Startup' in content:
        if 'grid grid-cols-1 md:grid-cols-4 gap-4' not in content and 'grid-cols-4' not in content:
            print(f"  ⚠ Warning: Startup grid target not found in {os.path.basename(path)}")

    if changed:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"  ✔ Patched bundle: {os.path.basename(path)}")
PYEOF

# Update Console.tsx terminal prelude
CONSOLE_TSX="$PANEL_DIR/resources/scripts/components/server/console/Console.tsx"
if [ -f "$CONSOLE_TSX" ]; then
    sed -i "s/container@pterodactyl~/container@nothing~/g" "$CONSOLE_TSX"
fi

# Update Wings config for daemon name (Nothing Daemon)
for cfg in /etc/nothing/config.yml /etc/pterodactyl/config.yml; do
    if [ -f "$cfg" ]; then
        sed -i "s/app_name: Pterodactyl/app_name: Nothing/g" "$cfg"
        sed -i 's/app_name: "Pterodactyl"/app_name: "Nothing"/g' "$cfg"
    fi
done
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet wings; then
    systemctl restart wings || true
fi

# 4. Deploy Static Assets (Theme CSS and JS)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_RAW="https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master"
mkdir -p "$PANEL_DIR/public/assets"

for asset in np-theme.css np-theme.js; do
    if [ -f "$SCRIPT_DIR/../assets/$asset" ]; then
        cp "$SCRIPT_DIR/../assets/$asset" "$PANEL_DIR/public/assets/$asset"
    elif [ -f "$SCRIPT_DIR/assets/$asset" ]; then
        cp "$SCRIPT_DIR/assets/$asset" "$PANEL_DIR/public/assets/$asset"
    elif [ -f "/usr/local/share/nothing-panel/assets/$asset" ]; then
        cp "/usr/local/share/nothing-panel/assets/$asset" "$PANEL_DIR/public/assets/$asset"
    else
        curl -fsSL "$REPO_RAW/assets/$asset" -o "$PANEL_DIR/public/assets/$asset"
    fi
    chmod 644 "$PANEL_DIR/public/assets/$asset"
    chown www-data:www-data "$PANEL_DIR/public/assets/$asset"
    echo "  ✔ Static asset deployed: /assets/$asset"
done

# 4a. Inject Modern Custom Theme references into wrapper.blade.php
SERVER_IP=$(curl -4 -fsSL https://api.ipify.org 2>/dev/null || curl -4 -fsSL https://ifconfig.me 2>/dev/null || curl -4 -fsSL https://icanhazip.com 2>/dev/null || echo "213.136.89.90")
export SERVER_IP
WRAPPER="$PANEL_DIR/resources/views/templates/wrapper.blade.php"
if [ -f "$WRAPPER" ]; then
  cp "$WRAPPER" "$WRAPPER.np-backup"
  sed -i "s@config('app.name', 'Pterodactyl')@config('app.name', 'Nothing Panel')@g" "$WRAPPER"
  sed -i "s@color=\"#bc6e3c\"@color=\"#C268F2\"@g" "$WRAPPER" 2>/dev/null || true

  python3 - << 'PYEOF'
import os, re

panel_dir = os.environ.get('PANEL_DIR', '/var/www/nothing')
server_ip = os.environ.get('SERVER_IP', '213.136.89.90')
wrapper_path = os.path.join(panel_dir, "resources/views/templates/wrapper.blade.php")
with open(wrapper_path, "r", encoding="utf-8") as f:
    wrapper = f.read()

# Clean up any legacy injected blocks or duplicate heads
wrapper = re.sub(r"<!-- (Nothing Panel Custom UI|Vercel-Style|Custom Domains).*?</head>", "</head>", wrapper, flags=re.DOTALL)
wrapper = re.sub(r"</head>\s*</head>", "</head>", wrapper)

theme_inject = f"""<!-- Nothing Panel Custom UI & Branding -->
        <link rel="stylesheet" href="/assets/np-theme.css">
        <script>window.NP_VPS_IP = '{server_ip}';</script>
        <script defer src="/assets/np-theme.js"></script>
    </head>"""

wrapper = wrapper.replace("</head>", theme_inject, 1)
with open(wrapper_path, "w", encoding="utf-8") as f:
    f.write(wrapper)
PYEOF

  # Pre-step validation: Check injected JavaScript with node --check
  CHECK_SCRIPT="$SCRIPT_DIR/tests/check-injected-js.sh"
  if [ ! -f "$CHECK_SCRIPT" ] && [ -f "$SCRIPT_DIR/../scripts/tests/check-injected-js.sh" ]; then
    CHECK_SCRIPT="$SCRIPT_DIR/../scripts/tests/check-injected-js.sh"
  fi
  if [ -f "$CHECK_SCRIPT" ] && command -v node >/dev/null 2>&1; then
    if ! bash "$CHECK_SCRIPT" "$WRAPPER"; then
      echo "❌ Injected JavaScript verification failed! Restoring backup wrapper..." >&2
      cp "$WRAPPER.np-backup" "$WRAPPER"
      exit 1
    fi
    echo "  ✔ Injected JavaScript syntax verified with node --check"
  fi
fi

# 4b. Deploy 1-Click Domain Manager Backend Controller & Routes
mkdir -p "$PANEL_DIR/app/Http/Controllers/Base"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
DM_TARGET="$PANEL_DIR/app/Http/Controllers/Base/DomainManagerController.php"
if [ -f "$SCRIPT_DIR/DomainManagerController.php" ]; then
    cp "$SCRIPT_DIR/DomainManagerController.php" "$DM_TARGET"
elif [ -f "/usr/local/share/nothing-panel/DomainManagerController.php" ]; then
    cp "/usr/local/share/nothing-panel/DomainManagerController.php" "$DM_TARGET"
else
    curl -fsSL "https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/scripts/DomainManagerController.php" -o "$DM_TARGET"
fi

if [ ! -s "$DM_TARGET" ]; then
    echo "❌ Error: Failed to deploy DomainManagerController.php (file is empty or missing)!" >&2
    exit 1
fi
chmod 644 "$DM_TARGET"
chown www-data:www-data "$DM_TARGET"
echo "  ✔ DomainManagerController.php deployed successfully" 

# Add Sudoers rule for www-data to control Nginx & Certbot without password
cat << 'SUDOEOF' > /etc/sudoers.d/nothing-panel
www-data ALL=(ALL) NOPASSWD: /bin/mv, /bin/ln, /bin/rm, /usr/sbin/nginx, /bin/systemctl reload nginx, /usr/bin/certbot, /usr/local/bin/np-domain
SUDOEOF
chmod 440 /etc/sudoers.d/nothing-panel

# Ensure routes are registered in routes/base.php
python3 - << 'PYEOF'
import os
panel_dir = os.environ.get('PANEL_DIR', '/var/www/nothing')
base_routes = os.path.join(panel_dir, "routes/base.php")
if os.path.exists(base_routes):
    with open(base_routes, "r") as f:
        routes_content = f.read()

    route_block = """
Route::prefix('/api/server/{server}/domains')->group(function () {
    Route::get('/', [\\Pterodactyl\\Http\\Controllers\\Base\\DomainManagerController::class, 'index']);
    Route::post('/', [\\Pterodactyl\\Http\\Controllers\\Base\\DomainManagerController::class, 'store']);
    Route::post('/delete', [\\Pterodactyl\\Http\\Controllers\\Base\\DomainManagerController::class, 'destroy']);
});
"""
    if "[Base\\DomainManagerController::class" in routes_content:
        routes_content = routes_content.replace("[Base\\DomainManagerController::class", "[\\Pterodactyl\\Http\\Controllers\\Base\\DomainManagerController::class")
    if "DomainManagerController" not in routes_content:
        routes_content = routes_content.replace("Route::get('/{react}'", route_block + "\nRoute::get('/{react}'")
    with open(base_routes, "w") as f:
        f.write(routes_content)
print("  ✔ Domain routes verified in routes/base.php")
PYEOF

# Verify routes using php artisan route:list
if command -v php >/dev/null 2>&1 && [ -f "$PANEL_DIR/artisan" ]; then
    echo "Verifying routes with php artisan..."
    cd "$PANEL_DIR"
    php artisan route:clear 2>/dev/null || true
    if ! php artisan route:list | grep -q "domains"; then
        echo "❌ Error: Domain routes verification failed in php artisan route:list!" >&2
        exit 1
    fi
    echo "  ✔ Confirmed domain routes active in artisan route:list"
fi

# 5. Universal Rebranding across all Views, Lang, and Configs & Inject Admin Theme
python3 - << 'PYEOF'
import os, re

panel_dir = os.environ.get('PANEL_DIR', '/var/www/nothing')

search_targets = [
    os.path.join(panel_dir, 'resources/views'),
    os.path.join(panel_dir, 'resources/lang'),
    os.path.join(panel_dir, 'config'),
]

exact_replacements = [
    ('Configure Pterodactyl to your liking.', 'Configure Nothing Panel to your liking.'),
    ('Configure Pterodactyl to your liking', 'Configure Nothing Panel to your liking'),
    ('Configure advanced settings for Pterodactyl.', 'Configure advanced settings for Nothing Panel.'),
    ('Configure advanced settings for Pterodactyl', 'Configure advanced settings for Nothing Panel'),
    ('Configure how Pterodactyl should handle sending emails.', 'Configure how Nothing Panel should handle sending emails.'),
    ('Configure how Pterodactyl should handle sending emails', 'Configure how Nothing Panel should handle sending emails'),
    ('All nodes currently configured on the Pterodactyl Panel.', 'All nodes currently configured on Nothing Panel.'),
    ('All servers currently configured on the Pterodactyl Panel.', 'All servers currently configured on Nothing Panel.'),
    ('All registered users on the Pterodactyl Panel.', 'All registered users on Nothing Panel.'),
    ('Pterodactyl Software', 'Nothing Panel'),
    ('Pterodactyl Panel', 'Nothing Panel'),
    ('Pterodactyl Wings', 'Nothing Wings'),
    ('https://pterodactyl.io/', '#'),
    ('https://pterodactyl.io', '#'),
    ('http://pterodactyl.io', '#'),
    ('pterodactyl.io', 'nothingx.top'),
    ('https://github.com/pterodactyl/panel', 'https://github.com/nothingxdev-top/nothing-x-panel'),
    ('https://github.com/pterodactyl', 'https://github.com/nothingxdev-top'),
    ('https://discord.gg/pterodactyl', '#'),
    ('https://github.com/sponsors/pterodactyl', 'https://github.com/nothingxdev-top'),
    ('<b>Pterodactyl</b>', '<b>Nothing</b> Panel'),
    ('Pterodactyl&reg;', 'Nothing Panel'),
    ('Pterodactyl®', 'Nothing Panel'),
    ("config('app.name', 'Pterodactyl')", "config('app.name', 'Nothing Panel')"),
    ('color="#bc6e3c"', 'color="#C268F2"'),
]

for starget in search_targets:
    if not os.path.exists(starget):
        continue
    for root, dirs, files in os.walk(starget):
        for file in files:
            if file.endswith(('.blade.php', '.php', '.json')):
                filepath = os.path.join(root, file)
                try:
                    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                        content = f.read()

                    orig = content
                    for old, new in exact_replacements:
                        if old in content:
                            content = content.replace(old, new)

                    if 'copyright' in content.lower() or 'main-footer' in content.lower() or 'copy;' in content.lower():
                        content = re.sub(r'<footer\b[^>]*>.*?</footer>', '', content, flags=re.DOTALL | re.IGNORECASE)
                        lines = []
                        for line in content.splitlines(True):
                            l = line.lower()
                            if 'copyright' in l or 'copy;' in l or 'laravel_start' in l or '$appversion' in l or 'main-footer' in l or 'pterodactyl software' in l:
                                continue
                            lines.append(line)
                        content = ''.join(lines)

                    if file.endswith('.blade.php'):
                        content = re.sub(r'(?<![\\a-zA-Z0-9_])Pterodactyl(?![\\a-zA-Z0-9_])', 'Nothing Panel', content)
                        content = re.sub(r'Nothing Panel Panel', 'Nothing Panel', content)
                    elif 'lang' in root:
                        content = re.sub(r'(?<![\\a-zA-Z0-9_])Pterodactyl(?![\\a-zA-Z0-9_])', 'Nothing Panel', content)
                        content = re.sub(r'Nothing Panel Panel', 'Nothing Panel', content)
                    elif file == 'app.php' and 'config' in root:
                        content = re.sub(r"'name'\s*=>\s*env\('APP_NAME',\s*'Pterodactyl'\)", "'name' => env('APP_NAME', 'Nothing Panel')", content)

                    if content != orig:
                        with open(filepath, 'w', encoding='utf-8') as f:
                            f.write(content)
                except Exception:
                    pass

env_path = os.path.join(panel_dir, '.env')
if os.path.exists(env_path):
    try:
        with open(env_path, 'r', encoding='utf-8') as f:
            env_content = f.read()
        if 'APP_NAME=' in env_content:
            env_content = re.sub(r'APP_NAME=.*', 'APP_NAME="Nothing Panel"', env_content)
        else:
            env_content += '\nAPP_NAME="Nothing Panel"\n'
        with open(env_path, 'w', encoding='utf-8') as f:
            f.write(env_content)
    except Exception:
        pass

lang_strings = os.path.join(panel_dir, 'resources/lang/en/strings.php')
if os.path.exists(lang_strings):
    try:
        with open(lang_strings, 'r', encoding='utf-8') as f:
            lcontent = f.read()
        lcontent = re.sub(r"'copyright'\s*=>\s*.*", "'copyright' => '',", lcontent)
        with open(lang_strings, 'w', encoding='utf-8') as f:
            f.write(lcontent)
    except Exception:
        pass
PYEOF

ADMIN_BLADE="$PANEL_DIR/resources/views/layouts/admin.blade.php"
if [ -f "$ADMIN_BLADE" ]; then
  python3 - << 'PYEOF'
import os, re

panel_dir = os.environ.get('PANEL_DIR', '/var/www/nothing')
admin_blade = os.path.join(panel_dir, 'resources/views/layouts/admin.blade.php')
with open(admin_blade, 'r', encoding='utf-8') as f:
    admin_content = f.read()

admin_content = re.sub(r"<!-- Nothing Admin Theme.*?<\/style>", "", admin_content, flags=re.DOTALL)
admin_content = re.sub(r"<!-- Nothing Admin Custom Select.*?<\/script>", "", admin_content, flags=re.DOTALL)
admin_content = re.sub(r'<footer\b[^>]*>.*?</footer>', '', admin_content, flags=re.DOTALL | re.IGNORECASE)
admin_content = re.sub(r'<div\b[^>]*class="[^"]*main-footer[^"]*"[^>]*>.*?</div>', '', admin_content, flags=re.DOTALL | re.IGNORECASE)

admin_lines = []
for line in admin_content.splitlines(True):
    l = line.lower()
    if 'copyright' in l or 'copy;' in l or 'laravel_start' in l or '$appversion' in l or 'main-footer' in l or 'pterodactyl software' in l:
        continue
    admin_lines.append(line)
admin_content = "".join(admin_lines)

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
                font-size: 1.25rem !important;
            }
            .skin-blue .main-header .logo::before {
                content: "";
                display: inline-block;
                width: 30px;
                height: 30px;
                margin-right: 10px;
                vertical-align: middle;
                background: url("/assets/logo.png") no-repeat center center;
                background-size: contain;
                border-radius: 8px;
                filter: drop-shadow(0 0 8px rgba(194, 104, 242, 0.6));
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
                border-radius: 12px !important;
                box-shadow: 0 4px 18px rgba(0, 0, 0, 0.45) !important;
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
            /* ADMINLTE FORM CONTROLS & NATIVE SELECTS */
            .form-control, input.form-control, textarea.form-control {
                background-color: #0b0817 !important;
                border: 1.5px solid rgba(194, 104, 242, 0.35) !important;
                color: #ffffff !important;
                border-radius: 8px !important;
            }
            .form-control:focus, input.form-control:focus, textarea.form-control:focus {
                border-color: #C268F2 !important;
                box-shadow: 0 0 14px rgba(194, 104, 242, 0.5) !important;
                background-color: #0e091e !important;
            }
            select.form-control, select {
                appearance: none !important;
                -webkit-appearance: none !important;
                -moz-appearance: none !important;
                background-color: #0d091a !important;
                background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='14' height='14' viewBox='0 0 24 24' fill='none' stroke='%23C268F2' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpolyline points='6 9 12 15 18 9'%3E%3C/polyline%3E%3C/svg%3E") !important;
                background-repeat: no-repeat !important;
                background-position: right 1rem center !important;
                background-size: 14px 14px !important;
                border: 1.5px solid rgba(194, 104, 242, 0.45) !important;
                border-radius: 8px !important;
                color: #f1e5ff !important;
                padding-right: 2.5rem !important;
                cursor: pointer !important;
            }
            select.form-control:focus, select:focus {
                border-color: #C268F2 !important;
                box-shadow: 0 0 16px rgba(194, 104, 242, 0.5) !important;
            }
            select option {
                background-color: #120e24 !important;
                color: #ffffff !important;
            }
            /* ADVANCED SELECT2 THEME (#C268F2) */
            .select2-container--default .select2-selection--single,
            .select2-container--default .select2-selection--multiple {
                background-color: #0d091a !important;
                border: 1.5px solid rgba(194, 104, 242, 0.4) !important;
                border-radius: 8px !important;
                min-height: 38px !important;
                padding: 4px 8px !important;
                color: #f1e5ff !important;
                transition: all 0.2s ease !important;
            }
            .select2-container--default .select2-selection--single .select2-selection__rendered {
                color: #f1e5ff !important;
                line-height: 28px !important;
            }
            .select2-container--default .select2-selection--single .select2-selection__arrow b {
                border-color: #C268F2 transparent transparent transparent !important;
                border-width: 6px 5px 0 5px !important;
            }
            .select2-container--default.select2-container--open .select2-selection--single .select2-selection__arrow b {
                border-color: transparent transparent #C268F2 transparent !important;
                border-width: 0 5px 6px 5px !important;
            }
            .select2-container--default.select2-container--focus .select2-selection--single,
            .select2-container--default.select2-container--open .select2-selection--single,
            .select2-container--default.select2-container--focus .select2-selection--multiple,
            .select2-container--default.select2-container--open .select2-selection--multiple {
                border-color: #C268F2 !important;
                box-shadow: 0 0 18px rgba(194, 104, 242, 0.55) !important;
                outline: none !important;
            }
            .select2-dropdown {
                background-color: #120e24 !important;
                background: #120e24 !important;
                border: 1.5px solid #C268F2 !important;
                border-radius: 10px !important;
                box-shadow: 0 15px 40px rgba(0, 0, 0, 0.85), 0 0 20px rgba(194, 104, 242, 0.3) !important;
                overflow: hidden !important;
            }
            .select2-container--default .select2-results,
            .select2-results,
            .select2-results__options,
            ul.select2-results__options,
            .select2-container--default .select2-results > .select2-results__options {
                background-color: #120e24 !important;
                background: #120e24 !important;
            }
            .select2-container--default .select2-search--dropdown {
                background-color: #120e24 !important;
                padding: 8px !important;
            }
            .select2-container--default .select2-search--dropdown .select2-search__field {
                background-color: #090613 !important;
                border: 1px solid rgba(194, 104, 242, 0.4) !important;
                border-radius: 6px !important;
                color: #ffffff !important;
                padding: 6px 10px !important;
            }
            .select2-container--default .select2-search--dropdown .select2-search__field:focus {
                border-color: #C268F2 !important;
                box-shadow: 0 0 10px rgba(194, 104, 242, 0.5) !important;
                outline: none !important;
            }
            .select2-results__option,
            .select2-container--default .select2-results__option {
                background-color: #120e24 !important;
                color: #dcc7f5 !important;
                padding: 8px 12px !important;
                transition: all 0.15s ease !important;
            }
            .select2-container--default .select2-results__option--highlighted[aria-selected],
            .select2-container--default .select2-results__option:hover {
                background: linear-gradient(90deg, #C268F2 0%, #8A2BE2 100%) !important;
                background-color: #C268F2 !important;
                color: #ffffff !important;
            }
            .select2-container--default .select2-results__option[aria-selected="true"] {
                background: rgba(194, 104, 242, 0.25) !important;
                color: #ffffff !important;
                font-weight: 700 !important;
            }

            /* OBSIDIAN ELECTRIC PURPLE CUSTOM SELECTS FOR ADMIN */
            .np-custom-select-wrap {
                position: relative !important;
                display: inline-block !important;
                width: 100% !important;
                user-select: none !important;
                font-family: inherit !important;
            }
            .np-custom-select-trigger {
                width: 100% !important;
                min-height: 38px !important;
                background: #0b0717 !important;
                border: 1.5px solid rgba(194, 104, 242, 0.45) !important;
                border-radius: 8px !important;
                color: #ffffff !important;
                padding: 8px 38px 8px 14px !important;
                font-size: 0.92rem !important;
                font-weight: 500 !important;
                display: flex !important;
                align-items: center !important;
                justify-content: space-between !important;
                cursor: pointer !important;
                box-sizing: border-box !important;
                transition: all 0.2s ease !important;
            }
            .np-custom-select-trigger:hover {
                border-color: #C268F2 !important;
                box-shadow: 0 0 14px rgba(194, 104, 242, 0.35) !important;
            }
            .np-custom-select-menu {
                display: none !important;
                position: absolute !important;
                top: calc(100% + 4px) !important;
                left: 0 !important;
                width: 100% !important;
                max-height: 250px !important;
                overflow-y: auto !important;
                background: #120e24 !important;
                border: 1.5px solid #C268F2 !important;
                border-radius: 10px !important;
                box-shadow: 0 16px 45px rgba(0, 0, 0, 0.95), 0 0 25px rgba(194, 104, 242, 0.35) !important;
                z-index: 9999999 !important;
                padding: 4px !important;
                box-sizing: border-box !important;
                backdrop-filter: blur(12px) !important;
            }
            .np-custom-select-menu::-webkit-scrollbar {
                width: 6px !important;
            }
            .np-custom-select-menu::-webkit-scrollbar-thumb {
                background: #C268F2 !important;
                border-radius: 3px !important;
            }
            .np-custom-select-item {
                padding: 10px 14px !important;
                margin: 2px 0 !important;
                border-radius: 6px !important;
                font-size: 0.9rem !important;
                cursor: pointer !important;
                display: flex !important;
                align-items: center !important;
                justify-content: space-between !important;
                transition: all 0.15s ease !important;
            }

            /* Custom Scrollbars */
            ::-webkit-scrollbar {
                width: 8px;
                height: 8px;
            }
            ::-webkit-scrollbar-track {
                background: #090613;
            }
            ::-webkit-scrollbar-thumb {
                background: #462575;
                border-radius: 4px;
            }
            ::-webkit-scrollbar-thumb:hover {
                background: #C268F2;
            }
            /* ELIMINATE FOOTER COMPLETELY */
            .main-footer, footer, div.main-footer, .pull-right.small.text-gray {
                display: none !important;
                visibility: hidden !important;
                height: 0 !important;
                min-height: 0 !important;
                max-height: 0 !important;
                padding: 0 !important;
                margin: 0 !important;
                border: none !important;
                overflow: hidden !important;
                pointer-events: none !important;
            }
            .content-wrapper {
                margin-bottom: 0 !important;
                padding-bottom: 25px !important;
            }
        </style>
    </head>"""

admin_js = """<!-- Nothing Admin Custom Select & Real-time Sanitizer -->
        <script>
        (function() {
            function sanitizePterodactylText(node) {
                if (!node) return;
                if (node.nodeType === 3) {
                    var val = node.nodeValue;
                    if (val && (val.indexOf('pterodactyl') !== -1 || val.indexOf('Pterodactyl') !== -1 || val.indexOf('PTERODACTYL') !== -1)) {
                        node.nodeValue = val
                            .replace(/Configure Pterodactyl to your liking\.?/gi, 'Configure Nothing Panel to your liking.')
                            .replace(/Configure advanced settings for Pterodactyl\.?/gi, 'Configure advanced settings for Nothing Panel.')
                            .replace(/Configure how Pterodactyl should handle sending emails\.?/gi, 'Configure how Nothing Panel should handle sending emails.')
                            .replace(/All nodes currently configured on the Pterodactyl Panel\.?/gi, 'All nodes currently configured on Nothing Panel.')
                            .replace(/All servers currently configured on the Pterodactyl Panel\.?/gi, 'All servers currently configured on Nothing Panel.')
                            .replace(/All registered users on the Pterodactyl Panel\.?/gi, 'All registered users on Nothing Panel.')
                            .replace(/Pterodactyl Software/gi, 'Nothing Panel')
                            .replace(/Pterodactyl Panel/gi, 'Nothing Panel')
                            .replace(/Pterodactyl Wings/gi, 'Nothing Wings')
                            .replace(/container@pterodactyl~/g, 'container@nothing~')
                            .replace(/container@pterodactyl/g, 'container@nothing')
                            .replace(/\[Pterodactyl Daemon\]:/g, '[Nothing Daemon]:')
                            .replace(/Pterodactyl Daemon/g, 'Nothing Daemon')
                            .replace(/https?:\/\/pterodactyl\.io[^\s"']*/gi, '#')
                            .replace(/pterodactyl\.io/gi, 'nothingx.top')
                            .replace(/Pterodactyl/gi, 'Nothing Panel')
                            .replace(/pterodactyl/gi, 'nothing');
                    }
                } else if (node.nodeType === 1) {
                    ['title', 'placeholder', 'alt', 'aria-label'].forEach(function(attr) {
                        var aVal = node.getAttribute && node.getAttribute(attr);
                        if (aVal && (aVal.indexOf('pterodactyl') !== -1 || aVal.indexOf('Pterodactyl') !== -1)) {
                            node.setAttribute(attr, aVal
                                .replace(/Configure Pterodactyl to your liking\.?/gi, 'Configure Nothing Panel to your liking.')
                                .replace(/Pterodactyl Software/gi, 'Nothing Panel')
                                .replace(/Pterodactyl Panel/gi, 'Nothing Panel')
                                .replace(/Pterodactyl/gi, 'Nothing Panel')
                                .replace(/pterodactyl/gi, 'nothing')
                            );
                        }
                    });
                    var children = node.childNodes;
                    for (var k = 0; k < children.length; k++) {
                        sanitizePterodactylText(children[k]);
                    }
                }
            }

            function initCustomSelects() {
                document.querySelectorAll('.np-custom-select-wrap').forEach(function(wrap) {
                    var prev = wrap.previousElementSibling;
                    if (!prev || prev.tagName !== 'SELECT' || !document.body.contains(prev)) {
                        wrap.remove();
                    }
                });

                var selects = Array.from(document.querySelectorAll('select:not([data-np-select="true"])'));
                selects.forEach(function(select) {
                    if (select.classList.contains('select2-hidden-accessible')) return;

                    select.setAttribute('data-np-select', 'true');
                    select.style.cssText = 'position: absolute !important; opacity: 0 !important; pointer-events: none !important; width: 0 !important; height: 0 !important; margin: 0 !important; padding: 0 !important; border: none !important; z-index: -1 !important;';

                    var container = document.createElement('div');
                    container.className = 'np-custom-select-wrap';
                    container.style.cssText = 'position: relative !important; width: 100% !important; min-width: 140px !important; box-sizing: border-box !important; font-family: inherit !important; user-select: none !important;';

                    var trigger = document.createElement('div');
                    trigger.className = 'np-custom-select-trigger';
                    trigger.style.cssText = 'width: 100% !important; min-height: 38px !important; background: #0b0717 !important; border: 1.5px solid rgba(194, 104, 242, 0.45) !important; border-radius: 8px !important; color: #ffffff !important; padding: 8px 38px 8px 14px !important; font-size: 0.92rem !important; font-weight: 500 !important; display: flex !important; align-items: center !important; justify-content: space-between !important; cursor: pointer !important; box-sizing: border-box !important; transition: all 0.2s ease !important;';

                    var labelSpan = document.createElement('span');
                    labelSpan.className = 'np-custom-select-label';
                    labelSpan.style.cssText = 'overflow: hidden !important; text-overflow: ellipsis !important; white-space: nowrap !important; flex: 1 !important; color: #ffffff !important;';

                    var arrowSpan = document.createElement('span');
                    arrowSpan.className = 'np-custom-select-arrow';
                    arrowSpan.style.cssText = 'position: absolute !important; right: 12px !important; top: 50% !important; transform: translateY(-50%) !important; display: flex !important; align-items: center !important; transition: transform 0.2s ease !important; pointer-events: none !important;';
                    arrowSpan.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#C268F2" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"></polyline></svg>';

                    trigger.appendChild(labelSpan);
                    trigger.appendChild(arrowSpan);
                    container.appendChild(trigger);

                    var menu = document.createElement('div');
                    menu.className = 'np-custom-select-menu';
                    menu.style.cssText = 'display: none !important; position: absolute !important; top: calc(100% + 4px) !important; left: 0 !important; width: 100% !important; max-height: 250px !important; overflow-y: auto !important; background: #120e24 !important; border: 1.5px solid #C268F2 !important; border-radius: 10px !important; box-shadow: 0 16px 45px rgba(0, 0, 0, 0.95), 0 0 25px rgba(194, 104, 242, 0.35) !important; z-index: 9999999 !important; padding: 4px !important; box-sizing: border-box !important; backdrop-filter: blur(12px) !important;';

                    function syncOptions() {
                        menu.innerHTML = '';
                        var opts = Array.from(select.options);
                        if (opts.length > 0 && select.selectedIndex < 0) {
                            select.selectedIndex = 0;
                        }
                        var selOpt = select.options[select.selectedIndex];
                        labelSpan.textContent = selOpt ? selOpt.text : (opts[0] ? opts[0].text : 'Select...');

                        opts.forEach(function(opt, idx) {
                            var item = document.createElement('div');
                            var isSelected = idx === select.selectedIndex;
                            item.className = 'np-custom-select-item';
                            item.style.cssText = 'padding: 10px 14px !important; margin: 2px 0 !important; border-radius: 6px !important; font-size: 0.9rem !important; cursor: pointer !important; color: ' + (isSelected ? '#ffffff' : '#dcc7f5') + ' !important; background: ' + (isSelected ? 'linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%)' : 'transparent') + ' !important; font-weight: ' + (isSelected ? '700' : '500') + ' !important; display: flex !important; align-items: center !important; justify-content: space-between !important; transition: all 0.15s ease !important;';

                            item.innerHTML = '<span>' + opt.text + '</span>' + (isSelected ? '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>' : '');

                            item.onmouseenter = function() {
                                if (idx !== select.selectedIndex) {
                                    item.style.background = 'rgba(194, 104, 242, 0.22)';
                                    item.style.color = '#ffffff';
                                }
                            };
                            item.onmouseleave = function() {
                                if (idx !== select.selectedIndex) {
                                    item.style.background = 'transparent';
                                    item.style.color = '#dcc7f5';
                                }
                            };

                            item.onclick = function(e) {
                                e.stopPropagation();
                                select.selectedIndex = idx;
                                select.value = opt.value;
                                if (window.jQuery) {
                                    window.jQuery(select).val(opt.value).trigger('change');
                                }
                                select.dispatchEvent(new Event('change', { bubbles: true }));
                                select.dispatchEvent(new Event('input', { bubbles: true }));
                                closeSelect();
                                syncOptions();
                            };

                            menu.appendChild(item);
                        });
                    }

                    var optObserver = new MutationObserver(function() { syncOptions(); });
                    optObserver.observe(select, { childList: true, subtree: true, characterData: true });

                    function openSelect() {
                        document.querySelectorAll('.np-custom-select-menu').forEach(function(m) { m.style.display = 'none'; });
                        document.querySelectorAll('.np-custom-select-arrow').forEach(function(a) { a.style.transform = 'translateY(-50%) rotate(0deg)'; });
                        document.querySelectorAll('.np-custom-select-trigger').forEach(function(t) {
                            t.style.borderColor = 'rgba(194, 104, 242, 0.45)';
                            t.style.boxShadow = 'none';
                        });

                        syncOptions();
                        menu.style.display = 'block';
                        trigger.style.borderColor = '#C268F2';
                        trigger.style.boxShadow = '0 0 16px rgba(194, 104, 242, 0.45)';
                        arrowSpan.style.transform = 'translateY(-50%) rotate(180deg)';
                    }

                    function closeSelect() {
                        menu.style.display = 'none';
                        trigger.style.borderColor = 'rgba(194, 104, 242, 0.45)';
                        trigger.style.boxShadow = 'none';
                        arrowSpan.style.transform = 'translateY(-50%) rotate(0deg)';
                    }

                    trigger.onclick = function(e) {
                        e.stopPropagation();
                        if (menu.style.display === 'block') {
                            closeSelect();
                        } else {
                            openSelect();
                        }
                    };

                    container.appendChild(menu);
                    select.parentNode.insertBefore(container, select.nextSibling);
                    syncOptions();

                    select.addEventListener('change', syncOptions);
                });
            }

            document.addEventListener('click', function(e) {
                if (!e.target.closest('.np-custom-select-wrap')) {
                    document.querySelectorAll('.np-custom-select-menu').forEach(function(m) { m.style.display = 'none'; });
                    document.querySelectorAll('.np-custom-select-arrow').forEach(function(a) { a.style.transform = 'translateY(-50%) rotate(0deg)'; });
                    document.querySelectorAll('.np-custom-select-trigger').forEach(function(t) {
                        t.style.borderColor = 'rgba(194, 104, 242, 0.45)';
                        t.style.boxShadow = 'none';
                    });
                }
            });

            function runInit() {
                sanitizePterodactylText(document.body);
                initCustomSelects();
            }

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', runInit);
            } else {
                runInit();
            }

            var observer = new MutationObserver(function(mutations) {
                mutations.forEach(function(mutation) {
                    mutation.addedNodes.forEach(function(node) {
                        sanitizePterodactylText(node);
                    });
                });
                initCustomSelects();
            });
            observer.observe(document.documentElement, { childList: true, subtree: true });
        })();
        </script>
    </body>"""

admin_content = admin_content.replace("</head>", admin_css, 1)
admin_content = admin_content.replace("</body>", admin_js, 1)

with open(admin_blade, 'w', encoding='utf-8') as f:
    f.write(admin_content)
PYEOF
fi


# 6. Configure Nginx Cache-Control (Force Fresh Bundles) & SVG MIME type
python3 - << 'PYEOF'
import os
nginx_file = "/etc/nginx/sites-available/nothing.conf" if os.path.exists("/etc/nginx/sites-available/nothing.conf") else "/etc/nginx/sites-available/pterodactyl.conf"
if os.path.exists(nginx_file):
    with open(nginx_file, "r") as f:
        conf = f.read()

    cache_block = """
    # SVG with correct MIME type
    location ~* \\.svg$ {
        expires -1;
        add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0";
        add_header Content-Type "image/svg+xml";
        try_files $uri $uri/ /index.php?$query_string;
    }
    location ~* \\.(css|js|png|jpg|jpeg|gif|ico|woff|woff2|ttf)$ {
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

# Aggressively delete all compiled view caches
# Update all allocations in DB to use real VPS Public IP instead of panel domain
SERVER_IP=$(curl -4 -fsSL https://api.ipify.org 2>/dev/null || curl -4 -fsSL https://ifconfig.me 2>/dev/null || echo "213.136.89.90")
if [ -n "$SERVER_IP" ]; then
    for pdir in "$PANEL_DIR" /var/www/nothing /var/www/pterodactyl; do
        if [ -d "$pdir" ]; then
            cd "$pdir"
            php artisan tinker --execute="
            \$ip = '$SERVER_IP';
            if (!empty(\$ip)) {
                \Pterodactyl\Models\Allocation::query()->update(['ip_alias' => \$ip]);
            }
            " >/dev/null 2>&1 || true
        fi
    done
fi

rm -rf "$PANEL_DIR/storage/framework/views/"* 2>/dev/null || true
rm -rf /var/www/nothing/storage/framework/views/* 2>/dev/null || true
rm -rf /var/www/pterodactyl/storage/framework/views/* 2>/dev/null || true

for pdir in "$PANEL_DIR" /var/www/nothing /var/www/pterodactyl; do
    if [ -d "$pdir" ]; then
        cd "$pdir"
        php artisan view:clear >/dev/null 2>&1 || true
        php artisan config:clear >/dev/null 2>&1 || true
        php artisan cache:clear >/dev/null 2>&1 || true
    fi
done

# 8. Clean up Nginx conflicts & Ensure SSL certificate resolution
rm -f /etc/nginx/sites-enabled/pterodactyl.conf /etc/nginx/sites-available/pterodactyl.conf 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Auto-heal SSL certificates if Let's Encrypt certs exist
if [ -n "$PANEL_URL" ]; then
  DOMAIN_ONLY=$(echo "$PANEL_URL" | sed -e 's@^https://@@' -e 's@^http://@@' -e 's@/.*@@' -e 's@:.*@@')
  if [ -n "$DOMAIN_ONLY" ] && [ -d "/etc/letsencrypt/live/$DOMAIN_ONLY" ]; then
    mkdir -p /etc/ssl
    ln -sf "/etc/letsencrypt/live/$DOMAIN_ONLY/fullchain.pem" "/etc/ssl/${DOMAIN_ONLY}.pem" 2>/dev/null || true
    ln -sf "/etc/letsencrypt/live/$DOMAIN_ONLY/privkey.pem" "/etc/ssl/${DOMAIN_ONLY}.key" 2>/dev/null || true
    if [ -f /etc/nginx/sites-available/nothing.conf ]; then
      sed -i -e "s@/etc/ssl/${DOMAIN_ONLY}.pem@/etc/letsencrypt/live/${DOMAIN_ONLY}/fullchain.pem@g" /etc/nginx/sites-available/nothing.conf
      sed -i -e "s@/etc/ssl/${DOMAIN_ONLY}.key@/etc/letsencrypt/live/${DOMAIN_ONLY}/privkey.pem@g" /etc/nginx/sites-available/nothing.conf
    fi
  fi
fi

# Ensure sites-enabled has nothing.conf
if [ -f /etc/nginx/sites-available/nothing.conf ]; then
  ln -sf /etc/nginx/sites-available/nothing.conf /etc/nginx/sites-enabled/nothing.conf 2>/dev/null || true
fi

if nginx -t >/dev/null 2>&1; then
  systemctl restart nginx 2>/dev/null || systemctl reload nginx 2>/dev/null || true
fi
systemctl restart php8.3-fpm 2>/dev/null || true

echo "Nothing Panel custom branding applied successfully!"

# Seamlessly launch the Nothing Panel menu if not running from inside an updater
if [ -z "$NP_NO_MENU" ]; then
    echo ""
    echo "  ╔══════════════════════════════════════════════════════════════════╗"
    echo "  ║  Opening Nothing Panel Installer & Manager...                    ║"
    echo "  ╚══════════════════════════════════════════════════════════════════╝"
    echo ""
    TMP_MENU=$(mktemp /tmp/np-menu.XXXXXX.sh)
    trap 'rm -f "$TMP_MENU"' EXIT
    curl -fsSL "https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/install.sh" -o "$TMP_MENU" 2>/dev/null || true
    if [ -f "$TMP_MENU" ]; then
        chmod +x "$TMP_MENU"
        if [ -e /dev/tty ]; then
            NP_REEXEC=1 exec bash "$TMP_MENU" "$@" < /dev/tty
        else
            NP_REEXEC=1 exec bash "$TMP_MENU" "$@"
        fi
    fi
fi
