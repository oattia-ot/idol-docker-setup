#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# init-vault.sh
# Placed in /custom-cont-init.d/ so the linuxserver s6-overlay init system
# runs it as root BEFORE Obsidian starts.
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

VAULT_DIR="${VAULT_PATH:-./vault}"
CONFIG_DIR="${CONFIG_PATH:-./config}"
OWNER="${PUID:-1000}:${PGID:-1000}"

# ──────────────────────────────────────────────────────────────────────────────
# Colors
# ──────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

# ──────────────────────────────────────────────────────────────────────────────
# Usage / Help
# ──────────────────────────────────────────────────────────────────────────────
usage() {
  echo -e "
${BOLD}${CYAN}Usage:${RESET} $(basename "$0") [OPTIONS]

Initialises the Obsidian vault and config directories, sets ownership and
permissions so the unprivileged container user can write to them.

${BOLD}${CYAN}Options:${RESET}
  ${GREEN}-l, --list${RESET}     List all content in the vault and config directories
  ${RED}-c, --clear${RESET}    Truncate (remove all content from) the vault and config directories
  ${BLUE}-h, --help${RESET}     Show this help message and exit

${BOLD}${CYAN}Environment variables:${RESET}
  ${YELLOW}VAULT_PATH${RESET}     Path to the vault directory  (default: ./vault)
  ${YELLOW}CONFIG_PATH${RESET}    Path to the config directory (default: ./config)
  ${YELLOW}PUID${RESET}           User ID for ownership        (default: 1000)
  ${YELLOW}PGID${RESET}           Group ID for ownership       (default: 1000)

${BOLD}${CYAN}Examples:${RESET}
  $(basename "$0")            ${YELLOW}# Normal init — create dirs, fix perms/ownership${RESET}
  $(basename "$0") --list     ${YELLOW}# Show contents of vault and config${RESET}
  $(basename "$0") --clear    ${YELLOW}# Wipe all content from vault and config${RESET}
"
}

# ──────────────────────────────────────────────────────────────────────────────
# Flag handlers
# ──────────────────────────────────────────────────────────────────────────────
do_list() {
  echo -e "${BOLD}${CYAN}[init-vault]${RESET} 📂  Listing contents of config: ${YELLOW}${CONFIG_DIR}${RESET}"
  if [ -d "${CONFIG_DIR}" ]; then
    ls -lah "${CONFIG_DIR}"
  else
    echo -e "${BOLD}${CYAN}[init-vault]${RESET} ${YELLOW}⚠️  Config directory does not exist: ${CONFIG_DIR}${RESET}"
  fi

  echo ""
  echo -e "${BOLD}${CYAN}[init-vault]${RESET} 📂  Listing contents of vault: ${YELLOW}${VAULT_DIR}${RESET}"
  if [ -d "${VAULT_DIR}" ]; then
    ls -lah "${VAULT_DIR}"
  else
    echo -e "${BOLD}${CYAN}[init-vault]${RESET} ${YELLOW}⚠️  Vault directory does not exist: ${VAULT_DIR}${RESET}"
  fi
}

do_clear() {
  echo -e "${BOLD}${CYAN}[init-vault]${RESET} 🗑️  Clearing config directory: ${YELLOW}${CONFIG_DIR}${RESET}"
  if [ -d "${CONFIG_DIR}" ]; then
    rm -rf "${CONFIG_DIR:?}"/*
    echo -e "${BOLD}${CYAN}[init-vault]${RESET} ${GREEN}✅  Config directory cleared.${RESET}"
  else
    echo -e "${BOLD}${CYAN}[init-vault]${RESET} ${YELLOW}⚠️  Config directory does not exist, nothing to clear.${RESET}"
  fi

  echo -e "${BOLD}${CYAN}[init-vault]${RESET} 🗑️  Clearing vault directory: ${YELLOW}${VAULT_DIR}${RESET}"
  if [ -d "${VAULT_DIR}" ]; then
    rm -rf "${VAULT_DIR:?}"/*
    echo -e "${BOLD}${CYAN}[init-vault]${RESET} ${GREEN}✅  Vault directory cleared.${RESET}"
  else
    echo -e "${BOLD}${CYAN}[init-vault]${RESET} ${YELLOW}⚠️  Vault directory does not exist, nothing to clear.${RESET}"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Argument parsing
# ──────────────────────────────────────────────────────────────────────────────
case "${1:-}" in
  -l|--list)
    do_list
    exit 0
    ;;
  -c|--clear)
    do_clear
    exit 0
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  "")
    : # No argument — fall through to normal init
    ;;
  *)
    echo -e "${BOLD}${CYAN}[init-vault]${RESET} ${RED}❌  Unknown option: $1${RESET}"
    usage
    exit 1
    ;;
esac

# ──────────────────────────────────────────────────────────────────────────────
# Normal init
# ──────────────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}[init-vault]${RESET} Preparing vault at ${YELLOW}${VAULT_DIR}${RESET} ..."

# Create directory tree if it doesn't exist yet
mkdir -p "${VAULT_DIR}"
mkdir -p "${CONFIG_DIR}"

# Ensure the directories are group-writable so plugins can create sub-folders
chmod 775 "${VAULT_DIR}"
chmod 775 "${CONFIG_DIR}"

# Hand ownership to the unprivileged user Obsidian will run as
chown -R "${OWNER}" "${VAULT_DIR}"
chown -R "${OWNER}" "${CONFIG_DIR}"

echo -e "${BOLD}${CYAN}[init-vault]${RESET} ${GREEN}✅  ${VAULT_DIR} is ready (owned by ${OWNER})${RESET}"
echo -e "${BOLD}${CYAN}[init-vault]${RESET} ${GREEN}✅  ${CONFIG_DIR} is ready (owned by ${OWNER})${RESET}"