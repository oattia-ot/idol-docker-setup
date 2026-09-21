#!/bin/bash
set -euo pipefail

# Determine script directory and source common library
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Default values
BASE_PATH="${SCRIPT_DIR}"
LOG_PATH="${BASE_PATH}/logs"
INSTALL_VERSION="1.0.0"
PROFILE_NAME=""
NON_INTERACTIVE=false
STANDALONE=false
LIST_PROFILES=false

# Parse command line arguments
usage() {
    cat <<EOL
Usage: $0 [options]

Options:
  --base-path PATH       Base directory for config, logs, etc. (default: script dir)
  --log-path PATH        Directory for log files (default: BASE_PATH/logs)
  --install-version VER  Version identifier for this installation (default: 1.0.0)
  --profile-name NAME    Directly use a specific profile (bypass selection)
  --non-interactive      Run without prompts (requires --profile-name)
  --standalone           Execute the full deployment (instead of just loading functions)
  --list-profiles        List existing Minikube profiles and exit
  -h, --help             Show this help
EOL
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --base-path)       BASE_PATH="$2"; shift 2 ;;
        --log-path)        LOG_PATH="$2"; shift 2 ;;
        --install-version) INSTALL_VERSION="$2"; shift 2 ;;
        --profile-name)    PROFILE_NAME="$2"; shift 2 ;;
        --non-interactive) NON_INTERACTIVE=true; shift ;;
        --standalone)      STANDALONE=true; shift ;;
        --list-profiles)   LIST_PROFILES=true; shift ;;
        -h|--help)         usage; exit 0 ;;
        *)                 error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# If --list-profiles, just run minikube profile list and exit
if [[ "$LIST_PROFILES" == true ]]; then
    if ! command -v minikube &>/dev/null; then
        echo "Minikube is not installed."
        exit 1
    fi
    minikube profile list
    exit 0
fi

# Validate required parameters for non-interactive mode
if [[ "$NON_INTERACTIVE" == true && -z "$PROFILE_NAME" ]]; then
    error "Non-interactive mode requires --profile-name"
    exit 1
fi

# Set up logging
setup_logging "$LOG_PATH" "deploy_minikube_${INSTALL_VERSION}.log"
log "INFO" "Starting Minikube deployment (version $INSTALL_VERSION)"

# Load configuration
PROFILES_FILE="${BASE_PATH}/config/profiles.json"
if [[ ! -f "$PROFILES_FILE" ]]; then
    error "Profiles file not found: $PROFILES_FILE"
    exit 1
fi
CONFIG_PROFILES=$(jq -c . "$PROFILES_FILE") || die "Invalid JSON in profiles file"

# Check prerequisites
source "$SCRIPT_DIR/lib/prerequisites.sh"
check_prerequisites || die "Prerequisites check failed"

# If no profile name given, let the user select one
if [[ -z "$PROFILE_NAME" ]]; then
    source "$SCRIPT_DIR/lib/profile.sh"
    PROFILE_NAME=$(select_profile "$PROFILES_FILE" "$NON_INTERACTIVE")
fi

# Load the selected profile settings
source "$SCRIPT_DIR/lib/profile.sh"
PROFILE_ENV=$(load_profile_settings "$PROFILES_FILE" "$PROFILE_NAME" "$BASE_PATH")
source "$PROFILE_ENV"   # This exports MINIKUBE_* variables

# Start Minikube with the profile
source "$SCRIPT_DIR/lib/minikube.sh"
start_minikube_profile "$PROFILE_NAME"

# Enable required add‑ons and configure registry
configure_minikube_addons "$PROFILE_NAME"

log "SUCCESS" "Minikube profile '$PROFILE_NAME' is ready."