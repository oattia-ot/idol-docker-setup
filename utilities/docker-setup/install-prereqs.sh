#!/usr/bin/env bash
# =============================================================================
# install-prereqs.sh
# Detect Ubuntu vs macOS and run the matching Phase 2 installer.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

uname_s="$(uname -s 2>/dev/null || echo unknown)"
case "$uname_s" in
    Darwin)
        echo "[OS] macOS detected → install-macos-prereqs.sh"
        exec bash "${SCRIPT_DIR}/install-macos-prereqs.sh" "$@"
        ;;
    Linux)
        echo "[OS] Linux detected → install-ubuntu-prereqs.sh"
        exec bash "${SCRIPT_DIR}/install-ubuntu-prereqs.sh" "$@"
        ;;
    *)
        echo "Unsupported host OS: $uname_s" >&2
        echo "Use install-ubuntu-prereqs.sh or install-macos-prereqs.sh explicitly." >&2
        exit 1
        ;;
esac
