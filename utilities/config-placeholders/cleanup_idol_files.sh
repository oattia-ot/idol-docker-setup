#!/usr/bin/env bash
# =============================================================================
# cleanup_idol_files.sh
# Dynamic cleanup: removes generated output files (scoped by deployment type)
# Now also supports -l / --list to show available deployment types.
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# Colours
# --------------------------------------------------------------------------- #
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

# --------------------------------------------------------------------------- #
# Usage / Help
# --------------------------------------------------------------------------- #
usage() {
  echo -e "
${YELLOW}USAGE${RESET}
  $(basename "$0") [OPTIONS] [JSON_FILE]

${YELLOW}ARGUMENTS${RESET}
  JSON_FILE     Optional. Path to the placeholders JSON file.
                Default: placeholders-replacement.json (in current directory)

${YELLOW}OPTIONS${RESET}
  -d, --deployment TYPE[,TYPE,...]
                Remove output files only for the given deployment type(s).
                Multiple types can be comma-separated.
                If omitted, ALL output files from the JSON are removed.
  -l, --list    List all available top-level deployment types (JSON keys)
                and exit. No cleanup is performed.
  -h, --help    Show this help message and exit.

${YELLOW}EXAMPLES${RESET}
  # List all available deployment types
  ./cleanup_idol_files.sh -l
  ./cleanup_idol_files.sh -l /path/to/custom.json

  # Remove all output files
  ./cleanup_idol_files.sh

  # Remove only basic-idol output files
  ./cleanup_idol_files.sh -d basic-idol

  # Remove multiple types
  ./cleanup_idol_files.sh -d basic-idol,rich-media

  # With custom JSON
  ./cleanup_idol_files.sh /path/to/custom/placeholders-replacement.json
"
  exit 0
}

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #
JSON_FILE="placeholders-replacement.json"
CLEANUP_TYPES=""     # empty = clean ALL
LIST_MODE=0          # 1 = only list keys and exit

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage ;;
    -l|--list)
      LIST_MODE=1
      shift ;;
    -d|--deployment)
      [[ -z "${2:-}" ]] && { echo -e "${RED}ERROR:${RESET} --deployment requires a TYPE argument."; exit 1; }
      CLEANUP_TYPES="$2"
      shift 2 ;;
    -*)
      echo -e "${RED}ERROR:${RESET} Unknown option: '$1'"
      echo -e "       Use ${CYAN}-h${RESET} or ${CYAN}--help${RESET} to see usage."
      exit 1 ;;
    *)
      JSON_FILE="$1"
      shift ;;
  esac
done

# --------------------------------------------------------------------------- #
# Early handling for --list mode
# --------------------------------------------------------------------------- #
if [[ $LIST_MODE -eq 1 ]]; then
  if [[ ! -f "$JSON_FILE" ]]; then
    echo -e "${RED}ERROR:${RESET} JSON file not found → ${CYAN}$JSON_FILE${RESET}"
    exit 1
  fi

  echo -e "${BOLD}━━  Available deployment types (top-level JSON keys)  ━━${RESET}\n"
  jq -r 'keys[]' "$JSON_FILE" | sort | while read -r key; do
    echo -e "  ${CYAN}•${RESET} ${key}"
  done
  echo -e "\n${GREEN}Listed ${RESET}$(jq 'keys | length' "$JSON_FILE")${GREEN} deployment type(s).${RESET}"
  exit 0
fi

# --------------------------------------------------------------------------- #
# Compute fixed paths from current script location
# --------------------------------------------------------------------------- #
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/../../"

llmsandbox_toolkit_path="${ROOT}/idol-containers-toolkit/data-admin/llm-sandbox"
licenseserver_toolkit_path="${ROOT}/idol-licenseserver"
basic_idol_toolkit_path="${ROOT}/idol-containers-toolkit/basic-idol"
data_admin_toolkit_path="${ROOT}/idol-containers-toolkit/data-admin"
rich_media_toolkit_path="${ROOT}/idol-containers-toolkit/rich-media"
persistent_data_path="${ROOT}/persistent-data"

export llmsandbox_toolkit_path \
       licenseserver_toolkit_path \
       basic_idol_toolkit_path \
       data_admin_toolkit_path \
       rich_media_toolkit_path \
       persistent_data_path

# --------------------------------------------------------------------------- #
# Sanity checks
# --------------------------------------------------------------------------- #
if [[ ! -f "$JSON_FILE" ]]; then
  echo -e "${RED}ERROR:${RESET} JSON file not found → ${CYAN}$JSON_FILE${RESET}"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo -e "${RED}ERROR:${RESET} 'jq' is required but not installed."
  exit 1
fi

echo -e "${GREEN}🗑️  Root directory:${RESET} ${CYAN}$ROOT${RESET}"
echo -e "${GREEN}🔍 JSON file     :${RESET} ${CYAN}$JSON_FILE${RESET}"

if [[ -n "$CLEANUP_TYPES" ]]; then
  echo -e "${GREEN}🎯 Deployment scope:${RESET} ${CYAN}${CLEANUP_TYPES}${RESET}"
else
  echo -e "${GREEN}🎯 Deployment scope:${RESET} ${CYAN}ALL${RESET}"
fi

echo -e "${BLUE}────────────────────────────────────────────────────────────${RESET}"

# --------------------------------------------------------------------------- #
# Extract unique "output" paths — scoped to deployment types if provided
# --------------------------------------------------------------------------- #
mapfile -t OUTPUT_FILES < <(
  if [[ -n "$CLEANUP_TYPES" ]]; then
    IFS=',' read -ra _TYPES <<< "$CLEANUP_TYPES"
    for dtype in "${_TYPES[@]}"; do
      dtype="$(echo "$dtype" | xargs)"  # trim whitespace
      jq -r --arg dtype "$dtype" '
        .[$dtype] |
        .. |
        objects |
        select(has("files")) |
        .files[] |
        .output
      ' "$JSON_FILE"
    done
  else
    jq -r '
      .. |
      objects |
      select(has("files")) |
      .files[] |
      .output
    ' "$JSON_FILE"
  fi | sort -u
)

if [[ ${#OUTPUT_FILES[@]} -eq 0 ]]; then
  echo -e "${YELLOW}⚠️  No output files found in the JSON.${RESET}"
  exit 0
fi

echo -e "${GREEN}✅ Found ${#OUTPUT_FILES[@]} unique files to remove.${RESET}"
echo -e "${BLUE}────────────────────────────────────────────────────────────${RESET}"

# --------------------------------------------------------------------------- #
# Main loop: expand placeholders + rm
# --------------------------------------------------------------------------- #
echo -e "${BOLD}${RED}Starting cleanup...${RESET}"

for output_template in "${OUTPUT_FILES[@]}"; do
  expanded_path="$(envsubst <<< "$output_template")"

  if [[ -f "$expanded_path" ]]; then
    rm -fv "$expanded_path"
  else
    echo -e "${YELLOW}⚠️  [SKIPPED - not found]${RESET} ${expanded_path}"
  fi
done

echo -e "${BLUE}────────────────────────────────────────────────────────────${RESET}"
echo -e "${GREEN}🎉 Cleanup completed!${RESET} All generated output files have been removed."