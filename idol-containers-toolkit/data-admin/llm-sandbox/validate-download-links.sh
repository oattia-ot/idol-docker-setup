#!/usr/bin/env bash
# =============================================================================
# LLM Models JSON Link Validator v4.2
# Validates ALL download links WITHOUT downloading files
# Preserves original JSON order and displays live progress
# =============================================================================

set -uo pipefail

# ─────────────────────────────────────────────
# Color codes (only used when output is a terminal)
# ─────────────────────────────────────────────
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'
    BOLD='\033[1m'
else
    GREEN=''; YELLOW=''; RED=''; BLUE=''; CYAN=''; NC=''; BOLD=''
fi

# ----------------------------- HELP -----------------------------------------
show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS] [JSON_FILE]

Description:
  Validates every URL found in a JSON file using HEAD requests only.
  Results are printed in the original JSON order after all checks finish.

Arguments:
  JSON_FILE              Path to the JSON file to validate.
                         Default: models.json

Options:
  -t, --timeout  SEC     Curl timeout in seconds       (default: 15)
  -r, --retries  N       Number of retry attempts      (default: 2)
  -p, --parallel N       Parallel workers              (default: 5)
  -o, --output   FILE    Save broken links to a file
  -q, --quiet            Only print failures + summary (no progress)
  -h, --help             Show this help message and exit

Version: 4.2
EOF
  exit 0
}

# ----------------------------- DEFAULTS -------------------------------------
JSON_FILE="models.json"
TIMEOUT_SEC=15
MAX_RETRIES=2
PARALLEL=5
OUTPUT_FILE=""
QUIET=false

# ----------------------------- ARGUMENT PARSING -----------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)     show_help ;;
    -t|--timeout)  TIMEOUT_SEC="${2:?'--timeout requires a value'}"; shift 2 ;;
    -r|--retries)  MAX_RETRIES="${2:?'--retries requires a value'}"; shift 2 ;;
    -p|--parallel) PARALLEL="${2:?'--parallel requires a value'}"; shift 2 ;;
    -o|--output)   OUTPUT_FILE="${2:?'--output requires a value'}"; shift 2 ;;
    -q|--quiet)    QUIET=true; shift ;;
    -*)
      echo "Error: Unknown option '$1'" >&2
      echo "Use '$(basename "$0") --help' for usage information." >&2
      exit 1
      ;;
    *)
      JSON_FILE="$1"
      shift
      ;;
  esac
done

# ----------------------------- DEPENDENCY CHECK -----------------------------
for cmd in jq curl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "${RED}❌ Error: '$cmd' is not installed.${NC}" >&2
    exit 1
  fi
done

# ----------------------------- FILE CHECK -----------------------------------
if [[ ! -f "$JSON_FILE" ]]; then
  echo -e "${RED}❌ Error: JSON file not found: '$JSON_FILE'${NC}" >&2
  exit 1
fi

if ! jq empty "$JSON_FILE" 2>/dev/null; then
  echo -e "${RED}❌ Error: '$JSON_FILE' is not valid JSON.${NC}" >&2
  exit 1
fi

# ----------------------------- URL EXTRACTION -------------------------------
mapfile -t URLS < <(
  jq -r '.. | strings | select(startswith("http://") or startswith("https://"))' "$JSON_FILE" \
  | awk '!seen[$0]++'
)

TOTAL="${#URLS[@]}"

if [[ "$TOTAL" -eq 0 ]]; then
  echo -e "${YELLOW}⚠️  No URLs found in '$JSON_FILE'.${NC}"
  exit 0
fi

PAD_WIDTH="${#TOTAL}"

# ----------------------------- TEMP FILES -----------------------------------
TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

RESULTS_DIR="$TMPDIR_WORK/results"
FAILED_FILE="$TMPDIR_WORK/failed.txt"
mkdir -p "$RESULTS_DIR"
touch "$FAILED_FILE"

# ----------------------------- HEADER ---------------------------------------
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║        LLM Model Link Validator  v4.2            ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}File     :${NC} $JSON_FILE"
echo -e "  ${BOLD}URLs     :${NC} $TOTAL"
echo -e "  ${BOLD}Parallel :${NC} $PARALLEL workers"
echo -e "  ${BOLD}Timeout  :${NC} ${TIMEOUT_SEC}s per request  |  Retries: $MAX_RETRIES"
echo ""

START_TIME=$(date +%s)

# ----------------------------- CHECK FUNCTION -------------------------------
# Stores raw result: "status_code|url" (status_code = OK or FAIL code)
check_url() {
  local url="$1"
  local index="$2"
  local http_code="000"
  local attempt

  for attempt in $(seq 1 "$MAX_RETRIES"); do
    http_code=$(
      curl -I -s -L \
           --max-time "$TIMEOUT_SEC" \
           --retry 0 \
           -w "%{http_code}" \
           -o /dev/null \
           "$url" 2>/dev/null
    ) || http_code="000"

    [[ "$http_code" =~ ^2 || "$http_code" =~ ^4 ]] && break
    [[ "$attempt" -lt "$MAX_RETRIES" ]] && sleep 1
  done

  local status
  if [[ "$http_code" =~ ^2 ]]; then
    status="OK|$http_code"
  else
    status="FAIL|$http_code"
    echo "$http_code|$url" >> "$FAILED_FILE"
  fi

  # Save raw data (no escape sequences)
  printf "%s|%s\n" "$status" "$url" > "$RESULTS_DIR/$(printf "%0${PAD_WIDTH}d" "$index").result"
}

export -f check_url
export TIMEOUT_SEC MAX_RETRIES RESULTS_DIR PAD_WIDTH FAILED_FILE

# ----------------------------- PROGRESS DISPLAY -----------------------------
show_progress() {
  local last_count=0
  local spinner=('|' '/' '-' '\')
  local spin_idx=0

  while true; do
    local current_count
    current_count=$(find "$RESULTS_DIR" -type f -name "*.result" 2>/dev/null | wc -l)
    local now=$(date +%s)
    local elapsed=$((now - START_TIME))
    local min=$((elapsed / 60))
    local sec=$((elapsed % 60))

    printf "\r${CYAN}[${spinner[$spin_idx]}]${NC} Progress: ${YELLOW}%d/%d${NC}  (elapsed %02d:%02d)" \
           "$current_count" "$TOTAL" "$min" "$sec"
    spin_idx=$(((spin_idx + 1) % 4))

    if [[ $current_count -ge $TOTAL ]]; then
      printf "\r%*s\r" 80 ""
      break
    fi
    sleep 0.2
  done
}

# ----------------------------- PARALLEL QUEUE -------------------------------
run_jobs() {
  local running=0
  local pids=()

  if [[ "$QUIET" == false ]]; then
    show_progress &
    PROGRESS_PID=$!
  fi

  for i in "${!URLS[@]}"; do
    local idx=$((i + 1))
    local url="${URLS[$i]}"

    check_url "$url" "$idx" &
    pids+=($!)
    ((running++))

    if [[ $running -ge $PARALLEL ]]; then
      wait -n
      local new_pids=()
      for pid in "${pids[@]}"; do
        kill -0 "$pid" 2>/dev/null && new_pids+=("$pid")
      done
      pids=("${new_pids[@]}")
      running=${#pids[@]}
    fi
  done

  wait

  if [[ "$QUIET" == false ]] && [[ -n "${PROGRESS_PID:-}" ]]; then
    kill "$PROGRESS_PID" 2>/dev/null || true
    wait "$PROGRESS_PID" 2>/dev/null || true
  fi
}

run_jobs

# ----------------------------- PRINT RESULTS (WITH COLOR) -------------------
echo ""
SUCCESS=0
FAILED_COUNT=$(wc -l < "$FAILED_FILE" 2>/dev/null || echo 0)

for idx in $(seq 1 "$TOTAL"); do
  result_file="$RESULTS_DIR/$(printf "%0${PAD_WIDTH}d" "$idx").result"
  if [[ -f "$result_file" ]]; then
    IFS='|' read -r status code url < "$result_file"
    counter="[${idx}/${TOTAL}]"

    if [[ "$status" == "OK" ]]; then
      printf "  ${GREEN}✅ OK  (%s)${NC}  ${YELLOW}%s${NC}  %s\n" "$code" "$counter" "$url"
      ((SUCCESS++))
    else
      printf "  ${RED}❌ FAIL (%s)${NC}  ${YELLOW}%s${NC}  %s\n" "$code" "$counter" "$url"
    fi
  fi
done

# ----------------------------- SUMMARY --------------------------------------
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "  ${BOLD}Results   :${NC}  ✅ $SUCCESS passed   ❌ $FAILED_COUNT failed   (of $TOTAL total)"
echo -e "  ${BOLD}Duration  :${NC}  ${ELAPSED}s"
echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${NC}"

if [[ $FAILED_COUNT -gt 0 ]]; then
  echo ""
  echo -e "${RED}${BOLD}Broken links:${NC}"
  while IFS='|' read -r code url; do
    echo -e "  ${RED}•${NC} [$code] $url"
  done < "$FAILED_FILE"

  if [[ -n "$OUTPUT_FILE" ]]; then
    cp "$FAILED_FILE" "$OUTPUT_FILE"
    echo ""
    echo -e "${YELLOW}💾 Broken links saved to: $OUTPUT_FILE${NC}"
  fi
  echo ""
  exit 1
else
  echo ""
  echo -e "${GREEN}${BOLD}🎉 All $TOTAL links are valid and reachable!${NC}"
  echo ""
  exit 0
fi