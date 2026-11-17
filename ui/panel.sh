#!/bin/bash

set -e -o pipefail

######################################################################################
#                                                                                    #
# Project 'nothing-panel-installer'                                                  #
#                                                                                    #
# Copyright (C) 2018 - 2026, Nothing Panel                                           #
#                                                                                    #
######################################################################################

# Check if script is loaded, load if not or fail otherwise.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh || source <(curl -sSL "$GITHUB_BASE_URL/$GITHUB_SOURCE"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* ERROR: Could not load lib script" && exit 1
fi

# ------------------ Variables ----------------- #

# Domain name / IP
export FQDN=""

# Default MySQL credentials
export MYSQL_DB=""
export MYSQL_USER=""
export MYSQL_PASSWORD=""

# Environment
export timezone=""
export email=""
export telemetry=""

# Initial admin account
export user_email=""
export user_username=""
export user_firstname=""
export user_lastname=""
export user_password=""

# Assume SSL, will fetch different config if true
export ASSUME_SSL=false
export CONFIGURE_LETSENCRYPT=false

# Firewall
export CONFIGURE_FIREWALL=false

if [ -z "${INSTALL_SETTINGS:-}" ]; then
  INSTALL_SETTINGS=$(mktemp)
  export INSTALL_SETTINGS
  trap 'rm -f "$INSTALL_SETTINGS"' EXIT
fi
check_install_settings

# ------------ User input functions ------------ #

ask_assume_ssl() {
  output "Let's Encrypt is not going to be automatically configured by this script (user opted out)."
  output "You can assume SSL to use an nginx HTTPS configuration with your own certificate."
  output "Place your certificate at /etc/ssl/$FQDN.pem and its private key at /etc/ssl/$FQDN.key before starting nginx."
  output "After installation, run nginx -t && systemctl restart nginx once both certificate files are in place."

  select_menu "Assume SSL with your own certificate?" \
    "No - Proceed without SSL" \
    "Yes - Assume SSL (I will place certificates manually)"

  [ "$MENU_RESULT" == "1" ] && ASSUME_SSL=true
  true
}

ask_telemetry() {
  output "Nothing Panel may collect anonymous usage statistics to help improve the software."

  select_menu "Enable anonymous telemetry data?" \
    "No - Disable telemetry" \
    "Yes - Enable anonymous telemetry (Recommended)"

  if [ "$MENU_RESULT" == "1" ]; then
    telemetry="true"
  else
    telemetry="false"
  fi
}

check_FQDN_SSL() {
  SSL_AVAILABLE=false
  if ! is_ip_address "$FQDN" && [ "$FQDN" != localhost ]; then
    SSL_AVAILABLE=true
  else
    warning "Let's Encrypt will not be available for IP addresses."
    output "To use Let's Encrypt, you must use a valid domain name."
  fi
}

main() {
  # check if we can detect an already existing installation
  if [ -d "/var/www/pterodactyl" ]; then
    error "An existing Panel installation was detected. This script only supports fresh installations."
    output "You can remove existing installations by running the uninstall script."
    output "Upgrade guide: https://docs.pterodactyl.io/v2/upgrading/upgrading-from-v1"
    exit 1
  fi

  ask_panel_version
  welcome "panel"

  check_os_x86_64

  # ─────────────────────────────────────────────
  draw_box "Database Configuration"
  output "These credentials are used for communication between MySQL"
  output "and the panel. The database will be created automatically."
  echo ""

  while true; do
    required_input MYSQL_DB "Database name (panel): " "" "panel"
    valid_database_identifier "$MYSQL_DB" && break
  done

  while true; do
    required_input MYSQL_USER "Database username (nothing_panel): " "" "nothing_panel"
    valid_database_identifier "$MYSQL_USER" && break
  done

  rand_pw=$(gen_passwd 64)
  while true; do
    password_input MYSQL_PASSWORD "Password (press enter to use randomly generated password): " "MySQL password cannot be empty" "$rand_pw"
    valid_panel_database_password "$MYSQL_PASSWORD" && break
  done

  # ─────────────────────────────────────────────
  draw_box "Timezone & Email"

  timezone_list=$(curl -fsSL "$GITHUB_URL/configs/valid_timezones.txt")
  readarray -t valid_timezones <<<"$timezone_list"
  output "Full timezone list: $(hyperlink "https://www.php.net/manual/en/timezones.php")"
  echo ""

  while [ -z "$timezone" ]; do
    printf "  ${COLOR_BOLD}→ ${COLOR_NC}Select timezone [Asia/Kolkata]: "
    read -r timezone_input

    array_contains_element "$timezone_input" "${valid_timezones[@]}" && timezone="$timezone_input"
    [ -z "$timezone_input" ] && timezone="Asia/Kolkata"
    [ -n "$timezone" ] || error "Invalid timezone. Try again."
  done

  email_input email "Email for Let's Encrypt & panel notifications: " "Email cannot be empty or invalid"

  # ─────────────────────────────────────────────
  draw_box "Admin Account Setup"

  email_input user_email "Admin email [$email]: " "Email cannot be empty or invalid" "$email"
  while true; do
    required_input user_username "Admin username: " "Username cannot be empty"
    valid_admin_username "$user_username" && break
  done
  while true; do
    required_input user_firstname "First name: " "Name cannot be empty"
    valid_admin_name "$user_firstname" && break
  done
  while true; do
    required_input user_lastname "Last name: " "Name cannot be empty"
    valid_admin_name "$user_lastname" && break
  done
  while true; do
    password_input user_password "Admin password: " "Password cannot be empty"
    valid_admin_password "$user_password" && break
  done

  # ─────────────────────────────────────────────
  draw_box "Panel Domain / FQDN"

  while true; do
    printf "  ${COLOR_BOLD}→ ${COLOR_NC}Set the FQDN of this panel (e.g. panel.yourdomain.com): "
    read -r FQDN
    valid_hostname "$FQDN" && break
  done
  FQDN="${FQDN%.}"
  [[ "$FQDN" != *:* || "$FQDN" == '['*']' ]] || FQDN="[$FQDN]"

  # Check if SSL is available
  check_FQDN_SSL

  # Ask if firewall is needed
  ask_firewall CONFIGURE_FIREWALL

  # Only ask about SSL if it is available
  if [ "$SSL_AVAILABLE" == true ]; then
    ask_letsencrypt
    [ "$CONFIGURE_LETSENCRYPT" == false ] && ask_assume_ssl
  fi

  # verify FQDN if user has selected to assume SSL or configure Let's Encrypt
  if [ "$CONFIGURE_LETSENCRYPT" == true ] || [ "$ASSUME_SSL" == true ]; then
    verify_fqdn "$FQDN"
  fi

  # ask telemetry preference
  ask_telemetry

  # summary
  summary

  # confirm installation
  echo ""
  printf "  ${COLOR_BOLD}→ ${COLOR_NC}Initial configuration completed. Continue with installation? (y/N): "
  read -r CONFIRM
  if is_yes "$CONFIRM"; then
    run_installer "panel"
    load_install_settings
  else
    error "Installation aborted."
    exit 1
  fi
}

summary() {
  echo ""
  echo -e "  ${COLOR_CYAN}╔══════════════════════════════════════════════════════════════╗${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}  ${COLOR_WHITE}${COLOR_BOLD}Installation Summary${COLOR_NC}                                      ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}╠══════════════════════════════════════════════════════════════╣${COLOR_NC}"
  printf "  ${COLOR_CYAN}║${COLOR_NC}  %-20s : %-36s${COLOR_CYAN}║${COLOR_NC}\n" "Panel Version"    "Nothing Panel $PTERODACTYL_PANEL_VERSION"
  printf "  ${COLOR_CYAN}║${COLOR_NC}  %-20s : %-36s${COLOR_CYAN}║${COLOR_NC}\n" "OS"               "$OS $OS_VER"
  printf "  ${COLOR_CYAN}║${COLOR_NC}  %-20s : %-36s${COLOR_CYAN}║${COLOR_NC}\n" "Database"         "$MYSQL_DB"
  printf "  ${COLOR_CYAN}║${COLOR_NC}  %-20s : %-36s${COLOR_CYAN}║${COLOR_NC}\n" "DB User"          "$MYSQL_USER"
  printf "  ${COLOR_CYAN}║${COLOR_NC}  %-20s : %-36s${COLOR_CYAN}║${COLOR_NC}\n" "DB Password"      "(hidden)"
  printf "  ${COLOR_CYAN}║${COLOR_NC}  %-20s : %-36s${COLOR_CYAN}║${COLOR_NC}\n" "Timezone"         "$timezone"
  printf "  ${COLOR_CYAN}║${COLOR_NC}  %-20s : %-36s${COLOR_CYAN}║${COLOR_NC}\n" "Email"            "$email"
  printf "  ${COLOR_CYAN}║${COLOR_NC}  %-20s : %-36s${COLOR_CYAN}║${COLOR_NC}\n" "Admin User"       "$user_username"
  printf "  ${COLOR_CYAN}║${COLOR_NC}  %-20s : %-36s${COLOR_CYAN}║${COLOR_NC}\n" "Admin Password"   "(hidden)"
  printf "  ${COLOR_CYAN}║${COLOR_NC}  %-20s : %-36s${COLOR_CYAN}║${COLOR_NC}\n" "Panel FQDN"       "$FQDN"
  printf "  ${COLOR_CYAN}║${COLOR_NC}  %-20s : %-36s${COLOR_CYAN}║${COLOR_NC}\n" "Firewall"         "$CONFIGURE_FIREWALL"
  printf "  ${COLOR_CYAN}║${COLOR_NC}  %-20s : %-36s${COLOR_CYAN}║${COLOR_NC}\n" "Let's Encrypt"    "$CONFIGURE_LETSENCRYPT"
  printf "  ${COLOR_CYAN}║${COLOR_NC}  %-20s : %-36s${COLOR_CYAN}║${COLOR_NC}\n" "Assume SSL"       "$ASSUME_SSL"
  printf "  ${COLOR_CYAN}║${COLOR_NC}  %-20s : %-36s${COLOR_CYAN}║${COLOR_NC}\n" "Telemetry"        "$telemetry"
  echo -e "  ${COLOR_CYAN}╚══════════════════════════════════════════════════════════════╝${COLOR_NC}"
  echo ""
}

goodbye() {
  echo ""
  echo -e "  ${COLOR_CYAN}╔══════════════════════════════════════════════════════════════╗${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}  ${COLOR_GREEN}${COLOR_BOLD}✔ Nothing Panel Installation Complete!${COLOR_NC}                  ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}╚══════════════════════════════════════════════════════════════╝${COLOR_NC}"
  echo ""

  [ "$CONFIGURE_LETSENCRYPT" == true ] && output "  🌐 Your panel is accessible at: $(hyperlink "https://$FQDN")"
  if [ "$ASSUME_SSL" == true ] && [ "$CONFIGURE_LETSENCRYPT" == false ]; then
    output "  ⚠  SSL assumed but not auto-configured. Place certificates at:"
    output "     /etc/ssl/$FQDN.pem  and  /etc/ssl/$FQDN.key"
    output "     Then run: nginx -t && systemctl restart nginx"
  fi
  [ "$ASSUME_SSL" == false ] && [ "$CONFIGURE_LETSENCRYPT" == false ] && output "  🌐 Your panel is accessible at: $(hyperlink "http://$FQDN")"

  echo ""
  output "  Web server: nginx on $OS"
  [ "$CONFIGURE_FIREWALL" == false ] && echo -e "  ${COLOR_RED}⚠  Note${COLOR_NC}: Make sure ports 80 and 443 are open in your firewall!"
  echo ""

  # Offer domain management after install
  if command -v nginx >/dev/null 2>&1; then
    select_menu "Would you like to set up domain mappings for server ports?" \
      "No - Skip domain management" \
      "Yes - Configure domain → port mappings now"

    if [ "$MENU_RESULT" == "1" ]; then
      domain_management_menu "$email"
    fi
  fi

  echo ""
  output "  Thank you for using Nothing Panel!"
  echo ""
}

# run script
main
goodbye
