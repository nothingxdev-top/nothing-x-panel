#!/bin/bash

set -e

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
#   This program is distributed in the hope that it will be useful,                  #
#   but WITHOUT ANY WARRANTY; without even the implied warranty of                   #
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                    #
#   GNU General Public License for more details.                                     #
#                                                                                    #
#   You should have received a copy of the GNU General Public License                #
#   along with this program.  If not, see <https://www.gnu.org/licenses/>.           #
#                                                                                    #
######################################################################################

# ------------------ Variables ----------------- #

# Versioning
export GITHUB_SOURCE=${GITHUB_SOURCE:-master}
export SCRIPT_RELEASE=${SCRIPT_RELEASE:-master}

# Pterodactyl versions (backend engine - kept for compatibility)
export PANEL_MAJOR_VERSION="${PANEL_MAJOR_VERSION:-1}"
export PTERODACTYL_PANEL_VERSION="${PTERODACTYL_PANEL_VERSION:-}"
export PTERODACTYL_PANEL_COMMIT="${PTERODACTYL_PANEL_COMMIT:-}"
export PTERODACTYL_WINGS_VERSION="${PTERODACTYL_WINGS_VERSION:-}"

# Path (export everything that is possible, doesn't matter that it exists already)
export PATH="$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"

# OS
export OS=""
export OS_VER_MAJOR=""
export CPU_ARCHITECTURE=""
export ARCH=""
export SUPPORTED=false

# download URLs
export PANEL_DL_URL="${PANEL_DL_URL:-}"
export WINGS_DL_BASE_URL="${WINGS_DL_BASE_URL:-}"
export MARIADB_URL="https://downloads.mariadb.com/MariaDB/mariadb_repo_setup"
export GITHUB_BASE_URL=${GITHUB_BASE_URL:-"https://raw.githubusercontent.com/nothingxdev-top/nothing-x-panel"}
export GITHUB_URL="$GITHUB_BASE_URL/$GITHUB_SOURCE"

# Colors
COLOR_YELLOW=$'\033[1;33m'
COLOR_GREEN=$'\033[0;32m'
COLOR_RED=$'\033[0;31m'
COLOR_BLUE=$'\033[0;34m'
COLOR_CYAN=$'\033[38;2;194;104;242m'
COLOR_MAGENTA=$'\033[0;35m'
COLOR_WHITE=$'\033[1;37m'
COLOR_BOLD=$'\033[1m'
COLOR_NC=$'\033[0m'

# email input validation regex
email_regex="^[A-Za-z0-9_+-]+(\.[A-Za-z0-9_+-]+)*@([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$"

# Charset used to generate random passwords
password_charset='A-Za-z0-9!#%&()*+,-./:;<=>?@[\]^_`{|}~'

# --------------------- Lib -------------------- #

lib_loaded() {
  return 0
}

# -------------- Visual functions -------------- #

output() {
  printf '  %s\n' "$1"
}

success() {
  echo ""
  echo -e "  ${COLOR_GREEN}✔ SUCCESS${COLOR_NC}: $1"
  echo ""
}

error() {
  echo ""
  printf '  %s✖ ERROR%s: %s\n' "$COLOR_RED" "$COLOR_NC" "$1" 1>&2
  echo ""
}

warning() {
  echo ""
  echo -e "  ${COLOR_YELLOW}⚠ WARNING${COLOR_NC}: $1"
  echo ""
}

print_brake() {
  local char="${2:-─}"
  printf '  '
  for ((n = 0; n < $1; n++)); do
    printf '%s' "$char"
  done
  echo ""
}

print_list() {
  print_brake 50
  for word in $1; do
    output "$word"
  done
  print_brake 50
  echo ""
}

hyperlink() {
  echo -e "\e]8;;${1}\a${1}\e]8;;\a"
}

# ----------- Custom Styled Box ------------ #

draw_box() {
  local title="$1"
  local width=60
  local title_len=${#title}
  local pad=$(( (width - title_len - 2) / 2 ))
  local pad_right=$(( width - title_len - 2 - pad ))

  echo ""
  echo -e "  ${COLOR_CYAN}╔$(printf '═%.0s' $(seq 1 $width))╗${COLOR_NC}"
  printf "  ${COLOR_CYAN}║${COLOR_NC}%${pad}s${COLOR_WHITE}${COLOR_BOLD} %s ${COLOR_NC}%${pad_right}s${COLOR_CYAN}║${COLOR_NC}\n" "" "$title" ""
  echo -e "  ${COLOR_CYAN}╚$(printf '═%.0s' $(seq 1 $width))╝${COLOR_NC}"
  echo ""
}

# ----------- Custom Select Menu ----------- #

# Custom Electric Purple theme color for Nothing Panel (#C268F2)
COLOR_PURPLE="\e[38;2;194;104;242m"
COLOR_PURPLE_BOLD="\e[1;38;2;194;104;242m"
COLOR_DARK_PURPLE="\e[38;2;138;43;226m"

# Usage: select_menu "title" "opt1" "opt2" ...
# Returns selected index in MENU_RESULT (0-based)
select_menu() {
  local title="$1"
  shift
  local options=("$@")
  local count=${#options[@]}

  echo ""
  echo -e "  ${COLOR_PURPLE}╔══════════════════════════════════════════════════════════════════╗${COLOR_NC}"
  printf "  ${COLOR_PURPLE}║${COLOR_NC}  ${COLOR_WHITE}${COLOR_BOLD}%-64s${COLOR_NC}${COLOR_PURPLE}║${COLOR_NC}\n" "$title"
  echo -e "  ${COLOR_PURPLE}╠══════════════════════════════════════════════════════════════════╣${COLOR_NC}"

  local selectable_indices=()
  for i in "${!options[@]}"; do
    local opt="${options[$i]}"
    # Check if option is a divider (starts with ─── or contains Advanced)
    if [[ "$opt" =~ ^[─-]+ ]] || [[ "$opt" =~ "Advanced" ]]; then
      echo -e "  ${COLOR_PURPLE}╟──────────────────────────────────────────────────────────────────╢${COLOR_NC}"
      printf "  ${COLOR_PURPLE}║${COLOR_NC}  ${COLOR_PURPLE_BOLD}%-64s${COLOR_NC}${COLOR_PURPLE}║${COLOR_NC}\n" "  $opt"
      echo -e "  ${COLOR_PURPLE}╟──────────────────────────────────────────────────────────────────╢${COLOR_NC}"
    else
      selectable_indices+=("$i")
      printf "  ${COLOR_PURPLE}║${COLOR_NC}  ${COLOR_PURPLE_BOLD}[%2d]${COLOR_NC} %-59s${COLOR_PURPLE}║${COLOR_NC}\n" "$i" "$opt"
    fi
  done

  echo -e "  ${COLOR_PURPLE}╚══════════════════════════════════════════════════════════════════╝${COLOR_NC}"
  echo ""

  local valid=false
  while [ "$valid" == false ]; do
    printf "  ${COLOR_PURPLE_BOLD}❯${COLOR_NC} ${COLOR_BOLD}Select an option [0-$((count - 1))]: ${COLOR_NC}"
    read -r MENU_RESULT
    if [[ "$MENU_RESULT" =~ ^[0-9]+$ ]] && (( MENU_RESULT >= 0 && MENU_RESULT < count )); then
      # Make sure user didn't pick a divider
      local chosen_opt="${options[$MENU_RESULT]}"
      if [[ "$chosen_opt" =~ ^[─-]+ ]] || [[ "$chosen_opt" =~ "Advanced" ]]; then
        error "That is a section divider. Please choose a numbered menu option."
      else
        valid=true
      fi
    else
      error "Invalid selection. Please enter a valid number."
    fi
  done
}

# First argument is wings / panel / neither
welcome() {
  get_latest_versions "$1"

  clear
  echo ""
  echo -e "${COLOR_CYAN}  ███╗   ██╗ ██████╗ ████████╗██╗  ██╗██╗███╗   ██╗ ██████╗ ${COLOR_NC}"
  echo -e "${COLOR_CYAN}  ████╗  ██║██╔═══██╗╚══██╔══╝██║  ██║██║████╗  ██║██╔════╝ ${COLOR_NC}"
  echo -e "${COLOR_CYAN}  ██╔██╗ ██║██║   ██║   ██║   ███████║██║██╔██╗ ██║██║  ███╗${COLOR_NC}"
  echo -e "${COLOR_CYAN}  ██║╚██╗██║██║   ██║   ██║   ██╔══██║██║██║╚██╗██║██║   ██║${COLOR_NC}"
  echo -e "${COLOR_CYAN}  ██║ ╚████║╚██████╔╝   ██║   ██║  ██║██║██║ ╚████║╚██████╔╝${COLOR_NC}"
  echo -e "${COLOR_CYAN}  ╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ${COLOR_NC}"
  echo -e "${COLOR_WHITE}  ██████╗  █████╗ ███╗   ██╗███████╗██╗     ${COLOR_NC}"
  echo -e "${COLOR_WHITE}  ██╔══██╗██╔══██╗████╗  ██║██╔════╝██║     ${COLOR_NC}"
  echo -e "${COLOR_WHITE}  ██████╔╝███████║██╔██╗ ██║█████╗  ██║     ${COLOR_NC}"
  echo -e "${COLOR_WHITE}  ██╔═══╝ ██╔══██║██║╚██╗██║██╔══╝  ██║     ${COLOR_NC}"
  echo -e "${COLOR_WHITE}  ██║     ██║  ██║██║ ╚████║███████╗███████╗ ${COLOR_NC}"
  echo -e "${COLOR_WHITE}  ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝${COLOR_NC}"
  echo ""
  print_brake 64 "═"
  output "${COLOR_BOLD}Nothing Panel Installer${COLOR_NC} @ $SCRIPT_RELEASE"
  output ""
  output "Running $OS version $OS_VER."
  if [ "$1" == "panel" ]; then
    output "Nothing Panel version: $PTERODACTYL_PANEL_VERSION"
  elif [ "$1" == "wings" ]; then
    output "Nothing Wings version: $PTERODACTYL_WINGS_VERSION"
  fi
  print_brake 64 "═"
  echo ""
}

# ---------------- Lib functions --------------- #

ensure_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    update_repos
    install_packages "jq"
  fi
}

validate_panel_version() {
  PANEL_MAJOR_VERSION="${PANEL_MAJOR_VERSION:-1}"
  PANEL_MAJOR_VERSION="${PANEL_MAJOR_VERSION#v}"
  if [[ ! "$PANEL_MAJOR_VERSION" =~ ^[12]$ ]]; then
    error "PANEL_MAJOR_VERSION must be 1, v1, 2 or v2"
    return 1
  fi
}

ask_panel_version() {
  export PANEL_MAJOR_VERSION="1"
}

get_latest_release() {
  local repo="$1"
  local major="${2:-}"
  local releases tag
  local page=1
  if [ -z "$major" ]; then
    releases=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest") || return 1
    tag=$(jq -er 'select(.draft == false and .prerelease == false) | .tag_name' <<<"$releases") || return 1
  else
    while true; do
      releases=$(curl -fsSL "https://api.github.com/repos/$repo/releases?per_page=100&page=$page") || return 1
      jq -e 'type == "array" and length > 0' <<<"$releases" >/dev/null || return 1
      tag=$(jq -r --arg major "$major" '[.[] | select(.draft == false and .prerelease == false) |
        .tag_name | select(test("^v" + $major + "\\.[0-9]+\\.[0-9]+$"))] |
        sort_by(ltrimstr("v") | split(".") | map(tonumber)) | last // empty' <<<"$releases") || return 1
      [ -n "$tag" ] && break
      page=$((page + 1))
    done
  fi
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  echo "$tag"
}

get_latest_versions() {
  local response
  case "${1:-}" in
  panel)
    validate_panel_version || return 1
    ensure_jq
    output "Retrieving panel engine version information..."
    if [ "$PANEL_MAJOR_VERSION" == "2" ]; then
      if [ -z "$PTERODACTYL_PANEL_COMMIT" ]; then
        response=$(curl -fsSL https://api.github.com/repos/pterodactyl/panel/commits/2.0-develop) || return 1
        PTERODACTYL_PANEL_COMMIT=$(jq -er '.sha' <<<"$response") || return 1
      fi
      [[ "$PTERODACTYL_PANEL_COMMIT" =~ ^[0-9a-f]{40}$ ]] || return 1
      PTERODACTYL_PANEL_VERSION="2.0-develop@$PTERODACTYL_PANEL_COMMIT (experimental)"
      PANEL_DL_URL="https://github.com/pterodactyl/panel/archive/$PTERODACTYL_PANEL_COMMIT.tar.gz"
    else
      if [[ ! "$PTERODACTYL_PANEL_VERSION" =~ ^v1\.[0-9]+\.[0-9]+$ ]]; then
        PTERODACTYL_PANEL_VERSION=$(get_latest_release "pterodactyl/panel" 1) || return 1
      fi
      PANEL_DL_URL="https://github.com/pterodactyl/panel/releases/download/$PTERODACTYL_PANEL_VERSION/panel.tar.gz"
    fi
    ;;
  wings)
    ensure_jq
    output "Retrieving Wings engine version information..."
    if [ -z "$PTERODACTYL_WINGS_VERSION" ]; then
      PTERODACTYL_WINGS_VERSION=$(get_latest_release "pterodactyl/wings") || return 1
    fi
    [[ "$PTERODACTYL_WINGS_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    WINGS_DL_BASE_URL="https://github.com/pterodactyl/wings/releases/download/$PTERODACTYL_WINGS_VERSION/wings_linux_"
    ;;
  esac
}

update_lib_source() {
  GITHUB_URL="$GITHUB_BASE_URL/$GITHUB_SOURCE"
  rm -rf /tmp/lib.sh
  curl -fsSL -o /tmp/lib.sh "$GITHUB_URL"/lib/lib.sh
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh
}

run_installer() {
  local script
  script=$(curl -fsSL "$GITHUB_URL/installers/$1.sh") || return 1
  bash -e -o pipefail -c "$script"
}

run_ui() {
  local script
  script=$(curl -fsSL "$GITHUB_URL/ui/$1.sh") || return 1
  bash -e -o pipefail -c "$script"
}

array_contains_element() {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

valid_email() {
  local local_part="${1%@*}"
  [[ ${#1} -le 191 && ${#local_part} -le 64 && "$1" =~ ${email_regex} ]]
}

is_ip_address() {
  local address="$1"
  if [[ "$address" == '['* || "$address" == *']' ]]; then
    [[ "$address" == '['*']' && "$address" == *:* ]] || return 1
    address="${address#[}"
    address="${address%]}"
  fi
  local part
  local parts
  local count=0
  if [[ "$address" == *:* ]]; then
    if [[ "$address" == *.* ]]; then
      is_ip_address "${address##*:}" || return 1
      address="${address%:*}:0:0"
    fi
    [[ "$address" != *[!0-9a-fA-F:]* && "$address" != *:::* ]] || return 1
    [[ "$address" != :* || "$address" == ::* ]] || return 1
    [[ "$address" != *: || "$address" == *:: ]] || return 1
    if [[ "$address" == *::* ]]; then
      [[ "${address#*::}" != *::* ]] || return 1
    fi
    IFS=: read -r -a parts <<<"$address"
    for part in "${parts[@]}"; do
      [ -z "$part" ] && continue
      [ "${#part}" -le 4 ] || return 1
      count=$((count + 1))
    done
    [[ "$address" == *::* && "$count" -lt 8 || "$count" == 8 && "$address" != *::* ]]
  else
    [[ "$address" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    IFS=. read -r -a parts <<<"$address"
    for part in "${parts[@]}"; do
      [[ "$part" == 0 || "$part" != 0* ]] || return 1
      (( 10#$part <= 255 )) || return 1
    done
  fi
}

valid_hostname() {
  if is_ip_address "$1"; then
    return 0
  fi
  [[ ${#1} -le 253 && ! "$1" =~ ^[0-9.]+$ && "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.?$ ]] || {
    error "Enter a valid hostname or IP address."
    return 1
  }
}

check_install_settings() {
  [ -f "$INSTALL_SETTINGS" ] && [ ! -L "$INSTALL_SETTINGS" ] && [ -O "$INSTALL_SETTINGS" ] &&
    [[ "$(stat -c %a "$INSTALL_SETTINGS")" =~ ^[46]00$ ]] &&
    [ "$(stat -c %s "$INSTALL_SETTINGS")" -le 4096 ] || {
    error "INSTALL_SETTINGS must be a regular file owned by root with mode 400 or 600 (maximum 4096 bytes)."
    return 1
  }
}

load_install_settings() {
  check_install_settings || return 1
  if LC_ALL=C grep -aq '[^ -~]' "$INSTALL_SETTINGS"; then
    error "INSTALL_SETTINGS must contain plain ASCII text without control characters."
    return 1
  fi
  local key value
  local seen=" "
  local count=0
  while IFS='=' read -r key value || [ -n "$key$value" ]; do
    case "$key" in
    CONFIGURE_FIREWALL | CONFIGURE_LETSENCRYPT | ASSUME_SSL)
      [[ "$value" =~ ^(true|false)$ ]] || return 1
      ;;
    FQDN)
      valid_hostname "$value" || return 1
      ;;
    EMAIL)
      valid_email "$value" || return 1
      ;;
    PANEL_MAJOR_VERSION)
      [[ "$value" =~ ^[12]$ ]] || return 1
      ;;
    *)
      error "Invalid INSTALL_SETTINGS entry."
      return 1
      ;;
    esac
    if [[ "$seen" == *" $key "* ]]; then
      error "Duplicate INSTALL_SETTINGS entry."
      return 1
    fi
    seen+="$key "
    count=$((count + 1))
    printf -v "$key" '%s' "$value"
  done <"$INSTALL_SETTINGS"
  if [ "$count" != 6 ]; then
    error "INSTALL_SETTINGS is incomplete."
    return 1
  fi
  if [ "$CONFIGURE_LETSENCRYPT" == true ] && { is_ip_address "$FQDN" || [ "$FQDN" == localhost ]; }; then
    error "INSTALL_SETTINGS cannot enable Let's Encrypt for an IP address or localhost."
    return 1
  fi
  return 0
}

verify_fqdn() {
  local script
  script=$(curl -fsSL "$GITHUB_URL/lib/verify-fqdn.sh") || return 1
  bash -e -o pipefail -c "$script" -- "$1"
}

gen_passwd() {
  local length=$1
  local password=""
  while [ ${#password} -lt "$length" ]; do
    password=$(echo "$password""$(head -c 100 /dev/urandom | LC_ALL=C tr -dc "$password_charset")" | fold -w "$length" | head -n 1)
  done
  echo "$password"
}

# -------------------- MYSQL ------------------- #

check_database_connection() {
  mariadb -u root -e "SELECT 1;" >/dev/null || {
    error "Cannot connect to MariaDB as root. Configure root access in $HOME/.my.cnf before running the installer."
    return 1
  }
}

# MariaDB 10.3 on EL8 only provides the legacy mysql client name.
mariadb() {
  if type -P mariadb >/dev/null 2>&1; then
    command mariadb "$@"
  else
    command mysql "$@"
  fi
}

create_db_user() {
  local db_user_name="$1"
  local db_user_password="$2"
  local db_host="${3:-127.0.0.1}"
  db_user_password="${db_user_password//\'/\'\'}"

  output "Creating database user $db_user_name..."

  mariadb -u root -e "SET SESSION sql_mode = 'NO_BACKSLASH_ESCAPES'; CREATE USER '$db_user_name'@'$db_host' IDENTIFIED BY '$db_user_password';"
  mariadb -u root -e "FLUSH PRIVILEGES;"

  output "Database user $db_user_name created"
}

grant_all_privileges() {
  local db_name="$1"
  local db_user_name="$2"
  local db_host="${3:-127.0.0.1}"
  local db_identifier="\`$db_name\`"
  [ "$db_name" != "*" ] || db_identifier="*"

  output "Granting all privileges on $db_name to $db_user_name..."

  mariadb -u root -e "GRANT ALL PRIVILEGES ON $db_identifier.* TO '$db_user_name'@'$db_host' WITH GRANT OPTION;"
  mariadb -u root -e "FLUSH PRIVILEGES;"

  output "Privileges granted"

}

create_db() {
  local db_name="$1"
  local db_user_name="$2"
  local db_host="${3:-127.0.0.1}"

  output "Creating database $db_name..."

  mariadb -u root -e "CREATE DATABASE \`$db_name\`;"
  grant_all_privileges "$db_name" "$db_user_name" "$db_host"

  output "Database $db_name created"
}

# --------------- Package Manager -------------- #

update_repos() {
  local args=""
  
  [[ "$1" == true ]] && args="-qq"

  case "$OS" in
    ubuntu | debian)
      output "Updating package repositories..."
      if ! apt-get update -y $args; then
        error "Failed to update repositories."
        return 1
      fi
      ;;
    rocky | almalinux)
      # Skip since these distros auto-refresh metadata
      output "Skipping repository update (handled automatically on $OS)."
      ;;
    *)
      warning "Unsupported OS: $OS — skipping repository update."
      ;;
  esac
}


# First argument list of packages to install, second argument for quite mode
install_packages() {
  local args=""
  if [[ $2 == true ]]; then
    case "$OS" in
    ubuntu | debian) args="-qq" ;;
    *) args="-q" ;;
    esac
  fi

  # Eval needed for proper expansion of arguments
  case "$OS" in
  ubuntu | debian)
    eval DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -y $args install "$1"
    ;;
  rocky | almalinux)
    eval dnf -y $args install "$1"
    ;;
  esac
}

# ------------ User input functions ------------ #

valid_database_identifier() {
  [[ "$1" =~ ^[a-zA-Z0-9_]+$ && ${#1} -le 64 ]] || {
    error "Database names and usernames must contain only letters, numbers and underscores (maximum 64 characters)."
    return 1
  }
}

valid_admin_username() {
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]+[a-zA-Z0-9]$ && ${#1} -le 191 ]] || {
    error "Username must be 3-191 characters, start and end with a letter or number, and contain only letters, numbers, dashes, underscores and periods."
    return 1
  }
}

valid_admin_name() {
  [[ "$1" =~ [^[:space:]] && ! "$1" =~ [[:cntrl:]] && ${#1} -le 191 ]] || {
    error "Name must be 1-191 characters without control characters."
    return 1
  }
}

valid_admin_password() {
  [[ ${#1} -ge 8 && "$1" =~ [^[:space:]] && ! "$1" =~ [[:cntrl:]] ]] || {
    error "Admin password must contain at least 8 characters and cannot be blank or contain control characters."
    return 1
  }
}

valid_panel_database_password() {
  [[ "$1" =~ [^[:space:]] && "$1" != *"'"* && "$1" != *'"'* && "$1" != *\\* && "$1" != *'$'* && ! "$1" =~ [[:cntrl:]] ]] || {
    error "Panel database password cannot be blank or contain quotes, backslashes, dollar signs or control characters."
    return 1
  }
}

is_yes() {
  [[ "$1" =~ ^[Yy]([Ee][Ss])?$ ]]
}

required_input() {
  local __resultvar=$1
  local result=''

  while [ -z "$result" ]; do
    printf "  ${COLOR_BOLD}→ ${COLOR_NC}${2}"
    read -r result

    if [ -z "${3}" ]; then
      [ -z "$result" ] && result="${4}"
    else
      [ -z "$result" ] && error "${3}"
    fi
  done

  printf -v "$__resultvar" '%s' "$result"
}

email_input() {
  local __resultvar=$1
  local result=''

  while ! valid_email "$result"; do
    printf "  ${COLOR_BOLD}→ ${COLOR_NC}${2}"
    read -r result
    [ -z "$result" ] && result="${4}"

    valid_email "$result" || error "${3}"
  done

  printf -v "$__resultvar" '%s' "$result"
}

password_input() {
  local __resultvar=$1
  local result=''
  local default="$4"

  while [ -z "$result" ]; do
    printf "  ${COLOR_BOLD}→ ${COLOR_NC}${2}"

    # modified from https://stackoverflow.com/a/22940001
    while true; do
      IFS= read -r -s -n1 char || return 1
      [[ -z $char ]] && {
        printf '\n'
        break
      }                               # ENTER pressed; output \n and break.
      if [[ $char == $'\x7f' ]]; then # backspace was pressed
        # Only if variable is not empty
        if [ -n "$result" ]; then
          # Remove last char from output variable.
          result=${result%?}
          # Erase '*' to the left.
          printf '\b \b'
        fi
      else
        # Add typed char to output variable.
        result+=$char
        # Print '*' in its stead.
        printf '*'
      fi
    done
    [ -z "$result" ] && [ -n "$default" ] && result="$default"
    [ -z "$result" ] && error "${3}"
  done

  printf -v "$__resultvar" '%s' "$result"
}

ask_letsencrypt() {
  if [ "$CONFIGURE_FIREWALL" == false ]; then
    warning "Let's Encrypt requires port 80/443 to be opened! You have opted out of the automatic firewall configuration; use this at your own risk (if port 80/443 is closed, the script will fail)!"
  fi

  select_menu "Configure HTTPS with Let's Encrypt?" \
    "No - Skip SSL configuration" \
    "Yes - Automatically configure HTTPS (Recommended)"

  if [ "$MENU_RESULT" == "1" ]; then
    export CONFIGURE_LETSENCRYPT=true
  fi
}

# ------------------ Firewall ------------------ #

ask_firewall() {
  local __resultvar=$1

  case "$OS" in
  ubuntu | debian)
    select_menu "Configure UFW Firewall?" \
      "No - Skip firewall configuration" \
      "Yes - Automatically configure UFW (Recommended)"

    if [ "$MENU_RESULT" == "1" ]; then
      printf -v "$__resultvar" '%s' true
    fi
    ;;
  rocky | almalinux)
    select_menu "Configure firewall-cmd?" \
      "No - Skip firewall configuration" \
      "Yes - Automatically configure firewall-cmd (Recommended)"

    if [ "$MENU_RESULT" == "1" ]; then
      printf -v "$__resultvar" '%s' true
    fi
    ;;
  esac
}

install_firewall() {
  case "$OS" in
  ubuntu | debian)
    output ""
    output "Installing Uncomplicated Firewall (UFW)"

    if ! [ -x "$(command -v ufw)" ]; then
      update_repos true
      install_packages "ufw" true
    fi

    ufw --force enable

    success "Enabled Uncomplicated Firewall (UFW)"

    ;;
  rocky | almalinux)

    output ""
    output "Installing FirewallD"

    if ! [ -x "$(command -v firewall-cmd)" ]; then
      install_packages "firewalld" true
    fi

    systemctl --now enable firewalld >/dev/null

    success "Enabled FirewallD"

    ;;
  esac
}

firewall_allow_ports() {
  case "$OS" in
  ubuntu | debian)
    for port in $1; do
      ufw allow "$port"
    done
    ufw --force reload
    ;;
  rocky | almalinux)
    for port in $1; do
      firewall-cmd --zone=public --add-port="$port"/tcp --permanent
    done
    firewall-cmd --reload -q
    ;;
  esac
}

# ---------------- System checks --------------- #

# panel x86_64 check
check_os_x86_64() {
  if [ "${ARCH}" != "amd64" ]; then
    warning "Detected CPU architecture $CPU_ARCHITECTURE"
    warning "Using any other architecture than 64 bit (x86_64) will cause problems."

    echo -e -n "  → Are you sure you want to proceed? (y/N):"
    read -r choice

    if ! is_yes "$choice"; then
      error "Installation aborted!"
      exit 1
    fi
  fi
}

# wings virtualization check
check_virt() {
  output "Installing virt-what..."

  update_repos true
  install_packages "virt-what" true

  virt_serv=$(virt-what)

  case "$virt_serv" in
  *openvz* | *lxc*)
    warning "Unsupported type of virtualization detected. Please consult with your hosting provider whether your server can run Docker or not. Proceed at your own risk."
    echo -e -n "  → Are you sure you want to proceed? (y/N): "
    read -r CONFIRM_PROCEED
    if ! is_yes "$CONFIRM_PROCEED"; then
      error "Installation aborted!"
      exit 1
    fi
    ;;
  *)
    [ "$virt_serv" != "" ] && warning "Virtualization: $virt_serv detected."
    ;;
  esac

  if uname -r | grep -q "xxxx"; then
    error "Unsupported kernel detected."
    exit 1
  fi

  success "System is compatible with docker"
}

# ========== DOMAIN MANAGEMENT FEATURE ========== #
# Assign a domain to a port and get automatic SSL
# This is called after Wings installation when setting up a node

# Ask user if they want to map a domain to a port
ask_domain_for_port() {
  local port="${1:-8080}"
  export PORT_DOMAIN=""
  export PORT_CONFIGURE_SSL=false

  echo ""
  echo -e "  ${COLOR_CYAN}╔══════════════════════════════════════════════════════════════╗${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}║${COLOR_NC}  ${COLOR_WHITE}${COLOR_BOLD}Domain Mapping for Port $port${COLOR_NC}                            ${COLOR_CYAN}║${COLOR_NC}"
  echo -e "  ${COLOR_CYAN}╚══════════════════════════════════════════════════════════════╝${COLOR_NC}"
  echo ""
  output "You can assign a domain name to port $port on this server."
  output "This allows accessing your game servers via a domain instead of IP:port."
  echo ""

  select_menu "Do you want to assign a domain to port $port?" \
    "No - Use IP:port directly" \
    "Yes - Assign a domain to this port"

  if [ "$MENU_RESULT" == "0" ]; then
    return 0
  fi

  # Get domain name
  while true; do
    printf "  ${COLOR_BOLD}→ ${COLOR_NC}Enter domain for port $port (e.g. game.yourdomain.com): "
    read -r PORT_DOMAIN
    [ -z "$PORT_DOMAIN" ] && error "Domain cannot be empty" && continue
    valid_hostname "$PORT_DOMAIN" && break
  done

  output "Domain: $PORT_DOMAIN → Port: $port"

  # Ask about SSL
  if ! is_ip_address "$PORT_DOMAIN" && [ "$PORT_DOMAIN" != "localhost" ]; then
    select_menu "Configure SSL for $PORT_DOMAIN?" \
      "No - HTTP only" \
      "Yes - Get Let's Encrypt SSL certificate (Recommended)"

    if [ "$MENU_RESULT" == "1" ]; then
      PORT_CONFIGURE_SSL=true
    fi
  fi

  success "Domain mapping configured: $PORT_DOMAIN → Port $port"
}

# Configure nginx reverse proxy for a port domain
configure_domain_for_port() {
  local domain="$1"
  local port="$2"
  local ssl="${3:-false}"
  local email_addr="${4:-}"

  output "Configuring nginx proxy for $domain → port $port ..."

  local conf_path="/etc/nginx/sites-available/np-port-${port}.conf"
  local enabled_path="/etc/nginx/sites-enabled/np-port-${port}.conf"

  # Write HTTP config (also used for certbot challenge)
  cat > "$conf_path" <<NGINXCONF
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
    }

    # Nothing Panel - Domain Port Mapping
    access_log /var/log/nginx/np-port-${port}.access.log;
    error_log  /var/log/nginx/np-port-${port}.error.log error;
}
NGINXCONF

  ln -sf "$conf_path" "$enabled_path"
  nginx -t && systemctl reload nginx

  if [ "$ssl" == "true" ] && [ -n "$email_addr" ]; then
    output "Obtaining SSL certificate for $domain ..."
    certbot --nginx --redirect --no-eff-email --email "$email_addr" -d "$domain" && \
      success "SSL certificate obtained for $domain!" || \
      warning "SSL certificate could not be obtained. Check your DNS and try again."
  fi

  success "Domain $domain is now mapped to port $port!"
  output "Access your server at: $([ "$ssl" == "true" ] && echo "https://$domain" || echo "http://$domain")"
}

# Interactive domain management menu
domain_management_menu() {
  local email_addr="${1:-}"

  while true; do
    select_menu "Nothing Panel - Domain Management" \
      "Exit domain management" \
      "Add domain for a port" \
      "Remove domain mapping" \
      "List active domain mappings"

    case "$MENU_RESULT" in
    0)
      break
      ;;
    1)
      printf "  ${COLOR_BOLD}→ ${COLOR_NC}Enter port number: "
      read -r dm_port
      [[ "$dm_port" =~ ^[0-9]+$ ]] || { error "Invalid port number"; continue; }

      printf "  ${COLOR_BOLD}→ ${COLOR_NC}Enter domain (e.g. game.yourdomain.com): "
      read -r dm_domain
      valid_hostname "$dm_domain" || continue

      local dm_ssl=false
      if ! is_ip_address "$dm_domain"; then
        select_menu "Enable SSL for $dm_domain?" \
          "No - HTTP only" \
          "Yes - Let's Encrypt SSL"
        [ "$MENU_RESULT" == "1" ] && dm_ssl=true

        if [ "$dm_ssl" == "true" ] && [ -z "$email_addr" ]; then
          email_input email_addr "Email for Let's Encrypt: " "Email cannot be empty or invalid"
        fi
      fi

      configure_domain_for_port "$dm_domain" "$dm_port" "$dm_ssl" "$email_addr"
      ;;
    2)
      printf "  ${COLOR_BOLD}→ ${COLOR_NC}Enter port number to remove mapping: "
      read -r rm_port
      local rm_conf="/etc/nginx/sites-available/np-port-${rm_port}.conf"
      local rm_enabled="/etc/nginx/sites-enabled/np-port-${rm_port}.conf"
      if [ -f "$rm_conf" ]; then
        rm -f "$rm_conf" "$rm_enabled"
        nginx -t && systemctl reload nginx
        success "Domain mapping for port $rm_port removed!"
      else
        warning "No domain mapping found for port $rm_port"
      fi
      ;;
    3)
      output "Active domain mappings:"
      print_brake 50
      local found=false
      for conf in /etc/nginx/sites-available/np-port-*.conf; do
        [ -f "$conf" ] || continue
        found=true
        local prt
        prt=$(echo "$conf" | grep -oP 'np-port-\K[0-9]+')
        local dom
        dom=$(grep -oP 'server_name \K[^;]+' "$conf" 2>/dev/null || echo "unknown")
        output "  Port $prt → $dom"
      done
      [ "$found" == "false" ] && output "  No domain mappings configured yet."
      print_brake 50
      ;;
    esac
  done
}

# Exit with error status code if user is not root
if [[ $EUID -ne 0 ]]; then
  error "This script must be executed with root privileges."
  exit 1
fi

if [ -z "$HOME" ]; then
  error "HOME must be set before running this script."
  exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
  # freedesktop.org and systemd
  . /etc/os-release
  OS=$(echo "$ID" | awk '{print tolower($0)}')
  OS_VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
  # linuxbase.org
  OS=$(lsb_release -si | awk '{print tolower($0)}')
  OS_VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
  # For some versions of Debian/Ubuntu without lsb_release command
  . /etc/lsb-release
  OS=$(echo "$DISTRIB_ID" | awk '{print tolower($0)}')
  OS_VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
  # Older Debian/Ubuntu/etc.
  OS="debian"
  OS_VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSe-release ]; then
  # Older SuSE/etc.
  OS="SuSE"
  OS_VER="?"
elif [ -f /etc/redhat-release ]; then
  # Older Red Hat, CentOS, etc.
  OS="Red Hat/CentOS"
  OS_VER="?"
else
  # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
  OS=$(uname -s)
  OS_VER=$(uname -r)
fi

OS=$(echo "$OS" | awk '{print tolower($0)}')
if [ "$OS" == "debian" ] && [ -z "$OS_VER" ] && [ -f /etc/debian_version ]; then
  OS_VER=$(cat /etc/debian_version)
fi
OS_VER_MAJOR=$(echo "$OS_VER" | cut -d. -f1)
CPU_ARCHITECTURE=$(uname -m)

case "$CPU_ARCHITECTURE" in
x86_64)
  ARCH=amd64
  ;;
arm64 | aarch64)
  ARCH=arm64
  ;;
*)
  warning "Unknown CPU architecture detected! ($CPU_ARCHITECTURE)"
  ARCH=amd64
  ;;
esac

case "$OS" in
ubuntu)
  PHP_SOCKET="/run/php/php8.3-fpm.sock"
  CACHE_SERVICE="redis-server"
  case "$OS_VER_MAJOR" in
  22 | 24 | 26)
    SUPPORTED=true
    ;;
  esac
  ;;
debian)
  PHP_SOCKET="/run/php/php8.3-fpm.sock"
  CACHE_SERVICE="redis-server"
  case "$OS_VER_MAJOR" in
  12 | 13)
    SUPPORTED=true
    ;;
  esac
  ;;
rocky)
  PHP_SOCKET="/var/run/php-fpm/pterodactyl.sock"
  CACHE_SERVICE="redis"
  case "$OS_VER_MAJOR" in
  8 | 9 | 10)
    SUPPORTED=true
    ;;
  esac
  ;;
almalinux)
  PHP_SOCKET="/var/run/php-fpm/pterodactyl.sock"
  CACHE_SERVICE="redis"
  case "$OS_VER_MAJOR" in
  8 | 9 | 10)
    SUPPORTED=true
    ;;
  esac
  ;;
*)
  SUPPORTED=false
  ;;
esac

# exit if not supported
if [ "$SUPPORTED" == false ]; then
  output "The following OS is not supported by Nothing Panel installer: $OS $OS_VER"
  error "Unsupported OS"
  exit 1
fi

export PHP_BIN
PHP_BIN=$(command -v php8.3 2>/dev/null || command -v php 2>/dev/null || echo "php")
if [ -z "$PHP_BIN" ]; then
  PHP_BIN="php"
fi
