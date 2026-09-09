#!/bin/bash
# Common functions for logging, prompting, validation

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly ORANGE='\033[0;38;5;214m'
readonly CYAN='\033[0;36m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

LOGFILE=""

setup_logging() {
    local log_dir="$1"
    local log_file="$2"
    mkdir -p "$log_dir"
    LOGFILE="${log_dir}/${log_file}"
    touch "$LOGFILE"

    # Terminal keeps colors; log file gets ANSI codes stripped
    exec > >(tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$LOGFILE")) 2>&1
}

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local color=""
    case $level in
        INFO)  color="$GREEN" ;;
        WARN)  color="$YELLOW" ;;
        ERROR) color="$RED" ;;
        *)     color="$NC" ;;
    esac
    echo -e "${timestamp} ${color}[${level}]${NC} ${message}" | tee -a "$LOGFILE"
}

die() {
    log "ERROR" "$1"
    exit 1
}

prompt_yn() {
    local prompt="$1"
    local default="${2:-Y}"
    local response
    while true; do
        read -p "$prompt (Y/n): " response
        response=${response:-$default}
        case "${response,,}" in
            y) return 0 ;;
            n) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        return 1
    fi
    return 0
}

has_sudo() {
    if [[ $EUID -eq 0 ]]; then
        die "This script should not be run as root. Run as a user with sudo privileges."
    fi
    if ! sudo -n true 2>/dev/null; then
        return 1
    fi
    return 0
}
