#!/bin/bash
#
# fix-idol-ownership.sh
# Recursively chown IDOL_BASE_PATH to the invoking user.
#
# Used by deploy-data-admin-v2.sh before any "docker compose up".
# Can also be run standalone:
#   export IDOL_BASE_PATH=/home/kduser6/idol-docker-setup
#   ./fix-idol-ownership.sh
#
# Or source pre-setup.sh first:
#   source ./pre-setup.sh
#   ./fix-idol-ownership.sh
#

set -Eeuo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

_idol_own_log() {
    local level="$1"; shift
    local color="$NC"
    case "$level" in
        INFO)    color="$CYAN" ;;
        SUCCESS) color="$GREEN" ;;
        WARN)    color="$YELLOW" ;;
        ERROR)   color="$RED" ;;
        STEP)    color="$BLUE" ;;
    esac
    printf "%b[%s]%b %s\n" "$color" "$level" "$NC" "$*"
}

fix_idol_base_ownership() {
    local base owner group before after
    base="${IDOL_BASE_PATH:-}"
    if [[ -z "$base" ]]; then
        _idol_own_log ERROR "IDOL_BASE_PATH is not set."
        _idol_own_log ERROR "Export it or source pre-setup.sh first (e.g. IDOL_BASE_PATH=/home/kduser6/idol-docker-setup)."
        return 1
    fi

    # Expand leading ~
    base="${base/#\~/$HOME}"

    if [[ ! -d "$base" ]]; then
        _idol_own_log ERROR "IDOL_BASE_PATH is not a directory: $base"
        return 1
    fi

    owner="$(id -un)"
    group="$(id -gn)"

    if ! command -v sudo >/dev/null; then
        _idol_own_log ERROR "sudo is required to fix ownership on $base"
        return 1
    fi

    before="$(stat -c '%U:%G' "$base" 2>/dev/null || echo unknown)"
    _idol_own_log STEP "Fixing ownership on IDOL base root: $base"
    _idol_own_log INFO "Target owner: ${owner}:${group}  |  current dir owner: ${before}"
    _idol_own_log INFO "Running: sudo chown ${owner}:${group} -R -- $base"

    if ! sudo chown "${owner}:${group}" -R -- "$base"; then
        _idol_own_log ERROR "Failed to chown $base → ${owner}:${group}"
        return 1
    fi

    after="$(stat -c '%U:%G' "$base" 2>/dev/null || echo unknown)"
    if [[ "$after" != "${owner}:${group}" ]]; then
        _idol_own_log ERROR "chown returned 0 but $base is still owned by ${after} (expected ${owner}:${group})"
        return 1
    fi

    _idol_own_log SUCCESS "Ownership set to ${owner}:${group} on $base"
    return 0
}

# If sourced, only define the function. If executed, run it.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    fix_idol_base_ownership
fi
