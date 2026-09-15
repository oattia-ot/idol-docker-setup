#!/bin/bash

# =====================================================
# Sample Bash Script: Directory Analyzer
# =====================================================
# Features demonstrated:
# - Shebang
# - Command-line argument handling (options + positional)
# - Input validation
# - Variables and quoting
# - Command substitution
# - Conditional statements
# - Functions
# - Colored output
# - Error handling
# - Help flag support (-h / --help)
# =====================================================

# Colors
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

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =====================================================
# Functions
# =====================================================

show_help() {
    echo -e "${YELLOW}Directory Analyzer${NC}"
    echo ""
    echo "Usage: $0 [OPTIONS] <directory_path>"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message and exit"
    echo ""
    echo "Examples:"
    echo "  $0 /home/user/documents"
    echo "  $0 --help"
    echo ""
}

analyze_directory() {
    local dir="$1"

    echo -e "\n${BLUE}=== Directory Analysis ===${NC}"
    echo -e "Directory: ${GREEN}$dir${NC}"
    echo -e "Analyzed on: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    if [ ! -d "$dir" ]; then
        echo -e "${RED}Error: '$dir' is not a valid directory.${NC}"
        return 1
    fi

    local file_count=$(find "$dir" -maxdepth 1 -type f | wc -l)
    local dir_count=$(find "$dir" -maxdepth 1 -type d | wc -l)
    local total_size=$(du -sh "$dir" 2>/dev/null | cut -f1)

    echo -e "${YELLOW}Summary:${NC}"
    echo "  Files:          $file_count"
    echo "  Subdirectories: $((dir_count - 1))"
    echo "  Total size:     $total_size"
    echo ""

    echo -e "${YELLOW}Top 5 largest files:${NC}"
    find "$dir" -maxdepth 1 -type f -exec ls -lh {} + 2>/dev/null | \
        sort -k5 -h | tail -5 | awk '{print "  " $9 " (" $5 ")"}'

    echo ""
    echo -e "${GREEN}Analysis complete!${NC}"
}

# =====================================================
# Main Script
# =====================================================

TARGET_DIR=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            echo -e "${RED}Error: Unknown option '$1'${NC}"
            show_help
            exit 1
            ;;
        *)
            if [ -n "$TARGET_DIR" ]; then
                echo -e "${RED}Error: Multiple directories specified.${NC}"
                show_help
                exit 1
            fi
            TARGET_DIR="$1"
            ;;
    esac
    shift
done

# Validate that a directory was provided
if [ -z "$TARGET_DIR" ]; then
    echo -e "${RED}Error: No directory specified.${NC}"
    show_help
    exit 1
fi

# Run analysis
analyze_directory "$TARGET_DIR"
exit 0