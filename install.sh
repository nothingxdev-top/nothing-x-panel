#!/bin/bash

set -e -o pipefail

# ── Pipe fix: when run via "curl | bash", download and re-exec as a file with /dev/tty ──
# This allows interactive prompts to work properly even when piped.
if [ ! -t 0 ] && [ -z "$NP_REEXEC" ]; then
  TMPFILE=$(mktemp /tmp/np-install.XXXXXX.sh)
  trap 'rm -f "$TMPFILE"' EXIT
  curl -fsSL "https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel/master/install.sh" -o "$TMPFILE"
  chmod +x "$TMPFILE"
  if [ -e /dev/tty ]; then
    NP_REEXEC=1 exec bash "$TMPFILE" "$@" < /dev/tty
  else
    NP_REEXEC=1 exec bash "$TMPFILE" "$@"
  fi
fi

######################################################################################
#                                                                                    #
# Project 'nothing-panel-installer'                                                  #
#                                                                                    #
# Copyright (C) 2018 - 2026, Nothing Panel                                           #
#                                                                                    #
#   This program is free software: you can redistribute it and/or modify             #
#   it under the terms of the GNU General Public License as published by             #
#   the Free Software Foundation, either version 3 of the License, or                #
#   (at your option) any later version.                                              #
#                                                                                    #
######################################################################################

export GITHUB_SOURCE="master"
export SCRIPT_RELEASE="v1.0.0"
export GITHUB_BASE_URL="https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel"

LOG_PATH="/var/log/nothing-panel-installer.log"

# check for curl
if ! [ -x "$(command -v curl)" ]; then
  echo "* curl is required in order for this script to work."
  echo "* install using apt (Debian and derivatives) or yum/dnf (CentOS)"
  exit 1
fi

# Always remove lib.sh, before downloading it
[ -f /tmp/lib.sh ] && rm -rf /tmp/lib.sh
curl -fsSL -o /tmp/lib.sh "$GITHUB_BASE_URL"/master/lib/lib.sh
# shellcheck source=lib/lib.sh
source /tmp/lib.sh

execute() {
  if [[ -n $2 ]]; then
    INSTALL_SETTINGS=$(mktemp)
    export INSTALL_SETTINGS
    trap 'rm -f "$INSTALL_SETTINGS"' EXIT
  fi
  echo -e "\n\n* nothing-panel-installer $(date) \n\n" >>$LOG_PATH

  [[ "$1" == *"canary"* ]] && export GITHUB_SOURCE="master" && export SCRIPT_RELEASE="canary"
  update_lib_source
  run_ui "${1//_canary/}" |& tee -a $LOG_PATH

  if [[ -n $2 ]]; then
    echo ""
    echo -e "  ${COLOR_GREEN}✔${COLOR_NC} Installation of $1 completed."
    printf "  → Proceed to $2 installation? (y/N): "
    read -r CONFIRM
    if is_yes "$CONFIRM"; then
      execute "$2"
    else
      error "Installation of $2 aborted."
      exit 1
    fi
  fi
}

welcome ""

done=false
while [ "$done" == false ]; do

  select_menu "Nothing Panel Installer — What would you like to do?" \
    "Install Panel + Wings (Automatic 1-Click Setup - Recommended)" \
    "Install Panel on NAT VPS / IPv6 (via Cloudflare Tunnel - No Open Ports)" \
    "Install the Panel only" \
    "Install Wings (Game Server Node) only" \
    "Update Panel (Preserve Data & Database)" \
    "Domain Manager (np-domain - Map domain to port)" \
    "Rebrand / Apply Nothing UI Theme & Logo" \
    "Uninstall Panel or Wings" \
    "──────── Advanced / Canary ────────" \
    "Install Panel (canary/dev version)" \
    "Install Wings (canary/dev version)" \
    "Install Panel + Wings (canary/dev)" \
    "Uninstall using canary version"

  actions=(
    "panel"
    "panel_nat"
    "panel"
    "wings"
    "update"
    "domain_manager"
    "rebrand"
    "uninstall"
    ""
    "panel_canary"
    "wings_canary"
    "panel_canary;wings_canary"
    "uninstall_canary"
  )

  # Skip the separator option
  if [ "$MENU_RESULT" == "8" ]; then
    continue
  fi

  action="${actions[$MENU_RESULT]}"

  if [ -z "$action" ]; then
    continue
  fi

  if [ "$action" == "panel_nat" ]; then
    export USE_CLOUDFLARE_TUNNEL=true
    execute "panel"
    continue
  fi

  if [ "$action" == "update" ]; then
    curl -fsSL "$GITHUB_URL/scripts/update-panel.sh" | bash
    exit 0
  fi

  if [ "$action" == "domain_manager" ]; then
    if [ -f "/usr/local/bin/np-domain" ]; then
      /usr/local/bin/np-domain
    else
      curl -fsSL "$GITHUB_URL/scripts/np-domain.sh" | bash
    fi
    exit 0
  fi

  if [ "$action" == "rebrand" ]; then
    curl -fsSL "$GITHUB_URL/scripts/brand-panel.sh" | bash
    exit 0
  fi

  done=true
  IFS=";" read -r i1 i2 <<<"${action}"
  execute "$i1" "$i2"
done

# Remove lib.sh, so next time the script is run the newest version is downloaded.
rm -rf /tmp/lib.sh
