#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────
# Color codes
# ─────────────────────────────────────────────
# IDOL OS detection (Ubuntu / macOS) — loads module/os-compat.sh when present
if [ -z "${IDOL_OS_COMPAT_LOADED:-}" ]; then
  _idol_os_src=""
  if [ -n "${IDOL_BASE_PATH:-}" ] && [ -f "${IDOL_BASE_PATH}/module/os-compat.sh" ]; then
    _idol_os_src="${IDOL_BASE_PATH}/module/os-compat.sh"
  else
    _idol_os_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
    _idol_os_probe="$_idol_os_dir"
    _idol_os_i=0
    while [ -n "$_idol_os_probe" ] && [ "$_idol_os_probe" != "/" ] && [ "$_idol_os_i" -lt 20 ]; do
      if [ -f "$_idol_os_probe/module/os-compat.sh" ]; then
        _idol_os_src="$_idol_os_probe/module/os-compat.sh"
        break
      fi
      _idol_os_probe="$(dirname "$_idol_os_probe")"
      _idol_os_i=$((_idol_os_i + 1))
    done
  fi
  if [ -n "$_idol_os_src" ]; then
    # shellcheck source=/dev/null
    . "$_idol_os_src"
  else
    case "$(uname -s 2>/dev/null)" in
      Darwin)
        export IDOL_HOST_OS=macos IDOL_OS_FAMILY=macos
        ;;
      Linux)
        export IDOL_OS_FAMILY=linux
        if [ -f /etc/os-release ] && grep -qi ubuntu /etc/os-release 2>/dev/null; then
          export IDOL_HOST_OS=ubuntu
        else
          export IDOL_HOST_OS=linux
        fi
        ;;
      *)
        export IDOL_HOST_OS=unknown IDOL_OS_FAMILY=unknown
        ;;
    esac
  fi
  unset _idol_os_src _idol_os_dir _idol_os_probe _idol_os_i
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# ─────────────────────────────────────────────
# Usage
# ─────────────────────────────────────────────
usage() {
    echo -e ""
    echo -e "${BOLD}Usage:${NC} $(basename "$0") <command> [options]"
    echo -e ""
    echo -e "${BOLD}Commands:${NC}"
    echo -e "  ${CYAN}up${NC}      Build and start the Obsidian container"
    echo -e "  ${CYAN}down${NC}    Stop and remove the Obsidian container and volumes"
    echo -e ""
    echo -e "${BOLD}Options:${NC}"
    echo -e "  ${CYAN}-d${NC}            Run containers in detached mode (used with up)"
    echo -e "  ${CYAN}--force, -f${NC}   Override an existing lock file"
    echo -e "  ${CYAN}-h, --help${NC}    Show this help message"
    echo -e ""
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  $(basename "$0") up -d"
    echo -e "  $(basename "$0") down"
    echo -e "  $(basename "$0") up -d --force"
    echo -e ""
}

if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

for arg in "$@"; do
    case $arg in
        -h|--help) usage; exit 0 ;;
    esac
done

# ─────────────────────────────────────────────
# Parse mode: up or down
# ─────────────────────────────────────────────
MODE="up"
FORCE_LOCK=0

for arg in "$@"; do
    case $arg in
        up)         MODE="up"   ;;
        down)       MODE="down" ;;
        --force|-f) FORCE_LOCK=1 ;;
    esac
done

# ─────────────────────────────────────────────
# Lock guard
# ─────────────────────────────────────────────
LOCK_FILE="/tmp/deploy-llm-wiki.lock"

if [[ $FORCE_LOCK -eq 1 ]]; then
    if [[ -f "$LOCK_FILE" ]]; then
        echo -e "${YELLOW}-> Lock file found — removing...${NC}"
        rm -f "$LOCK_FILE"
        echo -e "  ${GREEN}✓${NC}  Lock file removed. Run without ${CYAN}--force${NC} to start normally.\n"
        exit 0
    else
        echo -e "${YELLOW}-> No lock file found — running normally...${NC}\n"
        # Strip --force/-f from args and re-exec without it
        CLEAN_ARGS=()
        for arg in "$@"; do
            case $arg in
                --force|-f) ;;
                *) CLEAN_ARGS+=("$arg") ;;
            esac
        done
        exec "$0" "${CLEAN_ARGS[@]}"
    fi
fi

if [[ -f "$LOCK_FILE" ]]; then
    LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [[ -n "$LOCK_PID" ]] && ps -p "$LOCK_PID" > /dev/null 2>&1; then
        echo -e "${RED}${BOLD}ERROR:${NC} Another LLM-Wiki instance is already running (PID: $LOCK_PID)."
        echo -e "Use ${CYAN}--force${NC} to remove the lock file."
        exit 1
    else
        rm -f "$LOCK_FILE"
    fi
fi

echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE" 2>/dev/null || true' EXIT INT TERM

# ─────────────────────────────────────────────
# Spinner helper
# ─────────────────────────────────────────────
spinner() {
    local pid=$1
    local label=$2
    local spinchars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    tput civis 2>/dev/null
    while kill -0 "$pid" 2>/dev/null; do
        local frame="${spinchars:$((i % ${#spinchars})):1}"
        printf "\r  ${CYAN}${frame}${NC}  %s..." "$label"
        i=$(( i + 1 ))
        sleep 0.1
    done
    tput cnorm 2>/dev/null
}

# ─────────────────────────────────────────────
# Paths
# ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/obsidian-docker-compose.yml"
LOG_FILE="/tmp/llm-wiki.log"

# ─────────────────────────────────────────────
# DOWN mode
# ─────────────────────────────────────────────
if [[ "$MODE" == "down" ]]; then
    echo -e "${YELLOW}-> Stopping Obsidian...${NC}"

    docker compose -f "$COMPOSE_FILE" down -v >> "$LOG_FILE" 2>&1 &
    DOWN_PID=$!
    spinner $DOWN_PID "Stopping services"
    wait $DOWN_PID
    DOWN_EXIT=$?

    echo ""
    if [[ $DOWN_EXIT -eq 0 ]]; then
        printf "  ${GREEN}✓${NC}  Obsidian stopped and volumes removed\n"
        echo -e "\n${MAGENTA}${BOLD}  Finished tearing down Obsidian.${NC}\n"
    else
        printf "  ${RED}✗${NC}  Shutdown failed — see $LOG_FILE\n"
        exit 1
    fi
    exit 0
fi

# ─────────────────────────────────────────────
# UP mode
# ─────────────────────────────────────────────

# Step 1: init-vault.sh
echo -e "${CYAN}-> Initialising vault...${NC}"

"$SCRIPT_DIR/init-vault.sh" >> "$LOG_FILE" 2>&1 &
INIT_PID=$!
spinner $INIT_PID "Initialising vault"
wait $INIT_PID
INIT_EXIT=$?

if [[ $INIT_EXIT -eq 0 ]]; then
    printf "\r  ${GREEN}✓${NC}  Vault initialised successfully          \n"
else
    printf "\r  ${RED}✗${NC}  Vault initialisation failed — see $LOG_FILE\n"
    exit 1
fi

# Step 2: docker compose
echo -e "${CYAN}-> Starting Obsidian...${NC}"

docker compose -f "$COMPOSE_FILE" "$@" >> "$LOG_FILE" 2>&1 &
COMPOSE_PID=$!
spinner $COMPOSE_PID "Starting Obsidian"
wait $COMPOSE_PID
COMPOSE_EXIT=$?

echo ""
if [[ $COMPOSE_EXIT -eq 0 ]]; then
    printf "  ${GREEN}✓${NC}  Obsidian is running\n"
    echo -e "\n${GREEN}${BOLD}  ✦ Finished setting up Obsidian!${NC}"
    echo -e "  ${CYAN}Open:${NC} http://localhost:3000  (or https://localhost:3001)\n"
else
    printf "  ${RED}✗${NC}  Obsidian startup failed — see $LOG_FILE\n"
    exit 1
fi