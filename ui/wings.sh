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

# Install mariadb
export INSTALL_MARIADB=false

# Firewall
export CONFIGURE_FIREWALL=false

# SSL (Let's Encrypt)
export CONFIGURE_LETSENCRYPT=false
export FQDN=""
export EMAIL=""

# Database host
export CONFIGURE_DBHOST=false
export CONFIGURE_DB_FIREWALL=false
export MYSQL_DBHOST_HOST="127.0.0.1"
export MYSQL_DBHOST_USER="nothing_panel_user"
export MYSQL_DBHOST_PASSWORD=""

# Read previous choices, made during panel installation, if exists
if [ -n "${INSTALL_SETTINGS:-}" ]; then
  if ! load_install_settings; then
    error "Invalid INSTALL_SETTINGS file."
    exit 1
  fi
fi

# ------------ User input functions ------------ #

ask_database_user() {
  select_menu "Configure database host user for game servers?" \
    "No - Skip database host configuration" \
    "Yes - Automatically configure a database host user"

  if [ "$MENU_RESULT" == "1" ]; then
    ask_database_external
    CONFIGURE_DBHOST=true
  fi
}

ask_database_external() {
  select_menu "Configure MySQL for external access?" \
    "No - Local access only (127.0.0.1)" \
    "Yes - Allow external MySQL access"

  if [ "$MENU_RESULT" == "1" ]; then
    while true; do
      printf "  ${COLOR_BOLD}→ ${COLOR_NC}Enter panel address (blank for any address): "
      read -r CONFIRM_DBEXTERNAL_HOST
      [ -z "$CONFIRM_DBEXTERNAL_HOST" ] && break
      valid_hostname "$CONFIRM_DBEXTERNAL_HOST" && break
    done
    if [ "$CONFIRM_DBEXTERNAL_HOST" == "" ]; then
      MYSQL_DBHOST_HOST="%"
    else
      MYSQL_DBHOST_HOST="${CONFIRM_DBEXTERNAL_HOST#[}"
      MYSQL_DBHOST_HOST="${MYSQL_DBHOST_HOST%]}"
    fi
    [ "$CONFIGURE_FIREWALL" == true ] && ask_database_firewall
    return 0
  fi
}

ask_database_firewall() {
  warning "Allowing incoming traffic to port 3306 (MySQL) can be a security risk!"

  select_menu "Allow incoming traffic to MySQL port 3306?" \
    "No - Keep MySQL port closed (Recommended)" \
    "Yes - Open port 3306 (I understand the risks)"

  if [ "$MENU_RESULT" == "1" ]; then
    CONFIGURE_DB_FIREWALL=true
  fi
}

####################
## MAIN FUNCTIONS ##
####################

main() {
  # check if we can detect an already existing installation
  if [ -d "/etc/nothing" ] || [ -d "/etc/pterodactyl" ]; then
    warning "Wings is already installed on this system!"
    select_menu "Wings already detected. Continue anyway?" \
      "No - Abort installation" \
      "Yes - Continue (may cause issues)"
    if [ "$MENU_RESULT" == "0" ]; then
      error "Installation aborted!"
      exit 1
    fi
  fi

  welcome "wings"

  check_virt

  echo ""
  echo -e "  ${COLOR_CYAN}╔══════════════════════════════════════════════════════════════╗${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}  ${COLOR_WHITE}${COLOR_BOLD}Wings — Game Server Node${COLOR_NC}                                 ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}╠══════════════════════════════════════════════════════════════╣${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}  This will install Docker and the Wings daemon.              ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}  After installation, create a Node in your panel and         ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}  place the config at /etc/nothing/config.yml                 ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}                                                              ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}  ${COLOR_YELLOW}⚠${COLOR_NC}  Wings will NOT start automatically after install.      ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}  ${COLOR_YELLOW}⚠${COLOR_NC}  Swap is NOT enabled by this script.                   ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}╚══════════════════════════════════════════════════════════════╝${COLOR_NC}"
  echo ""

  [ -s "${INSTALL_SETTINGS:-}" ] || ask_firewall CONFIGURE_FIREWALL

  ask_database_user

  if [ "$CONFIGURE_DBHOST" == true ]; then
    { type -P mariadb >/dev/null 2>&1 || type -P mysql >/dev/null 2>&1; } && HAS_MYSQL=true || HAS_MYSQL=false

    if [ "$HAS_MYSQL" == false ]; then
      INSTALL_MARIADB=true
    fi

    while true; do
      required_input MYSQL_DBHOST_USER "Database host username (nothing_panel_user): " "" "nothing_panel_user"
      valid_database_identifier "$MYSQL_DBHOST_USER" && break
    done

    password_input MYSQL_DBHOST_PASSWORD "Database host password: " "Password cannot be empty"
  fi

  if [ ! -s "${INSTALL_SETTINGS:-}" ]; then
    warning "Let's Encrypt cannot be used with an IP address! Use a valid FQDN (e.g. node.yourdomain.com)."
    ask_letsencrypt
  fi

  if [ "$CONFIGURE_LETSENCRYPT" == true ]; then
    while [ "$CONFIGURE_LETSENCRYPT" == true ] && [ -z "$FQDN" ]; do
      printf "  ${COLOR_BOLD}→ ${COLOR_NC}Set the FQDN for Let's Encrypt (node.yourdomain.com): "
      read -r FQDN

      ASK=false

      [ -z "$FQDN" ] && error "FQDN cannot be empty" && continue
      if ! valid_hostname "$FQDN"; then
        FQDN=""
        continue
      fi
      if is_ip_address "$FQDN" || [ "$FQDN" == localhost ]; then
        error "Let's Encrypt requires a public hostname, not an IP address or localhost."
        FQDN=""
        continue
      fi
      FQDN="${FQDN%.}"
      verify_fqdn "$FQDN" || ASK=true

      [ "$ASK" == true ] && FQDN=""
      if [ "$ASK" == true ]; then
        select_menu "Still configure HTTPS with Let's Encrypt?" \
          "No - Skip SSL" \
          "Yes - Try Let's Encrypt anyway"
        [ "$MENU_RESULT" == "0" ] && CONFIGURE_LETSENCRYPT=false && FQDN=""
      fi
    done
  fi

  if [ "$CONFIGURE_LETSENCRYPT" == true ] && ! valid_email "$EMAIL"; then
    email_input EMAIL "Email for Let's Encrypt: " "Email cannot be empty or invalid"
  fi

  echo ""
  printf "  ${COLOR_BOLD}→ ${COLOR_NC}Proceed with Wings installation? (y/N): "
  read -r CONFIRM
  if is_yes "$CONFIRM"; then
    run_installer "wings"
  else
    error "Installation aborted."
    exit 1
  fi
}

function goodbye {
  echo ""
  echo -e "  ${COLOR_CYAN}╔══════════════════════════════════════════════════════════════╗${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}  ${COLOR_GREEN}${COLOR_BOLD}✔ Wings Installation Complete!${COLOR_NC}                           ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}╠══════════════════════════════════════════════════════════════╣${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}  Next steps:                                                 ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}  1. Create a Node in your Nothing Panel                      ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}  2. Copy the config to /etc/nothing/config.yml               ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}     (or use the auto-deploy button in your panel)            ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}  3. Test Wings manually:                                     ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}       sudo wings                                             ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}  4. Start Wings as a service:                               ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}       systemctl start wings                                  ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}╚══════════════════════════════════════════════════════════════╝${COLOR_NC}"
  echo ""
  echo -e "  ${COLOR_YELLOW}⚠${COLOR_NC}  Enable swap for Docker! (see documentation for details)"
  [ "$CONFIGURE_FIREWALL" == false ] && echo -e "  ${COLOR_RED}⚠${COLOR_NC}  Ports 8080 and 2022 must be open in your firewall!"
  echo ""

  # ─── Domain Management After Wings Install ───
  if command -v nginx >/dev/null 2>&1; then
    echo ""
    echo -e "  ${COLOR_CYAN}╔══════════════════════════════════════════════════════════════╗${COLOR_NC}"
    echo -e "  ${COLOR_CYAN}║${COLOR_NC}  ${COLOR_WHITE}${COLOR_BOLD}Port → Domain Mapping${COLOR_NC}                                    ${COLOR_CYAN}║${COLOR_NC}"
    echo -e "  ${COLOR_CYAN}╠══════════════════════════════════════════════════════════════╣${COLOR_NC}"
    echo -e "  ${COLOR_CYAN}║${COLOR_NC}  You can assign domains to your game server ports.          ${COLOR_CYAN}║${COLOR_NC}"
    echo -e "  ${COLOR_CYAN}║${COLOR_NC}  Example: game.yourdomain.com → Port 25565                  ${COLOR_CYAN}║${COLOR_NC}"
    echo -e "  ${COLOR_CYAN}║${COLOR_NC}  SSL certificates will be obtained automatically.            ${COLOR_CYAN}║${COLOR_NC}"
    echo -e "  ${COLOR_CYAN}╚══════════════════════════════════════════════════════════════╝${COLOR_NC}"
    echo ""

    select_menu "Set up domain → port mappings now?" \
      "No - Skip (I'll do it later via np-domain command)" \
      "Yes - Configure domain mappings now"

    if [ "$MENU_RESULT" == "1" ]; then
      local dm_email="${EMAIL:-}"
      [ -z "$dm_email" ] && email_input dm_email "Email for Let's Encrypt SSL: " "Email cannot be empty or invalid"
      domain_management_menu "$dm_email"
    fi
  fi

  output "Thank you for using Nothing Panel!"
  echo ""
}

# run script
main
goodbye
