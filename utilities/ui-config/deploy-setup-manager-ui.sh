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
    echo -e "\n${BOLD}USAGE${NC}  $(basename "$0") <command> [--port <n>]\n"
    echo -e "${BOLD}COMMANDS${NC}"
    echo -e "  ${CYAN}-b, --build${NC}   Rebuild image (no cache) and deploy"
    echo -e "  ${CYAN}-d, --deploy${NC}  Deploy using existing image"
    echo -e "  ${CYAN}-c, --clean${NC}   Stop containers and remove Docker resources"
    echo -e "  ${CYAN}-f, --fix-mounts${NC}  Remove leftover pre-setup.sh directories and rebuild"
    echo -e "  ${CYAN}-h, --help${NC}    Show this help message\n"
    echo -e "${BOLD}OPTIONS${NC}"
    echo -e "  ${CYAN}-p, --port <n>${NC}  Host port for the Setup Manager UI (default: 5000)"
    echo -e "                   You can also set SETUP_UI_PORT. If neither is set,"
    echo -e "                   the script asks: \"What is the UI port? [5000]\"\n"
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
compose() {
    docker compose --project-directory "$PROJECT_ROOT" -f "$COMPOSE_FILE" "$@"
}

SERVICE_NAME="nifi-manager"
PORT="${SETUP_UI_PORT:-}"
CMD=""

while [ $# -gt 0 ]; do
    case "$1" in
        -b|--build|-d|--deploy|-c|--clean|-f|--fix-mounts|-s|--status|-l|--logs|-h|--help)
            CMD="$1"
            shift
            ;;
        -p|--port)
            PORT="${2:-}"
            shift 2
            ;;
        --port=*)
            PORT="${1#--port=}"
            shift
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done
set -- "$CMD"

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

ask_ui_port() {
    if [ -n "$PORT" ]; then
        :
    else
        echo ""
        echo -e "${CYAN}${BOLD}What is the UI port?${NC}  (Setup Manager web interface)"
        echo -e "  Default ${BOLD}5000${NC}. On macOS, AirPlay Receiver often already uses 5000 — pick 5001 if unsure."
        read -r -p "$(echo -e "${YELLOW}UI port [5000]: ")" answer
        PORT="${answer:-5000}"
    fi
    case "$PORT" in
        ''|*[!0-9]*)
            error "UI port must be a number between 1 and 65535 (got: $PORT)"
            exit 1
            ;;
    esac
    if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        error "UI port must be between 1 and 65535 (got: $PORT)"
        exit 1
    fi
    export SETUP_UI_PORT="$PORT"
    export PORT
    info "Setup Manager UI will be published on host port $PORT ${NC}"
}

port_listeners() {
    # Any TCP state, IPv4+IPv6. Unprivileged lsof often hides other users'
    # listeners, so this can be empty even when the port is reserved.
    lsof -nP -iTCP:"$PORT" 2>/dev/null || true
}

port_pids() {
    lsof -t -nP -iTCP:"$PORT" 2>/dev/null | sort -u
}

docker_publishers() {
    if ! command -v docker >/dev/null 2>&1; then
        return 0
    fi
    docker ps --filter "publish=$PORT" --format '{{.ID}} {{.Names}} {{.Ports}}' 2>/dev/null || true
}

# Prints "busy <reason>" or "free <reason>" on stdout. Exit 0 always.
port_probe() {
    local listing containers
    listing=$(port_listeners)
    if [ -n "$listing" ]; then
        echo "busy lsof"
        return 0
    fi
    containers=$(docker_publishers)
    if [ -n "$containers" ]; then
        echo "busy docker"
        return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        # Only EADDRINUSE counts. Binding 0.0.0.0 then 127.0.0.1 in a tight
        # loop is a known false-positive on macOS (the first close has not
        # released the port yet). Probe 0.0.0.0 once.
        python3 - "$PORT" <<'PY'
import errno, socket, sys
port = int(sys.argv[1])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    s.bind(("0.0.0.0", port))
except OSError as e:
    if e.errno == errno.EADDRINUSE:
        print("busy bind-eaddrinuse")
    else:
        # Permission / unavailable / etc. — not a live listener we can kill.
        print("free bind-other:" + errno.errorcode.get(e.errno, str(e.errno)))
else:
    print("free bind-ok")
finally:
    s.close()
PY
        return 0
    fi
    if bash -c "echo >/dev/tcp/127.0.0.1/$PORT" >/dev/null 2>&1; then
        echo "busy connect"
        return 0
    fi
    echo "free none"
}

port_is_busy() {
    case "$(port_probe)" in
        busy*) return 0 ;;
        *)     return 1 ;;
    esac
}

show_port_users() {
    local listing containers probe
    probe=$(port_probe)
    echo ""
    echo -e "${YELLOW}Probe:${NC} $probe"
    echo ""
    echo -e "${YELLOW}TCP sockets on $PORT (all states):${NC}"
    listing=$(port_listeners)
    if [ -n "$listing" ]; then
        echo "$listing"
    else
        echo "  (none visible to this user — try: sudo lsof -nP -iTCP:$PORT)"
    fi
    if command -v docker >/dev/null 2>&1; then
        echo ""
        echo -e "${YELLOW}Docker containers publishing $PORT:${NC}"
        containers=$(docker_publishers)
        if [ -n "$containers" ]; then
            echo "$containers" | awk '{printf "  %s  %s  %s\n", $1, $2, substr($0, index($0,$3))}'
        else
            echo "  (none)"
        fi
    fi
}

kill_port_users() {
    local killed=0
    local id name pids pid

    if command -v docker >/dev/null 2>&1; then
        while read -r id name _; do
            [ -z "$id" ] && continue
            info "Stopping container $name ($id)..."
            if docker stop "$id" >/dev/null 2>&1; then
                killed=1
            else
                warn "Could not stop container $name ($id)"
            fi
        done < <(docker_publishers)
        # Previous UI container may still be around even if the publish
        # filter did not match (odd Port column formatting).
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'nifi-manager'; then
            info "Stopping leftover nifi-manager container..."
            docker stop nifi-manager >/dev/null 2>&1 && killed=1 || true
        fi
    fi

    pids=$(port_pids)
    if [ -n "$pids" ]; then
        echo ""
        echo -e "${YELLOW}Host PIDs using $PORT:${NC} $pids"
        for pid in $pids; do
            if [ "$pid" = "1" ]; then
                warn "Refusing to kill PID 1"
                continue
            fi
            info "Sending TERM to PID $pid ($(ps -p "$pid" -o comm= 2>/dev/null || echo unknown))..."
            if kill "$pid" 2>/dev/null; then
                killed=1
            else
                warn "kill $pid failed (re-run with sudo to signal another user's process)"
            fi
        done
        sleep 1
        pids=$(port_pids)
        for pid in $pids; do
            [ "$pid" = "1" ] && continue
            warn "PID $pid still using the port — sending KILL"
            kill -9 "$pid" 2>/dev/null || true
        done
        sleep 1
    fi

    if [ "$killed" -eq 0 ]; then
        warn "Nothing visible to kill. The port may be held by Docker Desktop, another user, or TIME_WAIT."
        warn "Inspect with:  sudo lsof -nP -iTCP:$PORT"
        return 1
    fi
    return 0
}

abort_port_in_use() {
    echo ""
    echo -e "Pick a free port and retry:"
    echo -e "  ${CYAN}./deploy-setup-manager-ui.sh --deploy --port <free-port>${NC}"
    echo -e "On macOS, System Settings → General → AirDrop & Handoff → AirPlay Receiver → Off"
    echo -e "frees port 5000 (not $PORT unless that is the port you chose)."
    exit 1
}

# Reads a y/n answer that defaults to YES on a bare Enter (or any answer that
# isn't an explicit no). Returns 0 for yes, 1 for no.
confirm_default_yes() {
    local prompt="$1" answer
    read -r -p "$(echo -e "${YELLOW}${prompt} [Y/n]: ")" answer
    case "$answer" in
        n|N|no|NO) return 1 ;;
        *)         return 0 ;;
    esac
}

require_port_free() {
    local probe listing containers
    probe=$(port_probe)
    case "$probe" in
        free*)
            info "Port $PORT is free ($probe). Proceeding with deployment."
            return 0
            ;;
    esac

    error "Port $PORT appears to be in use ($probe)."
    show_port_users
    echo ""

    if [ ! -t 0 ]; then
        warn "Not a TTY — cannot ask to free the port. Proceeding anyway; pass --port <n> to pick a different one if the deploy fails."
        return 0
    fi

    listing=$(port_listeners)
    containers=$(docker_publishers)

    if [ -z "$listing" ] && [ -z "$containers" ]; then
        # "busy" from the probe but nothing visible in lsof or docker ps means
        # there is nothing to kill — this is almost always a stale TIME_WAIT
        # socket, Docker Desktop's VM holding the port, or another user's
        # process this shell can't see, not a real conflict.
        warn "Nothing found using port $PORT (no matching process or container), so there is nothing to kill."
        warn "This usually clears on its own and Docker will still bind the port fine."
        if confirm_default_yes "Continue and let Docker bind port $PORT"; then
            info "Continuing — Docker will attempt to bind port $PORT."
            return 0
        fi
        abort_port_in_use
    fi

    if confirm_default_yes "Kill the process/container using port $PORT and continue"; then
        if kill_port_users; then
            probe=$(port_probe)
            case "$probe" in
                free*)
                    success "Port $PORT is now free. Proceeding with deployment."
                    return 0
                    ;;
            esac
            error "Port $PORT still looks busy ($probe) after the kill attempt."
            show_port_users
        else
            warn "Nothing was actually killed (it may already be gone)."
        fi
        if confirm_default_yes "Continue and let Docker bind port $PORT anyway"; then
            warn "Continuing without a confirmed-free port. Docker publish may still fail."
            return 0
        fi
        abort_port_in_use
    else
        error "Port $PORT is already in use — setup cannot continue."
        abort_port_in_use
    fi
}

ensure_network() {
    local net="idol-demo-network"
    docker network inspect "$net" >/dev/null 2>&1 || docker network create "$net"
}

# Docker bind-mounts a missing host file as a directory inside the container.
# That makes /config-idol/save-script fail with:
#   [Errno 21] Is a directory: '/setup-scripts/pre-setup.sh'
# Always create a real file at the host source before compose up, and clean
# up any leftover directory from a previous bad mount.
ensure_pre_setup_file() {
    local dest_dir="$IDOL_BASE_PATH"
    local dest="$dest_dir/pre-setup.sh"

    if [ -z "$dest_dir" ]; then
        error "IDOL_BASE_PATH is empty; cannot prepare pre-setup.sh bind mount."
        exit 1
    fi

    mkdir -p "$dest_dir"

    if [ -d "$dest" ]; then
        warn "Found a directory at $dest (leftover from a missing-file Docker bind)."
        warn "Replacing it with an empty file so the container can save the script."
        rm -rf "$dest"
    fi

    if [ ! -e "$dest" ]; then
        touch "$dest"
        chmod 666 "$dest" 2>/dev/null || true
        info "Created host bind source: $dest"
    elif [ ! -f "$dest" ]; then
        error "$dest exists but is not a regular file. Remove it and retry."
        exit 1
    fi
}

cleanup_docker() {
    compose down --remove-orphans 2>/dev/null || true
}

# The Errno 21 error means Docker bind-mounted a missing host *file* as a
# *directory* at pre-setup.sh. That mount is baked into the running container;
# editing source files is not enough. Stop the container, delete those
# directories, then rebuild the image from this tree.
fix_pre_setup_mounts() {
    print_header
    info "Stopping UI container so the bind mount can be removed..."
    docker rm -f nifi-manager >/dev/null 2>&1 || true
    compose down --remove-orphans 2>/dev/null || true

    local candidates=(
        "$IDOL_BASE_PATH/pre-setup.sh"
        "$PROJECT_ROOT/pre-setup.sh"
        "$PROJECT_ROOT/../pre-setup.sh"
        "$PROJECT_ROOT/../../pre-setup.sh"
        "$PROJECT_ROOT/backend/../../../pre-setup.sh"
    )
    local found=0
    local path
    for path in "${candidates[@]}"; do
        [ -e "$path" ] || continue
        if [ -d "$path" ]; then
            warn "Removing leftover directory: $path"
            rm -rf "$path"
            found=1
        else
            info "Already a file (leaving it): $path"
        fi
    done
    if [ "$found" -eq 0 ]; then
        warn "No leftover pre-setup.sh directories found in the usual places."
        warn "If the error persists, run: docker inspect nifi-manager --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'"
    fi

    info "Rebuilding and deploying so the new /idol-base mount is used..."
    ask_ui_port
    ensure_network
    ensure_pre_setup_file
    require_port_free
    DOCKERFILE="$PROJECT_ROOT/backend/dockerfile"
    docker build --no-cache --pull -f "$DOCKERFILE" -t idol-config-nifi-manager "$PROJECT_ROOT"
    compose up -d --no-build "$SERVICE_NAME"
    sleep 3
    info "Container mounts:"
    docker inspect nifi-manager --format '{{range .Mounts}}{{println}}{{.Source}} -> {{.Destination}}{{end}}' 2>/dev/null || true
    success "Done. Hard-refresh the UI and save the script again."
}

show_status() {
    compose ps
}

show_logs() {
    compose logs -f "$SERVICE_NAME"
}

# Catches the "Is a directory: '/setup-scripts/pre-setup.sh'" failure right
# after deploy instead of letting the user discover it later in the UI.
# The app only falls back to /setup-scripts/pre-setup.sh when /idol-base
# did not mount as a real directory, so check that directly inside the
# running container.
verify_idol_base_mount() {
    if ! docker exec "$SERVICE_NAME" test -d /idol-base 2>/dev/null; then
        warn "/idol-base did not mount as a directory inside the container."
        warn "Saving the pre-setup script will fail with 'Is a directory: /setup-scripts/pre-setup.sh'."
        warn "Fix with: ./$(basename "$0") --fix-mounts --port $PORT"
        return 1
    fi
    if docker exec "$SERVICE_NAME" test -d /setup-scripts/pre-setup.sh 2>/dev/null; then
        warn "Found a stray directory at /setup-scripts/pre-setup.sh inside the container."
        warn "Fix with: ./$(basename "$0") --fix-mounts --port $PORT"
        return 1
    fi
    # Same class of bug for the LLM model list: if the host file at
    # $IDOL_BASE_PATH/idol-containers-toolkit/data-admin/llm-sandbox/default-models.json
    # doesn't exist, Docker mounts /setup-scripts/default-models.json as an
    # empty directory instead of failing, and the UI silently falls back to
    # the single demo model with no visible error.
    local host_models="$IDOL_BASE_PATH/idol-containers-toolkit/data-admin/llm-sandbox/default-models.json"
    if docker exec "$SERVICE_NAME" test -d /setup-scripts/default-models.json 2>/dev/null; then
        warn "/setup-scripts/default-models.json mounted as a directory, not a file."
        warn "Expected a real file on the host at: $host_models"
        if [ ! -e "$host_models" ]; then
            warn "That file does not exist on the host — create/copy it there, then:"
        else
            warn "That path exists on the host but the mount still shows a directory — recreate the container after fixing the file, then:"
        fi
        warn "  docker rm -f $SERVICE_NAME && ./$(basename "$0") --deploy --port $PORT"
        return 1
    elif ! docker exec "$SERVICE_NAME" test -f /setup-scripts/default-models.json 2>/dev/null; then
        warn "/setup-scripts/default-models.json is not present in the container (host file missing: $host_models)."
        warn "The UI will show only the built-in demo model until this file exists and the container is redeployed."
    fi
    return 0
}

build_and_deploy() {
    print_header
    ask_ui_port
    ensure_network
    ensure_pre_setup_file
    require_port_free
    cleanup_docker

    DOCKERFILE="$PROJECT_ROOT/backend/dockerfile"
    if [ ! -f "$DOCKERFILE" ]; then
        error "Dockerfile not found at: $DOCKERFILE"
        ls -la "$PROJECT_ROOT/backend" || true
        exit 1
    fi
    info "Building image from $DOCKERFILE (context $PROJECT_ROOT)..."
    docker build --no-cache --pull -f "$DOCKERFILE" -t idol-config-nifi-manager "$PROJECT_ROOT"

    info "Starting container..."
    compose up -d --no-build "$SERVICE_NAME"

    sleep 4
    if docker ps --format '{{.Names}}' | grep -q "$SERVICE_NAME"; then
        success "Deployment successful!"
        verify_idol_base_mount || true
        show_status
        print_urls
    else
        error "Container failed to start"
        compose logs "$SERVICE_NAME"
        exit 1
    fi
}

deploy_only() {
    print_header
    ask_ui_port
    ensure_network
    ensure_pre_setup_file
    require_port_free

    if ! docker image inspect idol-config-nifi-manager >/dev/null 2>&1; then
        DOCKERFILE="$PROJECT_ROOT/backend/dockerfile"
        if [ ! -f "$DOCKERFILE" ]; then
            error "Image 'idol-config-nifi-manager' does not exist and Dockerfile not found at: $DOCKERFILE"
            error "Run: $(basename "$0") --build --port $PORT"
            exit 1
        fi
        warn "Image 'idol-config-nifi-manager' not found locally."
        warn "Building it now from $DOCKERFILE (context $PROJECT_ROOT)..."
        warn "Tip: run '--build' instead if you've changed files, since --deploy reuses the existing image."
        docker build -f "$DOCKERFILE" -t idol-config-nifi-manager "$PROJECT_ROOT"
    fi

    compose down
    # --no-build: never let compose/Bake resolve its own build context and go
    # looking for a top-level ./dockerfile — the image above is already built.
    compose up -d --no-build "$SERVICE_NAME"
    sleep 3
    success "Deployed successfully!"
    verify_idol_base_mount || true
    show_status
    print_urls
}

print_urls() {
    local host_ip
    host_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$host_ip" ]; then
        host_ip=$(ipconfig getifaddr en0 2>/dev/null || true)
    fi
    [ -z "$host_ip" ] && host_ip="localhost"
    echo ""
    echo -e "${CYAN}Access the UI at:${NC}"
    echo -e "  → http://localhost:$PORT/"
    echo -e "  → http://$host_ip:$PORT/"
    echo -e "  → http://localhost:$PORT/config-idol"
    echo -e "  → http://localhost:$PORT/config-nifi"
    echo ""
}

# ==================== MAIN ====================
case "${1:-}" in
    -b|--build)  build_and_deploy ;;
    -d|--deploy) deploy_only ;;
    -c|--clean)  cleanup_docker; success "Cleanup done" ;;
    -f|--fix-mounts) fix_pre_setup_mounts ;;
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