#!/bin/bash

# OpenText IDOL on Ubuntu 24.04
# Deploy License Server Script - DevOps Best Practices

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
LIGHTER_YELLOW='\033[38;5;228m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
ORANGE='\033[0;38;5;214m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/../utilities/config-placeholders/placeholders-replacement.sh"

docker_compose_file="docker-compose.licenseserver.yml"
IDOL_DEPLOYMENT_TYPE="${IDOL_DEPLOYMENT_TYPE:-dev}"
network_name="${IDOL_DEPLOYMENT_NETWORK}"
health_check_timeout=30
health_check_interval=2

# Reusable Docker Compose command (as array — critical for correct quoting)
DOCKER_COMPOSE_CMD=(docker compose -f "./${docker_compose_file}")

# Path to licenseserver.cfg on the host — bind-mounted into the container.
IDOL_PRESERVE_LICENSESERVER_CFG_PATH="${IDOL_PRESERVE_LICENSESERVER_CFG_PATH:-}"

# Path to idol.common.cfg on the host — bind-mounted into the container.
IDOL_PRESERVE_IDOL_COMMON_CFG_PATH="${IDOL_PRESERVE_IDOL_COMMON_CFG_PATH:-}"

# Prevent unbound variable crash with set -euo pipefail
IDOL_PRESERVE_IDOL_COMMON_CFG_FILENAME="${IDOL_PRESERVE_IDOL_COMMON_CFG_FILENAME:-}"

# ---------------------------------------------------------------------------
# Logging functions
# ---------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------

error_handler() {
    local line_number=$1
    log_error "Script failed at line $line_number"
    log_error "Cleaning up..."
    set_license_active_status "FALSE"
    cleanup_on_error
    exit 1
}

set -euo pipefail
trap 'error_handler $LINENO' ERR

cleanup_on_error() {
    log_info "Performing error cleanup..."
    if "${DOCKER_COMPOSE_CMD[@]}" ps -q licenseserver 2>/dev/null | grep -q .; then
        log_info "Stopping license server container..."
        "${DOCKER_COMPOSE_CMD[@]}" down || true
    fi
    set_license_active_status "FALSE"
}

# ---------------------------------------------------------------------------
# Copy Fresh License Server
# ---------------------------------------------------------------------------
# Define common exclude list once (DRY principle)
EXCLUDES=(
    --exclude='licenseserver.lck'
    --exclude='licenseserver.pid'
    --exclude='license.log'
    --exclude='licenseserver.log'
    --exclude='service.log'
    --exclude='usage_statistics.dat'
)

copy_fresh_license_server() {
    local dest="$1"
    local parent_dir

    # Remove stale destination if it exists
    if [ -d "$dest" ]; then
        log_info "Removing existing destination folder: $dest"
        if ! sudo rm -rf "$dest"; then
            log_error "Failed to remove existing destination folder: $dest"
            return 1
        fi
    fi

    # Ensure parent directory exists (important for ../templates/... paths)
    parent_dir="$(dirname "$dest")"
    if [[ "$parent_dir" != "." && "$parent_dir" != ".." ]]; then
        if ! sudo mkdir -p "$parent_dir"; then
            log_error "Failed to create parent directory: $parent_dir"
            return 1
        fi
    fi

    # Copy fresh
    log_info "Copying license server folder to $dest (excluding lock/log files)..."
    if ! sudo rsync -av "${EXCLUDES[@]}" \
                    "$SOURCE_IDOL_LICENSE_SERVER_PATH/." "$dest"; then
        log_error "Failed to copy license server folder to $dest"
        return 1
    fi

    log_info "Copying license key file to $dest ..."
    # Copy with sudo (needed in case target dir has restricted permissions)
    if ! sudo cp -f "$SOURCE_IDOL_LICENSE_KEY_PATH" "$dest"; then
        log_error "Failed to copy license key file to $dest"
        return 1
    fi

    # ownership so the file belongs to your normal user, not root
    if ! sudo chown -R "$USER:$USER" "$dest"; then
        log_error "Failed to set ownership of license key file to $USER:$USER"
        return 1
    fi

    log_info "${GREEN}✅ License key copied and ownership set to ${USER}:${USER}${NC}"

    # Make shell scripts executable
    if compgen -G "$dest"/*.sh > /dev/null 2>&1; then
        sudo chmod +x "$dest"/*.sh
    else
        log_info "No .sh files found in $dest — skipping chmod"
    fi

    log_success "Environment loaded and files copied — license server path: $dest"

    return 0
}

# ---------------------------------------------------------------------------
# load_environment
# ---------------------------------------------------------------------------
load_environment() {
    local has_cli_args="$1"

    log_info "Loading environment configuration..."

    local missing=false
    [ -z "${IDOL_LICENSESERVER_FQDN:-}"                   ] && missing=true
    [ -z "${IDOL_LICENSESERVER_NAME:-}"                   ] && missing=true
    [ -z "${IDOL_LICENSE_KEY_MAC:-}"                      ] && missing=true
    [ -z "${SOURCE_IDOL_LICENSE_SERVER_PATH:-}"           ] && missing=true
    [ -z "${SOURCE_IDOL_LICENSE_KEY_PATH:-}"              ] && missing=true
    [ -z "${IDOL_PRESERVE_LICENSESERVER_CFG_PATH:-}"      ] && missing=true
    [ -z "${IDOL_PRESERVE_IDOL_COMMON_CFG_FILENAME:-}"    ] && missing=true

    if [ "$missing" = "true" ]; then
        echo ""
        log_error "════════════════════════════════════════════════════════════════════════════════"
        log_error "                    REQUIRED CONFIGURATION MISSING"
        log_error "════════════════════════════════════════════════════════════════════════════════"
        echo ""

        if [ "$has_cli_args" = "false" ]; then
            log_error "No command-line arguments provided and required environment variables are not set."
            echo ""
            log_error "You have two options to configure the license server:"
            echo ""
            log_error "OPTION 1: Pass arguments directly to the script"
            echo -e "  ${LIGHTER_YELLOW}$0 [http|https] <SOURCE_LICENSE_SERVER_PATH> <SOURCE_LICENSE_KEY_PATH> <MAC_ADDRESS>${NC}"
            echo ""
            log_error "  Example:"
            echo -e "  ${LIGHTER_YELLOW}$0 https /opt/backup_license/LicenseServer_25.3.0_LINUX_X86_64 /opt/backup_license/licensekey.dat 00:15:5d:73:9d:03${NC}"
            echo ""
            log_error "  Note: LICENSE_SERVER_NAME is auto-extracted from the path's last component."
            echo ""
            log_error "OPTION 2: Export environment variables"
    
            echo -e "  ${LIGHTER_YELLOW}export IDOL_LICENSESERVER_FQDN=${CYAN}<license_server_fqdn>${NC}"
            echo -e "  ${LIGHTER_YELLOW}export IDOL_LICENSESERVER_NAME=${CYAN}<license_server_folder_name>${NC}"
            echo -e "  ${LIGHTER_YELLOW}export IDOL_LICENSE_KEY_MAC=${CYAN}<mac_address>${NC}"
            echo -e "  ${LIGHTER_YELLOW}export SOURCE_IDOL_LICENSE_SERVER_PATH=${CYAN}<path_to_license_server_folder>${NC}"
            echo -e "  ${LIGHTER_YELLOW}export SOURCE_IDOL_LICENSE_KEY_PATH=${CYAN}<path_to_licensekey.dat>${NC}"
            echo -e "  ${LIGHTER_YELLOW}export IDOL_PRESERVE_LICENSESERVER_CFG_PATH=${CYAN}<path_to_licenseserver_folder>${NC}"
            echo -e "  ${LIGHTER_YELLOW}export IDOL_PRESERVE_IDOL_COMMON_CFG_PATH=${CYAN}<path_to_content_cfg_folder>${NC}"
            echo -e "  ${LIGHTER_YELLOW}export IDOL_PRESERVE_IDOL_COMMON_CFG_FILENAME=${CYAN}<idol.common.cfg_filename>${NC}"
            echo -e "  ${LIGHTER_YELLOW}export IDOL_LICENSESERVER_PROTOCOL=${CYAN}<http|https>  (optional, default: http)${NC}"
        else
            log_error "Some required environment variables are not set."
        fi

        echo ""    
        log_error "Missing variables:"
        [ -z "${IDOL_LICENSESERVER_FQDN:-}"                 ] && log_error "  ✗ IDOL_LICENSESERVER_FQDN                — license server FQDN"
        [ -z "${IDOL_LICENSESERVER_NAME:-}"                 ] && log_error "  ✗ IDOL_LICENSESERVER_NAME                — license server folder name"
        [ -z "${IDOL_LICENSE_KEY_MAC:-}"                    ] && log_error "  ✗ IDOL_LICENSE_KEY_MAC                    — MAC address (format: xx:xx:xx:xx:xx:xx)"
        [ -z "${SOURCE_IDOL_LICENSE_SERVER_PATH:-}"         ] && log_error "  ✗ SOURCE_IDOL_LICENSE_SERVER_PATH         — path to license server folder"
        [ -z "${SOURCE_IDOL_LICENSE_KEY_PATH:-}"            ] && log_error "  ✗ SOURCE_IDOL_LICENSE_KEY_PATH            — path to license key file (.dat)"
        [ -z "${IDOL_LICENSESERVER_PROTOCOL:-}"            ] && log_error "  ✗ IDOL_LICENSESERVER_PROTOCOL            — protocol (http | https)"
        [ -z "${IDOL_PRESERVE_LICENSESERVER_CFG_PATH:-}"   ] && log_error "  ✗ IDOL_PRESERVE_LICENSESERVER_CFG_PATH   — path to licenseserver.cfg (bind-mount target)"
        [ -z "${IDOL_PRESERVE_IDOL_COMMON_CFG_PATH:-}"     ] && log_error "  ✗ IDOL_PRESERVE_IDOL_COMMON_CFG_PATH     — path to idol.common.cfg folder (bind-mount target)"
        [ -z "${IDOL_PRESERVE_IDOL_COMMON_CFG_FILENAME:-}" ] && log_error "  ✗ IDOL_PRESERVE_IDOL_COMMON_CFG_FILENAME — idol.common.cfg filename"
        echo ""
        log_error "════════════════════════════════════════════════════════════════════════════════"
        log_error "For more information, run: $0 --help"
        log_error "════════════════════════════════════════════════════════════════════════════════"
        echo ""
        return 1
    fi

    log_info "  License server FQDN            : ${LIGHTER_YELLOW}${IDOL_LICENSESERVER_FQDN}${NC}"
    log_info "  License server name            : ${LIGHTER_YELLOW}${IDOL_LICENSESERVER_NAME}${NC}"
    log_info "  License server MAC address     : ${LIGHTER_YELLOW}${IDOL_LICENSE_KEY_MAC}${NC}"
    log_info "  Source license server path     : ${LIGHTER_YELLOW}${SOURCE_IDOL_LICENSE_SERVER_PATH}${NC}"
    log_info "  Source license key path        : ${LIGHTER_YELLOW}${SOURCE_IDOL_LICENSE_KEY_PATH}${NC}"
    log_info "  Preserved licenseserver.cfg    : ${LIGHTER_YELLOW}${IDOL_PRESERVE_LICENSESERVER_CFG_PATH}${NC}"

    # Validate source paths
    if [ ! -d "$SOURCE_IDOL_LICENSE_SERVER_PATH" ]; then
        log_error "Source license server path does not exist: $SOURCE_IDOL_LICENSE_SERVER_PATH"
        return 1
    fi
    if [ ! -f "$SOURCE_IDOL_LICENSE_KEY_PATH" ]; then
        log_error "Source license key file does not exist: $SOURCE_IDOL_LICENSE_KEY_PATH"
        return 1
    fi

    # ============================================
    # Copy Fresh License Server logic
    # ============================================
    DESTINATIONS=(
        "./$IDOL_LICENSESERVER_NAME"
        "../templates/license-server/template-script/$IDOL_LICENSESERVER_NAME"
    )

    # Optional but recommended: fail early if source is missing
    if [ ! -d "$SOURCE_IDOL_LICENSE_SERVER_PATH" ]; then
        log_error "Source directory does not exist: $SOURCE_IDOL_LICENSE_SERVER_PATH"
        return 1
    fi

    # Process all destinations cleanly
    for dest in "${DESTINATIONS[@]}"; do
        if ! copy_fresh_license_server "$dest"; then
            return 1
        fi
    done

    log_info "License server folders successfully prepared."
    return 0
}

# ---------------------------------------------------------------------------
# validate_prerequisites
# ---------------------------------------------------------------------------
validate_prerequisites() {
    log_info "Validating prerequisites..."

    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running or not accessible"
        exit 1
    fi

    if ! docker compose version >/dev/null 2>&1; then
        log_error "Docker Compose plugin is not available"
        exit 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl is not installed or not in PATH"
        exit 1
    fi

    if ! command -v ss >/dev/null 2>&1; then
        log_error "ss (iproute2) is not installed or not in PATH"
        exit 1
    fi

    if [ -z "${license_server_domain:-}" ]; then
        log_error "license_server_domain is not set"
        exit 1
    fi

    log_success "All prerequisites validated"
}

# ---------------------------------------------------------------------------
# setup_docker_network
# ---------------------------------------------------------------------------
setup_docker_network() {
    log_info "Setting up Docker network: ${YELLOW}$network_name${NC}"

    if docker network ls --format '{{.Name}}' | grep -qxF "$network_name"; then
        log_success "Network '$network_name' already exists — reusing it"
    else
        log_info "Network '$network_name' does not exist → creating it now..."
        if docker network create "$network_name"; then
            log_success "Docker network created successfully: $network_name"
        else
            log_error "Failed to create Docker network: $network_name"
            exit 1
        fi
    fi
}

# ---------------------------------------------------------------------------
# clean_license_files
# ---------------------------------------------------------------------------
clean_license_files() {
    log_info "Cleaning license server runtime files ..."

    local lock_file="./$IDOL_LICENSESERVER_NAME/licenseserver.lck"
    if [ -f "$lock_file" ]; then
        sudo rm -f "$lock_file" && log_success "Removed lock file: $lock_file" || { log_error "Failed to remove lock file: $lock_file"; exit 1; }
    else
        log_info "Lock file not present (normal on first run): $lock_file"
    fi

    local uid_dir="./$IDOL_LICENSESERVER_NAME/uid"
    if [ -d "$uid_dir" ]; then
        sudo rm -rf "$uid_dir" && log_success "Removed uid directory: $uid_dir" || { log_error "Failed to remove uid directory: $uid_dir"; exit 1; }
    else
        log_info "uid directory not present: $uid_dir"
    fi

    local license_subdir="./$IDOL_LICENSESERVER_NAME/license"
    if [ -d "$license_subdir" ]; then
        sudo rm -rf "$license_subdir" && log_success "Removed license directory: $license_subdir" || { log_error "Failed to remove license directory: $license_subdir"; exit 1; }
    else
        log_info "license subdirectory not present: $license_subdir"
    fi
}

# ---------------------------------------------------------------------------
# License Server Status Management
# ---------------------------------------------------------------------------
set_license_active_status() {
    local status="${1:-FALSE}"
    export IS_IDOL_LICENSE_ACTIVE="${status}"

    local pre_setup_file="${SCRIPT_DIR}/../pre-setup.sh"

    if [ -f "$pre_setup_file" ]; then
        if sed -i "s/^export IS_IDOL_LICENSE_ACTIVE=.*$/export IS_IDOL_LICENSE_ACTIVE=${status}/" "$pre_setup_file"; then
            log_info "✅ Updated pre-setup.sh → IS_IDOL_LICENSE_ACTIVE=${status}"
        else
            log_warning "Failed to update pre-setup.sh (sed error)"
        fi
    else
        log_warning "pre-setup.sh not found at ${pre_setup_file} — only current shell updated"
    fi

    if [ "${status}" = "TRUE" ]; then
        log_success "IS_IDOL_LICENSE_ACTIVE set to TRUE - License server is ACTIVE"
    else
        log_info "IS_IDOL_LICENSE_ACTIVE set to FALSE - License server is INACTIVE"
    fi
}

# ---------------------------------------------------------------------------
# initialize_connection_params
# ---------------------------------------------------------------------------
initialize_connection_params() {
    if [ "${IDOL_LICENSESERVER_MODE:-}" = "NEW" ]; then
        log_info "IDOL_LICENSESERVER_MODE=NEW — connection params are set to localhost defaults"
        license_server_domain="localhost"
        license_server_port="20000"
        license_server_protocol="${IDOL_LICENSESERVER_PROTOCOL:-http}"
    else
        log_info "IDOL_LICENSESERVER_MODE is not NEW — connection params are derived from env vars"
        license_server_domain="${IDOL_LICENSESERVER_FQDN}"
        license_server_port="${IDOL_LICENSESERVER_PORT}"
        license_server_protocol="${IDOL_LICENSESERVER_PROTOCOL}"
    fi

    export IDOL_LICENSESERVER_PROTOCOL="$license_server_protocol"

    log_info "  → protocol : ${license_server_protocol}"
    log_info "  → domain   : ${license_server_domain}"
    log_info "  → port     : ${license_server_port}"

    if [ "$license_server_protocol" = "https" ]; then
        curl_opts="-k -s"
    else
        curl_opts="-s"
    fi

    log_info "License server endpoint → ${license_server_protocol}://${license_server_domain}:${license_server_port}"
}

# ---------------------------------------------------------------------------
# stop_existing_server
# ---------------------------------------------------------------------------
stop_existing_server() {
    log_info "Stopping existing license server containers (if any) ..."

    if "${DOCKER_COMPOSE_CMD[@]}" ps -q licenseserver 2>/dev/null | grep -q .; then
        log_info "Found running license server — stopping ..."
        if "${DOCKER_COMPOSE_CMD[@]}" down; then
            log_success "Stopped existing license server"
            set_license_active_status "FALSE"
        else
            log_error "Failed to stop existing license server"
            set_license_active_status "FALSE"
        fi
    else
        log_info "No running license server found"
        set_license_active_status "FALSE"
    fi
}

# ---------------------------------------------------------------------------
# start_license_server
# ---------------------------------------------------------------------------
start_license_server() {
    log_info "Building licenseserver Docker image ..."
    docker build -t licenseserver .

    log_info "Starting license server container ..."
    set_license_active_status "TRUE"

    if "${DOCKER_COMPOSE_CMD[@]}" up -d; then
        log_success "License server container started"
    else
        log_error "Failed to start license server container"
        set_license_active_status "FALSE"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# wait_for_service
# ---------------------------------------------------------------------------
wait_for_service() {
    log_info "Waiting for license server to be ready ..."

    local count=0
    local max_attempts=$(( health_check_timeout / health_check_interval ))
    local url="${license_server_protocol}://${license_server_domain}:${license_server_port}/a=getlicenseinfo"

    log_info "Health-check URL: ${url}"

    while [ $count -lt $max_attempts ]; do
        if curl $curl_opts --connect-timeout 5 "$url" >/dev/null 2>&1; then
            log_success "License server is ready!"
            return 0
        fi
        count=$(( count + 1 ))
        log_info "Attempt $count/$max_attempts — not ready yet, waiting ${health_check_interval}s ..."
        sleep $health_check_interval
    done

    log_error "License server did not become ready within ${health_check_timeout} seconds"
    log_info "Container logs (last 20 lines):"
    "${DOCKER_COMPOSE_CMD[@]}" logs licenseserver --tail=20 || true
    return 1
}

# ---------------------------------------------------------------------------
# test_license_server
# ---------------------------------------------------------------------------
test_license_server() {
    log_info "Testing license server functionality ..."

    local url="${license_server_protocol}://${license_server_domain}:${license_server_port}/a=getlicenseinfo"
    local response
    if response=$(curl $curl_opts --connect-timeout 10 "$url" 2>&1); then
        log_success "License server is responding"
        log_info "Response preview: ${response:0:200}..."
        return 0
    else
        log_error "License server test failed: $response"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# show_status
# ---------------------------------------------------------------------------
show_status() {
    log_info "Deployment Status:"
    echo "===================="

    log_info "Container status:"
    "${DOCKER_COMPOSE_CMD[@]}" ps

    log_info "Network status:"
    docker network ls | grep "$network_name" || log_warning "Network $network_name not found"

    log_info "Port status:"
    if ss -lnp | grep -q ":${license_server_port} "; then
        log_success "Port $license_server_port is listening"
    else
        log_warning "Port $license_server_port not detected in ss output"
    fi

    echo "===================="
}

# ---------------------------------------------------------------------------
# Lightweight start / stop / restart handlers
# ---------------------------------------------------------------------------
start_license_server_only() {
    log_info "Starting license server (quick mode) ..."
    set_license_active_status "TRUE"

    if "${DOCKER_COMPOSE_CMD[@]}" up -d --force-recreate; then
        log_success "License server started successfully"
    else
        log_error "Failed to start license server"
        set_license_active_status "FALSE"
        exit 1
    fi
}

stop_license_server_only() {
    log_info "Stopping license server ..."
    if "${DOCKER_COMPOSE_CMD[@]}" ps -q licenseserver 2>/dev/null | grep -q .; then
        if "${DOCKER_COMPOSE_CMD[@]}" down; then
            log_success "License server stopped"
            set_license_active_status "FALSE"
        else
            log_error "Failed to stop license server"
            set_license_active_status "FALSE"
        fi
    else
        log_info "No running license server found"
        set_license_active_status "FALSE"
    fi
}

restart_license_server() {
    log_info "Restarting license server ..."
    stop_license_server_only
    sleep 2
    start_license_server_only
}

show_license_status() {
    log_info "License Server Status:"
    echo "===================="

    if "${DOCKER_COMPOSE_CMD[@]}" ps -q licenseserver 2>/dev/null | grep -q .; then
        log_success "Container is RUNNING"
    else
        log_warning "Container is STOPPED"
    fi

    log_info "IS_IDOL_LICENSE_ACTIVE = ${IS_IDOL_LICENSE_ACTIVE:-NOT_SET}"
    echo "===================="
}

# ---------------------------------------------------------------------------
# configure_license_deployment_scripts
# ---------------------------------------------------------------------------
configure_license_deployment_scripts() {
    local idol_licenseserver_fqdn="$1"
    local license_server_name="$2"
    local mac_address="$3"
    local protocol="$4"
    local licenseserver_idol_common_cfg="$5"
    local licenseserver_licenseserver_cfg="$6"
    local common_idol_common_cfg="$7"

    log_info "Configuring IDOL license server deployment scripts ..."
    log_info "  FQDN                             : ${YELLOW}${idol_licenseserver_fqdn}${NC}"
    log_info "  License Server Name              : ${YELLOW}${license_server_name}${NC}"
    log_info "  MAC Address                      : ${YELLOW}${mac_address}${NC}"
    log_info "  Protocol                         : ${YELLOW}${protocol}${NC}"
    log_info "  licenseserver/idol.common.cfg    : ${YELLOW}${licenseserver_idol_common_cfg}${NC}"
    log_info "  licenseserver.cfg                : ${YELLOW}${licenseserver_licenseserver_cfg}${NC}"
    log_info "  common idol.common.cfg           : ${YELLOW}${common_idol_common_cfg}${NC}"

    [[ ! -f "$licenseserver_idol_common_cfg" ]] && { log_error "licenseserver idol.common.cfg not found at: ${licenseserver_idol_common_cfg}"; return 1; }
    [[ ! -f "$licenseserver_licenseserver_cfg" ]] && { log_error "licenseserver.cfg not found at: ${licenseserver_licenseserver_cfg}"; return 1; }
    [[ ! -f "$common_idol_common_cfg" ]] && { log_error "common idol.common.cfg not found at: ${common_idol_common_cfg}"; return 1; }

    log_info "Changing execution mode of $IDOL_LICENSESERVER_NAME to [chmod +x ./*]"
    if ! sudo chmod +x "./$IDOL_LICENSESERVER_NAME"/*; then
        log_error "Failed to change execution mode of ./$IDOL_LICENSESERVER_NAME"
        return 1
    fi

    log_info "Copying config files into ./$IDOL_LICENSESERVER_NAME ..."
    cp -f "${IDOL_PRESERVE_LICENSESERVER_CFG_PATH}/idol.common.cfg" "./$IDOL_LICENSESERVER_NAME/" \
        && log_success "Copied idol.common.cfg → ./$IDOL_LICENSESERVER_NAME/idol.common.cfg" \
        || { log_error "Failed to copy idol.common.cfg"; return 1; }

    cp -f "${IDOL_PRESERVE_LICENSESERVER_CFG_PATH}/licenseserver.cfg" "./$IDOL_LICENSESERVER_NAME/" \
        && log_success "Copied licenseserver.cfg → ./$IDOL_LICENSESERVER_NAME/licenseserver.cfg" \
        || { log_error "Failed to copy licenseserver.cfg"; return 1; }

    # Update LicenseServerHost
    log_info "Updating LicenseServerHost in idol.common.cfg ..."
    if ! sudo sed -i "s|^\(//\)\{0,1\}LicenseServerHost=.*|LicenseServerHost=${idol_licenseserver_fqdn}|g" "${licenseserver_idol_common_cfg}"; then
        log_error "Failed to update LicenseServerHost in ./$IDOL_LICENSESERVER_NAME/idol.common.cfg"
        return 1
    fi
    log_success "LicenseServerHost updated in idol.common.cfg [LicenseServerHost=${idol_licenseserver_fqdn}]"

    cp -f "${licenseserver_idol_common_cfg}" "${IDOL_LICENSESERVER_NAME}/idol.common.cfg" \
        && log_success "Backed up updated idol.common.cfg" \
        || log_warning "Failed to back up updated idol.common.cfg"

    # ------------------------------------------------------------------------
    # SSLConfig handling (single clean block)
    # ------------------------------------------------------------------------
    log_info "Updating SSLConfig for protocol [${protocol}] ..."

    if [ "$protocol" = "http" ]; then
        sudo sed -i 's|^\(//\)\{0,1\}SSLConfig=LicenseSSL|//SSLConfig=LicenseSSL|g' "$licenseserver_licenseserver_cfg"
        log_success "SSLConfig disabled in licenseserver.cfg"
        sudo sed -i 's|^\(//\)\{0,1\}SSLConfig=LicenseSSL|//SSLConfig=LicenseSSL|g' "$licenseserver_idol_common_cfg"
        log_success "SSLConfig disabled in licenseserver/idol.common.cfg"
        sudo sed -i 's|^\(//\)\{0,1\}SSLConfig=LicenseSSL|//SSLConfig=LicenseSSL|g' "$common_idol_common_cfg"
        log_success "SSLConfig disabled in common idol.common.cfg"
    else
        sudo sed -i 's|^\(//\)\{0,1\}SSLConfig=LicenseSSL|SSLConfig=LicenseSSL|g' "$licenseserver_licenseserver_cfg"
        log_success "SSLConfig enabled in licenseserver.cfg"
        sudo sed -i 's|^\(//\)\{0,1\}SSLConfig=LicenseSSL|SSLConfig=LicenseSSL|g' "$licenseserver_idol_common_cfg"
        log_success "SSLConfig enabled in licenseserver/idol.common.cfg"
        sudo sed -i 's|^\(//\)\{0,1\}SSLConfig=LicenseSSL|SSLConfig=LicenseSSL|g' "$common_idol_common_cfg"
        log_success "SSLConfig enabled in common idol.common.cfg"
    fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    local cli_protocol="${1:-}"
    local source_license_server_path="${2:-}"
    local source_license_key_path="${3:-}"
    local mac_address="${4:-}"
    local has_cli_args="false"

    log_info "Starting License Server Deployment"
    echo "===================================="

    initialize_connection_params
    set_license_active_status "FALSE"

    # Protocol resolution (original logic preserved)
    if [ -n "${IDOL_LICENSESERVER_URL:-}" ]; then
        log_info "Protocol locked by IDOL_LICENSESERVER_URL : ${YELLOW}${license_server_protocol}${NC}"
        if [ -n "$cli_protocol" ] && [ "$cli_protocol" != "$license_server_protocol" ]; then
            log_warning "CLI protocol arg '${cli_protocol}' ignored — IDOL_LICENSESERVER_URL takes precedence"
        fi
    else
        if [ -n "$cli_protocol" ]; then
            license_server_protocol="$cli_protocol"
            log_info "Protocol from CLI argument          : ${YELLOW}${license_server_protocol}${NC}"
        else
            license_server_protocol="${IDOL_LICENSESERVER_PROTOCOL}"
            log_info "Protocol from env / default         : ${YELLOW}${license_server_protocol}${NC}"
        fi
    fi

    if [ "$license_server_protocol" != "http" ] && [ "$license_server_protocol" != "https" ]; then
        log_error "Invalid protocol '${license_server_protocol}'. Accepted values: http | https"
        exit 1
    fi

    log_info "curl options                        : ${YELLOW}${curl_opts}${NC}"

    # Populate env vars from CLI args
    if [ -n "$source_license_server_path" ] && [ -n "$source_license_key_path" ] && [ -n "$mac_address" ]; then
        has_cli_args="true"
    fi

    if [ -n "$source_license_server_path" ]; then
        export SOURCE_IDOL_LICENSE_SERVER_PATH="$source_license_server_path"
        export IDOL_LICENSESERVER_NAME="$(basename "$source_license_server_path")"
        log_info "SOURCE_IDOL_LICENSE_SERVER_PATH      : ${YELLOW}${SOURCE_IDOL_LICENSE_SERVER_PATH}${NC}"
        log_info "IDOL_LICENSESERVER_NAME (extracted) : ${YELLOW}${IDOL_LICENSESERVER_NAME}${NC}"
    fi

    if [ -n "$source_license_key_path" ]; then
        export SOURCE_IDOL_LICENSE_KEY_PATH="$source_license_key_path"
        log_info "SOURCE_IDOL_LICENSE_KEY_PATH         : ${YELLOW}${SOURCE_IDOL_LICENSE_KEY_PATH}${NC}"
    fi

    if [ -n "$mac_address" ]; then
        export IDOL_LICENSE_KEY_MAC="$mac_address"
        log_info "IDOL_LICENSE_KEY_MAC                 : ${YELLOW}${IDOL_LICENSE_KEY_MAC}${NC}"
    fi

    log_info "IDOL_LICENSESERVER_FQDN              : ${YELLOW}${IDOL_LICENSESERVER_FQDN:-localhost}${NC}"
    log_info "IDOL_DEPLOYMENT_TYPE                 : ${YELLOW}${IDOL_DEPLOYMENT_TYPE}${NC}"
    log_info "Network name                         : ${YELLOW}${network_name}${NC}"

    # Refresh docker-compose file from template
    log_info "Refreshing ${docker_compose_file} from template..."
    rm -f "${docker_compose_file}"
    cp "${IDOL_BASE_PATH}/templates/license-server/template-script/docker-compose.licenseserver.yml-template" "${docker_compose_file}"
    log_success "docker-compose file refreshed from template"

    # Placeholder replacement
    echo -e "🔧 ${ORANGE}Executing config placeholders replacement...${NC}"
    if [ ! -f "$SCRIPT_PATH" ]; then
        echo -e "${RED}❌ Error: placeholders-replacement.sh not found at: $SCRIPT_PATH${NC}"
        exit 1
    fi
    if bash "$SCRIPT_PATH" -d licenseserver; then
        echo -e "${GREEN}✅ Config Placeholders Replacement for [-d licenseserver] PASSED${NC}"
    else
        EXIT_CODE=$?
        echo -e "${RED}❌ Config Placeholders Replacement failed with exit code [$EXIT_CODE]${NC}"
        exit 1
    fi

    load_environment "$has_cli_args"
    validate_prerequisites
    setup_docker_network
    stop_existing_server
    clean_license_files

    configure_license_deployment_scripts \
        "${IDOL_LICENSESERVER_FQDN:-localhost}" \
        "$IDOL_LICENSESERVER_NAME" \
        "$IDOL_LICENSE_KEY_MAC" \
        "$license_server_protocol" \
        "${IDOL_PRESERVE_LICENSESERVER_CFG_PATH}/idol.common.cfg" \
        "${IDOL_PRESERVE_LICENSESERVER_CFG_PATH}/licenseserver.cfg" \
        "$IDOL_PRESERVE_IDOL_COMMON_CFG_PATH/$IDOL_PRESERVE_IDOL_COMMON_CFG_FILENAME"

    start_license_server

    if ! wait_for_service; then
        log_error "License server deployment failed — service did not become ready"
        show_status
        exit 1
    fi

    if ! test_license_server; then
        log_error "License server deployment failed — API test failed"
        show_status
        exit 1
    fi

    show_status

    local url="${license_server_protocol}://${license_server_domain}:${license_server_port}"
    log_info "License server URL  : ${url}"
    log_info "Test command        : curl ${curl_opts} --connect-timeout 10 ${url}/a=getlicenseinfo"

    echo -e "${LIGHTER_YELLOW}"
    curl $curl_opts --connect-timeout 10 "${url}/a=getlicenseinfo"
    echo -e "${NC}"

    log_success "License Server Deployment Completed Successfully!"
}

# ---------------------------------------------------------------------------
# usage 
# ---------------------------------------------------------------------------
usage() {
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    IDOL License Server Deployment Script${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}USAGE:${NC}"
    echo -e "  ${LIGHTER_YELLOW}$0${NC}                                          # use environment variables"
    echo -e "  ${LIGHTER_YELLOW}$0 <http|https> <SERVER_PATH> <KEY_PATH> <MAC>${NC}  # use CLI arguments"
    echo -e "  ${LIGHTER_YELLOW}$0 start${NC}                                     # start only"
    echo -e "  ${LIGHTER_YELLOW}$0 stop${NC}                                      # stop only"
    echo -e "  ${LIGHTER_YELLOW}$0 restart${NC}                                   # restart"
    echo -e "  ${LIGHTER_YELLOW}$0 status${NC}                                    # show status"
    echo -e "  ${LIGHTER_YELLOW}$0 --help | --version${NC}"
    echo ""
    echo -e "${YELLOW}COMMANDS:${NC}"
    echo -e "  start    → Starts the license server container and sets IS_IDOL_LICENSE_ACTIVE=TRUE"
    echo -e "  stop     → Stops the license server container and sets IS_IDOL_LICENSE_ACTIVE=FALSE"
    echo -e "  restart  → stop + start"
    echo -e "  status   → Shows container + IS_IDOL_LICENSE_ACTIVE status"
    echo ""
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    -v|--version)
        echo "License Server Deployment Script v1.11"
        exit 0
        ;;
    "")
        echo ""
        log_error "════════════════════════════════════════════════════════════════════════════════"
        log_error "                         NO ARGUMENTS PROVIDED"
        log_error "════════════════════════════════════════════════════════════════════════════════"
        echo ""
        log_error "This script requires either a subcommand or 4 deployment arguments."
        echo ""
        log_error "SUBCOMMANDS:"
        echo -e "  ${LIGHTER_YELLOW}$0 start${NC}                                     # start the license server container"
        echo -e "  ${LIGHTER_YELLOW}$0 stop${NC}                                      # stop the license server container"
        echo -e "  ${LIGHTER_YELLOW}$0 restart${NC}                                   # restart the license server container"
        echo -e "  ${LIGHTER_YELLOW}$0 status${NC}                                    # show container and license status"
        echo ""
        log_error "FULL DEPLOYMENT (4 arguments required):"
        echo -e "  ${LIGHTER_YELLOW}$0 <http|https> <SERVER_PATH> <KEY_PATH> <MAC_ADDRESS>${NC}"
        echo ""
        log_error "Run '$0 --help' for full documentation."
        log_error "════════════════════════════════════════════════════════════════════════════════"
        echo ""
        exit 1
        ;;
    start)
        initialize_connection_params
        validate_prerequisites
        setup_docker_network
        stop_existing_server
        clean_license_files
        start_license_server_only
        wait_for_service
        test_license_server
        show_license_status
        ;;
    stop)
        initialize_connection_params
        validate_prerequisites
        stop_license_server_only
        show_license_status
        ;;
    restart)
        initialize_connection_params
        validate_prerequisites
        setup_docker_network
        restart_license_server
        wait_for_service
        test_license_server
        show_license_status
        ;;
    status)
        initialize_connection_params
        validate_prerequisites
        show_license_status
        ;;
    *)
        if [ "$#" -eq 4 ]; then
            main "$1" "$2" "$3" "$4"
        else
            log_error "Invalid number of arguments: $# (expected 0, 4, or one of: start|stop|restart|status)"
            usage
            exit 1
        fi
        ;;
esac
