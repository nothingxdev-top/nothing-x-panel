#!/bin/bash

set -e

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

export RM_PANEL=false
export RM_WINGS=false

# --------------- Main functions --------------- #

main() {
  welcome ""

  if [ -d "/var/www/pterodactyl" ]; then
    output "Panel installation detected."
    select_menu "Remove Nothing Panel?" \
      "No - Keep the panel" \
      "Yes - Remove the panel"
    [ "$MENU_RESULT" == "1" ] && RM_PANEL=true
  fi

  if [ -d "/etc/pterodactyl" ]; then
    output "Wings installation detected."
    warning "Removing Wings will delete ALL game servers and their data!"
    select_menu "Remove Wings (daemon)?" \
      "No - Keep Wings" \
      "Yes - Remove Wings and all servers"
    [ "$MENU_RESULT" == "1" ] && RM_WINGS=true
  fi

  if [ "$RM_PANEL" == false ] && [ "$RM_WINGS" == false ]; then
    error "Nothing to uninstall!"
    exit 1
  fi

  summary

  printf "  ${COLOR_BOLD}→ ${COLOR_NC}Continue with uninstallation? (y/N): "
  read -r CONFIRM
  if is_yes "$CONFIRM"; then
    run_installer "uninstall"
  else
    error "Uninstallation aborted."
    exit 1
  fi
}

summary() {
  echo ""
  echo -e "  ${COLOR_CYAN}╔══════════════════════════════════════════════════════════════╗${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}  ${COLOR_WHITE}${COLOR_BOLD}Uninstall Summary${COLOR_NC}                                        ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}╠══════════════════════════════════════════════════════════════╣${COLOR_NC}"
  printf "  ${COLOR_CYAN}║${COLOR_NC}  %-20s : %-36s${COLOR_CYAN}║${COLOR_NC}\n" "Remove Panel"  "$RM_PANEL"
  printf "  ${COLOR_CYAN}║${COLOR_NC}  %-20s : %-36s${COLOR_CYAN}║${COLOR_NC}\n" "Remove Wings"  "$RM_WINGS"
  echo -e "  ${COLOR_CYAN}╚══════════════════════════════════════════════════════════════╝${COLOR_NC}"
  echo ""
}

goodbye() {
  echo ""
  echo -e "  ${COLOR_CYAN}╔══════════════════════════════════════════════════════════════╗${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}  ${COLOR_GREEN}${COLOR_BOLD}✔ Uninstallation Complete!${COLOR_NC}                               ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}╚══════════════════════════════════════════════════════════════╝${COLOR_NC}"
  echo ""
  [ "$RM_PANEL" == true ] && output "  ✔ Panel has been removed."
  [ "$RM_WINGS" == true ] && output "  ✔ Wings and all server data has been removed."
  output ""
  output "  Thank you for using Nothing Panel."
  echo ""
}

main
goodbye
