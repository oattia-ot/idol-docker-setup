#!/bin/bash

# ─────────────────────────────────────────────
# Color codes
# ─────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[SKIP]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
section() { echo -e "\n${BOLD}${BLUE}── $1 ──${NC}"; }
ask()     { echo -e "${YELLOW}[?]${NC}     $1"; }

# ─────────────────────────────────────────────
# Usage / Help
# ─────────────────────────────────────────────
usage() {
  echo -e "
${BOLD}Usage:${NC}
  $(basename "$0") [options]

${BOLD}Description:${NC}
  Finds and removes all Docker volumes matching 'idol-demo'.
  Optionally runs 'docker compose down' before removing volumes.

${BOLD}Options:${NC}
  ${YELLOW}-h, --help${NC}    Show this help message and exit

${BOLD}Examples:${NC}
  ${CYAN}./$(basename "$0")${NC}           Run interactively
  ${CYAN}./$(basename "$0") --help${NC}    Show this help message
"
}

# ─────────────────────────────────────────────
# Parse arguments
# ─────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    *) error "Unknown option: $arg"; usage; exit 1 ;;
  esac
done

# ─────────────────────────────────────────────
# IDOL Docker Volume Cleanup
# ─────────────────────────────────────────────
section "IDOL Docker Volume Cleanup"

# Check for idol-demo volumes
info "Checking for idol-demo volumes..."
echo ""

VOLUMES=$(docker volume ls -q | grep idol-demo || true)

if [ -z "$VOLUMES" ]; then
    warn "No idol-demo volumes found. Nothing to clean up."
    exit 0
fi

info "Found the following volumes:"
echo ""
docker volume ls | grep idol-demo
echo ""

# Confirm before deleting
ask "Remove all idol-demo volumes listed above? [y/N]"
read -rp "      " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    warn "Aborted. No volumes were removed."
    exit 0
fi

# Bring down the stack first
section "Bringing Down Docker Compose Stack"

if [ -f "docker-compose.yml" ] || [ -f "compose.yml" ]; then
    info "Running docker compose down..."
    if docker compose down; then
        success "docker compose down"
    else
        error "docker compose down failed"
        exit 1
    fi
else
    warn "No compose file found in current directory — skipping 'docker compose down'"
fi

# Remove the volumes
section "Removing Volumes"

for VOL in $VOLUMES; do
    if docker volume rm "$VOL" 2>/dev/null; then
        success "$VOL"
    else
        error "$VOL (failed to remove)"
    fi
done

# Done
section "Done"
info "All idol-demo volumes removed. Run 'docker compose up -d' to recreate them fresh."