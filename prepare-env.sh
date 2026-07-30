#!/bin/bash
# OpenText IDOL on Ubuntu 24.04
# Fully refactored & cleaned version - March 2026

set -u

# =============================================================================
# COLORS & CONFIG
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
LIGHTER_YELLOW='\033[38;5;228m'
BLUE='\033[0;34m'
ORANGE='\033[0;38;5;214m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

SILENT_MODE="false"
EXE_SCRIPT_NAME=$(basename "$0")
BASE_IDOL_SETUP_DIR="$IDOL_BASE_PATH"

# =============================================================================
# TRAP – run cleanup/recovery on any unexpected (non-zero) exit
# =============================================================================
_trap_on_error() {
    local exit_code=$?
    local line_no=${1:-"unknown"}
    if [ "$exit_code" -ne 0 ]; then
        echo -e "${RED}[TRAP] Script failed at line ${line_no} (exit code: ${exit_code})...${NC}" >&2
        exit "$exit_code"   # <-- re-exit with the original failure code
    fi
}
trap '_trap_on_error $LINENO' EXIT
export LOGFILE="$BASE_IDOL_SETUP_DIR/logs/${EXE_SCRIPT_NAME%.*}_$(date +"%Y%m%d").log"
mkdir -p "$(dirname "$LOGFILE")"

export IDOL_ENV="$BASE_IDOL_SETUP_DIR/env/env_variables_${EXE_SCRIPT_NAME%.*}_$(date +"%Y%m%d").env"
mkdir -p "$(dirname "$IDOL_ENV")"

# =============================================================================
# UTILITIES
# =============================================================================
source "$BASE_IDOL_SETUP_DIR/module/general-utilities.code"
source "$BASE_IDOL_SETUP_DIR/module/pre-setup.code"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Define source hotfolder relative to the script
HOTFOLDER_SOURCE="${SCRIPT_DIR}/persistent-data/nifi-data/hotfolder"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================
verify_docker() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [verify_docker] module${ORANGE}"
    if command -v docker &>/dev/null; then
        client_version=$(docker version --format '{{.Client.Version}}' 2>/dev/null)
        if [ $? -ne 0 ]; then
            log "${CALLING_SCRIPT} ${YELLOW}Docker client exists but may not be functioning properly.${NC}"
            return 1
        fi
        client_major_version=$(echo "$client_version" | cut -d'.' -f1)
        if [ "$client_major_version" -ge 28 ] && docker info &>/dev/null; then
            log "${CALLING_SCRIPT} ${GREEN}Docker $client_version is installed and running correctly.${NC}"
            return 0
        else
            log "${CALLING_SCRIPT} ${YELLOW}Docker version is too old or daemon is not responding.${NC}"
            return 1
        fi
    else
        log "${CALLING_SCRIPT} ${RED}Docker is not installed.${NC}"
        return 1
    fi
}

verify_docker_compose() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [verify_docker_compose] module${ORANGE}"
    if command -v docker-compose &>/dev/null || docker compose version &>/dev/null; then
        log "${CALLING_SCRIPT} ${GREEN}Docker Compose is installed.${NC}"
        return 0
    else
        log "${CALLING_SCRIPT} ${RED}Docker Compose is not installed.${NC}"
        return 1
    fi
}

diagnose_docker_installation() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${BOLD} Docker Installation Diagnostics ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    # (full diagnostic output kept exactly as original)
    if command -v docker &> /dev/null; then
        echo -e " ${GREEN}✓ Docker binary found: $(which docker)${NC}"
        docker --version 2>/dev/null || echo -e " ${RED}✗${NC} Cannot get Docker version"
    else
        echo -e " ${RED}✗ Docker binary not found in PATH${NC}"
    fi
    echo ""
    echo -e "${BOLD}${YELLOW}2. Installation Method:${NC}"
    echo " -------------------"
    if command -v snap &> /dev/null && snap list docker &> /dev/null 2>&1; then
        echo -e " ${GREEN}✓ Docker installed via Snap${NC}"
    elif [ -f /etc/systemd/system/docker.service ] || [ -f /lib/systemd/system/docker.service ]; then
        echo -e " ${GREEN}✓ Docker installed with systemd service${NC}"
    else
        echo -e " ${YELLOW}⚠ Docker binary exists but no service manager found${NC}"
    fi
    echo ""
    echo -e "${BOLD}${YELLOW}3. Docker Service Status:${NC}"
    echo " ----------------------"
    if systemctl list-unit-files docker.service &> /dev/null; then
        sudo systemctl status docker.service --no-pager --lines=10 || true
    else
        echo -e " ${RED}✗ Docker service not found in systemd${NC}"
    fi
    echo ""
    echo -e "${BOLD}${YELLOW}4. Containerd Status:${NC}"
    echo " ------------------"
    if systemctl list-unit-files containerd.service &> /dev/null; then
        sudo systemctl status containerd --no-pager --lines=5 || true
    else
        echo -e " ${RED}✗ Containerd service not found${NC}"
    fi
    echo ""
    echo -e "${BOLD}${YELLOW}5. Docker Daemon Test:${NC}"
    echo " -------------------"
    if sudo docker info &> /dev/null; then
        echo -e " ${GREEN}✓ Docker daemon is accessible${NC}"
    else
        echo -e " ${RED}✗ Cannot connect to Docker daemon${NC}"
    fi
    echo ""
    echo -e "${BOLD}${YELLOW}6. System Resources:${NC}"
    echo " -----------------"
    echo -e " ${BLUE}Disk Space:${NC}"
    df -h / | tail -n 1
    echo -e " ${BLUE}Memory:${NC}"
    free -h | grep "^Mem:"
    echo ""
}

install_docker() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [install_docker] module${ORANGE}"
    log "${CALLING_SCRIPT} ${YELLOW}Installing Docker...${NC}"
    sudo apt update -y
    sudo apt remove -y docker docker-engine docker.io containerd runc &>/dev/null || true
    sudo apt install -y apt-transport-https ca-certificates curl gnupg-agent lsb-release software-properties-common
    sudo mkdir -p /etc/apt/keyrings
    sudo chmod 755 /etc/apt/keyrings/
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update -y
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo chmod 666 /var/run/docker.sock
    sudo systemctl stop docker.socket docker.service 2>/dev/null || true
    sudo rm -rf /var/lib/docker/network/files/ /var/lib/docker/runtimes/
    if sudo systemctl start docker; then
        log "${CALLING_SCRIPT} ✅${GREEN}Docker service started successfully${NC}"
    else
        log "${CALLING_SCRIPT} ⚠️${LIGHTER_YELLOW}Docker service failed to start. Attempting recovery...${NC}"
        sudo systemctl reset-failed docker.service 2>/dev/null || true
        sleep 2
        sudo systemctl start docker || {
            log "${CALLING_SCRIPT} ❌${RED}Docker failed to start after recovery${NC}"
            diagnose_docker_installation
            return 1
        }
    fi
    sudo groupadd -f docker
    if [ -n "${SUDO_USER:-}" ]; then
        MAINUSER="$SUDO_USER"
    else
        MAINUSER=$(logname 2>/dev/null || echo "${USER:-root}")
    fi
    sudo usermod -aG docker "$MAINUSER"
    log "${CALLING_SCRIPT} ✅${GREEN}Docker installed successfully.${NC}"
}

install_docker_compose() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [install_docker_compose] module${ORANGE}"
    log "${CALLING_SCRIPT} ${YELLOW}Installing Docker Compose...${NC}"
    if docker compose version &>/dev/null; then
        log "${CALLING_SCRIPT} ${GREEN}Docker Compose plugin is already installed.${NC}"
        return 0
    fi
    LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    sudo curl -L "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    if docker-compose --version &>/dev/null; then
        log "${CALLING_SCRIPT} ✅${GREEN}Docker Compose installed successfully.${NC}"
        return 0
    else
        log "${CALLING_SCRIPT} ${RED}Docker Compose installation failed.${NC}"
        return 1
    fi
}

check_idol_prerequisites() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [check_idol_prerequisites] module${ORANGE}"
    log "${CALLING_SCRIPT} ${YELLOW}Checking IDOL Prerequisites...${NC}"
    local missing_prereqs=()
    ! command -v java &>/dev/null && missing_prereqs+=("java (openjdk-21-jdk)")
    ! command -v openssl &>/dev/null && missing_prereqs+=("openssl")
    ! command -v jq &>/dev/null && missing_prereqs+=("jq")
    ! command -v docker &>/dev/null && missing_prereqs+=("docker")
    ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null && missing_prereqs+=("docker-compose")
    if [ ${#missing_prereqs[@]} -eq 0 ]; then
        log "${CALLING_SCRIPT} ✅${GREEN}All prerequisites are installed!${NC}"
        return 0
    else
        log "${CALLING_SCRIPT} ⚠️${YELLOW}Missing prerequisites:${NC}"
        for prereq in "${missing_prereqs[@]}"; do
            log "${CALLING_SCRIPT} - ${RED}${prereq}${NC}"
        done
        return 1
    fi
}

validate_license_server_source_environment_variables() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [validate_license_server_source_environment_variables] module${ORANGE}"
    log "${CALLING_SCRIPT} ${YELLOW}Validating License Server Source Environment Variables...${NC}"
    if [ -z "${SOURCE_IDOL_LICENSE_KEY_PATH+x}" ] || [ -z "${SOURCE_IDOL_LICENSE_SERVER_PATH+x}" ]; then
        log "${CALLING_SCRIPT} ${RED}Error: License Server source paths are not properly set${NC}"
        exit 1
    fi
    if [ ! -d "$SOURCE_IDOL_LICENSE_SERVER_PATH" ]; then
        log "${CALLING_SCRIPT} ${RED}Source license server folder does not exist: ${YELLOW}$SOURCE_IDOL_LICENSE_SERVER_PATH${NC}"
        exit 1
    fi
    if [ ! -f "$SOURCE_IDOL_LICENSE_KEY_PATH" ]; then
        log "${CALLING_SCRIPT} ${RED}Source license key file does not exist: ${YELLOW}$SOURCE_IDOL_LICENSE_KEY_PATH${NC}"
        exit 1
    fi
    log "${CALLING_SCRIPT} ${GREEN}License Server Source paths are valid.${NC}"
}

validate_cert_passwords() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [validate_cert_passwords] module${ORANGE}"
    log "${CALLING_SCRIPT} ${YELLOW}Validating certificate password variables...${NC}"
    local missing=()
    [ -z "${IDOL_CERT_KEYSTORE_PASS+x}" ] && missing+=("IDOL_CERT_KEYSTORE_PASS")
    [ -z "${IDOL_CERT_TRUSTSTORE_PASS+x}" ] && missing+=("IDOL_CERT_TRUSTSTORE_PASS")
    if [ ${#missing[@]} -gt 0 ]; then
        log "${CALLING_SCRIPT} ${RED}❌ Required certificate variables are missing:${NC}"
        for var in "${missing[@]}"; do log "${CALLING_SCRIPT} • ${RED}${var}${NC}"; done
        exit 1
    else
        log "${CALLING_SCRIPT} ${GREEN}✅ Certificate passwords are correctly set.${NC}"
    fi
}

validate_idol_prerequisites() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [validate_idol_prerequisites] module${ORANGE}"
    log "${CALLING_SCRIPT} ${YELLOW}Validating IDOL Prerequisites...${NC}"
    update_file_row "$IDOL_ENV" "export IS_IDOL_VALIDATION_MET" "UNVALIDATION" "=" "$SILENT_MODE" "$SILENT_MODE"
    if prompt_yn "Are you considering validate IDOL prerequisites?" "Y"; then
        validate_idol_components
        update_file_row "$IDOL_ENV" "export IS_IDOL_VALIDATION_MET" "TRUE" "=" "$SILENT_MODE" "$SILENT_MODE"
    fi
}

validate_idol_components() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [validate_idol_components] module${ORANGE}"
    log "${CALLING_SCRIPT} ${YELLOW}Validating IDOL Components...${NC}"
    command_exists openssl || error_exit "OpenSSL is not installed."
    if ! command_exists java; then
        echo -e "${YELLOW}JAVA is not installed.${RED}"
        if prompt_yn "Do you want to install openjdk-21-jdk now?" "Y"; then
            sudo apt install openjdk-21-jdk || error_exit "JAVA installation failed."
            echo -e "${GREEN}JAVA was installed successfully. Please re-run the script.${NC}"
            exit 1
        else
            error_exit "JAVA installation cancelled."
        fi
    fi
    if ! command_exists docker; then
        install_docker
        verify_docker || error_exit "Docker installation failed."
    fi
    if ! command_exists docker-compose && ! docker compose version &>/dev/null; then
        install_docker_compose
        verify_docker_compose || error_exit "Docker Compose installation failed."
    fi
    log "${CALLING_SCRIPT} ✅${GREEN}All prerequisites met!${NC}"
}

###########################################################################
## Generic folder structure refresher for any deployment subtype
## Private helper: process one subtype given explicit paths
## Usage: _process_single_subtype <label> <target_folder> <templates_folder>
##        (or any other subtype like "basic-idol", "rich-media")
###########################################################################
_process_single_subtype() {
    local label="$1"
    local target_folder="$2"
    local templates_folder="$3"

    # ── Validate templates folder ─────────────────────────────────────────────
    if [[ ! -d "$templates_folder" ]]; then
        log "${CALLING_SCRIPT} ${RED}Error: Templates folder does not exist: ${YELLOW}${templates_folder}${NC}"
        return 1
    fi

    echo -e "${CYAN}→ Refreshing ${label} folder structure...${NC}"
    echo -e "${CYAN}DEBUG: Target folder   →${NC} ${YELLOW}$(realpath "$target_folder" 2>/dev/null || echo "$target_folder")${NC}"
    echo -e "${CYAN}DEBUG: Current directory →${NC} ${YELLOW}$BASE_IDOL_SETUP_DIR${NC}"

    # ── Create target folder owned by the correct user ────────────────────────
    # NOTE: this performs `rm -rf "$target_folder"` internally, which destroys
    # any pre-setup.sh copy that was placed here earlier (e.g. by the master
    # setup script in STEP 2/5). We must restore it below.
    create_directory_as_user "$target_folder"

    # ── Restore pre-setup.sh into the freshly-recreated target folder ────────
    local PRE_SETUP_BACKUP="${IDOL_BASE_PATH}/pre-setup-backup.sh"
    local PRE_SETUP_DEST="${target_folder}/pre-setup.sh"

    if [[ -s "$PRE_SETUP_BACKUP" ]]; then
        if cp -f "$PRE_SETUP_BACKUP" "$PRE_SETUP_DEST"; then
            log "${CALLING_SCRIPT} ${GREEN}✅ Restored pre-setup.sh → ${ORANGE}${PRE_SETUP_DEST}${NC}"
        else
            log "${CALLING_SCRIPT} ${RED}❌ Failed to restore pre-setup.sh → ${ORANGE}${PRE_SETUP_DEST}${NC}"
            return 1
        fi
    else
        log "${CALLING_SCRIPT} ${YELLOW}⚠ pre-setup-backup.sh not found or empty at ${ORANGE}${PRE_SETUP_BACKUP}${YELLOW} — skipping restore for ${label}.${NC}"
    fi

    echo -e "${CYAN}→ Copying ALL files and folders recursively from template...${NC}"

    if ! cp -af "$templates_folder/." "$target_folder/" 2>/dev/null; then
        echo -e "${RED}✗ Failed to copy template structure (check permissions)${NC}"
        return 1
    fi

    # ── Rename *-template files (recursive, handles extensions) ──────────────
    local renamed=0
    echo -e "${CYAN}→ Renaming *-template files (removing suffix)...${NC}"

    while IFS= read -r -d '' item; do
        local dirname basename new_basename
        dirname=$(dirname "$item")
        basename=$(basename "$item")
        new_basename="$basename"

        if [[ $basename == *-template.* ]]; then
            local name_part ext
            name_part="${basename%-template.*}"
            ext="${basename##*.}"
            new_basename="${name_part}.${ext}"
        elif [[ $basename == *-template ]]; then
            new_basename="${basename%-template}"
        fi

        if [[ "$basename" != "$new_basename" ]]; then
            if mv "$item" "$dirname/$new_basename" 2>/dev/null; then
                echo -e "  ${BLUE}→${NC} ${YELLOW}$basename${NC} → ${GREEN}$new_basename${NC} ${GREEN}[OK]${NC}"
                ((renamed++))
            else
                echo -e "  ${RED}✗ Failed to rename${NC} $basename"
            fi
        fi
    done < <(find "$target_folder" -name '*-template*' -print0 2>/dev/null)

    echo -e "${GREEN}✓ Successfully refreshed ${label} folder structure [${renamed} items renamed]${NC}"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Public: orchestrate folder structure refresh for a given deployment subtype
# Possible values: basic-idol | data-admin | licenseserver | llm | rich-media
# ─────────────────────────────────────────────────────────────────────────────
refresh_folder_structure() {
    local deployment_subtype="${1:-}"

    # ── Input validation ──────────────────────────────────────────────────────
    if [[ -z "$deployment_subtype" ]]; then
        log "${RED}Error: No deployment subtype provided to refresh_folder_structure${NC}"
        return 1
    fi

    # ── Setup logging context ─────────────────────────────────────────────────
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [refresh_folder_structure:${deployment_subtype}]${ORANGE}"
    log "${CALLING_SCRIPT} ${YELLOW}Initializing ${deployment_subtype} toolkit deployment scripts...${NC}"

    # ── Step 1: Resolve paths based on subtype ────────────────────────────────
    local target_folder templates_folder

    if [[ "$deployment_subtype" == "licenseserver" ]]; then
        # Licenseserver uses its own hardcoded paths
        target_folder="$BASE_IDOL_SETUP_DIR/idol-licenseserver"
        templates_folder="$BASE_IDOL_SETUP_DIR/templates/license-server/template-script"
    else
        # All other subtypes follow the standard pattern
        target_folder="$BASE_IDOL_SETUP_DIR/$IDOL_TOOLKIT_PATH/${deployment_subtype}"
        templates_folder="$BASE_IDOL_SETUP_DIR/templates/${deployment_subtype}/template-script"

        _process_single_subtype "$deployment_subtype" "$target_folder" "$templates_folder" || return 1
    fi

    # ── Step 2: data-admin → also process llm ────────────────────────────────
    if [[ "$deployment_subtype" == "data-admin" ]]; then
        local llm_target="$BASE_IDOL_SETUP_DIR/$IDOL_TOOLKIT_PATH/data-admin/llm-sandbox"
        local llm_templates="$BASE_IDOL_SETUP_DIR/templates/data-admin/template-script/llm-sandbox"

        _process_single_subtype "llm" "$llm_target" "$llm_templates" || return 1
    fi

    # ── Done ──────────────────────────────────────────────────────────────────
    log "${CALLING_SCRIPT} ${GREEN}✅ Successfully initialized ${deployment_subtype} toolkit deployment scripts${NC}"
    return 0
}

# =============================================================================
# DEPLOYMENT SUBTYPE HELPERS
# =============================================================================
# Function to Init licenseserver deployment scripts
init_licenseserver_deployment_scripts() {
    ###########################################################################
    ## Prepare copy [LICENSE-SERVER] deployment scripts
    ###########################################################################

    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [init_licenseserver_deployment_scripts] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Init license-server deployment scripts...${NC}"

    # Prepare copy [LICENSE-SERVER] deployment scripts
    refresh_folder_structure "licenseserver"

    log "${CALLING_SCRIPT} ${GREEN}✅ Successfully initialized license-server deployment scripts${NC}"
    return 0
}

# Function to Init basic-idol toolkit deployment scripts
init_basic_idol_toolkit_deployment_scripts() {
    ###########################################################################
    ## Prepare copy [BASIC-IDOL] deployment scripts
    ###########################################################################

    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [init_basic_idol_toolkit_deployment_scripts] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Init basic-idol toolkit deployment scripts...${NC}"

    # Prepare copy [BASIC-IDOL] deployment scripts
    refresh_folder_structure "basic-idol"

    log "${CALLING_SCRIPT} ${GREEN}✅ Successfully initialized basic-idol toolkit deployment scripts${NC}"
    return 0
}

# Function to Init rich-media toolkit deployment scripts
init_rich_media_toolkit_deployment_scripts() {
    ###########################################################################
    ## Prepare copy [RICH-MEDIA] deployment scripts
    ###########################################################################

    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [init_rich_media_toolkit_deployment_scripts] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Init rich-media toolkit deployment scripts...${NC}"

    # Prepare copy [RICH-MEDIA] deployment scripts
    refresh_folder_structure "rich-media"

    log "${CALLING_SCRIPT} ${GREEN}✅ Successfully initialized rich-media toolkit deployment scripts${NC}"
    return 0
}

# Function to Init data-admin toolkit deployment scripts
init_data_admin_toolkit_deployment_scripts() {
    ###########################################################################
    ## Prepare copy [DATA-ADMIN] deployment scripts
    ###########################################################################
    
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [init_data_admin_toolkit_deployment_scripts] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Init data-admin toolkit deployment scripts...${NC}"

    # Prepare copy [LLM] deployment scripts
    refresh_folder_structure "llm"

    # Prepare copy [DATA-ADMIN] deployment scripts
    refresh_folder_structure "data-admin"

    log "${CALLING_SCRIPT} ${GREEN}✅ Successfully initialized data-admin toolkit deployment scripts${NC}"
    return 0
}

verify_ssl_folder_existance() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [verify_ssl_folder_existance] module${ORANGE}"
    log "${CALLING_SCRIPT} ${YELLOW}Verifying SSL folder existence...${NC}"

    # Define source and destination paths
    local src_dir="$BASE_IDOL_SETUP_DIR/utilities/generate-ssl-certs/ssl"
    local dest_dirs=(
        "$BASE_IDOL_SETUP_DIR/idol-containers-toolkit/basic-idol/ssl"
        "$BASE_IDOL_SETUP_DIR/idol-containers-toolkit/data-admin/ssl"
        "$BASE_IDOL_SETUP_DIR/idol-containers-toolkit/rich-media/ssl"
    )

    # Check if source exists before copying
    if [[ ! -d "$src_dir" ]]; then
        log "${CALLING_SCRIPT} ${RED}ERROR: Source SSL directory '$src_dir' does not exist.${NC}"
        exit 1
    fi

    # Copy to each destination
    for dest in "${dest_dirs[@]}"; do
        if cp -frp "$src_dir/." "$dest/"; then   # -p preserves permissions
            log "${CALLING_SCRIPT} ${GREEN}Successfully copied SSL to $dest${NC}"
        else
            log "${CALLING_SCRIPT} ${RED}ERROR: Failed to copy SSL to $dest${NC}"
            exit 1
        fi
    done

    log "${CALLING_SCRIPT} ${GREEN}SSL symbolic links created.${NC}"
}

# Create directory owned by a specific (non-root) user
create_directory_as_user() {
    local target="$1"
    local user="${2:-${MAINUSER:-${SUDO_USER:-$USER}}}"
    local group="${3:-$user}"

    if [ -z "$target" ]; then
        log "${RED}❌ create_directory_as_user: No target folder specified${NC}"
        return 1
    fi

    echo -e "${CYAN}🔧 Creating directory as user: ${ORANGE}$user${NC} → ${YELLOW}$target${NC}"

    # Remove if exists (to ensure clean ownership)
    rm -rf "$target" 2>/dev/null || true

    # Create as the correct user
    if [ "$(id -u)" -eq 0 ]; then
        # Running as root → use sudo -u
        sudo -u "$user" mkdir -p "$target"
        sudo chown -R "$user:$group" "$target"
    else
        mkdir -p "$target"
        chown -R "$user:$group" "$target" 2>/dev/null || sudo chown -R "$user:$group" "$target"
    fi

    echo -e "${GREEN}✅ Directory created and owned by ${BOLD}$user:$group${NC}"
    return 0
}

# =============================================================================
# MAIN DEPLOYMENT FUNCTION
# =============================================================================
install_application() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [install_application] module${ORANGE}"
    log "${CALLING_SCRIPT} ${YELLOW}Starting IDOL application deployment...${NC}"

    validate_license_server_source_environment_variables
    validate_cert_passwords

    # Ensure target directory exists
    if [ ! -d "${IDOL_HOST_STORAGE_PATH}" ]; then
        log "${CALLING_SCRIPT} ${YELLOW}Creating IDOL_HOST_STORAGE_PATH: ${ORANGE}${IDOL_HOST_STORAGE_PATH}${NC}"
        mkdir -p "${IDOL_HOST_STORAGE_PATH}"
    else
        log "${CALLING_SCRIPT} ${GREEN}IDOL_HOST_STORAGE_PATH exists: ${ORANGE}${IDOL_HOST_STORAGE_PATH}${NC}"
    fi

    # Copy hotfolder (only if source exists)
    if [ -d "${HOTFOLDER_SOURCE}" ]; then
        log "${CALLING_SCRIPT} Copying hotfolder to ${ORANGE}${IDOL_HOST_STORAGE_PATH}${NC}..."
        cp -rf "${HOTFOLDER_SOURCE}/." "${IDOL_HOST_STORAGE_PATH}/"
    else
        log "${CALLING_SCRIPT} ${YELLOW}Source hotfolder not found, skipping copy: ${HOTFOLDER_SOURCE}${NC}"
    fi
    
    export IDOL_COUNT=$(env | grep IDOL | grep -v TOKEN | wc -l)
    log "${CALLING_SCRIPT} ${GREEN}Found ${ORANGE}${IDOL_COUNT}${GREEN} IDOL environment variables.${NC}"
    echo "export IS_IDOL_VALIDATION_MET=SUCCESS" > "$IDOL_ENV"

    log "${CALLING_SCRIPT} ${YELLOW}Deployment subtype(s): ${ORANGE}[${IDOL_DEPLOYMENT_SUBTYPE}]${NC}"
    IFS=',' read -ra DEPLOYMENT_SUBTYPES <<< "${IDOL_DEPLOYMENT_SUBTYPE}"

    # Prepare licenseserver deployment scripts
    log "${CALLING_SCRIPT} ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${CALLING_SCRIPT} ${YELLOW}▶ Pre-Processing: ${ORANGE}[licenseserver]${NC}"
    init_licenseserver_deployment_scripts

    for subtype in "${DEPLOYMENT_SUBTYPES[@]}"; do
        subtype="$(echo "$subtype" | xargs)"
        log "${CALLING_SCRIPT} ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        log "${CALLING_SCRIPT} ${YELLOW}▶ Processing subtype: ${ORANGE}[${subtype}]${NC}"

        case "${subtype}" in
            basic-idol)
                init_basic_idol_toolkit_deployment_scripts
                ;;
            data-admin)
                init_data_admin_toolkit_deployment_scripts
                ;;
            rich-media)
                init_rich_media_toolkit_deployment_scripts
                ;;                
            *)
                log "${CALLING_SCRIPT} ${RED}Unknown subtype: ${subtype}${NC}"
                exit 1
                ;;
        esac
        log "${CALLING_SCRIPT} ${GREEN}✅ Subtype [${subtype}] completed.${NC}"
    done

    # verify SSL folder existence after all subtypes have been processed
    verify_ssl_folder_existance
}

# =============================================================================
# SETUP PREREQUISITES
# =============================================================================
setup_prerequisites() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [setup_prerequisites] module${ORANGE}"
    log "${CALLING_SCRIPT} ${YELLOW}Setting up prerequisites...${NC}"
    if ! check_idol_prerequisites; then
        validate_idol_prerequisites
    fi
    IDOL_COUNT=$(env | grep IDOL | grep -v TOKEN | wc -l)
    if [ "$IDOL_COUNT" -lt 10 ]; then
        log "${CALLING_SCRIPT} ${RED}Missing required IDOL environment variables.${NC}"
        log "${CALLING_SCRIPT} ${YELLOW}Please run the IDOL Setup UI first: http://localhost:5000${NC}"
        exit 1
    fi
}

# =============================================================================
# USAGE & MAIN
# =============================================================================
usage() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${BOLD} IDOL Installation Script ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}${YELLOW}USAGE:${NC} ${GREEN}$0${NC} ${CYAN}[OPTIONS]${NC}"
    echo ""
    echo -e "${CYAN}--setup-prerequisites${NC}   Install system dependencies"
    echo -e "${CYAN}--config${NC}                Configure and deploy IDOL"
    echo -e "${CYAN}-d, --diagnose${NC}          Run Docker diagnostics"
    echo -e "${CYAN}-h, --help${NC}              Show this help"
    echo ""
    exit 1
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
if [ $# -eq 0 ]; then
    usage
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --setup-prerequisites)
            setup_prerequisites
            ;;
        --config)
            install_application
            ;;
        -d|--diagnose)
            diagnose_docker_installation
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown option $1"
            usage
            ;;
    esac
    shift
done

echo ''
log "${CALLING_SCRIPT} ✅${GREEN} Script execution completed successfully!${NC}"
echo ''
log "${CALLING_SCRIPT} ${YELLOW}Log files are located at ${ORANGE}$BASE_IDOL_SETUP_DIR/logs/${NC}"