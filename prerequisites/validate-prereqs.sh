#!/bin/bash

# OpenText IDOL on Ubuntu 24.04

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
LIGHTER_YELLOW='\033[38;5;228m'
BLUE='\033[0;34m'
ORANGE='\033[0;38;5;214m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Execute script name
EXE_SCRIPT_NAME=$(basename "$0")

# Define global log file path and ensure log directory exists
export LOGFILE="./logs/${EXE_SCRIPT_NAME%.*}_$(date +"%Y%m%d").log"
mkdir -p "$(dirname "$LOGFILE")"

log() {
    # Ensure log file exists
    if [ ! -f "$LOGFILE" ]; then
        touch "$LOGFILE"
    fi

    # Write log
    echo -e "${LIGHTER_YELLOW}$(date +"%Y-%m-%d %H:%M:%S")${NC} ${ORANGE}$1${NC}" | tee -a "$LOGFILE"
}

# Function to check if the script is run as root
is_root() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [is_root] module${ORANGE}"
    if [ "$EUID" -eq 0 ]; then
        log "${CALLING_SCRIPT} ${ORANGE}This script is running as root.${NC}"
        return 0
    else
        log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW}This script is not running as root.${NC}"
        return 1
    fi
}

# Function to check if a command exists and is functional
command_exists() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [command_exists] module${ORANGE}"
    
    local cmd="$1"
    if [ -z "$cmd" ]; then
        log "${CALLING_SCRIPT} ${RED}Empty command is an error.${NC}"
        return 1
    fi
    
    # First check if command exists in PATH
    if ! command -v "$cmd" >/dev/null 2>&1; then
        # Special handling for docker-compose if not found in PATH
        if [ "$cmd" == "docker-compose" ]; then
            # Check if docker exists and if docker compose plugin works
            if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
                log "${CALLING_SCRIPT} ${GREEN}Command ${YELLOW}[docker compose]${GREEN} exists (plugin).${NC}"
                return 0
            fi
        fi
        log "${CALLING_SCRIPT} ${RED}Command ${YELLOW}[$cmd]${RED} does not exist.${NC}"
        return 1
    fi
    
    # Command exists in PATH, now test if it actually works
    case "$cmd" in
        "docker")
            if docker version >/dev/null 2>&1; then
                log "${CALLING_SCRIPT} ${GREEN}Command ${YELLOW}[$cmd]${GREEN} exists and is functional.${NC}"
                return 0
            else
                log "${CALLING_SCRIPT} ${RED}Command ${YELLOW}[$cmd]${RED} exists but is not functional (check Docker Desktop WSL integration).${NC}"
                return 1
            fi
            ;;
        "docker-compose")
            if docker-compose version >/dev/null 2>&1; then
                log "${CALLING_SCRIPT} ${GREEN}Command ${YELLOW}[$cmd]${GREEN} exists and is functional.${NC}"
                return 0
            elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
                log "${CALLING_SCRIPT} ${GREEN}Command ${YELLOW}[docker compose]${GREEN} exists and is functional (plugin).${NC}"
                return 0
            else
                log "${CALLING_SCRIPT} ${RED}Command ${YELLOW}[$cmd]${RED} exists but is not functional.${NC}"
                return 1
            fi
            ;;
        "git"|"curl"|"wget"|"jq"|"yq"|"java"|"openssl")
            # For these commands, test with --version or --help
            if $cmd --version >/dev/null 2>&1 || $cmd --help >/dev/null 2>&1; then
                log "${CALLING_SCRIPT} ${GREEN}Command ${YELLOW}[$cmd]${GREEN} exists and is functional.${NC}"
                return 0
            else
                log "${CALLING_SCRIPT} ${RED}Command ${YELLOW}[$cmd]${RED} exists but is not functional.${NC}"
                return 1
            fi
            ;;
        *)
            # For other commands, just check if they exist and can be executed
            if $cmd --version >/dev/null 2>&1 || $cmd -h >/dev/null 2>&1 || $cmd --help >/dev/null 2>&1; then
                log "${CALLING_SCRIPT} ${GREEN}Command ${YELLOW}[$cmd]${GREEN} exists and appears functional.${NC}"
                return 0
            else
                # Fallback: assume it's functional if it exists in PATH
                log "${CALLING_SCRIPT} ${GREEN}Command ${YELLOW}[$cmd]${GREEN} exists.${NC}"
                return 0
            fi
            ;;
    esac
}

# Function to print the error message and exit
error_exit() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [error_exit] module${ORANGE}"
    log "${CALLING_SCRIPT} ${RED}ERROR: $1${NC}"
    exit 1
}

# Function to prompt user with Y/n question
prompt_yn() {
    local prompt="$1"
    local default="$2"
    local response

    echo -e "${YELLOW}"
    while true; do
        read -p "$prompt (Y/n): [default $default] " response
        response=${response:-${default}}

        # Normalize to lowercase to simplify case handling
        case "${response,,}" in
            y) return 0 ;;   # Yes
            n) return 1 ;;   # No
            *) echo -e "${RED}Please answer yes or no.${NC}" ;;  # Invalid input
        esac
    done
    echo -e "${NC}"
}

# Function to verify Docker version
verify_docker() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [verify_docker] module${ORANGE}"

    if command -v docker &>/dev/null; then
        client_version=$(docker version --format '{{.Client.Version}}' 2>/dev/null)
        if [ $? -ne 0 ]; then
            log "${CALLING_SCRIPT} ${YELLOW}Docker client exists but may not be functioning properly.${NC}"
            return 1
        fi

        client_major_version=$(echo "$client_version" | cut -d'.' -f1)
        if [ "$client_major_version" -ge 20 ]; then  # Changed from 28 to 20 (more realistic)
            # Also verify docker daemon is running
            if docker info &>/dev/null; then
                log "${CALLING_SCRIPT} ${GREEN}Docker $client_version is installed and running correctly.${NC}"
                return 0
            else
                log "${CALLING_SCRIPT} ${YELLOW}Docker client is installed but the daemon isn't responding.${NC}"
                return 1
            fi
        else
            log "${CALLING_SCRIPT} ${YELLOW}Docker version $client_version is too old (requires version 20+).${NC}"
            return 1
        fi
    else
        log "${CALLING_SCRIPT} ${RED}Docker is not installed.${NC}"
        return 1
    fi
}

# Function to verify Docker Compose
verify_docker_compose() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [verify_docker_compose] module${ORANGE}"

    # Check for standalone docker-compose
    if command -v docker-compose &>/dev/null && docker-compose version &>/dev/null; then
        compose_version=$(docker-compose --version | grep -oP '(\d+\.\d+\.\d+)')
        log "${CALLING_SCRIPT} ${GREEN}Docker Compose standalone version $compose_version is installed.${NC}"
        return 0
    fi

    # Check Docker Compose plugin (new method)
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        compose_version=$(docker compose version --short)
        log "${CALLING_SCRIPT} ${GREEN}Docker Compose plugin version $compose_version is installed.${NC}"
        return 0
    fi

    log "${CALLING_SCRIPT} ${RED}Docker Compose is not installed or not functional.${NC}"
    return 1
}

# Function to install Docker
install_docker() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [install_docker] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Installing Docker...${NC}"

    # First remove any old versions that might exist
    apt update -y
    apt remove -y docker docker-engine docker.io containerd runc &>/dev/null || true

    # Install dependencies
    apt update -y
    apt install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common

    # Set up the Docker repository
    mkdir -p /etc/apt/keyrings
    chmod 755 /etc/apt/keyrings/
    if [ -f "/etc/apt/keyrings/docker.gpg" ]; then
        rm -f /etc/apt/keyrings/docker.gpg || error_exit "Failed to remove /etc/apt/keyrings/docker.gpg"
        log "${CALLING_SCRIPT} ${RED}File /etc/apt/keyrings/docker.gpg has been removed.${NC}"
    else
        log "${CALLING_SCRIPT} File /etc/apt/keyrings/docker.gpg does not exist."
    fi
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    apt update -y
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Add permissions
    chmod 666 /var/run/docker.sock

    # Set up Docker service
    systemctl enable docker
    systemctl start docker

    # Add current user to docker group
    if [ -n "$SUDO_USER" ]; then
        MAINUSER="$SUDO_USER"
    else
        MAINUSER=$(logname 2>/dev/null || echo "${USER}")
    fi

    groupadd -f docker || true
    usermod -aG docker "$MAINUSER"

    log "${CALLING_SCRIPT} ✅${GREEN}Docker installed successfully.${NC}"
    log "${CALLING_SCRIPT} ${YELLOW}NOTE: User $MAINUSER added to docker group. Please log out and log back in for changes to take effect.${NC}"
}

# Function to install Docker Compose
install_docker_compose() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [install_docker_compose] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Installing Docker Compose...${NC}"

    # First check if Docker Compose plugin is already available through Docker installation
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        log "${CALLING_SCRIPT} ${GREEN}Docker Compose plugin is already installed.${NC}"
        return 0
    fi

    # Install the standalone version
    LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    # Remove existing installation if present
    [ -f /usr/local/bin/docker-compose ] && rm -f /usr/local/bin/docker-compose
    
    curl -L "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

    if [ $? -ne 0 ]; then
        log "${CALLING_SCRIPT} ${RED}Failed to download Docker Compose. Trying alternative method...${NC}"
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    fi

    chmod +x /usr/local/bin/docker-compose

    # Create symbolic link for command completion
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

    if docker-compose --version &>/dev/null; then
        log "${CALLING_SCRIPT} ✅${GREEN}Docker Compose standalone installed successfully.${NC}"
        return 0
    else
        log "${CALLING_SCRIPT} ${RED}Docker Compose installation failed.${NC}"
        return 1
    fi
}

main() {
    export CALLING_SCRIPT="${CYAN}${EXE_SCRIPT_NAME%.*} [main] module${ORANGE}"

    # Display Info
    log "${CALLING_SCRIPT} ${GREEN}#########################################${NC}"
    log "${CALLING_SCRIPT} ${GREEN}##### IDOL - Validate Prerequisites #####${NC}"
    log "${CALLING_SCRIPT} ${GREEN}#########################################${NC}"
    log "${CALLING_SCRIPT} ${GREEN}##### $(date +"%Y-%m-%d")                ${NC}"

    # Init log file
    if [ -f "$LOGFILE" ]; then
        rm -f "$LOGFILE"
        log "Old log deleted"
    fi
    log "Script started. Log path: ${LOGFILE}"

    # Check if we need root privileges for installation
    NEED_ROOT_INSTALL=false

    # Check basic prerequisites
    log "${CALLING_SCRIPT} ${YELLOW}Checking basic prerequisites...${NC}"
    
    if ! command_exists java; then
        error_exit "JAVA is not installed. Please install it first."
    fi

    if ! command_exists openssl; then
        error_exit "OpenSSL is not installed. Please install it first."
    fi

    # Check Docker
    log "${CALLING_SCRIPT} ${YELLOW}Checking Docker installation...${NC}"
    if ! command_exists docker || ! verify_docker; then
        log "${CALLING_SCRIPT} ${YELLOW}Docker needs to be installed or is not functional.${NC}"
        NEED_ROOT_INSTALL=true
    else
        log "${CALLING_SCRIPT} ${GREEN}Docker is installed and functional.${NC}"
    fi

    # Check Docker Compose
    log "${CALLING_SCRIPT} ${YELLOW}Checking Docker Compose installation...${NC}"
    if ! command_exists docker-compose && ! verify_docker_compose; then
        log "${CALLING_SCRIPT} ${YELLOW}Docker Compose needs to be installed.${NC}"
        NEED_ROOT_INSTALL=true
    else
        log "${CALLING_SCRIPT} ${GREEN}Docker Compose is installed and functional.${NC}"
    fi

    # Handle installations that require root
    if [ "$NEED_ROOT_INSTALL" = true ]; then
        if ! is_root; then
            echo ''
            log "${CALLING_SCRIPT} ${RED}#############################################${NC}"
            log "${CALLING_SCRIPT} ${RED}Docker installation requires root privileges.${NC}"
            log "${CALLING_SCRIPT} ${RED}            Please run this script with ${YELLOW}sudo.${NC}"
            log "${CALLING_SCRIPT} ${RED}#############################################${NC}"
            error_exit "Docker installation requires root privileges. Please run this script with sudo."
        fi

        log "${CALLING_SCRIPT} ${YELLOW}Starting Docker installation process...${NC}"

        # Install Docker if needed
        if ! verify_docker; then
            log "${CALLING_SCRIPT} ${YELLOW}Installing Docker...${NC}"
            install_docker
            
            # Verify installation was successful
            if ! verify_docker; then
                error_exit "Docker installation failed. Please check error messages above."
            fi
        fi

        # Install Docker Compose if needed
        if ! verify_docker_compose; then
            log "${CALLING_SCRIPT} ${YELLOW}Installing Docker Compose...${NC}"
            install_docker_compose
            
            # Verify installation was successful
            if ! verify_docker_compose; then
                error_exit "Docker Compose installation failed. Please check error messages above."
            fi
        fi

        log "${CALLING_SCRIPT} ✅${GREEN}Installation complete! Docker and Docker Compose are ready to use.${NC}"
        log "${CALLING_SCRIPT} ${LIGHTER_YELLOW}IMPORTANT: Please log out and log back in for group changes to take effect.${NC}"
        log "${CALLING_SCRIPT} ${LIGHTER_YELLOW}Alternatively, run 'newgrp docker' to use Docker without sudo in the current session.${NC}"
    else
        log "${CALLING_SCRIPT} ✅${GREEN}All prerequisites are met!${NC}"
        log "${CALLING_SCRIPT} ${GREEN}You can proceed with the IDOL installation.${NC}"
    fi

    echo ''
    log "${CALLING_SCRIPT} ${GREEN}################################################${NC}"
    log "${CALLING_SCRIPT} ${GREEN}Prerequisites validation completed successfully.${NC}"
    log "${CALLING_SCRIPT} ${GREEN}################################################${NC}"
}

# ********************************** #
# ********** MAIN SECTION ********** #
# ********************************** #

main "$@"