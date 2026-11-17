#!/bin/bash

######################################################################################
#                                                                                    #
#  Nothing Panel — Domain Manager (np-domain)                                        #
#                                                                                    #
#  Manage domain → port mappings with automatic SSL for your game servers.           #
#                                                                                    #
#  Usage:                                                                            #
#    np-domain                     → Interactive menu                                #
#    np-domain add <domain> <port> → Add domain mapping                             #
#    np-domain remove <port>       → Remove domain mapping                           #
#    np-domain list                → List all mappings                               #
#    np-domain ssl <domain>        → Get SSL for existing domain                     #
#                                                                                    #
######################################################################################

set -e

# Colors
COLOR_YELLOW=$'\033[1;33m'
COLOR_GREEN=$'\033[0;32m'
COLOR_RED=$'\033[0;31m'
COLOR_BLUE=$'\033[0;34m'
COLOR_CYAN=$'\033[0;36m'
COLOR_WHITE=$'\033[1;37m'
COLOR_BOLD=$'\033[1m'
COLOR_NC=$'\033[0m'

# Check root
if [[ $EUID -ne 0 ]]; then
  echo -e "${COLOR_RED}✖ ERROR${COLOR_NC}: This script must be run as root (sudo np-domain)"
  exit 1
fi

output() { printf '  %s\n' "$1"; }
success() { echo -e "  ${COLOR_GREEN}✔ SUCCESS${COLOR_NC}: $1"; }
error()   { echo -e "  ${COLOR_RED}✖ ERROR${COLOR_NC}: $1" >&2; }
warning() { echo -e "  ${COLOR_YELLOW}⚠ WARNING${COLOR_NC}: $1"; }

valid_hostname() {
  [[ ${#1} -le 253 && ! "$1" =~ ^[0-9.]+$ && "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.?$ ]]
}

email_regex="^[A-Za-z0-9_+-]+(\.[A-Za-z0-9_+-]+)*@([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$"
valid_email() { [[ "$1" =~ ${email_regex} ]]; }

select_menu() {
  local title="$1"; shift
  local options=("$@")
  local count=${#options[@]}
  echo ""
  echo -e "  ${COLOR_CYAN}┌──────────────────────────────────────────────────────────────┐${COLOR_NC}"
  printf "  ${COLOR_CYAN}│${COLOR_NC}  ${COLOR_WHITE}${COLOR_BOLD}%-60s${COLOR_NC}${COLOR_CYAN}│${COLOR_NC}\n" "$title"
  echo -e "  ${COLOR_CYAN}├──────────────────────────────────────────────────────────────┤${COLOR_NC}"
  for i in "${!options[@]}"; do
    printf "  ${COLOR_CYAN}│${COLOR_NC}  ${COLOR_YELLOW}[%d]${COLOR_NC} %-56s${COLOR_CYAN}│${COLOR_NC}\n" "$i" "${options[$i]}"
  done
  echo -e "  ${COLOR_CYAN}└──────────────────────────────────────────────────────────────┘${COLOR_NC}"
  echo ""
  local valid=false
  while [ "$valid" == false ]; do
    printf "  ${COLOR_BOLD}→ Select [0-$((count-1))]: ${COLOR_NC}"
    read -r MENU_RESULT
    if [[ "$MENU_RESULT" =~ ^[0-9]+$ ]] && (( MENU_RESULT >= 0 && MENU_RESULT < count )); then
      valid=true
    else
      error "Invalid option."
    fi
  done
}

print_banner() {
  clear
  echo ""
  echo -e "${COLOR_CYAN}  ╔════════════════════════════════════════════════╗${COLOR_NC}"
  echo -e "${COLOR_CYAN}  ║${COLOR_NC}  ${COLOR_WHITE}${COLOR_BOLD}Nothing Panel — Domain Manager${COLOR_NC}               ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "${COLOR_CYAN}  ║${COLOR_NC}  Manage domain → port SSL mappings              ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "${COLOR_CYAN}  ╚════════════════════════════════════════════════╝${COLOR_NC}"
  echo ""
}

# ─── Core Functions ──────────────────────────────────────────

add_domain_mapping() {
  local domain="$1"
  local port="$2"
  local ssl="${3:-false}"
  local email_addr="${4:-}"

  if ! command -v nginx >/dev/null 2>&1; then
    error "nginx is not installed. Install Nothing Panel first."
    exit 1
  fi

  local conf_dir="/etc/nginx/sites-available"
  local enabled_dir="/etc/nginx/sites-enabled"
  mkdir -p "$conf_dir" "$enabled_dir"

  local conf_file="$conf_dir/np-port-${port}.conf"
  local enabled_link="$enabled_dir/np-port-${port}.conf"

  output "Creating nginx proxy config for $domain → port $port ..."

  cat > "$conf_file" <<NGINXCONF
# Nothing Panel — Domain Port Mapping
# Domain: $domain
# Port: $port
# Created: $(date)

server {
    listen 80;
    listen [::]:80;
    server_name ${domain};

    location / {
        proxy_pass http://127.0.0.1:${port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }

    # Nothing Panel domain mapping
    access_log /var/log/nginx/np-port-${port}.access.log;
    error_log  /var/log/nginx/np-port-${port}.error.log error;
}
NGINXCONF

  ln -sf "$conf_file" "$enabled_link"

  if nginx -t 2>/dev/null; then
    systemctl reload nginx
    success "nginx config created for $domain → port $port"
  else
    error "nginx config test failed! Check /etc/nginx/sites-available/np-port-${port}.conf"
    rm -f "$conf_file" "$enabled_link"
    exit 1
  fi

  if [ "$ssl" == "true" ]; then
    if ! command -v certbot >/dev/null 2>&1; then
      output "Installing certbot..."
      apt-get install -y certbot python3-certbot-nginx 2>/dev/null || \
        dnf install -y certbot python3-certbot-nginx 2>/dev/null || \
        { error "Could not install certbot. Install manually and run: np-domain ssl $domain"; exit 1; }
    fi

    if [ -z "$email_addr" ]; then
      while true; do
        printf "  ${COLOR_BOLD}→ ${COLOR_NC}Email for Let's Encrypt: "
        read -r email_addr
        valid_email "$email_addr" && break
        error "Invalid email address."
      done
    fi

    output "Obtaining SSL certificate for $domain ..."
    if certbot --nginx --redirect --no-eff-email --email "$email_addr" -d "$domain"; then
      success "SSL certificate obtained for $domain!"
      output "  🔒 Access your server at: https://$domain"
    else
      warning "SSL certificate could not be obtained."
      output "  Make sure:"
      output "  1. DNS for $domain points to this server's IP"
      output "  2. Port 80 and 443 are open"
      output "  Retry later: np-domain ssl $domain"
    fi
  else
    output "  🌐 Access your server at: http://$domain"
    output "  (Run 'np-domain ssl $domain' to add SSL later)"
  fi
}

remove_domain_mapping() {
  local port="$1"
  local conf_file="/etc/nginx/sites-available/np-port-${port}.conf"
  local enabled_link="/etc/nginx/sites-enabled/np-port-${port}.conf"

  if [ ! -f "$conf_file" ]; then
    error "No domain mapping found for port $port"
    exit 1
  fi

  local domain
  domain=$(grep -oP 'server_name \K[^;]+' "$conf_file" 2>/dev/null | xargs || echo "unknown")

  output "Removing domain mapping: $domain → port $port ..."

  # Remove certbot cert if exists
  if [ -d "/etc/letsencrypt/live/$domain" ]; then
    certbot delete --cert-name "$domain" --non-interactive 2>/dev/null && \
      output "SSL certificate removed." || \
      warning "Could not remove SSL certificate. Remove manually with: certbot delete --cert-name $domain"
  fi

  rm -f "$conf_file" "$enabled_link"

  if nginx -t 2>/dev/null; then
    systemctl reload nginx
    success "Domain mapping for port $port removed!"
  fi
}

get_ssl_for_domain() {
  local domain="$1"

  if ! command -v certbot >/dev/null 2>&1; then
    error "certbot is not installed."
    exit 1
  fi

  # Find which port conf this domain belongs to
  local conf_file
  conf_file=$(grep -rl "server_name ${domain}" /etc/nginx/sites-available/ 2>/dev/null | head -1 || true)

  if [ -z "$conf_file" ]; then
    error "No nginx config found for domain $domain. Run 'np-domain add' first."
    exit 1
  fi

  local email_addr
  while true; do
    printf "  ${COLOR_BOLD}→ ${COLOR_NC}Email for Let's Encrypt: "
    read -r email_addr
    valid_email "$email_addr" && break
    error "Invalid email."
  done

  certbot --nginx --redirect --no-eff-email --email "$email_addr" -d "$domain" && \
    success "SSL certificate obtained for $domain! Access: https://$domain" || \
    error "SSL setup failed. Check DNS and try again."
}

list_mappings() {
  echo ""
  echo -e "  ${COLOR_CYAN}╔══════════════════════════════════════════════════════════════╗${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}  ${COLOR_WHITE}${COLOR_BOLD}Active Domain → Port Mappings${COLOR_NC}                            ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}╠══════════════════════════════════════════════════════════════╣${COLOR_NC}"

  local found=false
  local count=0
  for conf in /etc/nginx/sites-available/np-port-*.conf; do
    [ -f "$conf" ] || continue
    found=true
    count=$((count + 1))
    local prt domain ssl_status
    prt=$(echo "$conf" | grep -oP 'np-port-\K[0-9]+')
    domain=$(grep -oP 'server_name \K[^;]+' "$conf" 2>/dev/null | xargs || echo "unknown")
    # Check SSL
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
      ssl_status="${COLOR_GREEN}✔ SSL${COLOR_NC}"
    else
      ssl_status="${COLOR_YELLOW}✗ No SSL${COLOR_NC}"
    fi
    printf "  ${COLOR_CYAN}║${COLOR_NC}  Port %-6s → %-30s [%b]  ${COLOR_CYAN}║${COLOR_NC}\n" "$prt" "$domain" "$ssl_status"
  done

  if [ "$found" == "false" ]; then
    echo -e "  ${COLOR_CYAN}║${COLOR_NC}  No domain mappings configured yet.                         ${COLOR_CYAN}║${COLOR_NC}"
  fi

  echo -e "  ${COLOR_CYAN}╠══════════════════════════════════════════════════════════════╣${COLOR_NC}"
  printf "  ${COLOR_CYAN}║${COLOR_NC}  Total: %-53s${COLOR_CYAN}║${COLOR_NC}\n" "$count mapping(s)"
  echo -e "  ${COLOR_CYAN}╚══════════════════════════════════════════════════════════════╝${COLOR_NC}"
  echo ""
}

# ─── Interactive Menu ─────────────────────────────────────────

interactive_menu() {
  while true; do
    print_banner
    list_mappings

    select_menu "What would you like to do?" \
      "Exit" \
      "Add domain → port mapping" \
      "Add domain + SSL → port mapping" \
      "Remove domain mapping" \
      "Get SSL for existing domain" \
      "List all mappings"

    case "$MENU_RESULT" in
    0) echo ""; output "Goodbye!"; echo ""; exit 0 ;;
    1)
      printf "  ${COLOR_BOLD}→ ${COLOR_NC}Domain (e.g. game.yourdomain.com): "
      read -r dm_domain
      printf "  ${COLOR_BOLD}→ ${COLOR_NC}Port number: "
      read -r dm_port
      add_domain_mapping "$dm_domain" "$dm_port" "false"
      read -rp "  Press Enter to continue..."
      ;;
    2)
      printf "  ${COLOR_BOLD}→ ${COLOR_NC}Domain (e.g. game.yourdomain.com): "
      read -r dm_domain
      printf "  ${COLOR_BOLD}→ ${COLOR_NC}Port number: "
      read -r dm_port
      add_domain_mapping "$dm_domain" "$dm_port" "true"
      read -rp "  Press Enter to continue..."
      ;;
    3)
      printf "  ${COLOR_BOLD}→ ${COLOR_NC}Port number to remove: "
      read -r rm_port
      remove_domain_mapping "$rm_port"
      read -rp "  Press Enter to continue..."
      ;;
    4)
      printf "  ${COLOR_BOLD}→ ${COLOR_NC}Domain to get SSL for: "
      read -r ssl_domain
      get_ssl_for_domain "$ssl_domain"
      read -rp "  Press Enter to continue..."
      ;;
    5)
      list_mappings
      read -rp "  Press Enter to continue..."
      ;;
    esac
  done
}

# ─── CLI Mode ────────────────────────────────────────────────

case "${1:-}" in
add)
  if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
    error "Usage: np-domain add <domain> <port> [--ssl] [--email <email>]"
    exit 1
  fi
  domain_arg="$2"
  port_arg="$3"
  ssl_arg="false"
  email_arg=""
  shift 3
  while [ $# -gt 0 ]; do
    case "$1" in
    --ssl) ssl_arg="true" ;;
    --email) email_arg="$2"; shift ;;
    esac
    shift
  done
  add_domain_mapping "$domain_arg" "$port_arg" "$ssl_arg" "$email_arg"
  ;;
remove)
  [ -z "${2:-}" ] && { error "Usage: np-domain remove <port>"; exit 1; }
  remove_domain_mapping "$2"
  ;;
list)
  list_mappings
  ;;
ssl)
  [ -z "${2:-}" ] && { error "Usage: np-domain ssl <domain>"; exit 1; }
  get_ssl_for_domain "$2"
  ;;
"")
  interactive_menu
  ;;
*)
  echo ""
  output "Nothing Panel — Domain Manager"
  output ""
  output "Usage:"
  output "  np-domain                           Interactive menu"
  output "  np-domain add <domain> <port>       Add domain → port mapping"
  output "  np-domain add <domain> <port> --ssl Add with SSL"
  output "  np-domain remove <port>             Remove mapping"
  output "  np-domain list                      List all mappings"
  output "  np-domain ssl <domain>              Get SSL for existing domain"
  echo ""
  ;;
esac
