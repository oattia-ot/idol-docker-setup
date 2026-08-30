#!/bin/bash
# ============================================================
# install-harbor.sh — Main Harbor Installer (Docker or Minikube)
# ============================================================

set -euo pipefail

# --- Colors ---
RED=$'\033[0;31m';    GREEN=$'\033[0;32m';   YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m';   BLUE=$'\033[0;34m';    MAGENTA=$'\033[0;35m'
WHITE=$'\033[1;37m';  GRAY=$'\033[0;90m';    BOLD=$'\033[1m'
RESET=$'\033[0m'

# ============================================================
# USAGE
# ============================================================
usage() {
    cat <<EOF
${BOLD}Usage:${RESET} $(basename "$0") [OPTION]

Main launcher for Harbor installation.

Options:
  -d, --docker          Deploy Harbor directly on Docker (standalone)
  -m, --minikube        Deploy Harbor on Minikube (with Kubernetes + Ingress)
  -y, --yes             Auto-answer yes to all prompts (non-interactive)
  -h, --help            Show this help message and exit

Examples:
  $(basename "$0")                    # Interactive menu
  $(basename "$0") --docker -y        # Non-interactive Docker install
  $(basename "$0") -m --clean-restart # Minikube with clean restart
  $(basename "$0") -m -y              # Minikube non-interactive

EOF
    exit 0
}

# ============================================================
# DEFAULTS & ARGUMENT PARSING
# ============================================================
MODE=""
AUTO_YES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)          usage ;;
        -d|--docker)        MODE="docker" ; shift ;;
        -m|--minikube)      MODE="minikube" ; shift ;;
        -y|--yes)           AUTO_YES=true ; shift ;;
        *) echo -e "${RED}❌ Unknown option: $1${RESET}"; usage ;;
    esac
done

# ============================================================
# INTERACTIVE MENU
# ============================================================
show_menu() {
    echo -e ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║          Harbor Registry Installer           ║${RESET}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════╝${RESET}"
    echo -e ""
    echo -e "  ${BOLD}Choose deployment method:${RESET}"
    echo -e ""
    echo -e "  ${GREEN}1${RESET}) Deploy Harbor on **Docker** (standalone, simple)"
    echo -e "  ${GREEN}2${RESET}) Deploy Harbor on **Minikube** (Kubernetes + Ingress)"
    echo -e "  ${GREEN}3${RESET}) Exit"
    echo -e ""
}

select_mode() {
    if [ "$AUTO_YES" = true ]; then
        MODE="minikube"   # default when using -y without explicit mode
        return
    fi

    while true; do
        show_menu
        read -rp "${CYAN}Enter your choice [1-3]: ${RESET}" choice
        case "$choice" in
            1) MODE="docker"; break ;;
            2) MODE="minikube"; break ;;
            3) echo -e "${GREEN}👋 Goodbye!${RESET}"; exit 0 ;;
            *) echo -e "${RED}❌ Invalid choice. Please select 1, 2 or 3.${RESET}" ;;
        esac
    done
}

# ============================================================
# MAIN
# ============================================================
echo -e "${BOLD}${CYAN}=== Harbor Setup Launcher ===${RESET}"

# If no mode selected via CLI → show interactive menu
if [ -z "$MODE" ]; then
    select_mode
fi

echo -e "${GREEN}✅ Selected: Harbor on ${BOLD}$MODE${RESET}"

# Execute the correct script and forward all remaining arguments
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$MODE" in
    docker)
        echo -e "${CYAN}Launching setup-harbor-docker.sh...${RESET}"
        exec "$SCRIPT_DIR/setup-harbor-docker.sh" "$@"
        ;;
    minikube)
        echo -e "${CYAN}Launching setup-harbor-minikube.sh...${RESET}"
        exec "$SCRIPT_DIR/setup-harbor-minikube.sh" "$@"
        ;;
esac