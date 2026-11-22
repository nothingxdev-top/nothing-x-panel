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
png_b64 = "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAATVUlEQVR4nIVaC6xlVXn+/7X23ud1X8yDGWbmDgwOA5Wxo1JaITYNUGwNA0oRW4g0obWYVNuitJpAkyZaaQqa2IeEojYNUGpoakPQkhIDDozGVBFKKyCvgWGGedzX3HvPc6/H36znXvvcO3Xfk3P33mfvtf7H9z/Xwo0AgAgAQOAPtOf2XjyQkp/MfwI0V8lT/jdmz5i9Fc/deAjAw00E5EDuMQTMgbj9tQBkAAVCAZSZS/P8BOIkz5qddlOpTr/XAWgAdDqthpCZGToO7w5Ha+QnubJsECASoeGh9qyhJlLsPo6tQHHFlRtJG8mZt7gdAOuS0GFkBsgRNZAZQQoiMzlpKkdCF3kWCTR/cQhDIlkRG3KBnNgdp45yAELz5+eAMFBFa9RZPJiVbpAVMa9XMwZainmUl5/Jk6bA0COEyPNclEIAZQxUKcBqyQvVPR+xY25UoPJkuAndM142VoSUkOtOdBjH/eSIJiArdWBmYsws3em7XoFoHhgDsEbQUqmiUHkmS6ERNRIJmRm6jYjJUBwFVknPod1JPAA2YN2RroMI4ydVRUSUwz1zSEhYzSwz7so+YMh1EtPhGQWgyRCpgLRRQjlCRkCcICMzInp5R/ONw9tLsjx4Ow6W5yZwLAbWqrfTT3w+4c3rFz2VBgk8KNqQmjzsHtAAijQpJRsNVpZYCsUZN7rygIzQqc0WsBNUgh6mqd7j4Yyh7r2qse3Hid+PGpXjqFTWkFoIfNy/gXTjEBjwaNLNluR8pPWAvA2sf0Q1RDbMTM62g9TdU5H9yNUYohxviY+quSwMJ8qOXdgxdKJqRZZDJK20LEvWKPTERDYaotKBgcSHRjxWbjKaQ8CVNRjHQ80D6oTQ+GJgw7xiHZFnfoztcIsEQNNoAw3i7WgaqLQY5khMSJlnPOPAWsYUI+5SuzcuiSon5+cwjrWaqv6GPyzpZsg1H+d8DPSxHtRYwnCwIkM6N2wYElxMkNbNayJNWg5HshQlUVlBKAFEFI6Lcc7cyLxvTT24CEioSVHnBBzvp6bsApYLCKnpYw2rfjwBlJsIjaU1cQk0cOjQOiPKlHZuMxtTpPPMfsTgl5xIDQ9B5s61Ome/1oFG5cRMwQWBZKrKEUPwniH2WYdjObR6wAaiCb8ApQnC0GJWDww4GTuxqUSUXpg5kYdzoamSKqM1/8ZUl/icenrl413EjMt8MOCHG/9WWS0LEC2BmlYPMuihp6GFqLV2syReKPW9zgCiQgMhnJmIoY0kzPipj1+bQKVsJL7AvGW9vgFSbv2yIZ2qyFglK/YzJGpYLAtrGGSxZJ63QSAbzzyDAI3kQ3oUVbCkTezKbTJYIGacGZsyOq/ejplFaprRYGKKarEBGVEDIUfMGBaIOSIn6mrdJ+OLHES11UMDcWjpsSK3U1rishT90YLTFMXdVQATWfbpvXuPNJuvLC29OT83P7+wKlULoMmQrE7X5kIxq3O5jQNSZvjHBlAB0OZsE2PncDZLdCbBJOJUkX+nFE+Wxm2qoAwFRuQF4NBCy2HPUWsYsJKJ+XI4wYojTZAhHBNi5uiR2/e9qze7fXHzlv/N86cXFp788TMvv/gCAk1wprXHlRvOufCoAZuzmPkKxCZQG9kuzt6L+B6ibUJN5Bk0ClB6WcNhKwxljNhrDABHQB07UtSMh8sGh/QYtsaS0uCOEGkEkBM8NT153kQbpqcbW7fBBe/s7dnzxGj09Ucf/f7Bg20Axqo8PLp5bpJW4+8KG6HaAOdk/IMIlxBsZhwY062myrgiakj1QK/3sFQ2hbZpop3a6S23Q/VCFPd63pD69uD1HQ9GZv6+wRwiLhLd2Grez7OlZl6cMZO1241Wh7/zQn3llf/4+qEvfv7zcjTKGdNkXEScxtZZZvqm/X4HZ59DtqfIdacj7JSs1STEYqX74nD4heHoFGlBBj9VdYFGHGhtb+QQFaPehsRvBH8NaRETix0zImKf6JGpyStGZZeo0WqwDWfA1FQ+dUZ+ww0Hp6c//olb+v2BCVg2bEc2Mgv6FkAH8e4825fnPa1Ra1QaMo6tJms2YTC4Y7X3rDIJkQghx8HP+1xbJ3BA44V8imFSCV/KBIu1l554U4PFX6PT/EJv0G81VZ6Z4uito3jsuD610L/3nvcfPfKlL94ptEbGxtJV55SWAD7K+T5kp0alGozUsBRCycFIdPtFWX5nWB6USltLtfgxELLf5lLabEIQGkOzllDam8xEtUCvi1Hejm1VGYOvLyyIJhB/qOT9ZTnNWT/PdFHIbo8WFnIxGtx3736gj1z74VWpODd5t9Obw+Qq4Syy30acRxjm2bDVHLVaslnILMtKMT8Yfq0sNRqPqVwFY0m33yZ+KSBpPoZ0tCbubhqZ2szN0U7rRCTLQkwWlG0c3DUoDyGgVkNNQkoxt6AXFjlpfd+9t15y6caZaalN8ZjGtQHQxzOOCCe17GnZRz3kMOKsLPJWnv+TVK8pzQx4rLDtx1Hv+IkslYYrw2Tl6ILIk5iTVADjNStRgfg20V1D0QTdz0DkmSIQJxf04ikxP/eOJ797029+sKcp8x7AwLcPdAnDy5Fe0Kqv9arSvbLslaMeqQzop5w9IGRhxG/ojhR75AQ1Rn5cduMe8KmAxb0tj8OsRt5jR1Ly5YAPjtSPJDVE2Qcq81wzppaWSSj9/advKbLd27aNQsJoW0BwM2NvIc4hdgG7QCuIfYChEJzjvUotas0tMLSJXw76qeANcuKlsqjwDLhkPXapXJaTyj9JNk0zyHh0ohZqAfRX0vzeF2WZYdkojNsejiTQ5scf+9S795UhaVsFupyx2QyfBepmfLHIVxgfaBrYoPbDkfi2VJNYgcTi2wkerR1XVUHkygWBGCsd3aRtQKjissVW0i3yF+6BFtIBqR7BrI3QK0ejjIlWQw2GVLTkyvL1Rw//yuyOUhNDnAT8SMb+S9OpUnZHZbcUK3nWzfO+piHgNzQNyThH14OInQgrY8OMpaHSifsOrbHQJnMKcH6zojUW1yErikCylSs1QP9tKRdZ1tW6W466HEZ5LheXZXui8fqrt050eJb1ifZzphFfareHzeYyQE/rQX+4QrrM8ycAD0j1nozPIJrw603OU0E1X+S1YZ2Sb+doMN0VrAJxTP5ji2UszfambOsPoimkV7V6UBEwflKplXK0nIHxrSu9EeOXLc79Rqc9Q/BrGX+KQA5Hg0aj35lYZXyZ4Smhjiv1gNTvYnhdns0TcRt1HAWRB5eNSut5or+xTPpLk04Huw09q7Hu1Nhh77Awx0aE+4V8X7OY4kwKOSrLMssAWatXktAnS/GBjP+M6JCQM6ah2W80CtHp9JVsAj49KkstvtrIvyp1l2gGUdZLkqTLTCm6nN93ztRE4vj4WJc6FhbrHgggiM5iTAI8KCQgzmXZAs8WlDpBejWDrwnxM6U3MXZQCAm0QnpZyaV+f6HXO1WKF/qDE1Le32oi4relnEKXPEcUVR7c4cdRHE3ZMUOmP7m+iJPMtN4AqQpw+zml9WUZ/08hL2W4Q6sTnK/ybInodYD7lL6As+ekXDYWb4ArjLFCpmlRiFar+ZVNG969uvKJ3lBYEEd4pLREJajQj7GgqgrdzGZdoQ8dyE0S0oSHNbAqAE+QSdEuzrNvSPWnzeKUppZWk4gHJPUtxcfIBI0+mY5Qg6HUekXri8/c/Nmztux4++iPhHxcygnDno/3qfXF6ts5P13vPTqDtg2O8B6haQI7Nql+EksVSu5ogDbid4W6rtlYQnZAapHnbxeNVzg/qPQMwDGtS5MAU4lYIhxTehnZjb+49693nb310CF1avXvhRy4hk8CjDpIvOu0RLuGhSPdmLXpSqxdjkmbvKFZFkyp3mwgs44CJ4F+ItXtmzbcfmLubDI51k8Ae0QTgAMw9a4CHGotAS7ZufNTu8+9+Njb/Rd+yjR+L+OPCTFp0eXiUYqfsfNYqztcWauwSjMFTQTGmpWlGh7H1mysL3CaWSb6j11n373SPbmwcEWzeHAkOtbBMUSpTVjdu3377+4575p+v3jppdXlFQ7QKLJrCJ4RcsoSlTKQdpmjWaedMrsuYTpfxgYqYY95nLXd56AB33KMvRY7/ZdOzn/lgvN+vdt9tBReT4hdTds2bvyjSy+9ejiYfP75pYX5Ms95s7m1LO8HeFqqLTaDYKeXfdqwSftiVcdpi/Vf9QTIPpKUOXFhJsrEdRl80LFPzhP9+/l7eu32zc8+t52ZeDTU+sJdu+751ffPfu/A3OHDo5xlzQbjrFNqpdQVQh7XerJqEieqrotuXbVktmpzyzk2SU7BnfR0PTNhBSYuc5goFrTmgmcb4HNvHr5ucuKjs7OrmpBocnLy7l+6aOJb//bi4cPLDS6A5GAgpZpB+BtNL2ttGmxVZF3X/VemPJYpuZhgsBffjJY6rrngjSNmok+KeZ8mU+y+PBx++Y03/273uZsnOgtEV23dMvODg691+7qZlQACmWRshuDHSv+DlDNWMsxP4pOIhFZzmTKQsmdKqZiNxiYRnU5b1apk9KSmk+Xbtz7hM/KYBrz76Nur83N3zu4YMLZ7YeGtpcVBwQZSmXUVIs5ZzthfCtklykMCQHX8BElHlEfGfPpp24C+ZWQ0EGocX8/XYFjn3Y/kah+rgyg2p78CYUWpP3n9zWuXlz7UbBzv9VYAVxqNLmelzY03Ejws1GNKb7IJjFu5cD4+VrTJ5A4k8X5szdewhGehKUNjJ9BjKfGSKUu+dvZZd62xDWbt2RjGMuBDzXynlt8i3CulyvhUkU8NR5sYNoBdLfQ86TZWy/Rjx+k8uZvf9cvQ5Ke+Fxf6wXHtqOotBrUkY4d2RRgzdsFcP84Ol5O+QyhEtgfhLc5XleorNeB8I+BdBIeJOr77sb6x0prLxBg9RRY/wYj90mxwnT4tStvV9cWWGmRNhuPTCmsXZtQJxENS3S70ZoCZIpdZzoXaztjXNT4k1EbT3vH+YozE1HGsZSmu6toTbxWGqK02C6/ypiSN8+nDGgfl+rSJ9fnFp5h1mSyVYDfDyznbzrDQdEDT40pP2taaWx2rNcDtMbYmEm+mYditBjjefKV+lnHGdiXZ7XyIb4Zlslp+iMAYI60Rzbe5EVYJTT0NxJlRp9I6Q+xpPQJsc2aWhhAnTc/Z5KSFZd4Vu+iWO21GjMzuGKjv2kgP1yKI/sfDYpuJxKaZ4RxBrSKKp8k60oCojTiwWTQilHYFF2zjFhBG9rJt7zfRrO/2AVphEZvZO64Sd25U2FkKNCfC9m4jJteWg1H88TA2YLsUpiz2SolBJRnAXRJBo9G4+XduEEQ3XX/9xpnpAcG1V1110YUX3njtb81MT68SfHj//qsvu2yq3fnAZZeZRcU8+72PfezW2267+aabGllWEly6Y/v7tm7dP7tj2+TkKsF79+375YsuWiHYtHHjZz/zmT/45CfPOfdcs7ZhDHMcY0mUqH4yaktp9QXAWv0RZJwvDIdZlv3FrbfOTE0fW1ltcP6DZ575s0/fNuz3F1ZWEODsHTv2X/OhP7zllj27z+sBzJ617Rf2nP/le+45f/d527duIYDnT578452zWxk/vNolgJ07z96169wBQLPdmtq0eWpqeseZZ6pqJdeL2a3K+HgVbnpcGXuPMSP5odazdqNos6D0zW/+y6Smh//5QabNMv8bx48/8tADB59+Cq1HOvTsc3f++R1H3nhj7tDrOcCJubmjz//371955ZH/ef7Y/IIG2NuZ+NdXXumKcmurpQGOHzp05LVXC4DFufkXnnwiO3FisihiKhE6QkYdsSmU8mBQswXtXZtSpgWcL/3HijxrZiMHVtO+dlujNDPtGRsM7cN9onZAPAOYmegsd3uul58jrmjdAGhwVmodow1jrNNoKCFXhcj9ziqbZYUFWesqMU2fvIffYlNCvy8r5tCVIsJXDHC2grabd1yS5/UdLh01fs3P7cmS5Bu9TtOhCecDDIWpDHIAMrNIVUveE88TN2HFHSaIZ/qdBImvx7FV+3qN6beZpRu6gqmH3oIv+5J/KUFjyQLWlnPHrS8LQW2sPLCi8amEk6uJo+kTMSzVs1MrOJeLVsbunJgP9v718M9lT3XJ1A6q8uA0NJqDh9R6bXETY4UpKf0PIRccqxjD72mNWllHqDIjxyHpsyuEVc8mYWosbac1JxE5wY7HGUuhbfZKVOJZi4v4Y6IQl/kEO7IntQIzzhD6nONjrUM01p+z1JtkO31lLLQ5xrLTDjx2VIzalMMnQ84T+RfHFhaipmvTJ/sgxgaOhXhcWUvpOl2abVfq3evVBqz6q+tw4suCan/hOgB2A0a81cb1yTdW87h/aUc8/Wntlrb4QISQcwYR0Guor0MonIXS3u169CK0DjkSnRpTFNVYtwZqJWA64c9tlvu+UM3rrBXCutvLKmU4mj0NMaOu54MJIWOC/3mYXZtgpwers5gW2WF5bH2zrs9UvRQ3ytZfS8ZZd4dX7RiT4Gl+pLoGvCiTYuz/XR1IBkySpmQnVx29ftOGvTMuWorxrpo5fp+u0xnvV17ImVDSUU9a67X663RDBbLTmBTE4R10JSArrhiQwlXCnn8h2QpUzZei+/8AvUU+k/OotK0AAAAASUVORK5CYII="

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

    # Fix StartupContainer layout in JS bundles: make Startup Command & Docker Image flex column
    for old_grid in ['grid-cols-1 md:grid-cols-4 gap-4', 'grid-cols-1 md:grid-cols-4 gap-x-8 gap-y-4', 'grid-cols-1 md:grid-cols-4']:
        if old_grid in content:
            content = content.replace(old_grid, 'flex flex-col gap-6')
            changed = True

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

# 4. Inject Modern Custom Theme into wrapper.blade.php
SERVER_IP=$(curl -4 -fsSL https://api.ipify.org 2>/dev/null || curl -4 -fsSL https://ifconfig.me 2>/dev/null || curl -4 -fsSL https://icanhazip.com 2>/dev/null || echo "213.136.89.90")
export SERVER_IP
WRAPPER="$PANEL_DIR/resources/views/templates/wrapper.blade.php"
if [ -f "$WRAPPER" ]; then
  sed -i "s@config('app.name', 'Pterodactyl')@config('app.name', 'Nothing Panel')@g" "$WRAPPER"
  sed -i "s@color=\"#bc6e3c\"@color=\"#C268F2\"@g" "$WRAPPER" 2>/dev/null || true

  python3 - << 'PYEOF'
import os, re

panel_dir = os.environ.get('PANEL_DIR', '/var/www/nothing')
server_ip = os.environ.get('SERVER_IP', '213.136.89.90')
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
            img[src*="svgs/"],
            img[src*="/assets/svgs"],
            div[class*="LoginFormContainer"] img,
            div[class*="sc-cyh04c"] img,
            div.sc-cyh04c-0 img,
            div.sc-cyh04c-3 img,
            div.sc-cyh04c-6 img,
            p[class*="LoginFormContainer___StyledP"],
            a[href*="pterodactyl"] {
                display: none !important;
                visibility: hidden !important;
                height: 0 !important;
                width: 0 !important;
                opacity: 0 !important;
                pointer-events: none !important;
            }
            /* ========================================================= */
            /* LOGIN CARD: CLEAN SINGLE OBSIDIAN CARD (NO NESTED BOXES)  */
            /* ========================================================= */
            div.sc-cyh04c-0,
            div[class*="LoginFormContainer__Container"] {
                background: transparent !important;
                border: none !important;
                box-shadow: none !important;
                width: 100% !important;
            }
            div[class*="LoginFormContainer"] form,
            div.sc-cyh04c-6,
            div[class*="LoginFormContainer___StyledDiv3"] {
                background: transparent !important;
                border: none !important;
                box-shadow: none !important;
                padding: 0 !important;
                margin: 0 !important;
                width: 100% !important;
            }
            div[class*="LoginFormContainer"] form::before,
            div.sc-cyh04c-0::before,
            div.sc-cyh04c-6::before {
                content: none !important;
                display: none !important;
            }
            div.sc-cyh04c-3,
            div[class*="LoginFormContainer___StyledDiv"]:not([class*="StyledDiv2"]):not([class*="StyledDiv3"]) {
                max-width: 440px !important;
                margin: 4rem auto 2rem auto !important;
                background-color: #120e22 !important;
                background: #120e22 !important;
                border: 1.5px solid rgba(194, 104, 242, 0.45) !important;
                box-shadow: 0 25px 70px rgba(0, 0, 0, 0.85), 0 0 35px rgba(194, 104, 242, 0.25) !important;
                border-radius: 16px !important;
                padding: 2.5rem 2rem !important;
                display: block !important;
                box-sizing: border-box !important;
            }
            /* BRAND LOGO ONLY ONCE ON LOGIN CARD */
            /* Circular Glowing Logo on /auth/login */
            div.sc-cyh04c-3::before,
            div[class*="LoginFormContainer___StyledDiv"]:not([class*="StyledDiv2"]):not([class*="StyledDiv3"])::before {
                content: "" !important;
                display: block !important;
                width: 88px !important;
                height: 88px !important;
                margin: 0 auto 1.75rem auto !important;
                background-image: url("/assets/logo.png") !important;
                background-size: cover !important;
                background-repeat: no-repeat !important;
                background-position: center center !important;
                border-radius: 50% !important;
                border: 2.5px solid #C268F2 !important;
                box-shadow: 0 0 25px rgba(194, 104, 242, 0.75), inset 0 0 12px rgba(194, 104, 242, 0.35) !important;
                overflow: hidden !important;
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
            /* Inputs & Textareas — Sleek Obsidian Dark Background (Excluding Checkboxes & Radios) */
            input:not([type="checkbox"]):not([type="radio"]):not([type="submit"]):not([type="button"]):not([type="range"]),
            input[type="text"],
            input[type="password"],
            input[type="email"],
            input[type="number"],
            input[type="search"],
            textarea {
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
            /* Startup VariableBox inputs — force dark bg to override styled-components */
            div[class*="VariableBox"] input[type="text"],
            div[class*="VariableBox"] input:not([type="checkbox"]):not([type="radio"]),
            div[class*="VariableBox"] textarea,
            div[class*="StartupContainer"] input[type="text"],
            div[class*="StartupContainer"] input:not([type="checkbox"]):not([type="radio"]),
            div[class*="StartupContainer"] textarea,
            div[class*="SettingsContainer"] input[type="text"],
            div[class*="SettingsContainer"] input:not([type="checkbox"]):not([type="radio"]),
            div[class*="TitledGreyBox"] input[type="text"],
            div[class*="TitledGreyBox"] input:not([type="checkbox"]):not([type="radio"]),
            div[class*="TitledGreyBox"] textarea {
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
            input:not([type="checkbox"]):not([type="radio"]):focus,
            input[type="text"]:focus,
            input[type="password"]:focus,
            input[type="email"]:focus,
            textarea:focus,
            input[class*="sc-19rce1w"]:not([type="checkbox"]):not([type="radio"]):focus,
            div[class*="VariableBox"] input:not([type="checkbox"]):focus,
            div[class*="StartupContainer"] input:not([type="checkbox"]):focus,
            div[class*="SettingsContainer"] input:not([type="checkbox"]):focus {
                border-color: #C268F2 !important;
                box-shadow: 0 0 16px rgba(194, 104, 242, 0.5) !important;
                background-color: #0e0920 !important;
                background: #0e0920 !important;
                color: #ffffff !important;
                outline: none !important;
            }
            /* ========================================================= */
            /* SWITCH / TOGGLE COMPONENT RESET (REMOVES FLOATING CIRCLE) */
            /* ========================================================= */
            div[class*="Switch"] input[type="checkbox"],
            div[class*="sc-1nxt82m"] input[type="checkbox"],
            div[class*="Toggle"] input[type="checkbox"],
            div[class*="ToggleContainer"] input[type="checkbox"],
            [role="switch"] input {
                display: none !important;
                position: absolute !important;
                opacity: 0 !important;
                width: 0 !important;
                height: 0 !important;
                min-width: 0 !important;
                max-width: 0 !important;
                min-height: 0 !important;
                max-height: 0 !important;
                pointer-events: none !important;
                border: none !important;
                background: transparent !important;
                box-shadow: none !important;
                margin: 0 !important;
                padding: 0 !important;
                visibility: hidden !important;
            }
            /* Switch Track */
            div[class*="Switch__ToggleContainer"],
            div[class*="sc-1nxt82m-0"],
            div[class*="sc-1nxt82m-1"] {
                width: 3.4rem !important;
                height: 1.85rem !important;
                position: relative !important;
                display: inline-block !important;
                user-select: none !important;
            }
            div[class*="Switch__ToggleContainer"] > label,
            div[class*="sc-1nxt82m-0"] > label,
            div[class*="sc-1nxt82m-1"] > label {
                display: block !important;
                width: 100% !important;
                height: 100% !important;
                border-radius: 9999px !important;
                background-color: #1a1330 !important;
                background: #1a1330 !important;
                border: 1.5px solid rgba(194, 104, 242, 0.4) !important;
                position: relative !important;
                cursor: pointer !important;
                transition: all 0.2s ease !important;
                box-sizing: border-box !important;
                margin: 0 !important;
            }
            /* Switch Thumb Knob */
            div[class*="Switch__ToggleContainer"] > label::before,
            div[class*="sc-1nxt82m-0"] > label::before,
            div[class*="sc-1nxt82m-1"] > label::before {
                content: "" !important;
                position: absolute !important;
                top: 2px !important;
                left: 3px !important;
                right: auto !important;
                width: 1.35rem !important;
                height: 1.35rem !important;
                border-radius: 50% !important;
                background: #ffffff !important;
                box-shadow: 0 2px 6px rgba(0, 0, 0, 0.5) !important;
                transition: transform 0.2s cubic-bezier(0.4, 0, 0.2, 1) !important;
            }
            /* Switch Track Checked */
            div[class*="Switch__ToggleContainer"] > input:checked + label,
            div[class*="sc-1nxt82m-0"] > input:checked + label,
            div[class*="sc-1nxt82m-1"] > input:checked + label,
            label.np-toggle-active {
                background: linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%) !important;
                background-color: #C268F2 !important;
                border-color: #C268F2 !important;
                box-shadow: 0 0 14px rgba(194, 104, 242, 0.6) !important;
            }
            /* Switch Thumb Knob Checked */
            div[class*="Switch__ToggleContainer"] > input:checked + label::before,
            div[class*="sc-1nxt82m-0"] > input:checked + label::before,
            div[class*="sc-1nxt82m-1"] > input:checked + label::before,
            label.np-toggle-active::before {
                transform: translateX(1.5rem) !important;
                left: 3px !important;
                right: auto !important;
                background: #ffffff !important;
            }
            /* ========================================================= */
            /* ALL CHECKBOXES: SOLID VISIBLE UNCHECKED & PURPLE CHECKED  */
            /* ========================================================= */
            input[type="checkbox"]:not([role="switch"]):not([id*="switch"]):not([name*="UPLOAD"]):not([name*="UPDATE"]) {
                appearance: none !important;
                -webkit-appearance: none !important;
                -moz-appearance: none !important;
                width: 20px !important;
                height: 20px !important;
                min-width: 20px !important;
                max-width: 20px !important;
                min-height: 20px !important;
                max-height: 20px !important;
                padding: 0 !important;
                margin: 0 !important;
                border-radius: 5px !important;
                border: 1.5px solid #5d447a !important;
                background-color: #0b0717 !important;
                background-image: none !important;
                cursor: pointer !important;
                display: inline-flex !important;
                align-items: center !important;
                justify-content: center !important;
                vertical-align: middle !important;
                box-sizing: border-box !important;
                outline: none !important;
                transition: border-color 0.15s ease, background-color 0.15s ease, box-shadow 0.15s ease !important;
            }
            input[type="checkbox"]:not([role="switch"]):not([id*="switch"]):not([name*="UPLOAD"]):not([name*="UPDATE"]):hover {
                border-color: #C268F2 !important;
                box-shadow: 0 0 8px rgba(194, 104, 242, 0.4) !important;
            }
            input[type="checkbox"]:not([role="switch"]):not([id*="switch"]):not([name*="UPLOAD"]):not([name*="UPDATE"]):checked,
            input[type="checkbox"][name="selectedFiles"]:checked {
                background-color: #C268F2 !important;
                background: #C268F2 url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20' fill='none' stroke='white' stroke-width='3' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpolyline points='4 11 8 15 16 6'/%3E%3C/svg%3E") no-repeat center center / 14px 14px !important;
                border: 1.5px solid #ffffff !important;
                border-color: #ffffff !important;
                background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20' fill='none' stroke='white' stroke-width='3' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpolyline points='4 11 8 15 16 6'/%3E%3C/svg%3E") !important;
                background-size: 14px 14px !important;
                background-position: center center !important;
                background-repeat: no-repeat !important;
                box-shadow: 0 0 12px rgba(194, 104, 242, 0.75) !important;
            }
            input[type="checkbox"]:not([role="switch"]):not([id*="switch"]):not([name*="UPLOAD"]):not([name*="UPDATE"]):indeterminate,
            input[class*="FileActionCheckbox"]:indeterminate {
                background-color: #C268F2 !important;
                border: 1.5px solid #ffffff !important;
                border-color: #ffffff !important;
                background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20' fill='none' stroke='white' stroke-width='3' stroke-linecap='round' stroke-linejoin='round'%3E%3Crect x='3' y='8' width='14' height='4' rx='2' fill='white'/%3E%3C/svg%3E") !important;
                background-size: 14px 14px !important;
                background-position: center center !important;
                background-repeat: no-repeat !important;
                box-shadow: 0 0 12px rgba(194, 104, 242, 0.75) !important;
            }
            label[class*="SelectFileCheckbox___StyledLabel"],
            label[class*="sc-1cv6gsl-1"],
            div[class*="file_row"] label {
                display: flex !important;
                align-items: center !important;
                justify-content: center !important;
                width: 36px !important;
                min-width: 36px !important;
                max-width: 36px !important;
                padding: 0 6px !important;
                flex: none !important;
                box-sizing: border-box !important;
            }
            /* File Manager Row Sizing & Sleek Hover */
            div[class*="file_row"],
            div[class*="style-module_HHpjDvv7"] {
                display: flex !important;
                align-items: center !important;
                padding: 0.55rem 0.85rem !important;
                border-radius: 8px !important;
                background: #120e24 !important;
                border: 1px solid rgba(194, 104, 242, 0.12) !important;
                margin-bottom: 4px !important;
                transition: all 0.18s ease !important;
            }
            div[class*="file_row"]:hover,
            div[class*="style-module_HHpjDvv7"]:hover {
                background: rgba(194, 104, 242, 0.1) !important;
                border-color: rgba(194, 104, 242, 0.4) !important;
            }
            div[class*="file_row"] svg,
            div[class*="style-module_HHpjDvv7"] svg {
                color: #C268F2 !important;
                flex-shrink: 0 !important;
            }
            @keyframes npFadeIn {
                from { opacity: 0; transform: scale(0.97); }
                to { opacity: 1; transform: scale(1); }
            }
            @keyframes npSpin {
                from { transform: rotate(0deg); }
                to { transform: rotate(360deg); }
            }
            /* PRIMARY CTA & ACTION BUTTONS (#C268F2 GRADIENT) */
            button[type="submit"],
            .btn-primary,
            button.primary,
            button[class*="primary"],
            button[class*="Primary"],
            button[class*="bg-primary"],
            button[class*="bg-blue"],
            .np-btn-purple,
            div[class*="FileManagerContainer"] button:not([class*="secondary"]):not([class*="p-"]):not([class*="danger"]),
            div[class*="FileManagerContainer"] a > button,
            div[class*="flex"] > a > button,
            div[class*="Modal"] button[type="submit"],
            button[class*="Button"]:not([class*="secondary"]):not([class*="danger"]):not([class*="text"]):not([class*="p-"]):not([class*="p-1"]):not([class*="p-2"]):not([aria-haspopup="true"]) {
                background: linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%) !important;
                background-color: #C268F2 !important;
                color: #ffffff !important;
                font-weight: 700 !important;
                letter-spacing: 0.5px !important;
                border-radius: 8px !important;
                box-shadow: 0 4px 16px rgba(194, 104, 242, 0.35) !important;
                transition: all 0.2s ease !important;
                text-transform: uppercase !important;
                border: none !important;
                padding: 0.75rem 1.4rem !important;
                cursor: pointer !important;
            }
            button[type="submit"]:hover,
            .btn-primary:hover,
            button.primary:hover,
            button[class*="bg-primary"]:hover,
            button[class*="bg-blue"]:hover,
            .np-btn-purple:hover,
            div[class*="FileManagerContainer"] button:not([class*="secondary"]):not([class*="p-"]):not([class*="danger"]):hover,
            div[class*="FileManagerContainer"] a > button:hover,
            button[class*="Button"]:not([class*="secondary"]):not([class*="danger"]):not([class*="text"]):not([class*="p-"]):not([class*="p-1"]):not([class*="p-2"]):hover {
                transform: translateY(-1px) !important;
                box-shadow: 0 6px 24px rgba(194, 104, 242, 0.6) !important;
                filter: brightness(1.08) !important;
            }

            /* SECONDARY BUTTONS: MINIMAL FLAT WITH SUBTLE OUTLINE */
            button[class*="secondary"],
            button.btn-default,
            button.btn-secondary,
            button[class*="Button___StyledButton"][class*="secondary"] {
                background: rgba(255, 255, 255, 0.05) !important;
                color: #d1b8eb !important;
                font-weight: 600 !important;
                border-radius: 8px !important;
                border: 1px solid rgba(194, 104, 242, 0.2) !important;
                box-shadow: none !important;
                padding: 0.65rem 1.25rem !important;
                cursor: pointer !important;
                transform: none !important;
            }
            button[class*="secondary"]:hover,
            button.btn-default:hover,
            button.btn-secondary:hover {
                background: rgba(194, 104, 242, 0.12) !important;
                color: #ffffff !important;
                border-color: #C268F2 !important;
                box-shadow: none !important;
                transform: none !important;
            }

            /* 3-DOTS ACTION BUTTON & ALL ICON-ONLY BUTTONS: STRICT ZERO OUTLINE & ZERO BORDER */
            div[class*="FileObjectRow"] button,
            div[class*="file_row"] button,
            div[class*="FileObjectRow"] div[class*="DropdownMenu"],
            div[class*="FileObjectRow"] div[class*="FileDropdownMenu"],
            div[class*="file_row"] div[class*="DropdownMenu"],
            div[class*="style-module_HHpjDvv7"] button,
            div[class*="style-module_HHpjDvv7"] div[class*="DropdownMenu"],
            button:has(svg[data-icon="ellipsis-h"]),
            button:has(svg.fa-ellipsis-h),
            button:has(svg[class*="ellipsis"]),
            button[class*="p-2"],
            button[class*="p-1"],
            button.p-2,
            button.p-1,
            div[class*="FileManager"] button:not([class*="bg-"]):not([type="submit"]):not([class*="btn"]):not([class*="primary"]):not([class*="Primary"]):not([class*="purple"]),
            div[class*="flex items-center"] > button:has(svg:only-child),
            button:has(svg:only-child):not([class*="bg-"]):not([type="submit"]):not([class*="primary"]) {
                background: transparent !important;
                background-color: transparent !important;
                border: none !important;
                border-width: 0 !important;
                border-color: transparent !important;
                outline: none !important;
                box-shadow: none !important;
                border-radius: 4px !important;
                padding: 4px 6px !important;
                min-width: 0 !important;
                max-width: none !important;
                width: auto !important;
                height: auto !important;
                color: #a394bf !important;
                margin: 0 !important;
                cursor: pointer !important;
                text-transform: none !important;
                letter-spacing: normal !important;
                transform: none !important;
            }
            button[class*="p-2"]:hover,
            button[class*="p-1"]:hover,
            button:has(svg:only-child):hover,
            button[aria-label]:hover,
            div[class*="file_row"] button:hover,
            div[class*="FileObjectRow"] button:hover,
            div[class*="style-module_HHpjDvv7"] button:hover,
            button.p-2:hover,
            button.p-1:hover {
                background: rgba(194, 104, 242, 0.12) !important;
                background-color: rgba(194, 104, 242, 0.12) !important;
                color: #C268F2 !important;
                border: none !important;
                outline: none !important;
                box-shadow: none !important;
                transform: none !important;
                filter: none !important;
            }
            button[class*="p-2"] svg,
            button[class*="p-1"] svg,
            div[class*="file_row"] button svg,
            div[class*="FileObjectRow"] button svg,
            div[class*="style-module_HHpjDvv7"] button svg {
                color: #a394bf !important;
                fill: currentColor !important;
            }
            button[class*="p-2"]:hover svg,
            button[class*="p-1"]:hover svg,
            div[class*="file_row"] button:hover svg,
            div[class*="FileObjectRow"] button:hover svg,
            div[class*="style-module_HHpjDvv7"] button:hover svg {
                color: #C268F2 !important;
                fill: currentColor !important;
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
            html, body, select, option {
                color-scheme: dark !important;
            }
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
            div[class*="ContentBox"] {
                background: transparent !important;
                border: none !important;
                box-shadow: none !important;
                padding: 0 !important;
            }

            /* THE ONE AND ONLY MAIN CARD: TitledGreyBox & Settings Cards */
            div.sc-gvsoy-0,
            div[class*="sc-gvsoy-0"],
            div[class*="sc-1bh2mfg-0"],
            div[class*="sc-1prmksw-1"],
            div[class*="sc-1e5ycmz-3"],
            div[class*="sc-1e5ycmz-10"],
            div[class*="TitledGreyBox"]:not([class*="StyledDiv2"]):not([class*="StyledDiv3"]) {
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
            div.sc-gvsoy-0:hover,
            div[class*="sc-gvsoy-0"]:hover,
            div[class*="sc-1bh2mfg-0"]:hover,
            div[class*="sc-1prmksw-1"]:hover,
            div[class*="sc-1e5ycmz-3"]:hover,
            div[class*="sc-1e5ycmz-10"]:hover {
                border-color: rgba(194, 104, 242, 0.45) !important;
                box-shadow: 0 6px 25px rgba(0, 0, 0, 0.55), 0 0 15px rgba(194, 104, 242, 0.15) !important;
            }

            /* REMOVE nested header box and borders inside TitledGreyBox */
            div[class*="TitledGreyBox___StyledDiv2"],
            div.sc-gvsoy-1,
            div[class*="sc-gvsoy-1"] {
                background: transparent !important;
                border: none !important;
                border-bottom: 1px solid rgba(194, 104, 242, 0.15) !important;
                border-radius: 0 !important;
                padding: 0 0 0.85rem 0 !important;
                margin-bottom: 1.25rem !important;
            }
            div[class*="TitledGreyBox___StyledDiv3"],
            div.sc-gvsoy-4,
            div[class*="sc-gvsoy-4"] {
                background: transparent !important;
                border: none !important;
                padding: 0 !important;
                box-shadow: none !important;
            }

            /* ========================================================= */
            /* SETTINGS PAGE: CLEAN 2-COLUMN BALANCED LAYOUT             */
            /* ========================================================= */
            /* Outer container: 2 equal-width columns on desktop, stacked on mobile */
            div.sc-1e5ycmz-1,
            div.SettingsContainer___StyledDiv-sc-1e5ycmz-1 {
                display: flex !important;
                flex-direction: row !important;
                gap: 1.75rem !important;
                width: 100% !important;
                align-items: flex-start !important;
            }
            @media (max-width: 900px) {
                div.sc-1e5ycmz-1,
                div.SettingsContainer___StyledDiv-sc-1e5ycmz-1 {
                    flex-direction: column !important;
                }
            }

            /* Left column (SFTP Details + Debug Information stacked vertically) */
            div.sc-1e5ycmz-2,
            div.SettingsContainer___StyledDiv2-sc-1e5ycmz-2 {
                flex: 1 1 50% !important;
                width: 50% !important;
                max-width: 50% !important;
                display: flex !important;
                flex-direction: column !important;
                gap: 1.5rem !important;
                margin: 0 !important;
                box-sizing: border-box !important;
            }

            /* Right column (Change Server Details + Reinstall Server stacked vertically) */
            div.sc-1e5ycmz-15,
            div.SettingsContainer___StyledDiv0-sc-1e5ycmz-15 {
                flex: 1 1 50% !important;
                width: 50% !important;
                max-width: 50% !important;
                display: flex !important;
                flex-direction: column !important;
                gap: 1.5rem !important;
                margin: 0 !important;
                box-sizing: border-box !important;
            }

            @media (max-width: 900px) {
                div.sc-1e5ycmz-2,
                div.SettingsContainer___StyledDiv2-sc-1e5ycmz-2,
                div.sc-1e5ycmz-15,
                div.SettingsContainer___StyledDiv0-sc-1e5ycmz-15 {
                    width: 100% !important;
                    max-width: 100% !important;
                }
            }

            /* Settings cards (SFTP Details, Debug Info, Change Details, Reinstall Server) */
            div.sc-gvsoy-0,
            div[class*="TitledGreyBox___StyledDiv"] {
                display: flex !important;
                flex-direction: column !important;
                background: #110d22 !important;
                background-color: #110d22 !important;
                border: 1px solid rgba(194, 104, 242, 0.22) !important;
                border-radius: 12px !important;
                padding: 1.5rem !important;
                margin: 0 0 1.5rem 0 !important;
                box-sizing: border-box !important;
                box-shadow: 0 4px 20px rgba(0, 0, 0, 0.4) !important;
                width: 100% !important;
                height: auto !important;
            }

            /* Card Header: stays on TOP, full width, with bottom border */
            div.sc-gvsoy-1,
            div[class*="TitledGreyBox___StyledDiv2"] {
                display: block !important;
                width: 100% !important;
                background: transparent !important;
                border: none !important;
                border-bottom: 1px solid rgba(194, 104, 242, 0.15) !important;
                border-radius: 0 !important;
                padding: 0 0 0.85rem 0 !important;
                margin-bottom: 1.25rem !important;
            }

            /* Card Body: stays BELOW header, full width */
            div.sc-gvsoy-4,
            div[class*="TitledGreyBox___StyledDiv3"] {
                display: flex !important;
                flex-direction: column !important;
                gap: 1rem !important;
                width: 100% !important;
                background: transparent !important;
                border: none !important;
                padding: 0 !important;
                box-shadow: none !important;
            }

            /* Inputs & Textareas inside settings cards: 100% width */
            div[class*="TitledGreyBox"] input[type="text"],
            div[class*="TitledGreyBox"] textarea,
            div.sc-gvsoy-4 input {
                width: 100% !important;
                box-sizing: border-box !important;
            }

            /* SFTP action row (note on left, button on right) */
            div.sc-1e5ycmz-5,
            div[class*="SettingsContainer___StyledDiv4"] {
                display: flex !important;
                flex-direction: row !important;
                align-items: center !important;
                justify-content: space-between !important;
                gap: 1rem !important;
                margin-top: 0.5rem !important;
            }

            /* Debug info rows (Node on left/badge on right, UUID on left/badge on right) */
            div.sc-1e5ycmz-11,
            div.sc-1e5ycmz-13,
            div[class*="SettingsContainer___StyledDiv8"],
            div[class*="SettingsContainer___StyledDiv9"] {
                display: flex !important;
                flex-direction: row !important;
                align-items: center !important;
                justify-content: space-between !important;
                padding: 0.5rem 0 !important;
                border-bottom: 1px solid rgba(194, 104, 242, 0.1) !important;
            }
            div.sc-1e5ycmz-13,
            div[class*="SettingsContainer___StyledDiv9"] {
                border-bottom: none !important;
            }

            /* Rename & Reinstall Server Forms */
            div[class*="RenameServerBox"] form,
            div[class*="ReinstallServerBox"] form,
            form[class*="RenameServerBox"] {
                display: flex !important;
                flex-direction: column !important;
                gap: 1rem !important;
                width: 100% !important;
            }

            /* REMOVE ALL decorative rectangular outlines & nested borders inside settings & forms */
            div[class*="SettingsContainer___StyledDiv"],
            div[class*="sc-1e5ycmz-4"],
            div[class*="sc-1e5ycmz-5"],
            div[class*="sc-1e5ycmz-6"],
            div[class*="sc-1e5ycmz-7"],
            div[class*="sc-1e5ycmz-8"],
            div[class*="sc-1e5ycmz-9"],
            div[class*="RenameServerBox___StyledDiv"],
            div[class*="RenameServerBox___StyledDiv2"],
            div[class*="sc-1bh2mfg-1"],
            div[class*="sc-1bh2mfg-2"],
            div[class*="sc-1bh2mfg-3"],
            div[class*="ReinstallServerBox___StyledDiv"],
            div[class*="sc-1prmksw-2"],
            div[class*="sc-1prmksw-3"],
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
                background-color: transparent !important;
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

            /* ========================================================= */
            /* STARTUP SETTINGS & COMMAND LAYOUT: WIDE TERMINAL CODE BOX */
            /* ========================================================= */
            div[class*="StartupContainer"] p,
            div[class*="VariableBox"] p,
            div[class*="TitledGreyBox"] p,
            div[class*="TitledGreyBox"] span,
            div[class*="TitledGreyBox"] code {
                opacity: 1 !important;
                visibility: visible !important;
            }

            /* FORCE STARTUP COMMAND & DOCKER IMAGE TO STACK VERTICALLY FULL WIDTH (100%) AT ALL SCREEN SIZES */
            div.grid.grid-cols-1.md\:grid-cols-4,
            div[class*="grid-cols-4"],
            div[class*="StartupContainer"] div[class*="grid-cols-4"],
            div:has(> div p.font-mono),
            div:has(> div > div p.font-mono),
            div:has(> div > div > div p.font-mono) {
                display: flex !important;
                flex-direction: column !important;
                grid-template-columns: 1fr !important;
                width: 100% !important;
                gap: 1.5rem !important;
            }

            div.grid.grid-cols-1.md\:grid-cols-4 > div,
            div[class*="grid-cols-4"] > div,
            div.col-span-3,
            div.col-span-1,
            div.md\:col-span-3,
            div.md\:col-span-1,
            div[class*="col-span-3"],
            div[class*="col-span-1"],
            div[class*="StartupContainer"] div[class*="md:col-span-1"],
            div[class*="StartupContainer"] div[class*="md:col-span-3"],
            div[class*="StartupContainer"] div[class*="col-span-1"],
            div[class*="StartupContainer"] div[class*="col-span-3"],
            div:has(> div p.font-mono) > div,
            div:has(> div > div p.font-mono) > div,
            div:has(> div > div > div p.font-mono) > div {
                grid-column: 1 / -1 !important;
                width: 100% !important;
                min-width: 100% !important;
                max-width: 100% !important;
                flex: 1 1 100% !important;
                box-sizing: border-box !important;
            }

            /* Startup Command Box: 100% Full Width Legible Terminal */
            div[class*="StartupContainer"] p[class*="font-mono"],
            div[class*="StartupContainer"] p.font-mono,
            div[class*="StartupContainer"] code,
            p[class*="StartupContainer___StyledP"] {
                width: 100% !important;
                min-width: 100% !important;
                max-width: 100% !important;
                box-sizing: border-box !important;
                display: block !important;
                white-space: pre-wrap !important;
                word-break: normal !important;
                overflow-wrap: break-word !important;
                word-wrap: break-word !important;
                font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace !important;
                font-size: 0.95rem !important;
                line-height: 1.6 !important;
                color: #38ef7d !important;
                background-color: #0b0717 !important;
                border: 1.5px solid rgba(194, 104, 242, 0.4) !important;
                border-radius: 10px !important;
                padding: 1.25rem 1.5rem !important;
                box-shadow: inset 0 2px 10px rgba(0, 0, 0, 0.7) !important;
            }

            /* Completely hide native selects once enhanced by custom select */
            select[data-np-select="true"],
            .np-custom-select-wrap select {
                display: none !important;
                opacity: 0 !important;
                pointer-events: none !important;
                width: 0 !important;
                height: 0 !important;
                position: absolute !important;
                visibility: hidden !important;
            }

            /* Startup settings select input (Docker Image selector) */
            div[class*="StartupContainer"] select,
            div[class*="StartupContainer"] div[class*="Select"],
            div[class*="StartupContainer"] input[type="text"],
            div[class*="StartupContainer"] input:not([type="checkbox"]):not([type="radio"]) {
                width: 100% !important;
                max-width: 100% !important;
                box-sizing: border-box !important;
            }

            /* Variable box description styling */
            p[class*="text-neutral-300"],
            div[class*="VariableBox"] p {
                color: #c9b6e3 !important;
                font-size: 0.85rem !important;
                margin-top: 0.4rem !important;
                display: block !important;
                line-height: 1.5 !important;
            }

            /* Variables section heading & grid */
            div[class*="StartupContainer"] h3 {
                color: #ffffff !important;
                font-weight: 700 !important;
                margin-top: 2rem !important;
                margin-bottom: 1rem !important;
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
            /* 2b. CONTEXT MENUS & ACTION DROPDOWNS (READABLE WHITE TEXT)*/
            /* ========================================================= */
            nav.react-contextmenu,
            .react-contextmenu,
            div.react-contextmenu,
            div[role="menu"],
            ul[role="menu"],
            div[class*="ContextMenu"]:not([class*="Row"]):not([class*="Container"]),
            div[class*="Menu___Styled"],
            div[class*="DropdownMenu__Menu"],
            div[class*="dropdown-menu"]:not([class*="btn"]):not([class*="toggle"]) {
                background-color: #120e24 !important;
                background: #120e24 !important;
                border: 1.5px solid #C268F2 !important;
                border-radius: 10px !important;
                box-shadow: 0 16px 45px rgba(0, 0, 0, 0.95), 0 0 25px rgba(194, 104, 242, 0.35) !important;
                padding: 6px !important;
                min-width: 190px !important;
                z-index: 999999 !important;
            }

            .react-contextmenu-item,
            nav.react-contextmenu .react-contextmenu-item,
            div.react-contextmenu .react-contextmenu-item,
            [role="menuitem"],
            div[role="menu"] button,
            div[role="menu"] a,
            div[role="menu"] div[role="menuitem"],
            ul[role="menu"] li,
            div[class*="ContextMenu"] button,
            div[class*="ContextMenu"] a,
            div[class*="Menu___Styled"] button,
            div[class*="DropdownMenu__Menu"] button,
            div[class*="DropdownMenu__Menu"] a,
            button[class*="ContextMenu__Item"] {
                display: flex !important;
                align-items: center !important;
                color: #ffffff !important;
                padding: 8px 14px !important;
                margin: 2px 0 !important;
                font-size: 0.88rem !important;
                font-weight: 600 !important;
                border-radius: 6px !important;
                background: transparent !important;
                border: none !important;
                cursor: pointer !important;
                transition: all 0.15s ease !important;
                width: 100% !important;
                box-sizing: border-box !important;
                white-space: nowrap !important;
            }

            .react-contextmenu-item *,
            nav.react-contextmenu *,
            div.react-contextmenu *,
            div[role="menu"] *,
            ul[role="menu"] *,
            div[class*="ContextMenu"]:not([class*="Row"]) *,
            div[class*="Menu___Styled"] *,
            div[class*="DropdownMenu__Menu"] *,
            button[class*="ContextMenu__Item"] * {
                color: #ffffff !important;
                opacity: 1 !important;
                visibility: visible !important;
            }

            .react-contextmenu-item:hover,
            .react-contextmenu-item--active,
            nav.react-contextmenu .react-contextmenu-item:hover,
            [role="menuitem"]:hover,
            div[role="menu"] button:hover,
            div[role="menu"] a:hover,
            div[role="menu"] div[role="menuitem"]:hover,
            ul[role="menu"] li:hover,
            div[class*="ContextMenu"] button:hover,
            div[class*="ContextMenu"] a:hover,
            div[class*="Menu___Styled"] button:hover,
            div[class*="DropdownMenu__Menu"] button:hover,
            button[class*="ContextMenu__Item"]:hover {
                background: linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%) !important;
                background-color: #C268F2 !important;
                color: #ffffff !important;
                box-shadow: 0 2px 10px rgba(194, 104, 242, 0.4) !important;
            }

            div[role="menu"] button:hover *,
            div[role="menu"] a:hover *,
            div[class*="ContextMenu"] button:hover *,
            div[class*="Menu___Styled"] button:hover *,
            div[class*="DropdownMenu__Menu"] button:hover * {
                color: #ffffff !important;
            }

            div[role="menu"] svg,
            ul[role="menu"] svg,
            div[class*="ContextMenu"] svg,
            div[class*="ActionMenu"] svg,
            div[class*="Menu___Styled"] svg,
            div[class*="DropdownMenu__Menu"] svg {
                color: #C268F2 !important;
                stroke: #C268F2 !important;
                fill: currentColor !important;
                width: 16px !important;
                height: 16px !important;
                margin-right: 10px !important;
                flex-shrink: 0 !important;
            }

            div[role="menu"] button:hover svg,
            div[class*="ContextMenu"] button:hover svg,
            div[class*="Menu___Styled"] button:hover svg,
            div[class*="DropdownMenu__Menu"] button:hover svg {
                color: #ffffff !important;
                stroke: #ffffff !important;
                fill: #ffffff !important;
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
            /* Server Row Icon Container (Eliminate Big Purple Blob) */
            a[href*="/server/"] div.icon,
            a[class*="ServerRow"] div.icon,
            div[class*="GreyRowBox"] div.icon,
            div.icon.mr-4 {
                background: transparent !important;
                background-color: transparent !important;
                width: 2.25rem !important;
                height: 2.25rem !important;
                min-width: 2.25rem !important;
                max-width: 2.25rem !important;
                padding: 0 !important;
                border-radius: 8px !important;
                box-shadow: none !important;
                display: flex !important;
                align-items: center !important;
                justify-content: center !important;
            }
            /* Icons */
            a[href*="/server/"] svg,
            a[class*="ServerRow"] div.icon svg,
            div.icon.mr-4 svg {
                color: #C268F2 !important;
                width: 1.35rem !important;
                height: 1.35rem !important;
                font-size: 1.35rem !important;
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
            /* CONSOLE STAT CARDS: ALL VALUES, TEXT & OFFLINE LABELS BRIGHT WHITE */
            div[class*="stat_block"],
            div[class*="style-module_V4CSEpa4"] {
                color: #ffffff !important;
            }
            div[class*="stat_block"] *,
            div[class*="style-module_V4CSEpa4"] * {
                color: #ffffff !important;
            }
            div[class*="stat_block"] p,
            div[class*="style-module_V4CSEpa4"] p {
                color: #c9b6e3 !important;
                font-weight: 600 !important;
            }
            div[class*="stat_block"] span,
            div[class*="stat_block"] div,
            div[class*="style-module_V4CSEpa4"] span,
            div[class*="style-module_V4CSEpa4"] div,
            div[class*="stat_block"] .text-gray-400,
            div[class*="style-module_V4CSEpa4"] .text-gray-400,
            .text-gray-400 {
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
            button[type="submit"], [class*="Button__Primary"], .btn-primary {
                background: linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%) !important;
                background-color: #C268F2 !important;
                color: #ffffff !important;
                font-weight: 800 !important;
                letter-spacing: 0.8px !important;
                border-radius: 8px !important;
                box-shadow: 0 4px 18px rgba(194, 104, 242, 0.45) !important;
                border: none !important;
            }
            button[type="submit"]:hover, [class*="Button__Primary"]:hover {
                transform: translateY(-2px) !important;
                box-shadow: 0 6px 28px rgba(194, 104, 242, 0.75) !important;
                filter: brightness(1.1) !important;
            }
            /* ELIMINATE ALL FOOTER ELEMENTS AND BOTTOM COPYRIGHT */
            footer,
            .main-footer,
            a[href*="pterodactyl.io"],
            p:has(> a[href*="pterodactyl.io"]),
            p[class*="LoginFormContainer___StyledP"],
            div[class*="ContentContainer"]:last-child:has(a),
            p[class*="text-neutral-500"],
            .text-neutral-500.text-xs.text-center,
            p.text-center.text-xs {
                display: none !important;
                visibility: hidden !important;
                opacity: 0 !important;
                height: 0 !important;
                min-height: 0 !important;
                margin: 0 !important;
                padding: 0 !important;
                overflow: hidden !important;
                pointer-events: none !important;
            }

            /* ========================================================= */
            /* ALL MODALS & DIALOGS: OBSIDIAN PURPLE GLASS THEME         */
            /* ========================================================= */
            div[role="dialog"],
            div[class*="Modal"] > div,
            div[class*="Dialog"] > div,
            div[class*="Modal__Container"],
            div[class*="Dialog___StyledDiv"],
            div[class*="ModalMask"] > div,
            div[class*="ConfirmationModal"] {
                background: #110d22 !important;
                background-color: #110d22 !important;
                border: 1.5px solid rgba(194, 104, 242, 0.35) !important;
                border-radius: 14px !important;
                box-shadow: 0 16px 50px rgba(0, 0, 0, 0.85), 0 0 25px rgba(194, 104, 242, 0.25) !important;
                color: #ffffff !important;
            }
            div[role="dialog"] h2,
            div[role="dialog"] p[class*="font-header"],
            div[class*="Modal"] h2,
            div[class*="Modal"] p[class*="title"],
            div[role="dialog"] label,
            div[role="dialog"] span {
                color: #ffffff !important;
            }
            div[role="dialog"] input,
            div[role="dialog"] textarea,
            div[class*="Modal"] input {
                background: #0b0717 !important;
                background-color: #0b0717 !important;
                border: 1.5px solid rgba(194, 104, 242, 0.3) !important;
                border-radius: 8px !important;
                color: #ffffff !important;
                padding: 10px 14px !important;
            }
            div[role="dialog"] input:focus,
            div[role="dialog"] textarea:focus,
            div[class*="Modal"] input:focus {
                border-color: #C268F2 !important;
                box-shadow: 0 0 12px rgba(194, 104, 242, 0.5) !important;
            }

            /* ========================================================= */
            /* ALL SELECT DROPDOWNS: OBSIDIAN PURPLE THEME               */
            /* ========================================================= */
            select,
            select[class*="Select"],
            div[class*="Select"] select {
                background-color: #0b0717 !important;
                background: #0b0717 !important;
                color: #ffffff !important;
                border: 1.5px solid rgba(194, 104, 242, 0.4) !important;
                border-radius: 8px !important;
                padding: 8px 32px 8px 12px !important;
                outline: none !important;
                box-shadow: none !important;
            }
            select:focus {
                border-color: #C268F2 !important;
                box-shadow: 0 0 12px rgba(194, 104, 242, 0.5) !important;
            }
            select option {
                background-color: #110d22 !important;
                color: #ffffff !important;
                padding: 10px 14px !important;
            }
            select option:hover,
            select option:focus,
            select option:checked {
                background-color: #C268F2 !important;
                background: linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%) !important;
                color: #ffffff !important;
            }
        </style>
        <!-- Custom Domains & Cloudflare Tunnel Router Script -->
        <script>
        window.NP_VPS_IP = '" + server_ip + "';
        // Intercept API responses to replace domain alias with VPS IP in React internal store
        (function() {
            const origFetch = window.fetch;
            if (!origFetch) return;
            window.fetch = async function(...args) {
                const response = await origFetch.apply(this, args);
                try {
                    const url = typeof args[0] === 'string' ? args[0] : (args[0] && args[0].url ? args[0].url : '');
                    if (url.includes('/api/client') || url.includes('/api/server')) {
                        const clone = response.clone();
                        const data = await clone.json();
                        const vpsIp = window.NP_VPS_IP || '213.136.89.90';
                        let modified = false;

                        function fixAlloc(obj) {
                            if (!obj || typeof obj !== 'object') return;
                            if (Array.isArray(obj)) {
                                obj.forEach(fixAlloc);
                                return;
                            }
                            if (typeof obj.alias === 'string' && (obj.alias.includes('panel.') || obj.alias.includes('.nx.kg') || obj.alias.includes('.top') || obj.alias.includes('.com') || obj.alias.includes('.net') || obj.alias === '0.0.0.0')) {
                                obj.alias = vpsIp;
                                modified = true;
                            }
                            if (typeof obj.ip_alias === 'string' && (obj.ip_alias.includes('panel.') || obj.ip_alias.includes('.nx.kg') || obj.ip_alias.includes('.top') || obj.ip_alias.includes('.com') || obj.ip_alias.includes('.net') || obj.ip_alias === '0.0.0.0')) {
                                obj.ip_alias = vpsIp;
                                modified = true;
                            }
                            if (typeof obj.ip === 'string' && (obj.ip.includes('panel.') || obj.ip.includes('.nx.kg') || obj.ip.includes('.top') || obj.ip.includes('.com') || obj.ip.includes('.net') || obj.ip === '0.0.0.0' || obj.ip === 'localhost' || obj.ip === '127.0.0.1')) {
                                obj.ip = vpsIp;
                                modified = true;
                            }
                            for (const k in obj) {
                                if (obj[k] && typeof obj[k] === 'object') {
                                    fixAlloc(obj[k]);
                                }
                            }
                        }

                        fixAlloc(data);

                        if (modified) {
                            return new Response(JSON.stringify(data), {
                                status: response.status,
                                statusText: response.statusText,
                                headers: response.headers
                            });
                        }
                    }
                } catch(e) {}
                return response;
            };
        })();
        // Clean daemon console output in real-time over WebSocket
        (function() {
            const OrigWebSocket = window.WebSocket;
            if (!OrigWebSocket) return;
            window.WebSocket = function(url, protocols) {
                const ws = protocols !== undefined ? new OrigWebSocket(url, protocols) : new OrigWebSocket(url);

                function cleanData(data) {
                    if (typeof data === 'string' && (data.includes('pterodactyl') || data.includes('Pterodactyl'))) {
                        return data
                            .replace(/container@pterodactyl~/g, 'container@nothing~')
                            .replace(/container@pterodactyl/g, 'container@nothing')
                            .replace(/\[Pterodactyl Daemon\]:/g, '[Nothing Daemon]:')
                            .replace(/Pterodactyl Daemon/g, 'Nothing Daemon')
                            .replace(/pterodactyl/g, 'nothing')
                            .replace(/Pterodactyl/g, 'Nothing');
                    }
                    return data;
                }

                const origAddEventListener = ws.addEventListener;
                ws.addEventListener = function(type, listener, options) {
                    if (type === 'message') {
                        const wrapped = function(event) {
                            let ev = event;
                            if (typeof event.data === 'string' && (event.data.includes('pterodactyl') || event.data.includes('Pterodactyl'))) {
                                try {
                                    ev = new MessageEvent('message', {
                                        data: cleanData(event.data),
                                        origin: event.origin,
                                        lastEventId: event.lastEventId,
                                        source: event.source,
                                        ports: event.ports
                                    });
                                } catch (err) {
                                    try {
                                        Object.defineProperty(event, 'data', { value: cleanData(event.data) });
                                    } catch (e) {}
                                }
                            }
                            return listener.call(this, ev);
                        };
                        return origAddEventListener.call(this, type, wrapped, options);
                    }
                    return origAddEventListener.call(this, type, listener, options);
                };

                let userOnMessage = null;
                Object.defineProperty(ws, 'onmessage', {
                    get() { return userOnMessage; },
                    set(handler) {
                        userOnMessage = handler;
                        if (!handler) {
                            return;
                        }
                        this._np_wrapped_onmessage = function(event) {
                            let ev = event;
                            if (typeof event.data === 'string' && (event.data.includes('pterodactyl') || event.data.includes('Pterodactyl'))) {
                                try {
                                    ev = new MessageEvent('message', {
                                        data: cleanData(event.data),
                                        origin: event.origin,
                                        lastEventId: event.lastEventId,
                                        source: event.source,
                                        ports: event.ports
                                    });
                                } catch (err) {
                                    try {
                                        Object.defineProperty(event, 'data', { value: cleanData(event.data) });
                                    } catch (e) {}
                                }
                            }
                            return handler.call(this, ev);
                        };
                        origAddEventListener.call(this, 'message', this._np_wrapped_onmessage);
                    }
                });

                return ws;
            };
            window.WebSocket.prototype = OrigWebSocket.prototype;
            window.WebSocket.CONNECTING = OrigWebSocket.CONNECTING;
            window.WebSocket.OPEN = OrigWebSocket.OPEN;
            window.WebSocket.CLOSING = OrigWebSocket.CLOSING;
            window.WebSocket.CLOSED = OrigWebSocket.CLOSED;
        })();

        (function() {
            let activeMode = 'nginx'; // 'nginx' or 'cloudflared'

            function injectDomainManager() {
                const path = window.location.pathname;
                const match = path.match(/^\/server\/([a-zA-Z0-9]+)\/domains/);
                const existing = document.getElementById('np-domain-manager-card');

                if (!match) {
                    if (existing) existing.remove();
                    const fb = document.getElementById('np-domains-fallback-mount');
                    if (fb) fb.remove();
                    document.querySelectorAll('[data-np-hidden-by-domains="true"]').forEach(el => {
                        el.style.display = '';
                        el.removeAttribute('data-np-hidden-by-domains');
                    });
                    return;
                }
                
                const serverId = match[1];

                const domainsLink = document.querySelector('a[href*="/domains"]');
                if (!domainsLink) {
                    return;
                }

                // Locate SubNavigation bar container
                const subNav = domainsLink.closest('div.bg-neutral-900, div[class*="SubNavigation"], div.flex.overflow-x-auto, nav') || domainsLink.parentElement.parentElement;
                if (!subNav || !subNav.parentElement) {
                    return;
                }

                // Dedicated mount target directly following SubNavigation
                let fb = document.getElementById('np-domains-fallback-mount');
                if (!fb) {
                    fb = document.createElement('div');
                    fb.id = 'np-domains-fallback-mount';
                    fb.style.cssText = 'position: relative !important; width: 100% !important; max-width: 1200px !important; margin: 1.5rem auto 3rem auto !important; padding: 0 1rem !important; box-sizing: border-box !important; display: block !important; clear: both !important; z-index: 100 !important;';
                }
                
                if (fb.parentElement !== subNav.parentElement) {
                    subNav.insertAdjacentElement('afterend', fb);
                }

                // Hide sibling content below subnav when on /domains route
                Array.from(subNav.parentElement.children).forEach(child => {
                    if (child !== subNav && child !== fb && child.style.display !== 'none' && !child.contains(fb)) {
                        child.style.display = 'none';
                        child.setAttribute('data-np-hidden-by-domains', 'true');
                    }
                });

                let mount = document.getElementById('np-domains-view-mount') || fb;
                mount.style.display = 'block';

                if (existing && mount.contains(existing) && existing.getAttribute('data-server-id') === serverId) {
                    return;
                }

                if (existing) {
                    existing.remove();
                }

                const card = document.createElement('div');
                card.id = 'np-domain-manager-card';
                card.setAttribute('data-server-id', serverId);
                card.style.cssText = 'width: 100% !important; background: #110d22 !important; border: 1.5px solid rgba(194, 104, 242, 0.35) !important; border-radius: 14px !important; padding: 1.75rem !important; box-shadow: 0 10px 35px rgba(0, 0, 0, 0.6), 0 0 20px rgba(194, 104, 242, 0.15) !important; box-sizing: border-box !important; display: block !important;';
                
                card.innerHTML = `
                    <div style="display:flex; justify-content:space-between; align-items:center; border-bottom:1px solid rgba(194,104,242,0.15); padding-bottom:0.85rem; margin-bottom:1.25rem;">
                        <div style="display:flex; align-items:center; gap:10px;">
                            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#C268F2" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:middle;"><circle cx="12" cy="12" r="10"></circle><line x1="2" y1="12" x2="22" y2="12"></line><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"></path></svg>
                            <h3 style="margin:0; font-size:1.15rem; font-weight:800; color:#ffffff; letter-spacing:0.5px;">CUSTOM DOMAINS &amp; PORT ROUTING</h3>
                            <span style="background:rgba(194,104,242,0.18); color:#C268F2; font-size:0.72rem; font-weight:800; padding:3px 10px; border-radius:20px; border:1px solid rgba(194,104,242,0.35); text-transform:uppercase; letter-spacing:0.5px;">INSTANT ROUTER</span>
                        </div>
                    </div>

                    <!-- MODE SELECTOR TABS -->
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
                        <div style="flex:2; min-width:200px;">
                            <label style="display:block; font-size:0.75rem; font-weight:700; color:#d1b8eb; text-transform:uppercase; margin-bottom:6px;">Domain Name</label>
                            <input type="text" id="np-cf-domain-input" placeholder="e.g. play.yourdomain.com" style="width:100%; height:42px; box-sizing:border-box; background:#0b0818; border:1px solid rgba(194,104,242,0.3); color:#fff; border-radius:8px; padding:0 14px; font-size:0.9rem; outline:none;" />
                        </div>
                        <div style="flex:2; min-width:200px;">
                            <label style="display:block; font-size:0.75rem; font-weight:700; color:#d1b8eb; text-transform:uppercase; margin-bottom:6px;">Cloudflare Tunnel Token</label>
                            <input type="text" id="np-cf-token-input" placeholder="Tunnel token (leave empty for Quick Tunnel)" style="width:100%; height:42px; box-sizing:border-box; background:#0b0818; border:1px solid rgba(194,104,242,0.3); color:#fff; border-radius:8px; padding:0 14px; font-size:0.9rem; outline:none;" />
                        </div>
                        <div style="flex:1; min-width:140px;">
                            <label style="display:block; font-size:0.75rem; font-weight:700; color:#d1b8eb; text-transform:uppercase; margin-bottom:6px;">Target Port</label>
                            <select id="np-cf-port-select" style="width:100%; height:42px; box-sizing:border-box; background:#0b0818; border:1px solid rgba(194,104,242,0.3); color:#fff; border-radius:8px; padding:0 36px 0 14px; font-size:0.9rem; outline:none; cursor:pointer;">
                                <option value="">Loading ports...</option>
                            </select>
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
                
                mount.appendChild(card);
                loadServerDomains(serverId);
                
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
                    const cfDomainInput = document.getElementById('np-cf-domain-input');
                    const tokenInput = document.getElementById('np-cf-token-input');
                    payload.domain = cfDomainInput ? cfDomainInput.value.trim() : '';
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

            // Real-time DOM text sanitizer (Guarantees zero Pterodactyl visibility anywhere)
            function sanitizePterodactylText(node) {
                if (!node) return;
                if (node.nodeType === 3) { // TEXT_NODE
                    var val = node.nodeValue;
                    if (val && (val.indexOf('pterodactyl') !== -1 || val.indexOf('Pterodactyl') !== -1)) {
                        node.nodeValue = val
                            .replace(/Configure Pterodactyl to your liking\.?/gi, 'Configure Nothing Panel to your liking.')
                            .replace(/Configure advanced settings for Pterodactyl\.?/gi, 'Configure advanced settings for Nothing Panel.')
                            .replace(/Configure how Pterodactyl should handle sending emails\.?/gi, 'Configure how Nothing Panel should handle sending emails.')
                            .replace(/All nodes currently configured on the Pterodactyl Panel\.?/gi, 'All nodes currently configured on Nothing Panel.')
                            .replace(/All servers currently configured on the Pterodactyl Panel\.?/gi, 'All servers currently configured on Nothing Panel.')
                            .replace(/Pterodactyl Software/gi, 'Nothing Panel')
                            .replace(/Pterodactyl Panel/gi, 'Nothing Panel')
                            .replace(/Pterodactyl Wings/gi, 'Nothing Wings')
                            .replace(/container@pterodactyl~/g, 'container@nothing~')
                            .replace(/container@pterodactyl/g, 'container@nothing')
                            .replace(/\[Pterodactyl Daemon\]:/g, '[Nothing Daemon]:')
                            .replace(/Pterodactyl Daemon/g, 'Nothing Daemon')
                            .replace(/https?:\/\/pterodactyl\.io[^\s"']*/gi, '#')
                            .replace(/pterodactyl\.io/gi, 'nothingx.top')
                            .replace(/Pterodactyl/g, 'Nothing Panel')
                            .replace(/pterodactyl/g, 'nothing');
                    }
                } else if (node.nodeType === 1) { // ELEMENT_NODE
                    ['title', 'placeholder', 'alt', 'aria-label'].forEach(function(attr) {
                        var aVal = node.getAttribute && node.getAttribute(attr);
                        if (aVal && (aVal.indexOf('pterodactyl') !== -1 || aVal.indexOf('Pterodactyl') !== -1)) {
                            node.setAttribute(attr, aVal
                                .replace(/Configure Pterodactyl to your liking\.?/gi, 'Configure Nothing Panel to your liking.')
                                .replace(/Pterodactyl Software/gi, 'Nothing Panel')
                                .replace(/Pterodactyl Panel/gi, 'Nothing Panel')
                                .replace(/Pterodactyl/g, 'Nothing Panel')
                                .replace(/pterodactyl/g, 'nothing')
                            );
                        }
                    });
                    var children = node.childNodes;
                    for (var k = 0; k < children.length; k++) {
                        sanitizePterodactylText(children[k]);
                    }
                }
            }

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
                    if (select.classList.contains('select2-hidden-accessible')) return;

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
                    trigger.style.cssText = 'width: 100% !important; min-height: 40px !important; background: #0b0717 !important; border: 1.5px solid rgba(194, 104, 242, 0.45) !important; border-radius: 8px !important; color: #ffffff !important; padding: 8px 38px 8px 14px !important; font-size: 0.92rem !important; font-weight: 500 !important; display: flex !important; align-items: center !important; justify-content: space-between !important; cursor: pointer !important; box-sizing: border-box !important; transition: all 0.2s ease !important;';

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
                    menu.style.cssText = 'display: none !important; position: absolute !important; top: calc(100% + 4px) !important; left: 0 !important; width: 100% !important; max-height: 250px !important; overflow-y: auto !important; background: #120e24 !important; border: 1.5px solid #C268F2 !important; border-radius: 10px !important; box-shadow: 0 16px 45px rgba(0, 0, 0, 0.95), 0 0 25px rgba(194, 104, 242, 0.35) !important; z-index: 9999999 !important; padding: 4px !important; box-sizing: border-box !important; backdrop-filter: blur(12px) !important;';

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
                            item.style.cssText = `padding: 10px 14px !important; margin: 2px 0 !important; border-radius: 6px !important; font-size: 0.9rem !important; cursor: pointer !important; color: ${isSelected ? '#ffffff' : '#dcc7f5'} !important; background: ${isSelected ? 'linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%)' : 'transparent'} !important; font-weight: ${isSelected ? '700' : '500'} !important; display: flex !important; align-items: center !important; justify-content: space-between !important; transition: all 0.15s ease !important;`;

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

                    // Dynamically sync options if select elements or text changes
                    const optObserver = new MutationObserver(() => syncOptions());
                    optObserver.observe(select, { childList: true, subtree: true, characterData: true });

                    function openSelect() {
                        document.querySelectorAll('.np-custom-select-menu').forEach(m => m.style.display = 'none');
                        document.querySelectorAll('.np-custom-select-arrow').forEach(a => a.style.transform = 'translateY(-50%) rotate(0deg)');
                        document.querySelectorAll('.np-custom-select-trigger').forEach(t => {
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

            document.addEventListener('click', function() {
                document.querySelectorAll('.np-custom-select-menu').forEach(m => m.style.display = 'none');
                document.querySelectorAll('.np-custom-select-arrow').forEach(a => a.style.transform = 'translateY(-50%) rotate(0deg)');
                document.querySelectorAll('.np-custom-select-trigger').forEach(t => {
                    t.style.borderColor = 'rgba(194, 104, 242, 0.4)';
                    t.style.boxShadow = 'none';
                });
            });

            // IMAGE PREVIEW MODAL FOR FILE MANAGER (PNG, JPG, GIF, WEBP, SVG)
            function openImageModal(serverId, filePath, fileName) {
                let modal = document.getElementById('np-image-preview-modal');
                if (!modal) {
                    modal = document.createElement('div');
                    modal.id = 'np-image-preview-modal';
                    document.body.appendChild(modal);
                }

                modal.style.cssText = 'position: fixed; inset: 0; z-index: 9999999; background: rgba(5, 3, 12, 0.85); backdrop-filter: blur(12px); display: flex; align-items: center; justify-content: center; padding: 20px; box-sizing: border-box; animation: npFadeIn 0.2s ease-out;';

                modal.innerHTML = `
                    <div style="background: #110d24; border: 1.5px solid rgba(194, 104, 242, 0.45); border-radius: 16px; width: 100%; max-width: 820px; max-height: 90vh; display: flex; flex-direction: column; overflow: hidden; box-shadow: 0 25px 60px rgba(0,0,0,0.9), 0 0 35px rgba(194,104,242,0.25);">
                        <div style="display: flex; align-items: center; justify-content: space-between; padding: 14px 20px; border-bottom: 1px solid rgba(194, 104, 242, 0.18); background: #0c081c;">
                            <div style="display: flex; align-items: center; gap: 10px; overflow: hidden;">
                                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#C268F2" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect><circle cx="8.5" cy="8.5" r="1.5"></circle><polyline points="21 15 16 10 5 21"></polyline></svg>
                                <span style="color: #ffffff; font-weight: 700; font-size: 1.05rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${fileName}</span>
                                <span id="np-img-meta" style="font-size: 0.72rem; color: #a794c2; background: rgba(194, 104, 242, 0.15); padding: 3px 8px; border-radius: 6px; border: 1px solid rgba(194, 104, 242, 0.3);">Loading...</span>
                            </div>
                            <button id="np-img-close-btn" style="background: transparent; border: none; color: #a794c2; font-size: 1.6rem; cursor: pointer; padding: 4px 8px; border-radius: 6px; display: flex; align-items: center; justify-content: center; transition: all 0.15s ease;">&times;</button>
                        </div>
                        <div style="flex: 1; min-height: 260px; max-height: calc(90vh - 140px); overflow: auto; display: flex; align-items: center; justify-content: center; padding: 24px; background: repeating-conic-gradient(#0b0717 0% 25%, #130e28 0% 50%) 50% / 20px 20px; position: relative;">
                            <div id="np-img-spinner" style="display: flex; flex-direction: column; align-items: center; gap: 12px; color: #C268F2;">
                                <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="animation: npSpin 1s linear infinite;"><line x1="12" y1="2" x2="12" y2="6"></line><line x1="12" y1="18" x2="12" y2="22"></line><line x1="4.93" y1="4.93" x2="7.76" y2="7.76"></line><line x1="16.24" y1="16.24" x2="19.07" y2="19.07"></line><line x1="2" y1="12" x2="6" y2="12"></line><line x1="18" y1="12" x2="22" y2="12"></line><line x1="4.93" y1="19.07" x2="7.76" y2="16.24"></line><line x1="16.24" y1="7.76" x2="19.07" y2="4.93"></line></svg>
                                <span style="font-size: 0.85rem; font-weight: 600;">Loading image...</span>
                            </div>
                            <img id="np-img-view" style="display: none; max-width: 100%; max-height: calc(90vh - 190px); object-fit: contain; border-radius: 6px; box-shadow: 0 10px 30px rgba(0,0,0,0.8);" alt="${fileName}" />
                        </div>
                        <div style="display: flex; align-items: center; justify-content: space-between; padding: 14px 20px; border-top: 1px solid rgba(194, 104, 242, 0.18); background: #0c081c;">
                            <span id="np-img-dims" style="color: #8b77a6; font-size: 0.82rem;"></span>
                            <div style="display: flex; gap: 10px;">
                                <a id="np-img-download-btn" href="#" download="${fileName}" target="_blank" style="display: inline-flex; align-items: center; gap: 6px; padding: 8px 16px; border-radius: 8px; font-size: 0.85rem; font-weight: 700; background: linear-gradient(135deg, #C268F2 0%, #8A2BE2 100%); color: #ffffff; text-decoration: none; box-shadow: 0 2px 10px rgba(194,104,242,0.4);">
                                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="7 10 12 15 17 10"></polyline><line x1="12" y1="15" x2="12" y2="3"></line></svg>
                                    Download
                                </a>
                                <button id="np-img-close-action" type="button" style="padding: 8px 16px; border-radius: 8px; font-size: 0.85rem; font-weight: 700; background: #1a1430; color: #dcc7f5; border: 1px solid rgba(194, 104, 242, 0.3); cursor: pointer;">Close</button>
                            </div>
                        </div>
                    </div>
                `;

                function closeModal() {
                    modal.style.display = 'none';
                    const img = document.getElementById('np-img-view');
                    if (img) img.src = '';
                }

                document.getElementById('np-img-close-btn').onclick = closeModal;
                document.getElementById('np-img-close-action').onclick = closeModal;
                modal.onclick = function(e) {
                    if (e.target === modal) closeModal();
                };
                window.addEventListener('keydown', function escHandler(e) {
                    if (e.key === 'Escape') {
                        closeModal();
                        window.removeEventListener('keydown', escHandler);
                    }
                });

                // Request signed download URL from client API
                fetch('/api/client/servers/' + serverId + '/files/download?file=' + encodeURIComponent(filePath), {
                    headers: { 'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest' }
                })
                .then(r => r.json())
                .then(res => {
                    const downloadUrl = res?.attributes?.url;
                    if (!downloadUrl) throw new Error('Could not retrieve image URL from daemon');

                    const imgEl = document.getElementById('np-img-view');
                    const spinner = document.getElementById('np-img-spinner');
                    const metaEl = document.getElementById('np-img-meta');
                    const dimsEl = document.getElementById('np-img-dims');
                    const dlBtn = document.getElementById('np-img-download-btn');

                    dlBtn.href = downloadUrl;

                    imgEl.onload = function() {
                        if (spinner) spinner.style.display = 'none';
                        imgEl.style.display = 'block';
                        if (metaEl) metaEl.textContent = `${imgEl.naturalWidth} × ${imgEl.naturalHeight} px`;
                        if (dimsEl) dimsEl.textContent = `Dimensions: ${imgEl.naturalWidth} × ${imgEl.naturalHeight} pixels`;
                    };
                    imgEl.onerror = function() {
                        if (spinner) spinner.innerHTML = '<span style="color:#ef4444; font-weight:700;">Failed to load image preview</span>';
                    };
                    imgEl.src = downloadUrl;
                })
                .catch(err => {
                    const spinner = document.getElementById('np-img-spinner');
                    if (spinner) spinner.innerHTML = `<span style="color:#ef4444; font-weight:700;">Error: ${err.message}</span>`;
                });
            }

            function initFileManagerImagePreview() {
                const path = window.location.pathname;
                const match = path.match(/^\/server\/([a-zA-Z0-9]+)\/files/);
                if (!match) return;
                const serverId = match[1];

                const imageExts = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.ico', '.bmp'];
                const rows = document.querySelectorAll('div[class*="file_row"], div[class*="style-module_HHpjDvv7"]');

                // Determine current directory from URL hash
                let currentDir = '';
                if (window.location.hash) {
                    try {
                        currentDir = decodeURIComponent(window.location.hash.replace(/^#\/?/, ''));
                    } catch (e) {
                        currentDir = window.location.hash.replace(/^#\/?/, '');
                    }
                }
                currentDir = currentDir.replace(/^\/+|\/+$/g, '');

                rows.forEach(row => {
                    if (row.getAttribute('data-np-img-bound')) return;

                    const detailsEl = row.querySelector('div[class*="details"], a[class*="details"], div[class*="style-module_le7taa7N"], a[class*="style-module_le7taa7N"]');
                    if (!detailsEl) return;

                    const textNodes = Array.from(detailsEl.querySelectorAll('div, span, p')).filter(el => el.children.length === 0);
                    let fileName = '';
                    for (const el of textNodes) {
                        const t = (el.textContent || '').trim();
                        if (imageExts.some(ext => t.toLowerCase().endsWith(ext))) {
                            fileName = t;
                            break;
                        }
                    }

                    if (!fileName) return;

                    row.setAttribute('data-np-img-bound', 'true');
                    detailsEl.style.cursor = 'pointer';
                    detailsEl.title = 'Click to view ' + fileName;

                    // Click handler to open image modal
                    detailsEl.addEventListener('click', function(e) {
                        // Ignore if user clicked on checkbox or context menu trigger
                        if (e.target.closest('label') || e.target.closest('input')) return;
                        e.preventDefault();
                        e.stopPropagation();

                        const fullPath = currentDir ? (currentDir + '/' + fileName) : fileName;
                        openImageModal(serverId, fullPath, fileName);
                    });
                });
            }

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

            // ============================================================
            // TOGGLE / SWITCH SYNC (Uses CSS classes without overriding styles)
            // ============================================================
            function syncToggles() {
                document.querySelectorAll('div[class*="sc-1nxt82m-0"] > input[type="checkbox"], div[class*="sc-1nxt82m-1"] > input[type="checkbox"], div[class*="Switch"] > input[type="checkbox"], div[class*="Toggle"] > input[type="checkbox"]').forEach(inp => {
                    const label = inp.nextElementSibling;
                    if (!label || label.tagName !== 'LABEL') return;
                    if (inp.checked) {
                        label.classList.add('np-toggle-active');
                    } else {
                        label.classList.remove('np-toggle-active');
                    }
                });
            }

            document.addEventListener('change', function(e) {
                if (e.target && e.target.type === 'checkbox') {
                    const parent = e.target.parentElement;
                    if (parent && (parent.className.includes('sc-1nxt82m') || parent.className.includes('Switch') || parent.className.includes('Toggle'))) {
                        syncToggles();
                    }
                }
            }, true);


            // ============================================================
            // CONSOLE ADDRESS STAT CARD & SERVER ROWS: Always Show Real VPS IP:Port
            // ============================================================
            function enforceVpsIpDisplay() {
                const vpsIp = window.NP_VPS_IP || '213.136.89.90';

                // 1. Dashboard server rows & cards (Replace domain or 0.0.0.0 with real VPS IP)
                document.querySelectorAll('a[href*="/server/"] div[class*="lg:col-span-2"] p, a[href*="/server/"] p, div[class*="ServerRow"] p').forEach(el => {
                    const txt = (el.textContent || '').trim();
                    if (txt.includes(':') && (txt.includes('panel.') || txt.includes('.nx.kg') || txt.includes('.top') || txt.includes('.com') || txt.includes('.net') || txt.includes('0.0.0.0') || txt.includes('localhost') || txt.includes('127.0.0.1'))) {
                        const portM = txt.match(/:(\d+)$/);
                        if (portM) {
                            el.textContent = vpsIp + ':' + portM[1];
                        }
                    }
                });

                // 2. Console Address Stat Card (Real-time DOM replacement)
                updateAddressStatCard();
            }

            function updateAddressStatCard() {
                const vpsIp = window.NP_VPS_IP || '213.136.89.90';

                // Scan all elements labeled "Address"
                document.querySelectorAll('p, span, div').forEach(el => {
                    if (el.children.length === 0 && (el.textContent || '').trim() === 'Address') {
                        const card = el.closest('div[class*="style-module_V4CSEpa4"]') || el.closest('div[class*="StatBlock"]') || el.parentElement?.parentElement || el.parentElement;
                        if (card) {
                            if (!card.hasAttribute('data-np-vps-copy')) {
                                card.setAttribute('data-np-vps-copy', 'true');
                                card.addEventListener('click', () => {
                                    const portM = card.textContent.match(/:(\d+)/);
                                    if (portM) {
                                        navigator.clipboard.writeText(vpsIp + ':' + portM[1]);
                                    }
                                }, true);
                            }
                            card.querySelectorAll('p, div, span').forEach(valEl => {
                                if (valEl !== el && valEl.children.length === 0) {
                                    const txt = (valEl.textContent || '').trim();
                                    if (txt.includes(':') && (txt.includes('panel') || txt.includes('.kg') || txt.includes('.com') || txt.includes('.net') || txt.includes('.top') || txt.includes('0.0.0.0') || txt.includes('localhost') || txt.includes('127.0.0.1'))) {
                                        const portM = txt.match(/:(\d+)$/);
                                        if (portM) {
                                            const target = vpsIp + ':' + portM[1];
                                            if (valEl.textContent !== target) {
                                                valEl.textContent = target;
                                            }
                                        }
                                    }
                                }
                            });
                        }
                    }
                });

                // Universal fallback: Any standalone element showing domain:port
                document.querySelectorAll('p, span, div, code').forEach(el => {
                    if (el.children.length === 0) {
                        const txt = (el.textContent || '').trim();
                        if (txt.includes(':') && (txt.includes('panel.') || txt.includes('.nx.kg') || txt.includes('.top') || txt.includes('0.0.0.0') || txt.includes('localhost') || txt.includes('127.0.0.1'))) {
                            const portM = txt.match(/^(?:https?:\/\/)?(?:[a-zA-Z0-9_.-]+):(\d+)$/);
                            if (portM) {
                                const target = vpsIp + ':' + portM[1];
                                if (el.textContent !== target) {
                                    el.textContent = target;
                                }
                            }
                        }
                    }
                });
            }

            // ============================================================
            // MARKDOWN (.md) EDITOR & GITHUB-STYLE PREVIEW CONTROLLER
            // ============================================================
            function simpleMarkdownToHtml(md) {
                if (!md) return '<p style="color:#7c6999;font-style:italic;">Nothing to preview</p>';
                let html = md;
                html = html.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
                
                // Code blocks
                html = html.replace(/```([a-zA-Z0-9_-]*)\n([\s\S]*?)```/g, function(match, lang, code) {
                    return '<pre style="background:#0d1117;border:1px solid rgba(194,104,242,0.25);border-radius:8px;padding:14px;overflow-x:auto;margin:12px 0;"><code style="color:#e2d4f8;font-family:monospace;font-size:0.88rem;">' + code.trim() + '</code></pre>';
                });

                // Inline code
                html = html.replace(/`([^`]+)`/g, '<code style="background:#1a1330;border:1px solid rgba(194,104,242,0.25);border-radius:4px;padding:2px 6px;color:#C268F2;font-family:monospace;font-size:0.88rem;">$1</code>');

                // Headers
                html = html.replace(/^###### (.*$)/gim, '<h6 style="color:#d8b4fe;font-size:0.95rem;font-weight:700;margin:14px 0 6px 0;">$1</h6>');
                html = html.replace(/^##### (.*$)/gim, '<h5 style="color:#d8b4fe;font-size:1.05rem;font-weight:700;margin:16px 0 8px 0;">$1</h5>');
                html = html.replace(/^#### (.*$)/gim, '<h4 style="color:#d8b4fe;font-size:1.15rem;font-weight:700;margin:18px 0 8px 0;">$1</h4>');
                html = html.replace(/^### (.*$)/gim, '<h3 style="color:#e9d5ff;font-size:1.3rem;font-weight:700;margin:20px 0 10px 0;border-bottom:1px solid rgba(194,104,242,0.15);padding-bottom:6px;">$1</h3>');
                html = html.replace(/^## (.*$)/gim, '<h2 style="color:#f3e8ff;font-size:1.55rem;font-weight:700;margin:24px 0 12px 0;border-bottom:1px solid rgba(194,104,242,0.2);padding-bottom:8px;">$1</h2>');
                html = html.replace(/^# (.*$)/gim, '<h1 style="color:#ffffff;font-size:1.85rem;font-weight:800;margin:28px 0 14px 0;border-bottom:2px solid #C268F2;padding-bottom:10px;">$1</h1>');

                // Blockquotes
                html = html.replace(/^\> (.*$)/gim, '<blockquote style="border-left:3.5px solid #C268F2;background:rgba(194,104,242,0.08);margin:12px 0;padding:8px 16px;color:#c4b5fd;border-radius:0 8px 8px 0;">$1</blockquote>');

                // Bold & Italic
                html = html.replace(/\*\*([^*]+)\*\*/g, '<strong style="color:#ffffff;font-weight:700;">$1</strong>');
                html = html.replace(/\*([^*]+)\*/g, '<em style="color:#e9d5ff;">$1</em>');
                html = html.replace(/__([^_]+)__/g, '<strong style="color:#ffffff;font-weight:700;">$1</strong>');
                html = html.replace(/_([^_]+)_/g, '<em style="color:#e9d5ff;">$1</em>');

                // Horizontal Rule
                html = html.replace(/^---$/gim, '<hr style="border:none;border-top:1px solid rgba(194,104,242,0.25);margin:20px 0;" />');

                // Task lists & Lists
                html = html.replace(/^- \[x\] (.*$)/gim, '<div style="display:flex;align-items:center;gap:8px;margin:4px 0;"><span style="color:#10b981;font-weight:bold;">☑</span> <span style="color:#94a3b8;text-decoration:line-through;">$1</span></div>');
                html = html.replace(/^- \[ \] (.*$)/gim, '<div style="display:flex;align-items:center;gap:8px;margin:4px 0;"><span style="color:#C268F2;">☐</span> <span style="color:#ffffff;">$1</span></div>');
                html = html.replace(/^\- (.*$)/gim, '<li style="color:#e2d4f8;margin:4px 0 4px 20px;">$1</li>');
                html = html.replace(/^\* (.*$)/gim, '<li style="color:#e2d4f8;margin:4px 0 4px 20px;">$1</li>');

                // Links
                html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer" style="color:#C268F2;text-decoration:underline;font-weight:600;">$1</a>');

                // Paragraphs
                html = html.split('\n\n').map(p => {
                    p = p.trim();
                    if (!p) return '';
                    if (p.startsWith('<h') || p.startsWith('<pre') || p.startsWith('<blockquote') || p.startsWith('<div') || p.startsWith('<li') || p.startsWith('<hr')) {
                        return p;
                    }
                    return '<p style="margin:8px 0;line-height:1.6;color:#e2d4f8;">' + p.replace(/\n/g, '<br/>') + '</p>';
                }).join('');

                return html;
            }

            function initMarkdownPreview() {
                const path = window.location.pathname;
                const isEditPage = path.includes('/files/edit');
                if (!isEditPage) {
                    const existingBar = document.getElementById('np-md-toolbar');
                    if (existingBar) existingBar.remove();
                    const existingPrev = document.getElementById('np-md-preview-container');
                    if (existingPrev) existingPrev.remove();
                    return;
                }

                const editorContainer = document.querySelector('.ace_editor') || document.querySelector('div[class*="FileEditContainer"]') || document.querySelector('div[class*="EditorContainer"]');
                if (!editorContainer) return;
                const parent = editorContainer.parentElement;
                if (!parent) return;

                let toolbar = document.getElementById('np-md-toolbar');
                if (!toolbar) {
                    toolbar = document.createElement('div');
                    toolbar.id = 'np-md-toolbar';
                    toolbar.style.cssText = 'display:flex;align-items:center;justify-content:space-between;background:#110d22;border:1px solid rgba(194,104,242,0.25);border-bottom:none;border-radius:10px 10px 0 0;padding:8px 14px;margin-bottom:0;width:100%;box-sizing:border-box;';

                    toolbar.innerHTML = `
                        <div style="display:flex;align-items:center;gap:8px;">
                            <span style="font-weight:700;font-size:0.85rem;color:#C268F2;display:inline-flex;align-items:center;gap:6px;">
                                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#C268F2" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path><polyline points="14 2 14 8 20 8"></polyline><line x1="16" y1="13" x2="8" y2="13"></line><line x1="16" y1="17" x2="8" y2="17"></line><polyline points="10 9 9 9 8 9"></polyline></svg>
                                MARKDOWN
                            </span>
                        </div>
                        <div style="display:flex;align-items:center;background:#0b0717;border:1px solid rgba(194,104,242,0.3);border-radius:8px;padding:3px;gap:4px;">
                            <button id="np-md-btn-edit" type="button" style="background:#C268F2;color:#ffffff;border:none;border-radius:6px;padding:5px 12px;font-size:0.82rem;font-weight:700;cursor:pointer;display:inline-flex;align-items:center;gap:5px;transition:all 0.15s ease;">
                                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20h9"></path><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"></path></svg>
                                Edit
                            </button>
                            <button id="np-md-btn-preview" type="button" style="background:transparent;color:#c4b5fd;border:none;border-radius:6px;padding:5px 12px;font-size:0.82rem;font-weight:600;cursor:pointer;display:inline-flex;align-items:center;gap:5px;transition:all 0.15s ease;">
                                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path><circle cx="12" cy="12" r="3"></circle></svg>
                                Preview
                            </button>
                        </div>
                    `;

                    parent.insertBefore(toolbar, editorContainer);

                    let previewCont = document.getElementById('np-md-preview-container');
                    if (!previewCont) {
                        previewCont = document.createElement('div');
                        previewCont.id = 'np-md-preview-container';
                        previewCont.style.cssText = 'display:none;width:100%;min-height:500px;max-height:75vh;overflow-y:auto;background:#0d1117;border:1px solid rgba(194,104,242,0.25);border-radius:0 0 10px 10px;padding:2rem;box-sizing:border-box;color:#e2d4f8;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;';
                        parent.insertBefore(previewCont, editorContainer.nextSibling);
                    }

                    const btnEdit = document.getElementById('np-md-btn-edit');
                    const btnPreview = document.getElementById('np-md-btn-preview');

                    btnEdit.onclick = function() {
                        btnEdit.style.background = '#C268F2';
                        btnEdit.style.color = '#ffffff';
                        btnPreview.style.background = 'transparent';
                        btnPreview.style.color = '#c4b5fd';
                        editorContainer.style.display = 'block';
                        previewCont.style.display = 'none';
                    };

                    btnPreview.onclick = function() {
                        btnPreview.style.background = '#C268F2';
                        btnPreview.style.color = '#ffffff';
                        btnEdit.style.background = 'transparent';
                        btnEdit.style.color = '#c4b5fd';

                        let text = '';
                        if (window.ace && window.ace.edit) {
                            try {
                                const ed = window.ace.edit(editorContainer);
                                if (ed) text = ed.getValue();
                            } catch(e) {}
                        }
                        if (!text) {
                            const ta = editorContainer.querySelector('textarea');
                            if (ta) text = ta.value;
                        }
                        if (!text) {
                            const lines = Array.from(editorContainer.querySelectorAll('.ace_line'));
                            if (lines.length > 0) text = lines.map(l => l.innerText).join('\n');
                        }

                        previewCont.innerHTML = simpleMarkdownToHtml(text);
                        editorContainer.style.display = 'none';
                        previewCont.style.display = 'block';
                    };
                }
            }

            function fixStartupLayout() {
                if (!window.location.pathname.includes('/startup')) return;

                // 1. Locate the Startup Command card title
                let cmdTitle = null;
                document.querySelectorAll('h1, h2, h3, h4, h5, h6, p, span, div').forEach(el => {
                    if (el.children.length === 0 && (el.textContent || '').trim().toUpperCase() === 'STARTUP COMMAND') {
                        cmdTitle = el;
                    }
                });

                if (cmdTitle) {
                    // Walk up to find the container holding both Startup Command and Docker Image
                    let gridContainer = cmdTitle.parentElement;
                    while (gridContainer && gridContainer !== document.body && gridContainer.id !== 'app') {
                        const text = (gridContainer.textContent || '').toUpperCase();
                        if (text.includes('STARTUP COMMAND') && text.includes('DOCKER IMAGE') && !text.includes('VARIABLES')) {
                            break;
                        }
                        gridContainer = gridContainer.parentElement;
                    }

                    if (gridContainer && gridContainer !== document.body) {
                        gridContainer.style.setProperty('display', 'flex', 'important');
                        gridContainer.style.setProperty('flex-direction', 'column', 'important');
                        gridContainer.style.setProperty('width', '100%', 'important');
                        gridContainer.style.setProperty('gap', '1.5rem', 'important');

                        Array.from(gridContainer.children).forEach(child => {
                            child.style.setProperty('width', '100%', 'important');
                            child.style.setProperty('max-width', '100%', 'important');
                            child.style.setProperty('min-width', '100%', 'important');
                            child.style.setProperty('flex', '1 1 100%', 'important');
                            child.style.setProperty('grid-column', '1 / -1', 'important');
                            child.style.setProperty('display', 'block', 'important');
                        });
                    }
                }

                // 2. Ensure terminal code box is full-width, clean pre-wrap
                document.querySelectorAll('p.font-mono, p[class*="font-mono"], code').forEach(box => {
                    box.style.setProperty('width', '100%', 'important');
                    box.style.setProperty('min-width', '100%', 'important');
                    box.style.setProperty('max-width', '100%', 'important');
                    box.style.setProperty('box-sizing', 'border-box', 'important');
                    box.style.setProperty('display', 'block', 'important');
                    box.style.setProperty('white-space', 'pre-wrap', 'important');
                    box.style.setProperty('word-break', 'break-all', 'important');
                    box.style.setProperty('overflow-wrap', 'anywhere', 'important');
                });
            }

            function fixContextMenuColors(root) {
                const target = root || document.body;
                target.querySelectorAll('nav.react-contextmenu, .react-contextmenu, div.react-contextmenu, div[role="menu"], ul[role="menu"], div[class*="ContextMenu"]:not([class*="Row"]):not([class*="Container"]), div[class*="Menu___Styled"], div[class*="DropdownMenu__Menu"], div[class*="dropdown-menu"]:not([class*="btn"]):not([class*="toggle"])').forEach(menu => {
                    menu.style.setProperty('background', '#120e24', 'important');
                    menu.style.setProperty('background-color', '#120e24', 'important');
                    menu.style.setProperty('border', '1.5px solid #C268F2', 'important');
                    menu.style.setProperty('box-shadow', '0 16px 45px rgba(0, 0, 0, 0.95), 0 0 25px rgba(194, 104, 242, 0.35)', 'important');
                    menu.style.setProperty('min-width', '190px', 'important');
                    menu.style.setProperty('border-radius', '10px', 'important');
                    menu.querySelectorAll('.react-contextmenu-item, [role="menuitem"], button, a, li, span, p, div').forEach(child => {
                        if (child.tagName === 'SVG' || child.tagName === 'path') {
                            child.style.setProperty('color', '#C268F2', 'important');
                            child.style.setProperty('stroke', '#C268F2', 'important');
                            child.style.setProperty('fill', 'currentColor', 'important');
                        } else if (child.children.length === 0 || child.textContent.trim().length > 0) {
                            child.style.setProperty('color', '#ffffff', 'important');
                            child.style.setProperty('opacity', '1', 'important');
                            child.style.setProperty('visibility', 'visible', 'important');
                        }
                    });
                });

                // Strictly ensure 3-dots action buttons and their wrappers in table rows are plain and borderless
                target.querySelectorAll('div[class*="FileObjectRow"] button, div[class*="file_row"] button, div[class*="FileObjectRow"] div[class*="DropdownMenu"], div[class*="FileObjectRow"] div[class*="FileDropdownMenu"], div[class*="file_row"] div[class*="DropdownMenu"], div[class*="style-module_HHpjDvv7"] button, button:has(svg[data-icon="ellipsis-h"]), button:has(svg.fa-ellipsis-h), button:has(svg[class*="ellipsis"])').forEach(btn => {
                    if (!btn.getAttribute('role') || btn.getAttribute('role') !== 'menu') {
                        btn.style.setProperty('border', 'none', 'important');
                        btn.style.setProperty('border-width', '0', 'important');
                        btn.style.setProperty('outline', 'none', 'important');
                        btn.style.setProperty('box-shadow', 'none', 'important');
                        btn.style.setProperty('background', 'transparent', 'important');
                        btn.style.setProperty('background-color', 'transparent', 'important');
                        btn.style.setProperty('min-width', '0', 'important');
                        btn.style.setProperty('width', 'auto', 'important');
                        btn.style.setProperty('padding', '4px 6px', 'important');
                    }
                });
            }

            function onNavigate() {
                sanitizePterodactylText(document.body);
                fixStartupLayout();
                fixContextMenuColors(document.body);
                injectDomainManager();
                initCustomSelects();
                initFileManagerImagePreview();
                syncToggles();
                enforceVpsIpDisplay();
                initMarkdownPreview();
            }

            window.addEventListener('popstate', onNavigate);
            window.addEventListener('np:locationchange', onNavigate);

            setInterval(onNavigate, 120);

            const bodyObserver = new MutationObserver((mutations) => {
                mutations.forEach(m => {
                    m.addedNodes.forEach(node => {
                        if (node.nodeType === 1) {
                            fixContextMenuColors(node);
                        }
                    });
                });
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
