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

# 2. Deploy Brand Logo, Favicons & Neutralize dinosaur SVG
mkdir -p "$PANEL_DIR/public/assets" "$PANEL_DIR/public/favicons" "$PANEL_DIR/public/assets/svgs"
curl -fsSL "https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/configs/logo.png" -o "$PANEL_DIR/public/assets/logo.png" 2>/dev/null || true
curl -fsSL "https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/configs/logo.png" -o "$PANEL_DIR/public/favicons/apple-touch-icon.png" 2>/dev/null || true
curl -fsSL "https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/configs/logo.png" -o "$PANEL_DIR/public/favicons/favicon-32x32.png" 2>/dev/null || true
curl -fsSL "https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/configs/favicon.ico" -o "$PANEL_DIR/public/favicons/favicon.ico" 2>/dev/null || true
chmod 644 "$PANEL_DIR/public/assets/logo.png" 2>/dev/null || true

# Render Vynoxis logo inside pterodactyl.svg so even cached or fallback references show the logo
cat << 'EOF' > "$PANEL_DIR/public/assets/svgs/pterodactyl.svg"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="100%" height="100%">
  <image href="/assets/logo.png" width="512" height="512" />
</svg>
EOF
chmod 644 "$PANEL_DIR/public/assets/svgs/pterodactyl.svg"
chown www-data:www-data "$PANEL_DIR/public/assets/svgs/pterodactyl.svg"

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

    # Force dark card background in auth bundle inline style
    if 'backgroundColor:"rgba(255, 255, 255, var(--tw-bg-opacity))"' in content:
        content = content.replace('backgroundColor:"rgba(255, 255, 255, var(--tw-bg-opacity))"', 'backgroundColor:"rgba(18, 14, 34, 1)"')
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
  sed -i "s@config('app.name', 'Pterodactyl')@config('app.name', 'Nothing Panel')@g" "$WRAPPER"

  python3 - << 'PYEOF'
import os, re

panel_dir = os.environ.get('PANEL_DIR', '/var/www/nothing')
wrapper_path = os.path.join(panel_dir, "resources/views/templates/wrapper.blade.php")
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
                background-image: radial-gradient(circle at 50% 10%, rgba(194, 104, 242, 0.18) 0%, transparent 60%) !important;
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif !important;
                color: #f1f5f9 !important;
            }
            /* MASCOT AND FOOTER REMOVAL (Target all styled component classes & DOM elements) */
            .sc-cyh04c-4,
            .sc-cyh04c-5,
            .sc-cyh04c-7,
            .sc-cyh04c-8,
            [class*="sc-cyh04c-4"],
            [class*="sc-cyh04c-5"],
            [class*="sc-cyh04c-7"],
            [class*="sc-cyh04c-8"],
            div[class*="LoginFormContainer___StyledDiv2"],
            img[src*="pterodactyl"],
            img[alt*="pterodactyl"],
            p[class*="LoginFormContainer___StyledP"],
            a[href*="pterodactyl"] {
                display: none !important;
                visibility: hidden !important;
                height: 0 !important;
                width: 0 !important;
                opacity: 0 !important;
            }
            /* CENTER AND STYLE THE LOGIN CARD */
            .sc-cyh04c-3,
            [class*="sc-cyh04c-3"],
            div[class*="LoginFormContainer___StyledDiv"],
            #app form > div,
            #app form {
                max-width: 440px !important;
                margin: 3.5rem auto 2rem auto !important;
                background-color: #120e22 !important;
                background: #120e22 !important;
                border: 1.5px solid rgba(194, 104, 242, 0.45) !important;
                box-shadow: 0 25px 70px rgba(0, 0, 0, 0.85), 0 0 35px rgba(194, 104, 242, 0.25) !important;
                border-radius: 16px !important;
                padding: 2.5rem 2rem !important;
                display: block !important;
            }
            /* BRAND LOGO ON LOGIN CARD */
            .sc-cyh04c-3::before,
            [class*="sc-cyh04c-3"]::before,
            div[class*="LoginFormContainer___StyledDiv"]::before {
                content: "";
                display: block;
                width: 100px;
                height: 100px;
                margin: 0 auto 1.5rem auto;
                background: url("/assets/logo.png") no-repeat center center;
                background-size: contain;
                border-radius: 20px;
                filter: drop-shadow(0 0 16px rgba(194, 104, 242, 0.65));
            }
            div[class*="LoginFormContainer___StyledDiv3"],
            .sc-cyh04c-6,
            [class*="sc-cyh04c-6"] {
                width: 100% !important;
                flex: none !important;
                color: #f1f5f9 !important;
            }
            /* Login Title */
            h2[class*="LoginFormContainer"], h2, .sc-cyh04c-1, [class*="sc-cyh04c-1"] {
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
                display: block !important;
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
                width: 100% !important;
                box-sizing: border-box !important;
            }
            input[type="text"]:focus, input[type="password"]:focus, input[type="email"]:focus {
                border-color: #C268F2 !important;
                box-shadow: 0 0 16px rgba(194, 104, 242, 0.5) !important;
                background-color: #0f0b20 !important;
                outline: none !important;
            }
            /* Buttons */
            button, button[type="submit"], .btn-primary, [class*="Button___StyledButton"], [class*="Button"] {
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
            button:hover, button[type="submit"]:hover, .btn-primary:hover, [class*="Button___StyledButton"]:hover, [class*="Button"]:hover {
                transform: translateY(-2px) !important;
                box-shadow: 0 6px 30px rgba(194, 104, 242, 0.8) !important;
                filter: brightness(1.1) !important;
            }
            /* ALL SELECT MENUS — ULTRA SLEEK #C268F2 CUSTOM STYLING */
            select, .form-control select, select.form-control, [class*="Select"] select {
                appearance: none !important;
                -webkit-appearance: none !important;
                -moz-appearance: none !important;
                background-color: #0d091a !important;
                background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='14' height='14' viewBox='0 0 24 24' fill='none' stroke='%23C268F2' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpolyline points='6 9 12 15 18 9'%3E%3C/polyline%3E%3C/svg%3E") !important;
                background-repeat: no-repeat !important;
                background-position: right 1rem center !important;
                background-size: 14px 14px !important;
                border: 1.5px solid rgba(194, 104, 242, 0.45) !important;
                border-radius: 10px !important;
                color: #f1e5ff !important;
                padding: 0.75rem 2.5rem 0.75rem 1rem !important;
                cursor: pointer !important;
                transition: all 0.2s ease !important;
                font-size: 0.95rem !important;
                box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3) !important;
            }
            select:focus, .form-control select:focus, select.form-control:focus {
                border-color: #C268F2 !important;
                box-shadow: 0 0 20px rgba(194, 104, 242, 0.55) !important;
                outline: none !important;
                background-color: #120c24 !important;
            }
            select option, .form-control select option {
                background-color: #120e24 !important;
                color: #f1e5ff !important;
                padding: 10px 14px !important;
            }
            select option:hover, select option:checked {
                background: linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%) !important;
                color: #ffffff !important;
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
            div[class*="FlashMessageRender"], .sc-cyh04c-2, [class*="sc-cyh04c-2"] {
                border-radius: 10px !important;
            }
            /* SERVER MANAGEMENT & SETTINGS CARDS (CUSTOM LUXURY THEME #C268F2) */
            div[class*="ServerContentBlock"] {
                background: transparent !important;
                border: none !important;
                box-shadow: none !important;
                padding: 0 !important;
            }
            div[class*="SettingsContainer"] {
                background: transparent !important;
                border: none !important;
                box-shadow: none !important;
                padding: 0 !important;
                display: grid !important;
                grid-template-columns: repeat(2, minmax(0, 1fr)) !important;
                gap: 1.5rem !important;
                width: 100% !important;
            }
            @media (max-width: 900px) {
                div[class*="SettingsContainer"] {
                    grid-template-columns: 1fr !important;
                }
            }
            /* ONLY individual cards get the card styling */
            div[class*="TitledGreyBox"],
            div[class*="ContentBox"] {
                background-color: #120e24 !important;
                background: #120e24 !important;
                border: 1.5px solid rgba(194, 104, 242, 0.28) !important;
                border-radius: 14px !important;
                box-shadow: 0 10px 30px rgba(0, 0, 0, 0.6), 0 0 15px rgba(194, 104, 242, 0.12) !important;
                transition: all 0.25s ease !important;
                margin-bottom: 1.5rem !important;
            }
            div[class*="TitledGreyBox"]:hover {
                border-color: rgba(194, 104, 242, 0.5) !important;
                box-shadow: 0 14px 40px rgba(0, 0, 0, 0.75), 0 0 22px rgba(194, 104, 242, 0.22) !important;
            }
            /* CONSOLE TERMINAL & GRAPHS & STAT BLOCKS */
            div[class*="ServerConsoleContainer"],
            div[class*="TerminalContainer"],
            div[class*="ConsoleContainer"] {
                background-color: #0b0717 !important;
                border: 1.5px solid rgba(194, 104, 242, 0.28) !important;
                border-radius: 14px !important;
                box-shadow: 0 10px 30px rgba(0, 0, 0, 0.7) !important;
                overflow: hidden !important;
            }
            input[class*="CommandInput"],
            div[class*="ServerConsoleContainer"] input,
            div[class*="Terminal"] + div input {
                background-color: #080512 !important;
                border: 1.5px solid rgba(194, 104, 242, 0.35) !important;
                color: #ffffff !important;
                border-radius: 8px !important;
            }
            input[class*="CommandInput"]:focus,
            div[class*="ServerConsoleContainer"] input:focus {
                border-color: #C268F2 !important;
                box-shadow: 0 0 16px rgba(194, 104, 242, 0.5) !important;
            }
            /* STAT CARDS (Offline, Disk, Memory) & GRAPH BOXES (CPU Load, Memory, Network) */
            div[class*="StatBlock"],
            div[class*="StatBox"],
            div[class*="ChartBlock"],
            div[class*="bg-gray-700"],
            div[class*="bg-gray-800"],
            div[class*="bg-neutral-700"],
            div[class*="bg-neutral-800"],
            div[class*="bg-neutral-900"],
            .bg-gray-700,
            .bg-gray-800,
            .bg-neutral-700,
            .bg-neutral-800 {
                background-color: #120e24 !important;
                background: #120e24 !important;
                border: 1.5px solid rgba(194, 104, 242, 0.28) !important;
                border-radius: 12px !important;
                box-shadow: 0 8px 24px rgba(0, 0, 0, 0.55) !important;
                transition: all 0.2s ease !important;
            }
            div[class*="StatBlock"]:hover,
            div[class*="StatBox"]:hover,
            div[class*="ChartBlock"]:hover,
            div[class*="bg-gray-700"]:hover,
            div[class*="bg-gray-800"]:hover {
                border-color: rgba(194, 104, 242, 0.55) !important;
                box-shadow: 0 10px 30px rgba(0, 0, 0, 0.75), 0 0 16px rgba(194, 104, 242, 0.22) !important;
            }
            div[class*="StatBlock"] p,
            div[class*="StatBox"] p,
            div[class*="ChartBlock"] p,
            div[class*="StatBlock"] span,
            div[class*="StatBox"] span,
            div[class*="bg-gray-700"] p,
            div[class*="bg-gray-800"] p {
                color: #e2d2f7 !important;
            }
            div[class*="ChartBlock"] h3,
            div[class*="ChartBlock"] h4,
            div[class*="StatBlock"] h3 {
                color: #ffffff !important;
                font-weight: 700 !important;
            }
            /* CARD HEADINGS */
            p[class*="TitledGreyBox___StyledP"],
            div[class*="TitledGreyBox"] > div:first-child p {
                color: #e2d2f7 !important;
                font-weight: 700 !important;
                letter-spacing: 0.8px !important;
                text-transform: uppercase !important;
                font-size: 0.85rem !important;
            }
            /* INPUTS AND TEXTAREAS */
            input[type="text"], input[type="password"], textarea {
                background-color: #0b0818 !important;
                border: 1.5px solid #2d1e4d !important;
                color: #ffffff !important;
                border-radius: 8px !important;
            }
            input[type="text"]:focus, input[type="password"]:focus, textarea:focus {
                border-color: #C268F2 !important;
                box-shadow: 0 0 16px rgba(194, 104, 242, 0.5) !important;
                background-color: #100b22 !important;
                outline: none !important;
            }
            /* BUTTONS IN SERVER PAGES */
            button, button[type="submit"], [class*="Button"] {
                background: linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%) !important;
                background-color: #C268F2 !important;
                color: #ffffff !important;
                font-weight: 800 !important;
                letter-spacing: 0.8px !important;
                border-radius: 8px !important;
                box-shadow: 0 4px 18px rgba(194, 104, 242, 0.45) !important;
                border: none !important;
            }
            button:hover, [class*="Button"]:hover {
                transform: translateY(-2px) !important;
                box-shadow: 0 6px 28px rgba(194, 104, 242, 0.75) !important;
                filter: brightness(1.1) !important;
            }
            /* HIDE PTERODACTYL FOOTER ON SERVER PAGES */
            div[class*="PageContentBlock"] > div > p,
            div[class*="PageContentBlock"] p,
            a[href*="pterodactyl.io"] {
                display: none !important;
                visibility: hidden !important;
                opacity: 0 !important;
                height: 0 !important;
            }
        </style>
        <!-- Custom Domains & Port Router Script -->
        <script>
        (function() {
            function injectDomainManager() {
                const path = window.location.pathname;
                const match = path.match(/^\/server\/([a-zA-Z0-9]+)\/settings/);
                if (!match) return;
                
                const serverId = match[1];
                if (document.getElementById('np-domain-manager-card')) return;
                
                const card = document.createElement('div');
                card.id = 'np-domain-manager-card';
                card.style.cssText = 'width: 100% !important; margin-top: 1.5rem !important; background: #120e24 !important; border: 1.5px solid rgba(194, 104, 242, 0.4) !important; border-radius: 14px !important; padding: 1.5rem 1.75rem !important; box-shadow: 0 10px 35px rgba(0,0,0,0.7), 0 0 20px rgba(194,104,242,0.15) !important; box-sizing: border-box !important; clear: both !important; display: block !important;';
                
                card.innerHTML = `
                    <div style="display:flex; justify-content:space-between; align-items:center; border-bottom:1px solid rgba(194,104,242,0.2); padding-bottom:1rem; margin-bottom:1.25rem;">
                        <div>
                            <div style="display:flex; align-items:center; gap:10px;">
                                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#C268F2" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:middle;"><circle cx="12" cy="12" r="10"></circle><line x1="2" y1="12" x2="22" y2="12"></line><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"></path></svg>
                                <h3 style="margin:0; font-size:1.15rem; font-weight:800; color:#ffffff; letter-spacing:0.5px;">CUSTOM DOMAINS &amp; PORT ROUTING</h3>
                                <span style="background:rgba(194,104,242,0.22); color:#C268F2; font-size:0.72rem; font-weight:800; padding:3px 10px; border-radius:20px; border:1px solid rgba(194,104,242,0.4); text-transform:uppercase; letter-spacing:0.5px;">INSTANT ROUTER</span>
                            </div>
                            <p style="margin:6px 0 0 0; font-size:0.85rem; color:#b7a4d6;">Connect your custom domain directly to this game server without any terminal commands.</p>
                        </div>
                    </div>
                    
                    <div style="display:flex; flex-wrap:wrap; gap:12px; align-items:flex-end; margin-bottom:1.25rem; background:#0b0818; padding:1.25rem; border-radius:10px; border:1px solid rgba(194,104,242,0.25);">
                        <div style="flex:2; min-width:220px;">
                            <label style="display:block; font-size:0.75rem; font-weight:700; color:#d1b8eb; text-transform:uppercase; margin-bottom:6px;">Custom Domain</label>
                            <input type="text" id="np-domain-input" placeholder="e.g. play.yourdomain.com" style="width:100%; box-sizing:border-box; background:#120e24; border:1.5px solid #322254; color:#fff; border-radius:8px; padding:10px 14px; font-size:0.9rem; outline:none;" />
                        </div>
                        <div style="flex:1; min-width:140px;">
                            <label style="display:block; font-size:0.75rem; font-weight:700; color:#d1b8eb; text-transform:uppercase; margin-bottom:6px;">Target Port</label>
                            <select id="np-port-select" style="width:100%; box-sizing:border-box; background:#120e24; border:1.5px solid #322254; color:#fff; border-radius:8px; padding:10px 14px; font-size:0.9rem; outline:none; cursor:pointer;">
                                <option value="">Loading ports...</option>
                            </select>
                        </div>
                        <div style="display:flex; align-items:center; gap:8px; padding:10px 6px;">
                            <input type="checkbox" id="np-ssl-toggle" checked style="cursor:pointer; accent-color:#C268F2; width:16px; height:16px;" />
                            <label for="np-ssl-toggle" style="font-size:0.82rem; color:#d1b8eb; cursor:pointer; font-weight:600;">Auto-SSL</label>
                        </div>
                        <div>
                            <button id="np-btn-add-domain" style="background:linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%); color:#fff; font-weight:700; font-size:0.85rem; padding:11px 22px; border-radius:8px; border:none; cursor:pointer; box-shadow:0 4px 15px rgba(194,104,242,0.4); text-transform:uppercase; letter-spacing:0.5px;">+ Connect Domain</button>
                        </div>
                    </div>

                    <div id="np-domain-msg" style="display:none; margin-bottom:1rem; padding:10px 14px; border-radius:8px; font-size:0.85rem; font-weight:600;"></div>

                    <div>
                        <h4 style="margin:0 0 10px 0; font-size:0.8rem; font-weight:700; color:#8e79b0; text-transform:uppercase; letter-spacing:0.8px;">Active Domains</h4>
                        <div id="np-domains-list">
                            <div style="color:#7c6999; font-size:0.85rem; font-style:italic; padding:12px 0;">Loading domains...</div>
                        </div>
                    </div>
                `;
                
                const settingsGrid = document.querySelector('div[class*="SettingsContainer"]');
                if (settingsGrid) {
                    settingsGrid.insertAdjacentElement('afterend', card);
                } else {
                    const target = document.querySelector('div[class*="ServerContentBlock"]') || document.querySelector('div[class*="PageContentBlock"]');
                    if (target) {
                        target.appendChild(card);
                    } else {
                        const boxes = document.querySelectorAll('div[class*="TitledGreyBox"]');
                        if (boxes.length > 0) {
                            boxes[boxes.length - 1].parentElement.insertAdjacentElement('afterend', card);
                        }
                    }
                }
                loadServerDomains(serverId);
                
                const btnAdd = document.getElementById('np-btn-add-domain');
                if (btnAdd) {
                    btnAdd.addEventListener('click', function() {
                        addServerDomain(serverId);
                    });
                }
            }
                });
            }

            function getCsrfToken() {
                const el = document.querySelector('meta[name="csrf-token"]');
                return el ? el.getAttribute('content') : '';
            }

            function showMsg(text, isError) {
                const msg = document.getElementById('np-domain-msg');
                if (!msg) return;
                msg.style.display = 'block';
                msg.style.background = isError ? 'rgba(239, 68, 68, 0.2)' : 'rgba(16, 185, 129, 0.2)';
                msg.style.border = isError ? '1px solid #ef4444' : '1px solid #10b981';
                msg.style.color = isError ? '#fca5a5' : '#a7f3d0';
                msg.textContent = text;
                setTimeout(() => { if (msg) msg.style.display = 'none'; }, 6000);
            }

            function loadServerDomains(serverId) {
                fetch('/api/server/' + serverId + '/domains', {
                    headers: { 'Accept': 'application/json' }
                })
                .then(r => r.json())
                .then(data => {
                    if (!data.success) return;
                    
                    const portSelect = document.getElementById('np-port-select');
                    if (portSelect && data.allocations) {
                        portSelect.innerHTML = data.allocations.map(a => 
                            `<option value="${a.port}">Port ${a.port}</option>`
                        ).join('');
                    }
                    
                    const list = document.getElementById('np-domains-list');
                    if (!list) return;
                    
                    if (!data.domains || data.domains.length === 0) {
                        list.innerHTML = `<div style="color:#7c6999; font-size:0.85rem; font-style:italic; padding:12px 0;">No custom domains connected yet. Enter your domain above to point directly to your server.</div>`;
                        return;
                    }
                    
                    list.innerHTML = data.domains.map(d => `
                        <div style="display:flex; justify-content:space-between; align-items:center; background:#0b0818; border:1px solid rgba(194,104,242,0.2); border-radius:10px; padding:12px 16px; margin-bottom:8px;">
                            <div style="display:flex; align-items:center; gap:12px;">
                                <a href="${d.ssl ? 'https://' : 'http://'}${d.domain}" target="_blank" style="font-weight:700; color:#fff; text-decoration:none; font-size:0.95rem; display:inline-flex; align-items:center; gap:4px;">${d.domain} <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#C268F2" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"></path><polyline points="15 3 21 3 21 9"></polyline><line x1="10" y1="14" x2="21" y2="3"></line></svg></a>
                                <span style="color:#a895c2; font-size:0.82rem;">Port ${d.port}</span>
                                <span style="display:inline-flex; align-items:center; gap:5px; background:rgba(16,185,129,0.2); color:#10b981; font-size:0.7rem; font-weight:700; padding:2px 8px; border-radius:12px; border:1px solid rgba(16,185,129,0.4);"><span style="width:6px; height:6px; border-radius:50%; background:#10b981; display:inline-block;"></span>CONNECTED</span>
                                ${d.ssl ? `<span style="display:inline-flex; align-items:center; gap:5px; background:rgba(194,104,242,0.2); color:#C268F2; font-size:0.7rem; font-weight:700; padding:2px 8px; border-radius:12px; border:1px solid rgba(194,104,242,0.4);"><svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#C268F2" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"></rect><path d="M7 11V7a5 5 0 0 1 10 0v4"></path></svg>SSL SECURED</span>` : ''}
                            </div>
                            <button onclick="window.npRemoveDomain('${serverId}', ${d.port})" style="background:transparent; border:1px solid #ef4444; color:#ef4444; font-size:0.75rem; font-weight:700; padding:5px 12px; border-radius:6px; cursor:pointer; text-transform:uppercase;">Remove</button>
                        </div>
                    `).join('');
                })
                .catch(e => console.error('Error loading domains:', e));
            }

            function addServerDomain(serverId) {
                const input = document.getElementById('np-domain-input');
                const portSelect = document.getElementById('np-port-select');
                const sslToggle = document.getElementById('np-ssl-toggle');
                const btn = document.getElementById('np-btn-add-domain');
                
                const domain = input ? input.value.trim() : '';
                const port = portSelect ? portSelect.value : '';
                const ssl = sslToggle ? sslToggle.checked : true;
                
                if (!domain) {
                    showMsg('Please enter a valid domain name.', true);
                    return;
                }
                
                btn.disabled = true;
                btn.textContent = 'Configuring Nginx & Proxy...';
                
                fetch('/api/server/' + serverId + '/domains', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Accept': 'application/json',
                        'X-CSRF-TOKEN': getCsrfToken()
                    },
                    body: JSON.stringify({ domain: domain, port: port, ssl: ssl })
                })
                .then(r => r.json())
                .then(res => {
                    btn.disabled = false;
                    btn.textContent = '+ Connect Domain';
                    if (res.success) {
                        showMsg(res.message, false);
                        input.value = '';
                        loadServerDomains(serverId);
                    } else {
                        showMsg(res.error || 'Failed to connect domain', true);
                    }
                })
                .catch(err => {
                    btn.disabled = false;
                    btn.textContent = '+ Connect Domain';
                    showMsg('Error: ' + err.message, true);
                });
            }

            window.npRemoveDomain = function(serverId, port) {
                if (!confirm('Are you sure you want to remove the domain mapping for port ' + port + '?')) return;
                
                fetch('/api/server/' + serverId + '/domains/delete', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Accept': 'application/json',
                        'X-CSRF-TOKEN': getCsrfToken()
                    },
                    body: JSON.stringify({ port: port })
                })
                .then(r => r.json())
                .then(res => {
                    if (res.success) {
                        showMsg(res.message, false);
                        loadServerDomains(serverId);
                    } else {
                        showMsg(res.error || 'Failed to remove domain', true);
                    }
                })
                .catch(err => showMsg('Error: ' + err.message, true));
            };

            setInterval(injectDomainManager, 1000);
        })();
        </script>
    </head>"""

wrapper = wrapper.replace("</head>", custom_css, 1)
with open(wrapper_path, "w", encoding="utf-8") as f:
    f.write(wrapper)
PYEOF
fi

# 4b. Deploy 1-Click Domain Manager Backend Controller & Routes
mkdir -p "$PANEL_DIR/app/Http/Controllers/Base"
curl -fsSL "https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/scripts/DomainManagerController.php" -o "$PANEL_DIR/app/Http/Controllers/Base/DomainManagerController.php" 2>/dev/null || true
chown www-data:www-data "$PANEL_DIR/app/Http/Controllers/Base/DomainManagerController.php" 2>/dev/null || true

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
    Route::get('/', [Base\\DomainManagerController::class, 'index']);
    Route::post('/', [Base\\DomainManagerController::class, 'store']);
    Route::post('/delete', [Base\\DomainManagerController::class, 'destroy']);
});
"""
    if "DomainManagerController" not in routes_content:
        routes_content = routes_content.replace("Route::get('/{react}'", route_block + "\nRoute::get('/{react}'")
        with open(base_routes, "w") as f:
            f.write(routes_content)
PYEOF

# 5. Rebrand Admin Views & Inject Admin UI Theme
ADMIN_BLADE="$PANEL_DIR/resources/views/layouts/admin.blade.php"
if [ -f "$ADMIN_BLADE" ]; then
  sed -i "s@config('app.name', 'Pterodactyl')@config('app.name', 'Nothing Panel')@g" "$ADMIN_BLADE"
  sed -i 's@https://pterodactyl\.io/@#@g' "$ADMIN_BLADE"
  sed -i 's@https://pterodactyl\.io@#@g' "$ADMIN_BLADE"
  sed -i 's@Pterodactyl Software@Nothing Panel@g' "$ADMIN_BLADE"
  sed -i 's@<b>Pterodactyl</b>@<b>Nothing</b> Panel@g' "$ADMIN_BLADE"
  sed -i "s@<span>{{ config('app.name', 'Pterodactyl') }}</span>@<span>Nothing Panel</span>@g" "$ADMIN_BLADE"
  sed -i "s@Copyright &copy; 2015 - {{ date('Y') }}@Copyright &copy; {{ date('Y') }}@g" "$ADMIN_BLADE"

  python3 - << 'PYEOF'
import os, re

panel_dir = os.environ.get('PANEL_DIR', '/var/www/nothing')
admin_blade = os.path.join(panel_dir, "resources/views/layouts/admin.blade.php")
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

# Update copyright string in lang file
LANG_STRINGS="$PANEL_DIR/resources/lang/en/strings.php"
if [ -f "$LANG_STRINGS" ]; then
  sed -i "s@'copyright' => '&copy; 2015 - :year Pterodactyl Software'@'copyright' => '&copy; 2015 - :year Nothing Panel'@g" "$LANG_STRINGS"
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
import os
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
