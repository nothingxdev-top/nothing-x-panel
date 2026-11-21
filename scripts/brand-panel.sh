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

# 2. Deploy Brand Logo, Favicons & Neutralize dinosaur SVG
mkdir -p "$PANEL_DIR/public/assets" "$PANEL_DIR/public/favicons" "$PANEL_DIR/public/assets/svgs"
curl -fsSL "https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/configs/logo.png" -o "$PANEL_DIR/public/assets/logo.png" 2>/dev/null || true
curl -fsSL "https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/configs/logo.png" -o "$PANEL_DIR/public/favicons/apple-touch-icon.png" 2>/dev/null || true
curl -fsSL "https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/configs/logo.png" -o "$PANEL_DIR/public/favicons/favicon-32x32.png" 2>/dev/null || true
curl -fsSL "https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/configs/favicon.ico" -o "$PANEL_DIR/public/favicons/favicon.ico" 2>/dev/null || true
chmod 644 "$PANEL_DIR/public/assets/logo.png" 2>/dev/null || true

# Render Vynoxis logo inside pterodactyl.svg and dinosaur SVGs so no mascot ever displays
for svg_file in \
  "$PANEL_DIR/public/assets/svgs/pterodactyl.svg" \
  "$PANEL_DIR/public/assets/svgs/not_found.svg" \
  "$PANEL_DIR/public/assets/svgs/server_error.svg" \
  "$PANEL_DIR/public/assets/svgs/server_installing.svg" \
  "$PANEL_DIR/resources/scripts/assets/images/pterodactyl.svg" \
  "$PANEL_DIR/resources/scripts/assets/images/not_found.svg" \
  "$PANEL_DIR/resources/scripts/assets/images/server_error.svg" \
  "$PANEL_DIR/resources/scripts/assets/images/server_installing.svg"; do
  if [ -f "$svg_file" ] || [ -d "$(dirname "$svg_file")" ]; then
    cat << 'EOF' > "$svg_file"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="100%" height="100%">
  <image href="/assets/logo.png" width="512" height="512" />
</svg>
EOF
    chmod 644 "$svg_file" 2>/dev/null || true
    chown www-data:www-data "$svg_file" 2>/dev/null || true
  fi
done

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
        ('"Pterodactyl®"', '""'),
        ('Pterodactyl®', 'Nothing Panel'),
        ('Pterodactyl&reg;', 'Nothing Panel'),
        ('"Pterodactyl"', '"Nothing Panel"'),
        ('>Pterodactyl<', '>Nothing Panel<'),
        ('© 2015 - ', '© '),
        ('"© 2015 - "', '""'),
        ('hsla(209, 14%, 37%, 1)', 'rgba(11, 7, 23, 1)'),
        ('hsla(209, 18%, 30%, 1)', 'rgba(18, 14, 36, 1)'),
        ('hsla(209, 18%, 30%', 'rgba(18, 14, 36'),
        ('hsla(211, 12%, 43%', 'rgba(194, 104, 242'),
        ('hsla(211, 10%, 53%', 'rgba(18, 14, 36'),
        ('hsla(209, 14%, 37%', 'rgba(11, 7, 23'),
        ('backgroundColor:"rgba(209, 184, 235', 'backgroundColor:"rgba(11, 7, 23'),
        ('rgba(209, 184, 235, var(--tw-bg-opacity))', 'rgba(11, 7, 23, var(--tw-bg-opacity))'),
        ('rgba(209, 184, 235', 'rgba(11, 7, 23'),
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

wrapper = re.sub(r"<!-- (Nothing Panel Custom UI|Vercel-Style|Custom Domains).*?</head>", "</head>", wrapper, flags=re.DOTALL)
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
            /* CENTER AND STYLE THE LOGIN CARD ONLY ON AUTH / LOGIN CONTAINER */
            div[class*="LoginFormContainer___StyledDiv"],
            div[class*="LoginFormContainer"] form {
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
            /* Inputs & Textareas — Sleek Obsidian Dark Background (NO Pastel Purple) */
            input,
            input[type="text"],
            input[type="password"],
            input[type="email"],
            input[type="number"],
            input[type="search"],
            textarea,
            div[class*="VariableBox"] input,
            div[class*="VariableBox"] textarea,
            div[class*="StartupContainer"] input,
            div[class*="SettingsContainer"] input,
            div[class*="TitledGreyBox"] input {
                background-color: #0b0717 !important;
                background: #0b0717 !important;
                border: 1.5px solid #281f3d !important;
                color: #ffffff !important;
                border-radius: 8px !important;
                padding: 0.75rem 1rem !important;
                transition: all 0.2s ease !important;
                font-size: 0.95rem !important;
                width: 100% !important;
                box-sizing: border-box !important;
            }
            input:focus,
            input[type="text"]:focus,
            input[type="password"]:focus,
            input[type="email"]:focus,
            textarea:focus,
            div[class*="VariableBox"] input:focus,
            div[class*="StartupContainer"] input:focus,
            div[class*="SettingsContainer"] input:focus {
                border-color: #C268F2 !important;
                box-shadow: 0 0 16px rgba(194, 104, 242, 0.5) !important;
                background-color: #0e0920 !important;
                background: #0e0920 !important;
                color: #ffffff !important;
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
            /* ALL SELECT MENUS & DROPDOWNS — ULTRA SLEEK #C268F2 CUSTOM STYLING */
            select,
            .form-control select,
            select.form-control,
            [class*="Select"] select,
            select[class*="Select"],
            [class*="Select___StyledSelect"] {
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
                color: #ffffff !important;
                padding: 0.75rem 2.5rem 0.75rem 1rem !important;
                cursor: pointer !important;
                transition: all 0.2s ease !important;
                font-size: 0.95rem !important;
                box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3) !important;
            }
            select:focus,
            .form-control select:focus,
            select.form-control:focus,
            [class*="Select___StyledSelect"]:focus {
                border-color: #C268F2 !important;
                box-shadow: 0 0 20px rgba(194, 104, 242, 0.55) !important;
                outline: none !important;
                background-color: #120c24 !important;
            }
            /* Options list and dropdown menu styling (fixes gray unreadable items) */
            select option,
            select optgroup,
            .form-control select option,
            [class*="Select"] option,
            ul[role="listbox"],
            div[role="listbox"],
            div[class*="menu"],
            div[class*="Select__menu"],
            div[class*="-menu"] {
                background-color: #120e24 !important;
                background: #120e24 !important;
                color: #ffffff !important;
                border: 1px solid rgba(194, 104, 242, 0.3) !important;
                border-radius: 8px !important;
            }
            select option,
            li[role="option"],
            div[role="option"],
            div[class*="option"],
            div[class*="Select__option"] {
                background-color: #120e24 !important;
                background: #120e24 !important;
                color: #ffffff !important;
                padding: 10px 14px !important;
            }
            select option:hover,
            select option:checked,
            li[role="option"]:hover,
            div[role="option"]:hover,
            div[class*="Select__option"]:hover,
            div[class*="Select__option--is-focused"] {
                background: linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%) !important;
                background-color: #C268F2 !important;
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
            /* ========================================================= */
            /* 1. CLEAN SINGLE-CONTAINER ARCHITECTURE (NO NESTED BOXES)   */
            /* ========================================================= */
            div[class*="ServerContentBlock"],
            div[class*="PageContentBlock"],
            div[class*="SettingsContainer"],
            div[class*="sc-1e5ycmz-1"],
            div[class*="sc-1e5ycmz-2"],
            div[class*="sc-1e5ycmz-15"],
            div[class*="sc-1e5ycmz-3"],
            div[class*="sc-1e5ycmz-10"],
            div[class*="sc-1bh2mfg-0"],
            div[class*="sc-1prmksw-1"],
            div[class*="ContentBox"] {
                background: transparent !important;
                border: none !important;
                box-shadow: none !important;
                padding: 0 !important;
            }

            /* THE ONE AND ONLY MAIN CARD: TitledGreyBox */
            div[class*="TitledGreyBox___StyledDiv"],
            div[class*="sc-gvsoy-0"],
            div[class*="TitledGreyBox"] {
                background-color: #110d22 !important;
                background: #110d22 !important;
                border: 1px solid rgba(194, 104, 242, 0.22) !important;
                border-radius: 12px !important;
                box-shadow: 0 4px 20px rgba(0, 0, 0, 0.4) !important;
                padding: 1.5rem !important;
                margin-bottom: 1.5rem !important;
                box-sizing: border-box !important;
                transition: border-color 0.2s ease, box-shadow 0.2s ease !important;
            }
            div[class*="TitledGreyBox___StyledDiv"]:hover,
            div[class*="sc-gvsoy-0"]:hover,
            div[class*="TitledGreyBox"]:hover {
                border-color: rgba(194, 104, 242, 0.45) !important;
                box-shadow: 0 6px 25px rgba(0, 0, 0, 0.55), 0 0 15px rgba(194, 104, 242, 0.15) !important;
            }

            /* REMOVE nested header box and borders inside TitledGreyBox */
            div[class*="TitledGreyBox___StyledDiv2"],
            div[class*="sc-gvsoy-1"] {
                background: transparent !important;
                border: none !important;
                border-bottom: 1px solid rgba(194, 104, 242, 0.15) !important;
                border-radius: 0 !important;
                padding: 0 0 0.85rem 0 !important;
                margin-bottom: 1.25rem !important;
            }
            div[class*="TitledGreyBox___StyledDiv3"],
            div[class*="sc-gvsoy-4"] {
                background: transparent !important;
                border: none !important;
                padding: 0 !important;
                box-shadow: none !important;
            }

            /* REMOVE all decorative rectangular outlines & nested borders inside settings & forms */
            div[class*="SettingsContainer___StyledDiv"],
            div[class*="sc-1e5ycmz-4"],
            div[class*="sc-1e5ycmz-5"],
            div[class*="sc-1e5ycmz-6"],
            div[class*="sc-1e5ycmz-7"],
            div[class*="sc-1e5ycmz-8"],
            div[class*="sc-1e5ycmz-9"],
            div[class*="RenameServerBox___StyledDiv"],
            div[class*="sc-1bh2mfg-2"],
            div[class*="sc-1bh2mfg-3"],
            div[class*="ReinstallServerBox___StyledDiv"],
            div[class*="sc-1prmksw-4"],
            div[class*="TitledGreyBox"] form,
            div[class*="TitledGreyBox"] form > div,
            div[class*="TitledGreyBox"] form div,
            div[class*="TitledGreyBox"] div[class*="FormikFieldWrapper"],
            div[class*="TitledGreyBox"] div[class*="Field"],
            div[class*="RenameServerBox"] form,
            div[class*="RenameServerBox"] form > div,
            div[class*="RenameServerBox"] div,
            div[class*="SettingsContainer"] form > div,
            div[class*="ReinstallServerBox"] form > div {
                background: transparent !important;
                border: none !important;
                box-shadow: none !important;
                border-radius: 0 !important;
                max-width: 100% !important;
            }
            div[class*="RenameServerBox"] form > div,
            div[class*="TitledGreyBox"] form > div {
                margin: 0 0 1.25rem 0 !important;
                padding: 0 !important;
            }
            div[class*="RenameServerBox"] form > div:last-child,
            div[class*="TitledGreyBox"] form > div:last-child {
                margin-bottom: 0 !important;
            }
            /* Code badge in debug info */
            code[class*="SettingsContainer___StyledCode"],
            div[class*="sc-1e5ycmz-12"],
            div[class*="sc-1e5ycmz-14"] {
                background: rgba(194, 104, 242, 0.12) !important;
                border: 1px solid rgba(194, 104, 242, 0.25) !important;
                color: #e2d2f7 !important;
                border-radius: 6px !important;
                padding: 3px 8px !important;
                font-size: 0.82rem !important;
            }

            /* STARTUP SETTINGS & VARIABLES — FULLY VISIBLE & VIBRANT */
            div[class*="StartupContainer"] p,
            div[class*="VariableBox"] p,
            div[class*="TitledGreyBox"] p,
            div[class*="TitledGreyBox"] span,
            div[class*="TitledGreyBox"] code {
                opacity: 1 !important;
                visibility: visible !important;
            }
            p[class*="StartupContainer___StyledP"],
            p[class*="font-mono"] {
                background-color: #0b0717 !important;
                border: 1.5px solid rgba(194, 104, 242, 0.35) !important;
                color: #38ef7d !important;
                font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace !important;
                padding: 0.75rem 1rem !important;
                border-radius: 8px !important;
                display: block !important;
                word-break: break-all !important;
                font-size: 0.95rem !important;
            }
            p[class*="text-neutral-300"],
            div[class*="VariableBox"] p {
                color: #c9b6e3 !important;
                font-size: 0.85rem !important;
                margin-top: 0.4rem !important;
                display: block !important;
            }

            /* ========================================================= */
            /* 2. FILES PAGE CLEANUP (CLEAN STANDARD TABLE LAYOUT)       */
            /* ========================================================= */
            div[class*="FileManagerContainer"] {
                background: transparent !important;
                border: none !important;
                box-shadow: none !important;
            }
            div[class*="FileManagerBreadcrumbs"],
            div[class*="sc-1yfrkfk"] {
                background: transparent !important;
                border: none !important;
                box-shadow: none !important;
                padding: 0.5rem 0 !important;
                margin-bottom: 0.75rem !important;
            }
            /* File rows: Clean table-like rows with only a subtle bottom divider, NO pill-shaped boxes */
            div[class*="file_row"],
            div[class*="style-module_HHpjDvv7"] {
                background: transparent !important;
                border: none !important;
                border-bottom: 1px solid rgba(194, 104, 242, 0.12) !important;
                border-radius: 0 !important;
                box-shadow: none !important;
                padding: 0.75rem 0.5rem !important;
                margin-bottom: 0 !important;
                transition: background 0.15s ease !important;
            }
            div[class*="file_row"]:hover,
            div[class*="style-module_HHpjDvv7"]:hover {
                background: rgba(194, 104, 242, 0.08) !important;
                border-radius: 6px !important;
            }
            /* File details: NO inner pill outlines */
            div[class*="details"],
            div[class*="style-module_le7taa7N"],
            div[class*="FileObjectRow"] > div {
                border: none !important;
                background: transparent !important;
                box-shadow: none !important;
                border-radius: 0 !important;
            }
            /* File name, size, date typography */
            div[class*="FileObjectRow___StyledDiv2"],
            div[class*="sc-wrdnyp-1"] {
                color: #ffffff !important;
                font-weight: 500 !important;
            }
            div[class*="FileObjectRow___StyledDiv3"],
            div[class*="FileObjectRow___StyledDiv4"],
            div[class*="sc-wrdnyp-2"],
            div[class*="sc-wrdnyp-3"] {
                color: #a394bf !important;
                font-size: 0.85rem !important;
            }

            /* ========================================================= */
            /* 3. DASHBOARD SERVER ROWS (CLEAN SINGLE CARDS, NO INNER BOXES) */
            /* ========================================================= */
            /* The outer server row link is the ONLY card */
            a[class*="ServerRow__StatusIndicatorBox"],
            a[class*="sc-1ibsw91-2"],
            div[class*="DashboardContainer"] a[href*="/server/"] {
                background-color: #110d22 !important;
                background: #110d22 !important;
                border: 1px solid rgba(194, 104, 242, 0.22) !important;
                border-radius: 12px !important;
                box-shadow: 0 4px 15px rgba(0, 0, 0, 0.35) !important;
                transition: all 0.2s ease !important;
                margin-bottom: 0.85rem !important;
                display: grid !important;
            }
            a[class*="ServerRow__StatusIndicatorBox"]:hover,
            a[class*="sc-1ibsw91-2"]:hover,
            div[class*="DashboardContainer"] a[href*="/server/"]:hover {
                border-color: #C268F2 !important;
                box-shadow: 0 6px 24px rgba(194, 104, 242, 0.35) !important;
                transform: translateY(-2px) !important;
            }

            /* ALL INNER DIVS AND SPANS INSIDE SERVER ROW MUST BE COMPLETELY PLAIN & BORDERLESS */
            a[class*="ServerRow__StatusIndicatorBox"] div,
            a[class*="ServerRow__StatusIndicatorBox"] span:not(.status-bar),
            a[class*="sc-1ibsw91-2"] div,
            a[class*="sc-1ibsw91-2"] span:not(.status-bar),
            div[class*="DashboardContainer"] a[href*="/server/"] div,
            div[class*="DashboardContainer"] a[href*="/server/"] span:not(.status-bar),
            div[class*="sc-1ibsw91-3"],
            div[class*="sc-1ibsw91-4"],
            div[class*="sc-1ibsw91-6"],
            div[class*="sc-1ibsw91-7"],
            div[class*="sc-1ibsw91-8"],
            div[class*="sc-1ibsw91-10"],
            div[class*="sc-1ibsw91-11"],
            div[class*="sc-1ibsw91-13"],
            div[class*="sc-1ibsw91-15"],
            div[class*="sc-1ibsw91-17"],
            div[class*="sc-1ibsw91-18"],
            div[class*="sc-1ibsw91-20"],
            div[class*="sc-1ibsw91-21"],
            div[class*="sc-1ibsw91-23"],
            div[class*="sc-1ibsw91-24"] {
                background: transparent !important;
                border: none !important;
                box-shadow: none !important;
                transform: none !important;
                border-radius: 0 !important;
            }

            /* ALL STATS, LABELS & ICONS ALWAYS 100% VISIBLE (FIX HOVER-ONLY BUG) */
            a[href*="/server/"] div,
            a[href*="/server/"] p,
            a[href*="/server/"] span,
            a[href*="/server/"] svg {
                opacity: 1 !important;
                visibility: visible !important;
            }
            a[href*="/server/"] p,
            div[class*="sc-1ibsw91"] p,
            div[class*="ServerRow"] p {
                color: #ffffff !important;
                font-weight: 600 !important;
            }
            /* Server name styling */
            a[href*="/server/"] p[class*="break-words"] {
                color: #ffffff !important;
                font-weight: 700 !important;
                font-size: 1.1rem !important;
            }
            /* Server IP / Port allocation */
            a[href*="/server/"] div[class*="lg:col-span-2"] p {
                color: #d1b8eb !important;
                font-weight: 600 !important;
            }
            /* Limit subtitles ("of Unlimited") */
            a[href*="/server/"] div[class*="flex-1"] p:last-child {
                color: #a394bf !important;
                font-size: 0.75rem !important;
                font-weight: 400 !important;
            }
            /* Icons */
            a[href*="/server/"] svg {
                color: #C268F2 !important;
            }

            /* ========================================================= */
            /* 4. OTHER ROWS (Databases, Schedules, Users, Backups)      */
            /* ========================================================= */
            div[class*="GreyRowBox"],
            div[class*="sc-1xo9c6v"] {
                background-color: #110d22 !important;
                background: #110d22 !important;
                border: 1px solid rgba(194, 104, 242, 0.2) !important;
                border-radius: 10px !important;
                box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3) !important;
                padding: 1rem !important;
                margin-bottom: 0.75rem !important;
            }
            div[class*="GreyRowBox"] > div,
            div[class*="sc-1xo9c6v"] > div {
                border: none !important;
                background: transparent !important;
                box-shadow: none !important;
            }

            /* ========================================================= */
            /* 5. CONSOLE TERMINAL, STAT CARDS & CHARTS                  */
            /* ========================================================= */
            div[class*="ServerConsoleContainer"],
            div[class*="TerminalContainer"],
            div[class*="ConsoleContainer"] {
                background-color: #0b0717 !important;
                border: 1px solid rgba(194, 104, 242, 0.22) !important;
                border-radius: 12px !important;
                box-shadow: 0 8px 25px rgba(0, 0, 0, 0.5) !important;
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
            div[class*="stat_block"],
            div[class*="style-module_V4CSEpa4"] {
                background-color: #110d22 !important;
                background: #110d22 !important;
                border: 1px solid rgba(194, 104, 242, 0.22) !important;
                border-radius: 10px !important;
                box-shadow: 0 4px 15px rgba(0, 0, 0, 0.35) !important;
                overflow: hidden !important;
            }
            div[class*="status_bar"],
            div[class*="style-module_M2eytJMi"] {
                background: #C268F2 !important;
                border: none !important;
            }
            div[class*="icon"][class*="style-module"] {
                background: transparent !important;
                border: none !important;
            }
            div[class*="chart_container"],
            div[class*="style-module_j35sQtg2"] {
                background-color: #110d22 !important;
                background: #110d22 !important;
                border: 1px solid rgba(194, 104, 242, 0.22) !important;
                border-bottom: 3px solid #C268F2 !important;
                border-radius: 10px !important;
                box-shadow: 0 4px 15px rgba(0, 0, 0, 0.35) !important;
            }
            div[class*="chart_container"]:hover,
            div[class*="style-module_j35sQtg2"]:hover {
                border-color: #C268F2 !important;
                box-shadow: 0 10px 32px rgba(194, 104, 242, 0.35) !important;
            }
            div[class*="chart_container"] h3,
            div[class*="style-module_j35sQtg2"] h3 {
                color: #ffffff !important;
                font-weight: 700 !important;
            }
            div[class*="chart_container"] p,
            div[class*="style-module_j35sQtg2"] p,
            div[class*="stat_block"] p,
            div[class*="stat_block"] span {
                color: #e2d2f7 !important;
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
            /* ELIMINATE ONLY PTERODACTYL COPYRIGHT & FOOTER LINKS */
            a[href*="pterodactyl.io"],
            p:has(> a[href*="pterodactyl.io"]),
            p[class*="LoginFormContainer___StyledP"],
            div[class*="ContentContainer"]:last-child:has(a[href*="pterodactyl.io"]),
            footer,
            .main-footer {
                display: none !important;
                visibility: hidden !important;
                opacity: 0 !important;
                height: 0 !important;
                margin: 0 !important;
                padding: 0 !important;
                overflow: hidden !important;
                pointer-events: none !important;
            }
        </style>
        <!-- Custom Domains & Cloudflare Tunnel Router Script -->
        <script>
        (function() {
            let activeMode = 'nginx'; // 'nginx' or 'cloudflared'

            function findSettingsFlexRow() {
                // Exact styled-component class for 2-column flex row in SettingsContainer
                const styledFlex = document.querySelector('div[class*="SettingsContainer___StyledDiv-sc-1e5ycmz-1"]') ||
                                   document.querySelector('div[class*="sc-1e5ycmz-1"]') ||
                                   document.querySelector('div[class*="SettingsContainer___StyledDiv"]');
                if (styledFlex && styledFlex.children.length >= 2) return styledFlex;

                const all = Array.from(document.querySelectorAll('div, p, h3, h2, h4, span'));
                const sftp = all.find(el => {
                    const t = (el.textContent || '').trim().toLowerCase();
                    return t === 'sftp details' || t === 'server address' || t === 'change server details' || t === 'reinstall server';
                });
                if (sftp) {
                    let el = sftp;
                    while (el && el !== document.body && !el.classList.contains('ContentContainer')) {
                        const style = window.getComputedStyle(el);
                        if (el.classList.contains('md:flex') || style.display === 'flex' || style.display === 'grid') {
                            if (el.children.length >= 2) return el;
                        }
                        el = el.parentElement;
                    }
                }

                // Fallback to ContentContainer
                const content = document.querySelector('div[class*="ContentContainer"]');
                if (content && content.children.length > 0) {
                    return content.lastElementChild;
                }
                return null;
            }

            function injectDomainManager() {
                const path = window.location.pathname;
                const match = path.match(/^\/server\/([a-zA-Z0-9]+)\/settings/);
                const existing = document.getElementById('np-domain-manager-card');

                // STRICT: Only show on /server/[id]/settings. Remove on ANY other route (Dashboard, Console, etc.)
                if (!match) {
                    if (existing) existing.remove();
                    return;
                }
                
                const serverId = match[1];

                // If card already exists on this server's settings and is connected to DOM, keep it
                if (existing && existing.getAttribute('data-server-id') === serverId && document.body.contains(existing)) {
                    return;
                }

                const flexRow = findSettingsFlexRow();
                if (!flexRow) {
                    // Settings page is still loading in React, retry on next tick
                    return;
                }

                if (existing) {
                    existing.remove();
                }

                const card = document.createElement('div');
                card.id = 'np-domain-manager-card';
                card.setAttribute('data-server-id', serverId);
                card.style.cssText = 'width: 100% !important; margin-top: 2rem !important; background: #110d22 !important; border: 1px solid rgba(194, 104, 242, 0.22) !important; border-radius: 12px !important; padding: 1.5rem !important; box-shadow: 0 4px 20px rgba(0, 0, 0, 0.4) !important; box-sizing: border-box !important; clear: both !important; display: block !important;';
                
                card.innerHTML = `
                    <div style="display:flex; justify-content:space-between; align-items:center; border-bottom:1px solid rgba(194,104,242,0.15); padding-bottom:0.85rem; margin-bottom:1.25rem;">
                        <div>
                            <div style="display:flex; align-items:center; gap:10px;">
                                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#C268F2" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:middle;"><circle cx="12" cy="12" r="10"></circle><line x1="2" y1="12" x2="22" y2="12"></line><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"></path></svg>
                                <h3 style="margin:0; font-size:1.15rem; font-weight:800; color:#ffffff; letter-spacing:0.5px;">CUSTOM DOMAINS &amp; PORT ROUTING</h3>
                                <span style="background:rgba(194,104,242,0.18); color:#C268F2; font-size:0.72rem; font-weight:800; padding:3px 10px; border-radius:20px; border:1px solid rgba(194,104,242,0.35); text-transform:uppercase; letter-spacing:0.5px;">INSTANT ROUTER</span>
                            </div>
                            <p style="margin:6px 0 0 0; font-size:0.85rem; color:#b7a4d6;">Connect your custom domain or route ports via Cloudflare Tunnel without terminal commands.</p>
                        </div>
                    </div>

                    <!-- MODE SELECTOR TABS (NO UNICODE EMOJIS) -->
                    <div style="display:flex; gap:10px; margin-bottom:1.25rem;">
                        <button id="np-tab-nginx" type="button" style="padding:8px 18px; border-radius:8px; font-size:0.82rem; font-weight:700; cursor:pointer; background:linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%); color:#fff; border:none; box-shadow:0 2px 10px rgba(194,104,242,0.4); display:inline-flex; align-items:center;">
                            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:middle; margin-right:7px;"><circle cx="12" cy="12" r="10"></circle><line x1="2" y1="12" x2="22" y2="12"></line><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"></path></svg>
                            CUSTOM DOMAIN (NGINX &amp; SSL)
                        </button>
                        <button id="np-tab-cf" type="button" style="padding:8px 18px; border-radius:8px; font-size:0.82rem; font-weight:700; cursor:pointer; background:#1b1531; color:#c7b4e2; border:1px solid rgba(194,104,242,0.25); display:inline-flex; align-items:center;">
                            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:middle; margin-right:7px;"><path d="M18 10h-1.26A8 8 0 1 0 9 20h9a5 5 0 0 0 0-10z"></path></svg>
                            CLOUDFLARE TUNNEL (NAT VPS / IPV6)
                        </button>
                    </div>
                    
                    <!-- NGINX REVERSE PROXY FORM -->
                    <div id="np-form-nginx" style="display:flex; flex-wrap:wrap; gap:14px; align-items:flex-end; margin-bottom:1.5rem;">
                        <div style="flex:2; min-width:220px;">
                            <label style="display:block; font-size:0.75rem; font-weight:700; color:#d1b8eb; text-transform:uppercase; margin-bottom:6px;">Custom Domain</label>
                            <input type="text" id="np-domain-input" placeholder="e.g. play.yourdomain.com" style="width:100%; height:42px; box-sizing:border-box; background:#0b0818; border:1px solid rgba(194,104,242,0.3); color:#fff; border-radius:8px; padding:0 14px; font-size:0.9rem; outline:none;" />
                        </div>
                        <div style="flex:1; min-width:140px;">
                            <label style="display:block; font-size:0.75rem; font-weight:700; color:#d1b8eb; text-transform:uppercase; margin-bottom:6px;">Target Port</label>
                            <select id="np-port-select" style="width:100%; height:42px; box-sizing:border-box; background:#0b0818; border:1px solid rgba(194,104,242,0.3); color:#fff; border-radius:8px; padding:0 36px 0 14px; font-size:0.9rem; outline:none; cursor:pointer;">
                                <option value="">Loading ports...</option>
                            </select>
                        </div>
                        <div style="display:flex; align-items:center; gap:8px; height:42px; padding:0 4px;">
                            <input type="checkbox" id="np-ssl-toggle" checked style="cursor:pointer; accent-color:#C268F2; width:16px; height:16px; margin:0;" />
                            <label for="np-ssl-toggle" style="font-size:0.82rem; color:#d1b8eb; cursor:pointer; font-weight:600; margin:0; text-transform:none;">Auto-SSL</label>
                        </div>
                        <div>
                            <button id="np-btn-add-domain" type="button" style="height:42px; background:linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%); color:#fff; font-weight:700; font-size:0.85rem; padding:0 24px; border-radius:8px; border:none; cursor:pointer; box-shadow:0 4px 15px rgba(194,104,242,0.4); text-transform:uppercase; letter-spacing:0.5px; display:inline-flex; align-items:center;">+ Connect Domain</button>
                        </div>
                    </div>

                    <!-- CLOUDFLARE TUNNEL FORM -->
                    <div id="np-form-cf" style="display:none; flex-wrap:wrap; gap:14px; align-items:flex-end; margin-bottom:1.5rem;">
                        <div style="flex:1; min-width:140px;">
                            <label style="display:block; font-size:0.75rem; font-weight:700; color:#d1b8eb; text-transform:uppercase; margin-bottom:6px;">Target Port</label>
                            <select id="np-cf-port-select" style="width:100%; height:42px; box-sizing:border-box; background:#0b0818; border:1px solid rgba(194,104,242,0.3); color:#fff; border-radius:8px; padding:0 36px 0 14px; font-size:0.9rem; outline:none; cursor:pointer;">
                                <option value="">Loading ports...</option>
                            </select>
                        </div>
                        <div style="flex:2; min-width:220px;">
                            <label style="display:block; font-size:0.75rem; font-weight:700; color:#d1b8eb; text-transform:uppercase; margin-bottom:6px;">Cloudflare Tunnel Token (Optional)</label>
                            <input type="text" id="np-cf-token-input" placeholder="Leave empty for instant Quick Tunnel (*.trycloudflare.com)" style="width:100%; height:42px; box-sizing:border-box; background:#0b0818; border:1px solid rgba(194,104,242,0.3); color:#fff; border-radius:8px; padding:0 14px; font-size:0.9rem; outline:none;" />
                        </div>
                        <div>
                            <button id="np-btn-launch-cf" type="button" style="height:42px; background:linear-gradient(135deg, #06b6d4 0%, #3b82f6 100%); color:#fff; font-weight:700; font-size:0.85rem; padding:0 24px; border-radius:8px; border:none; cursor:pointer; box-shadow:0 4px 15px rgba(6,182,212,0.4); text-transform:uppercase; letter-spacing:0.5px; display:inline-flex; align-items:center;">
                                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:middle; margin-right:7px;"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"></polygon></svg>
                                Launch Cloudflare Tunnel
                            </button>
                        </div>
                    </div>

                    <div id="np-domain-msg" style="display:none; margin-bottom:1rem; padding:10px 14px; border-radius:8px; font-size:0.85rem; font-weight:600;"></div>

                    <div>
                        <h4 style="margin:0 0 10px 0; font-size:0.8rem; font-weight:700; color:#8e79b0; text-transform:uppercase; letter-spacing:0.8px;">Active Domains &amp; Tunnels</h4>
                        <div id="np-domains-list">
                            <div style="color:#7c6999; font-size:0.85rem; font-style:italic; padding:8px 0;">Loading domains &amp; tunnels...</div>
                        </div>
                    </div>
                `;
                
                flexRow.insertAdjacentElement('afterend', card);
                loadServerDomains(serverId);
                
                // Tab switcher logic
                const tabNginx = document.getElementById('np-tab-nginx');
                const tabCf = document.getElementById('np-tab-cf');
                const formNginx = document.getElementById('np-form-nginx');
                const formCf = document.getElementById('np-form-cf');

                if (tabNginx && tabCf) {
                    tabNginx.onclick = function() {
                        activeMode = 'nginx';
                        formNginx.style.display = 'flex';
                        formCf.style.display = 'none';
                        tabNginx.style.background = 'linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%)';
                        tabNginx.style.color = '#fff';
                        tabCf.style.background = '#1b1531';
                        tabCf.style.color = '#c7b4e2';
                    };
                    tabCf.onclick = function() {
                        activeMode = 'cloudflared';
                        formNginx.style.display = 'none';
                        formCf.style.display = 'flex';
                        tabCf.style.background = 'linear-gradient(135deg, #06b6d4 0%, #3b82f6 100%)';
                        tabCf.style.color = '#fff';
                        tabNginx.style.background = '#1b1531';
                        tabNginx.style.color = '#c7b4e2';
                    };
                }

                const btnAdd = document.getElementById('np-btn-add-domain');
                if (btnAdd) {
                    btnAdd.addEventListener('click', function() {
                        addServerDomain(serverId, 'nginx');
                    });
                }

                const btnLaunchCf = document.getElementById('np-btn-launch-cf');
                if (btnLaunchCf) {
                    btnLaunchCf.addEventListener('click', function() {
                        addServerDomain(serverId, 'cloudflared');
                    });
                }
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
                setTimeout(() => { if (msg) msg.style.display = 'none'; }, 7000);
            }

            function loadServerDomains(serverId) {
                fetch('/api/server/' + serverId + '/domains', {
                    headers: { 'Accept': 'application/json' }
                })
                .then(r => r.json())
                .then(data => {
                    if (!data.success) return;
                    
                    const portSelect = document.getElementById('np-port-select');
                    const cfPortSelect = document.getElementById('np-cf-port-select');
                    if (data.allocations && data.allocations.length > 0) {
                        const optHtml = data.allocations.map(a => 
                            `<option value="${a.port}">Port ${a.port}${a.is_default ? ' (Primary)' : ''}</option>`
                        ).join('');
                        [portSelect, cfPortSelect].forEach(sel => {
                            if (!sel) return;
                            sel.innerHTML = optHtml;
                            sel.selectedIndex = 0;
                            // Reset custom select attribute & clean up wrap so it immediately re-renders with actual ports
                            sel.removeAttribute('data-np-select');
                            const prevWrap = sel.nextElementSibling;
                            if (prevWrap && prevWrap.classList.contains('np-custom-select-wrap')) {
                                prevWrap.remove();
                            }
                            sel.dispatchEvent(new Event('change', { bubbles: true }));
                            sel.dispatchEvent(new Event('input', { bubbles: true }));
                        });
                        initCustomSelects();
                    }
                    
                    const list = document.getElementById('np-domains-list');
                    if (!list) return;
                    
                    if (!data.domains || data.domains.length === 0) {
                        list.innerHTML = `<div style="color:#7c6999; font-size:0.85rem; font-style:italic; padding:12px 0;">No active domains or tunnels. Use the controls above to connect your server.</div>`;
                        return;
                    }
                    
                    list.innerHTML = data.domains.map(d => `
                        <div style="display:flex; justify-content:space-between; align-items:center; border-bottom:1px solid rgba(194,104,242,0.12); padding:10px 0;">
                            <div style="display:flex; align-items:center; gap:12px;">
                                <a href="https://${d.domain}" target="_blank" style="font-weight:700; color:#fff; text-decoration:none; font-size:0.95rem; display:inline-flex; align-items:center; gap:4px;">${d.domain} <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#C268F2" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"></path><polyline points="15 3 21 3 21 9"></polyline><line x1="10" y1="14" x2="21" y2="3"></line></svg></a>
                                <span style="color:#a895c2; font-size:0.82rem;">Port ${d.port}</span>
                                ${d.type === 'cloudflared' ? 
                                    `<span style="display:inline-flex; align-items:center; gap:5px; background:rgba(6,182,212,0.18); color:#06b6d4; font-size:0.7rem; font-weight:700; padding:2px 8px; border-radius:6px;"><span style="width:6px; height:6px; border-radius:50%; background:#06b6d4; display:inline-block;"></span>CLOUDFLARE TUNNEL</span>` : 
                                    `<span style="display:inline-flex; align-items:center; gap:5px; background:rgba(16,185,129,0.18); color:#10b981; font-size:0.7rem; font-weight:700; padding:2px 8px; border-radius:6px;"><span style="width:6px; height:6px; border-radius:50%; background:#10b981; display:inline-block;"></span>CONNECTED</span>`
                                }
                                ${d.ssl ? `<span style="display:inline-flex; align-items:center; gap:5px; background:rgba(194,104,242,0.18); color:#C268F2; font-size:0.7rem; font-weight:700; padding:2px 8px; border-radius:6px;"><svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#C268F2" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"></rect><path d="M7 11V7a5 5 0 0 1 10 0v4"></path></svg>SSL SECURED</span>` : ''}
                            </div>
                            <button onclick="window.npRemoveDomain('${serverId}', ${d.port})" style="background:transparent; border:1px solid #ef4444; color:#ef4444; font-size:0.75rem; font-weight:700; padding:4px 10px; border-radius:6px; cursor:pointer; text-transform:uppercase;">Disconnect</button>
                        </div>
                    `).join('');
                })
                .catch(e => console.error('Error loading domains:', e));
            }

            function addServerDomain(serverId, mode) {
                const portSelect = document.getElementById(mode === 'cloudflared' ? 'np-cf-port-select' : 'np-port-select');
                const port = portSelect ? portSelect.value : '';
                
                if (!port) {
                    showMsg('Please select a target port.', true);
                    return;
                }

                let payload = { mode: mode, port: port };

                if (mode === 'nginx') {
                    const input = document.getElementById('np-domain-input');
                    const sslToggle = document.getElementById('np-ssl-toggle');
                    const domain = input ? input.value.trim() : '';
                    if (!domain) {
                        showMsg('Please enter a valid domain name.', true);
                        return;
                    }
                    payload.domain = domain;
                    payload.ssl = sslToggle ? sslToggle.checked : true;

                    const btn = document.getElementById('np-btn-add-domain');
                    if (btn) {
                        btn.disabled = true;
                        btn.textContent = 'Configuring Nginx...';
                    }
                } else {
                    const tokenInput = document.getElementById('np-cf-token-input');
                    payload.cf_token = tokenInput ? tokenInput.value.trim() : '';

                    const btn = document.getElementById('np-btn-launch-cf');
                    if (btn) {
                        btn.disabled = true;
                        btn.textContent = 'Starting Tunnel...';
                    }
                }
                
                fetch('/api/server/' + serverId + '/domains', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Accept': 'application/json',
                        'X-CSRF-TOKEN': getCsrfToken()
                    },
                    body: JSON.stringify(payload)
                })
                .then(r => r.json())
                .then(res => {
                    const btn1 = document.getElementById('np-btn-add-domain');
                    const btn2 = document.getElementById('np-btn-launch-cf');
                    if (btn1) { btn1.disabled = false; btn1.textContent = '+ Connect Domain'; }
                    if (btn2) { btn2.disabled = false; btn2.innerHTML = '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:middle; margin-right:7px;"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"></polygon></svg>Launch Cloudflare Tunnel'; }

                    if (res.success) {
                        showMsg(res.message, false);
                        const inp = document.getElementById('np-domain-input');
                        if (inp) inp.value = '';
                        loadServerDomains(serverId);
                    } else {
                        showMsg(res.error || 'Operation failed', true);
                    }
                })
                .catch(err => {
                    const btn1 = document.getElementById('np-btn-add-domain');
                    const btn2 = document.getElementById('np-btn-launch-cf');
                    if (btn1) { btn1.disabled = false; btn1.textContent = '+ Connect Domain'; }
                    if (btn2) { btn2.disabled = false; btn2.innerHTML = '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:middle; margin-right:7px;"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"></polygon></svg>Launch Cloudflare Tunnel'; }
                    showMsg('Error: ' + err.message, true);
                });
            }

            window.npRemoveDomain = function(serverId, port) {
                if (!confirm('Are you sure you want to disconnect port ' + port + '?')) return;
                
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
                        showMsg(res.error || 'Failed to remove domain/tunnel', true);
                    }
                })
                .catch(err => showMsg('Error: ' + err.message, true));
            };

            // ULTRA-SLEEK CUSTOM SELECT CONTROLLER
            function initCustomSelects() {
                // Cleanup orphaned custom select wraps
                document.querySelectorAll('.np-custom-select-wrap').forEach(wrap => {
                    const prev = wrap.previousElementSibling;
                    if (!prev || prev.tagName !== 'SELECT' || !document.body.contains(prev)) {
                        wrap.remove();
                    }
                });

                const selects = Array.from(document.querySelectorAll('select:not([data-np-select="true"])'));
                selects.forEach(select => {
                    if (select.offsetParent === null && select.style.display === 'none') return;

                    select.setAttribute('data-np-select', 'true');

                    // Visually hide native select but keep it accessible for form submissions & state
                    select.style.cssText = 'position: absolute !important; opacity: 0 !important; pointer-events: none !important; width: 0 !important; height: 0 !important; margin: 0 !important; padding: 0 !important; border: none !important; z-index: -1 !important;';

                    // Wrapper container
                    const container = document.createElement('div');
                    container.className = 'np-custom-select-wrap';
                    container.style.cssText = 'position: relative !important; width: 100% !important; min-width: 140px !important; box-sizing: border-box !important; font-family: inherit !important; user-select: none !important;';

                    // Trigger button
                    const trigger = document.createElement('div');
                    trigger.className = 'np-custom-select-trigger';
                    trigger.style.cssText = 'width: 100% !important; height: 42px !important; background: #0b0717 !important; border: 1.5px solid rgba(194, 104, 242, 0.4) !important; border-radius: 8px !important; color: #ffffff !important; padding: 0 38px 0 14px !important; font-size: 0.92rem !important; font-weight: 500 !important; display: flex !important; align-items: center !important; justify-content: space-between !important; cursor: pointer !important; box-sizing: border-box !important; transition: all 0.2s ease !important;';

                    const labelSpan = document.createElement('span');
                    labelSpan.className = 'np-custom-select-label';
                    labelSpan.style.cssText = 'overflow: hidden !important; text-overflow: ellipsis !important; white-space: nowrap !important; flex: 1 !important; color: #ffffff !important;';

                    const arrowSpan = document.createElement('span');
                    arrowSpan.className = 'np-custom-select-arrow';
                    arrowSpan.style.cssText = 'position: absolute !important; right: 12px !important; top: 50% !important; transform: translateY(-50%) !important; display: flex !important; align-items: center !important; transition: transform 0.2s ease !important; pointer-events: none !important;';
                    arrowSpan.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#C268F2" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"></polyline></svg>';

                    trigger.appendChild(labelSpan);
                    trigger.appendChild(arrowSpan);
                    container.appendChild(trigger);

                    // Dropdown menu
                    const menu = document.createElement('div');
                    menu.className = 'np-custom-select-menu';
                    menu.style.cssText = 'display: none !important; position: absolute !important; top: calc(100% + 4px) !important; left: 0 !important; width: 100% !important; max-height: 240px !important; overflow-y: auto !important; background: #120e24 !important; border: 1.5px solid #C268F2 !important; border-radius: 10px !important; box-shadow: 0 14px 40px rgba(0, 0, 0, 0.9), 0 0 20px rgba(194, 104, 242, 0.3) !important; z-index: 999999 !important; padding: 4px 0 !important; box-sizing: border-box !important;';

                    function syncOptions() {
                        menu.innerHTML = '';
                        const opts = Array.from(select.options);
                        if (opts.length > 0 && select.selectedIndex < 0) {
                            select.selectedIndex = 0;
                        }
                        const selOpt = select.options[select.selectedIndex];
                        labelSpan.textContent = selOpt ? selOpt.text : (opts[0] ? opts[0].text : 'Select...');

                        opts.forEach((opt, idx) => {
                            const item = document.createElement('div');
                            const isSelected = idx === select.selectedIndex;
                            item.className = 'np-custom-select-item';
                            item.style.cssText = `padding: 10px 14px !important; font-size: 0.9rem !important; cursor: pointer !important; color: ${isSelected ? '#ffffff' : '#dcc7f5'} !important; background: ${isSelected ? 'linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%)' : 'transparent'} !important; font-weight: ${isSelected ? '700' : '500'} !important; display: flex !important; align-items: center !important; justify-content: space-between !important; transition: all 0.15s ease !important;`;

                            item.innerHTML = `<span>${opt.text}</span>` + (isSelected ? '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>' : '');

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
                                select.dispatchEvent(new Event('change', { bubbles: true }));
                                select.dispatchEvent(new Event('input', { bubbles: true }));
                                closeSelect();
                                syncOptions();
                            };

                            menu.appendChild(item);
                        });
                    }

                    // Dynamically sync options if select elements or text changes
                    const optObserver = new MutationObserver(() => syncOptions());
                    optObserver.observe(select, { childList: true, subtree: true, characterData: true });

                    function openSelect() {
                        document.querySelectorAll('.np-custom-select-menu').forEach(m => m.style.display = 'none');
                        document.querySelectorAll('.np-custom-select-arrow').forEach(a => a.style.transform = 'translateY(-50%) rotate(0deg)');
                        document.querySelectorAll('.np-custom-select-trigger').forEach(t => {
                            t.style.borderColor = 'rgba(194, 104, 242, 0.4)';
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
                        trigger.style.borderColor = 'rgba(194, 104, 242, 0.4)';
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

            document.addEventListener('click', function() {
                document.querySelectorAll('.np-custom-select-menu').forEach(m => m.style.display = 'none');
                document.querySelectorAll('.np-custom-select-arrow').forEach(a => a.style.transform = 'translateY(-50%) rotate(0deg)');
                document.querySelectorAll('.np-custom-select-trigger').forEach(t => {
                    t.style.borderColor = 'rgba(194, 104, 242, 0.4)';
                    t.style.boxShadow = 'none';
                });
            });

            // SPA Navigation Interceptors (React Router history.pushState & history.replaceState)
            const _historyPush = history.pushState;
            history.pushState = function() {
                const res = _historyPush.apply(this, arguments);
                window.dispatchEvent(new Event('np:locationchange'));
                return res;
            };
            const _historyReplace = history.replaceState;
            history.replaceState = function() {
                const res = _historyReplace.apply(this, arguments);
                window.dispatchEvent(new Event('np:locationchange'));
                return res;
            };

            function onNavigate() {
                injectDomainManager();
                initCustomSelects();
            }

            window.addEventListener('popstate', onNavigate);
            window.addEventListener('np:locationchange', onNavigate);

            // Interval safety net for fast route rendering
            setInterval(onNavigate, 250);

            // MutationObserver on document body to catch instant tab switches without refresh
            const bodyObserver = new MutationObserver(() => {
                onNavigate();
            });
            bodyObserver.observe(document.body, { childList: true, subtree: true });
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
