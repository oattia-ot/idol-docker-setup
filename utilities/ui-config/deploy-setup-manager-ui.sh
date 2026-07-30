#!/bin/bash
#
# deploy-setup-manager-ui.sh (Robust Auto-Detection Version)
# This version automatically finds the correct ui-config folder
#

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

usage() {
    echo -e "\n${BOLD}USAGE${NC}  $(basename "$0") <command>\n"
    echo -e "${BOLD}COMMANDS${NC}"
    echo -e "  ${CYAN}-b, --build${NC}   Rebuild image (no cache) and deploy"
    echo -e "  ${CYAN}-d, --deploy${NC}  Deploy using existing image"
    echo -e "  ${CYAN}-c, --clean${NC}   Stop containers and remove Docker resources"
    echo -e "  ${CYAN}-h, --help${NC}    Show this help message\n"
}

# ==================== SMART PROJECT ROOT DETECTION ====================

# Find the folder containing backend/ui-docker-compose.yml (for COMPOSE_FILE)
find_project_root() {
    local current_dir
    current_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    while [ "$current_dir" != "/" ]; do
        if [ -f "$current_dir/backend/ui-docker-compose.yml" ]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done

    if [ -f "$(pwd)/backend/ui-docker-compose.yml" ]; then
        echo "$(pwd)"
        return 0
    fi

    echo ""
    return 1
}

# Find the 'idol-docker-setup' folder (for IDOL_BASE_PATH)
find_idol_base_path() {
    local current_dir
    current_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Walk upwards looking for a folder named 'idol-docker-setup'
    for _ in {1..15}; do
        if [ "$(basename "$current_dir")" = "idol-docker-setup" ]; then
            echo "$current_dir"
            return 0
        fi
        local parent_dir
        parent_dir="$(dirname "$current_dir")"
        if [ "$parent_dir" = "$current_dir" ]; then
            break
        fi
        current_dir="$parent_dir"
    done

    # Fallback: ./idol-docker-setup relative to current working directory
    echo "$(pwd)/idol-docker-setup"
}

# ==================== SET PATHS ====================
PROJECT_ROOT=$(find_project_root)

if [ -z "$PROJECT_ROOT" ]; then
    error "Could not find ui-config folder containing backend/ui-docker-compose.yml"
    error "Please run this script from inside the ui-config directory."
    exit 1
fi

# Use smart detection for IDOL_BASE_PATH (looks for 'idol-docker-setup' folder)
export IDOL_BASE_PATH="$(find_idol_base_path)"
export IDOL_BASE_PATH="${IDOL_BASE_PATH%/}"   # remove trailing slash

COMPOSE_FILE="$PROJECT_ROOT/backend/ui-docker-compose.yml"
SERVICE_NAME="nifi-manager"
PORT=5000

export IDOL_NIFI_FLOWS_DIR="${IDOL_NIFI_FLOWS_DIR:-$IDOL_BASE_PATH/persistent-data/nifi-flows}"
export IDOL_SHARED_FOLDER_PATH="${IDOL_SHARED_FOLDER_PATH:-$IDOL_BASE_PATH/shared-folder}"

info "Detected Project Root     : $PROJECT_ROOT"
info "IDOL_BASE_PATH            : $IDOL_BASE_PATH"
info "Using Compose File        : $COMPOSE_FILE"

if [ ! -f "$COMPOSE_FILE" ]; then
    error "Compose file still not found at: $COMPOSE_FILE"
    exit 1
fi

# ==================== DOCKER CHECKS ====================
if ! command -v docker &> /dev/null; then
    error "Docker is not installed."
    exit 1
fi

if ! docker compose version &> /dev/null; then
    error "Docker Compose v2 is required."
    exit 1
fi

# ==================== FUNCTIONS ====================

print_header() {
    echo ""
    echo -e "${CYAN}${BOLD}==================================================${NC}"
    echo -e "${CYAN}${BOLD}   NiFi Config Manager UI - Deployment Tool${NC}"
    echo -e "${CYAN}${BOLD}==================================================${NC}"
    echo ""
}

kill_port() {
    local pids=$(sudo lsof -t -i:$PORT 2>/dev/null || true)

    if [ -z "$pids" ]; then
        info "Port $PORT is free. Proceeding with deployment."
        return 0
    fi

    warn "Port $PORT is already in use by the following process(es):"
    echo ""
    sudo lsof -i:$PORT -Pn 2>/dev/null || true
    echo ""
    for pid in $pids; do
        echo -e "  ${CYAN}PID $pid${NC}: $(ps -o cmd= -p "$pid" 2>/dev/null)"
    done
    echo ""

    read -r -p "$(echo -e "${YELLOW}Kill the above process(es) and continue deployment? [y/N]: ${NC}")" confirm
    case "$confirm" in
        [yY]|[yY][eE][sS])
            warn "Killing processes on port $PORT..."
            sudo kill -9 $pids 2>/dev/null || true
            sleep 2
            success "Port $PORT is now free."
            ;;
        *)
            error "Deployment aborted by user. Port $PORT is still in use."
            exit 1
            ;;
    esac
}

ensure_network() {
    local net="idol-demo-network"
    docker network inspect "$net" >/dev/null 2>&1 || docker network create "$net"
}

cleanup_docker() {
    docker compose -f "$COMPOSE_FILE" down --remove-orphans 2>/dev/null || true
}

show_status() {
    docker compose -f "$COMPOSE_FILE" ps
}

show_logs() {
    docker compose -f "$COMPOSE_FILE" logs -f "$SERVICE_NAME"
}

build_and_deploy() {
    print_header
    ensure_network
    kill_port
    cleanup_docker

    info "Building image..."
    docker compose -f "$COMPOSE_FILE" build --no-cache --pull "$SERVICE_NAME"

    info "Starting container..."
    docker compose -f "$COMPOSE_FILE" up -d "$SERVICE_NAME"

    sleep 4
    if docker ps --format '{{.Names}}' | grep -q "$SERVICE_NAME"; then
        success "Deployment successful!"
        show_status
        print_urls
    else
        error "Container failed to start"
        docker compose -f "$COMPOSE_FILE" logs "$SERVICE_NAME"
        exit 1
    fi
}

deploy_only() {
    print_header
    ensure_network
    kill_port
    docker compose -f "$COMPOSE_FILE" down
    docker compose -f "$COMPOSE_FILE" up -d "$SERVICE_NAME"
    sleep 3
    success "Deployed successfully!"
    show_status
    print_urls
}

print_urls() {
    local host_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    echo ""
    echo -e "${CYAN}Access the UI at:${NC}"
    echo -e "  → http://localhost:$PORT"
    echo -e "  → http://$host_ip:$PORT"
    echo ""
}

# ==================== MAIN ====================
case "${1:-}" in
    -b|--build)  build_and_deploy ;;
    -d|--deploy) deploy_only ;;
    -c|--clean)  cleanup_docker; success "Cleanup done" ;;
    -s|--status) show_status ;;
    -l|--logs)   show_logs ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        error "Unknown option: ${1:-}"
        usage
        exit 1
        ;;
esac