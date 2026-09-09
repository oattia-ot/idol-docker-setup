#!/bin/bash

# ======================================================
# Docker & Docker Compose Setup Script for Ubuntu 24.04
# ======================================================
# Updated version with:
# - Clean -h/--help and -s/--setup options
# - Interactive prompts (no more hardcoded paths)
# - Clear explanation that BASE_PATH/LOG_PATH are for logging only
# - Smart defaults so user can just press Enter
# - Colored professional help screen
# - Can still be sourced by parent scripts
# ======================================================

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

log() {
    echo -e "${LIGHTER_YELLOW}$(date +"%Y-%m-%d %H:%M:%S")${NC} ${ORANGE} $1 ${NC}" | sudo tee -a "$LOGFILE"
}

# Function to check if the script is run as root
is_root() {
    if [ "$EUID" -eq 0 ]; then
        log "${CALLING_SCRIPT} ${ORANGE}This script is running as root.${NC}"
        return 0
    else
        log "${CALLING_SCRIPT} ⚠️ ${LIGHTER_YELLOW}This script is not running as root.${NC}"
        return 1
    fi
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
    export CALLING_SCRIPT="${CYAN}setup-docker [verify_docker] module${ORANGE}"
    
    if command -v docker &>/dev/null; then
        client_version=$(docker version --format '{{.Client.Version}}' 2>/dev/null)
        if [ $? -ne 0 ]; then
            log "${CALLING_SCRIPT} ${YELLOW}Docker client exists but may not be functioning properly.${NC}"
            return 1
        fi
        
        client_major_version=$(echo "$client_version" | cut -d'.' -f1)
        if [ "$client_major_version" -ge 28 ]; then
            # Also verify docker daemon is running
            if docker info &>/dev/null; then
                log "${CALLING_SCRIPT} ${GREEN}Docker $client_version is installed and running correctly.${NC}"
                return 0
            else
                log "${CALLING_SCRIPT} ${YELLOW}Docker client is installed but the daemon isn't responding.${NC}"
                return 1
            fi
        else
            log "${CALLING_SCRIPT} ${YELLOW}Docker version $client_version is too old (requires version 28+).${NC}"
            return 1
        fi
    else
        log "${CALLING_SCRIPT} ${RED}Docker is not installed.${NC}"
        return 1
    fi
}

# Function to verify Docker Compose
verify_docker_compose() {
    export CALLING_SCRIPT="${CYAN}setup-docker [verify_docker_compose] module${ORANGE}"

    # Check for standalone docker-compose
    if command -v docker-compose &>/dev/null; then
        compose_version=$(docker-compose --version | grep -oP '(\d+\.\d+\.\d+)')
        log "${CALLING_SCRIPT} ${GREEN}Docker Compose standalone version $compose_version is installed.${NC}"
        return 0
    fi

    # Check Docker Compose plugin (new method)
    if docker compose version &>/dev/null; then
        compose_version=$(docker compose version --short)
        log "${CALLING_SCRIPT} ${GREEN}Docker Compose plugin version $compose_version is installed.${NC}"
        return 0
    fi
    
    log "${CALLING_SCRIPT} ${RED}Docker Compose is not installed.${NC}"
    return 1
}

# Function to install Docker
install_docker() {
    export CALLING_SCRIPT="${CYAN}setup-docker [install_docker] module${ORANGE}"

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

    # Create docker group (executed as a subshell)
    if ! groups $USER | grep -q docker; then
        log "${CALLING_SCRIPT} Added user to docker group. ${RED}Please log out and log back in for changes to take effect.${NC}"
        exit 1
    fi

    # Add permissions
    sudo chmod 666 /var/run/docker.sock

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
}

# Function to install Docker Compose
install_docker_compose() {
    export CALLING_SCRIPT="${CYAN}setup-docker [install_docker_compose] module${ORANGE}"

    log "${CALLING_SCRIPT} ${YELLOW}Installing Docker Compose...${NC}"
    
    # First check if Docker Compose plugin is already available through Docker installation
    if docker compose version &>/dev/null; then
        log "${CALLING_SCRIPT} ${GREEN}Docker Compose plugin is already installed.${NC}"
        return 0
    fi
    
    # Install the standalone version
    LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    sudo rm /usr/local/bin/docker-compose
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

main(){
    export CALLING_SCRIPT="${CYAN}setup-docker [main] module${ORANGE}"

    # Check if all required parameters are provided
    if [[ $# -lt 3 ]]; then
        log "${RED}Error: Not enough parameters. Usage: config_repository BASE_PATH LOG_PATH INSTALL_VERSION${NC}"
        exit 1
    fi

    local BASE_PATH=$1
    local LOG_PATH=$2
    local INSTALL_VERSION=$3

    # Additional validation for each parameter
    if [[ -z "$BASE_PATH" ]]; then
        log "${RED}Error: BASE_PATH cannot be empty${NC}"
        exit 1
    fi

    if [[ -z "$LOG_PATH" ]]; then
        log "${RED}Error: LOG_PATH cannot be empty${NC}"
        exit 1
    else
        # Initialize log file
        LOGFILE="${LOG_PATH}/install_harbor_${INSTALL_VERSION}.log"
        
        # First get just the filename (remove path)
        FILENAME=$(basename "$LOGFILE")
        FULL_LOG_PATH=$(realpath "$LOGFILE") 

        # Then extract the base name without extension
        LOG_BASE="${FILENAME%%.*}"  # Everything before the first dot
    fi

    if [[ -z "$INSTALL_VERSION" ]]; then
        log "${RED}Error: INSTALL_VERSION cannot be empty${NC}"
        exit 1
    fi

    log "${CALLING_SCRIPT} ${ORANGE}Using BASE_PATH:         $BASE_PATH${NC}"
    log "${CALLING_SCRIPT} ${ORANGE}Using LOG_PATH:          $LOGFILE${NC}"
    log "${CALLING_SCRIPT} ${ORANGE}Using INSTALL_VERSION:   $INSTALL_VERSION${NC}"
    echo ''

    # Check if running as root
    if is_root; then
        # Create a docker group if not already exist
        sudo usermod -aG docker $USER

        log "${CALLING_SCRIPT} ${YELLOW}Starting Docker and Docker Compose installation check...${NC}"

        # Verify and install Docker Compose if needed
        log "${CALLING_SCRIPT} ${YELLOW}Verify Docker Compose installation...${NC}"
        if ! verify_docker_compose; then
            log "${CALLING_SCRIPT} ${YELLOW}Docker Compose needs to be installed.${NC}"
            install_docker_compose
            
            # Verify installation was successful
            if ! verify_docker_compose; then
                log "${CALLING_SCRIPT} ❌${RED}Docker Compose installation failed. Please check error messages above.${NC}"
                exit 1
            fi
        fi

        # Check and install Docker if needed
        log "${CALLING_SCRIPT} ${YELLOW}Checking Docker installation...${NC}"
        if ! verify_docker; then
            log "${CALLING_SCRIPT} ${YELLOW}Docker needs to be installed or updated.${NC}"
            install_docker
            
            # Verify installation was successful
            if ! verify_docker; then
                log "${CALLING_SCRIPT} ❌${RED}Docker installation failed. Please check error messages above.${NC}"
                exit 1
            fi
        else
            log "${CALLING_SCRIPT} ${GREEN}Docker is already installed and up to date.${NC}"
        fi
        log "${CALLING_SCRIPT} ✅ ${GREEN}Installation complete! Docker and Docker Compose are ready to use.${NC}"
        log "${CALLING_SCRIPT} ${YELLOW}NOTE: You may need to log out and log back in for group changes to take effect.${NC}"
        log "${CALLING_SCRIPT} ${YELLOW}Alternatively, run 'newgrp docker' to use Docker without sudo in the current session.${NC}"
        echo -e "\n"


        log "${CALLING_SCRIPT} ⚠️ ${PURPLE}All prerequisites were met, to continue with the installation, log in as a sudo user and execute the desired script!${NC}"
        exit 1
    else
        log "${CALLING_SCRIPT} 📌 ${CYAN}Verify that all bellow requirements are met: ${NC}"
        log "${CALLING_SCRIPT} 📌 ${CYAN}   1) Verify you execute this script as a sudo user. ${NC}"
        log "${CALLING_SCRIPT} 📌 ${CYAN}   2) Verify Docker & Docke-Compose are installed. ${NC}"
        log "${CALLING_SCRIPT} 📌 ${CYAN}   3) Verify Minikube us installed. ${NC}"
        log "${CALLING_SCRIPT} 📌 ${CYAN}If so, confirm if installing Minikube is required.${NC}"
        
        echo -e "${YELLOW}"
        if prompt_yn "Do you confirm that all the requirements has been installed?" "Y"; then
            # Verify [verify_docker] installation was successful
            if ! verify_docker; then
                log "${CALLING_SCRIPT} ❌${RED}Docker installation failed. Please check error messages above.${NC}"
                exit 1
            fi
            # Verify [verify_docker_compose] installation was successful
            if ! verify_docker_compose; then
                log "${CALLING_SCRIPT} ❌ ${RED}Docker Compose installation failed. Please check error messages above.${NC}"
                exit 1
            fi
            log "${CALLING_SCRIPT} ✅ ${GREEN}All prerequisite has been satisfied.${NC}"
            exit 0
        else
            log "${CALLING_SCRIPT} ❌ ${RED}Not all of the requirements has been installed ${LIGHTER_YELLOW}Skipping installation...${NC}"
            exit 1
        fi
        echo -e "${NC}"
    fi 
}

# ********************************** #
# ********** MAIN SECTION ********** #
# ********************************** #

# Modern option-based argument parsing with colored help
# Supports: -h|--help   and   -s|--setup (interactive prompts for paths/version)

usage() {
    echo -e "${ORANGE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${ORANGE}║${NC}   ${CYAN}Docker & Docker Compose Setup Script - Usage Help${NC}        ${ORANGE}║${NC}"
    echo -e "${ORANGE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ''
    echo -e "${ORANGE}Usage:${NC} ${LIGHTER_YELLOW}$0${NC} ${CYAN}[OPTIONS]${NC}"
    echo ''
    echo -e "${ORANGE}Options:${NC}"
    echo -e "  ${CYAN}-h, --help${NC}     Display this colorful help message and exit"
    echo -e "  ${CYAN}-s, --setup${NC}    Run interactive setup (recommended)"
    echo ''
    echo -e "${ORANGE}Description:${NC}"
    echo -e "  Checks for Docker ≥28.x and Docker Compose. Installs them if missing."
    echo -e "  When run as root it auto-installs; otherwise verifies and asks confirmation."
    echo -e "  ${CYAN}--setup${NC} mode interactively asks for logging/tracking values (with smart defaults)."
    echo ''
    echo -e "${ORANGE}Interactive prompts (when using --setup):${NC}"
    echo -e "  ${YELLOW}BASE_PATH${NC}        Directory used for log files and tracking (Docker is installed system-wide)"
    echo -e "  ${YELLOW}LOG_PATH${NC}         Log directory (defaults to BASE_PATH/logs)"
    echo -e "  ${YELLOW}INSTALL_VERSION${NC}  Version string used in the log filename"
    echo ''
    echo -e "${ORANGE}Examples:${NC}"
    echo -e "  ${LIGHTER_YELLOW}$0 --help${NC}"
    echo -e "  ${LIGHTER_YELLOW}$0 --setup${NC}"
    echo ''
    echo -e "${ORANGE}Notes:${NC}"
    echo -e "  • Run with ${CYAN}sudo${NC} for automatic installation of Docker/Docker Compose."
    echo -e "  • Without sudo: verification + confirmation prompt only."
    echo -e "  • This script can also be ${CYAN}sourced${NC} by parent scripts to reuse its functions."
    echo ''
    exit 0
}

# Default
SETUP_REQUESTED="N"

# Parse command-line options (only -h/--help and -s/--setup supported)
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        -s|--setup)
            SETUP_REQUESTED="Y"
            shift
            ;;
        *)
            echo -e "${RED}Error: Unknown option '$1'${NC}"
            echo -e "${YELLOW}Only -h/--help and -s/--setup are supported.${NC}"
            echo ''
            usage
            ;;
    esac
done

# If --setup requested, run interactive prompts then execute main()
if [[ "$SETUP_REQUESTED" == "Y" || "$SETUP_REQUESTED" == "y" ]]; then
    echo -e "\n${PURPLE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}   ${CYAN}Interactive Docker & Docker Compose Setup${NC}                ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════════════╝${NC}\n"

    echo -e "${YELLOW}These values are used mainly for logging/tracking (Docker is installed system-wide).${NC}"
    echo -e "${YELLOW}You can just press Enter to accept the suggested defaults.${NC}\n"

    # BASE_PATH (with suggested default) — only used for the log file location in this Docker setup script
    DEFAULT_BASE_PATH="/home/$(whoami)/docker-setup"
    while true; do
        read -p "$(echo -e "${CYAN}BASE_PATH${NC} (for logs & tracking) [default: ${DEFAULT_BASE_PATH}]: ")" BASE_PATH
        BASE_PATH=${BASE_PATH:-$DEFAULT_BASE_PATH}
        if [[ -n "$BASE_PATH" ]]; then
            break
        else
            echo -e "${RED}  BASE_PATH cannot be empty. Please provide a valid directory path.${NC}"
        fi
    done

    # LOG_PATH (offer suggested default based on BASE_PATH)
    SUGGESTED_LOG_PATH="${BASE_PATH%/}/logs"
    while true; do
        read -p "$(echo -e "${CYAN}LOG_PATH${NC} [press Enter for default: ${SUGGESTED_LOG_PATH}]: ")" LOG_PATH
        LOG_PATH=${LOG_PATH:-$SUGGESTED_LOG_PATH}
        if [[ -n "$LOG_PATH" ]]; then
            break
        else
            echo -e "${RED}  LOG_PATH cannot be empty.${NC}"
        fi
    done

    # INSTALL_VERSION (with suggested default)
    DEFAULT_VERSION="1.0"
    while true; do
        read -p "$(echo -e "${CYAN}INSTALL_VERSION${NC} (version for logging) [default: ${DEFAULT_VERSION}]: ")" INSTALL_VERSION
        INSTALL_VERSION=${INSTALL_VERSION:-$DEFAULT_VERSION}
        if [[ -n "$INSTALL_VERSION" ]]; then
            break
        else
            echo -e "${RED}  INSTALL_VERSION cannot be empty. Please enter a version identifier.${NC}"
        fi
    done

    # Summary
    echo -e "\n${GREEN}✓ All inputs received:${NC}"
    echo -e "    ${ORANGE}BASE_PATH${NC}         = ${CYAN}$BASE_PATH${NC}"
    echo -e "    ${ORANGE}LOG_PATH${NC}          = ${CYAN}$LOG_PATH${NC}"
    echo -e "    ${ORANGE}INSTALL_VERSION${NC}   = ${CYAN}$INSTALL_VERSION${NC}"
    echo ''

    # Ensure log directory exists (best effort)
    mkdir -p "$LOG_PATH" 2>/dev/null || true

    echo -e "${YELLOW}Launching setup with the provided values...${NC}\n"

    # Execute the main logic (handles root detection, verification/install)
    STANDALONE_EXECUTION="Y"
    main "$BASE_PATH" "$LOG_PATH" "$INSTALL_VERSION"
    exit $?
fi

# If we reach here, the script was executed directly without --setup
# Show help (unless it was sourced by another script)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Direct execution with no/unknown options → show help
    if [[ "$SETUP_REQUESTED" != "Y" ]]; then
        usage
    fi
fi

# If sourced (BASH_SOURCE != $0), simply return without doing anything.
# Parent script can then call main() or other functions directly if desired.
