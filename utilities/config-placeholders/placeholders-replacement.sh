#!/usr/bin/env bash
# =============================================================================
# placeholders-replacement.sh
# NEW: Uses "output-path" and "template-path" from the updated JSON
# =============================================================================
set -euo pipefail

# --------------------------------------------------------------------------- #
# Bash version check
# --------------------------------------------------------------------------- #
if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
  echo -e "\033[0;31mERROR:\033[0m This script requires bash 4.0 or higher."
  echo "Your bash version: $BASH_VERSION"
  exit 1
fi

shopt -s dotglob

# --------------------------------------------------------------------------- #
# Colours
# --------------------------------------------------------------------------- #
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
SEP="$(printf '─%.0s' {1..72})"

# --------------------------------------------------------------------------- #
# Usage
# --------------------------------------------------------------------------- #
usage() {
  echo -e "
${YELLOW}USAGE${RESET}
  $(basename "$0") [OPTIONS] [CONFIG_JSON] [LOG_FILE]
${YELLOW}OPTIONS${RESET}
  -d, --deployment TYPE   Process only this deployment type
  -l, --list              List available deployment types
  -h, --help              Show help
"
}

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #
DEPLOYMENT_TYPE=""
LIST_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -l|--list) LIST_ONLY=1; shift ;;
    -d|--deployment)
      [[ -z "${2:-}" ]] && { echo -e "${RED}ERROR:${RESET} --deployment requires a TYPE"; exit 1; }
      DEPLOYMENT_TYPE="$2"
      shift 2 ;;
    -*) echo -e "${RED}ERROR:${RESET} Unknown option: '$1'"; usage; exit 1 ;;
    *) break ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
JSON_FILE="${1:-${SCRIPT_DIR}/placeholders-replacement.json}"

if [[ $LIST_ONLY -eq 1 ]]; then
  jq -r '
    to_entries[] |
    .value."deployment-type" |
    if type == "array" then .[] else . end
  ' "$JSON_FILE" | sort -u | sed 's/^/ • /'
  exit 0
fi

LOG_FILE="$(realpath -m "${2:-${LOG_FILE:-${SCRIPT_DIR}/../../logs/check_idol_ports_$(date '+%Y%m%d_%H%M%S').log}}")"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee >(sed 's/\x1B\[[0-9;]*[mK]//g' >> "$LOG_FILE")) \
     2> >(tee >(sed 's/\x1B\[[0-9;]*[mK]//g' >> "$LOG_FILE") >&2)

# --------------------------------------------------------------------------- #
# Default paths
# --------------------------------------------------------------------------- #
: "${llmsandbox_toolkit_path:=${SCRIPT_DIR}/../../idol-containers-toolkit/data-admin/llm-sandbox}"
: "${llmsandbox_templates_path:=${SCRIPT_DIR}/../../templates/data-admin/template-script/llm-sandbox}"
: "${licenseserver_toolkit_path:=${SCRIPT_DIR}/../../idol-licenseserver}"
: "${licenseserver_templates_path:=${SCRIPT_DIR}/../../templates/license-server/template-script}"
: "${basic_idol_toolkit_path:=${SCRIPT_DIR}/../../idol-containers-toolkit/basic-idol}"
: "${basic_idol_templates_path:=${SCRIPT_DIR}/../../templates/basic-idol/template-script}"
: "${data_admin_toolkit_path:=${SCRIPT_DIR}/../../idol-containers-toolkit/data-admin}"
: "${data_admin_templates_path:=${SCRIPT_DIR}/../../templates/data-admin/template-script}"
: "${rich_media_toolkit_path:=${SCRIPT_DIR}/../../idol-containers-toolkit/rich-media}"
: "${rich_media_templates_path:=${SCRIPT_DIR}/../../templates/rich-media/template-script}"
: "${persistent_data_path:=${SCRIPT_DIR}/../../persistent-data}"
: "${persistent_data_templates_path:=${SCRIPT_DIR}/../../persistent-data/templates}"
export llmsandbox_toolkit_path llmsandbox_templates_path \
       licenseserver_toolkit_path licenseserver_templates_path \
       basic_idol_toolkit_path basic_idol_templates_path \
       data_admin_toolkit_path data_admin_templates_path \
       rich_media_toolkit_path rich_media_templates_path \
       persistent_data_path persistent_data_templates_path

# --------------------------------------------------------------------------- #
# Cleanup phase
# --------------------------------------------------------------------------- #
echo -e "\n${BOLD}━━ CLEANUP PHASE ━━${RESET}\n"
if [[ -n "$DEPLOYMENT_TYPE" ]]; then
  echo -e "${BOLD}Single-deployment mode:${RESET} ${CYAN}${DEPLOYMENT_TYPE}${RESET}"
  ./cleanup_idol_files.sh -d "$DEPLOYMENT_TYPE"
  [[ "$DEPLOYMENT_TYPE" == "data-admin" ]] && ./cleanup_idol_files.sh -d llm
else
  if [[ -n "${IDOL_DEPLOYMENT_SUBTYPE:-}" ]]; then
    IFS=',' read -ra DEPLOYMENT_TYPES <<< "${IDOL_DEPLOYMENT_SUBTYPE}"
    for dt_raw in "${DEPLOYMENT_TYPES[@]}"; do
      dt="${dt_raw#"${dt_raw%%[![:space:]]*}"}"
      dt="${dt%"${dt##*[![:space:]]}"}"
      [[ -n "$dt" ]] && {
        ./cleanup_idol_files.sh -d "$dt"
        [[ "$dt" == "data-admin" ]] && ./cleanup_idol_files.sh -d llm
      }
    done
  else
    ./cleanup_idol_files.sh
  fi
fi
echo -e "$SEP"

# --------------------------------------------------------------------------- #
# Sanity checks
# --------------------------------------------------------------------------- #
[[ ! -f "$JSON_FILE" ]] && { echo -e "${RED}ERROR:${RESET} JSON file not found: $JSON_FILE"; exit 1; }
for cmd in jq sed; do
  command -v "$cmd" >/dev/null || { echo -e "${RED}ERROR:${RESET} '$cmd' is required"; exit 1; }
done

# --------------------------------------------------------------------------- #
# Build selected deployments
# --------------------------------------------------------------------------- #
declare -a SELECTED_MAIN_DT=()

if [[ -n "$DEPLOYMENT_TYPE" ]]; then
  SELECTED_MAIN_DT=("$DEPLOYMENT_TYPE")
elif [[ -n "${IDOL_DEPLOYMENT_SUBTYPE:-}" ]]; then
  IFS=',' read -ra tmp <<< "${IDOL_DEPLOYMENT_SUBTYPE}"
  for dt_raw in "${tmp[@]}"; do
    dt="${dt_raw#"${dt_raw%%[![:space:]]*}"}"
    dt="${dt%"${dt##*[![:space:]]}"}"
    [[ -n "$dt" ]] && SELECTED_MAIN_DT+=("$dt")
  done
else
  mapfile -t SELECTED_MAIN_DT < <(jq -r '
    to_entries[] |
    .value."deployment-type" as $d |
    (if ($d|type=="array") then $d[] else $d end) |
    select(. != "configuration")
  ' "$JSON_FILE" | sort -u)
fi

SELECTED_MAIN_DT+=("licenseserver")
if [[ " ${SELECTED_MAIN_DT[*]} " == *" data-admin "* ]]; then
  SELECTED_MAIN_DT+=("llm")
fi

mapfile -t SELECTED_MAIN_DT < <(printf '%s\n' "${SELECTED_MAIN_DT[@]}" | sort -u)
selected_dts_json=$(printf '%s\n' "${SELECTED_MAIN_DT[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0))')

echo -e "${BOLD}Deployments being processed:${RESET} ${CYAN}${SELECTED_MAIN_DT[*]}${RESET}\n"

# --------------------------------------------------------------------------- #
# Extract ENTRIES using new output-path / template-path
# --------------------------------------------------------------------------- #
mapfile -t ENTRIES < <(
  jq -r --argjson selected_dts "$selected_dts_json" '
    to_entries[] |
    .value as $entry |
    $entry."deployment-type" as $dts |
    (if ($dts | type == "array") then $dts else [$dts] end) as $file_dts |
    select( any( $file_dts[] ; . as $fdt | ($fdt == "configuration") or ($selected_dts | index($fdt) != null) ) ) |

    (
      ($entry.configuration // {}) +
      ($entry.licenseserver // {}) +
      (if ($selected_dts | index("llm") != null) then ($entry.llm // {}) else {} end) +
      (if ($selected_dts | index("basic-idol") != null) then ($entry["basic-idol"] // {}) else {} end) +
      (if ($selected_dts | index("data-admin") != null) then ($entry["data-admin"] // {}) else {} end) +
      (if ($selected_dts | index("rich-media") != null) then ($entry["rich-media"] // {}) else {} end)
    ) |
    to_entries[] |
    .value as $rule |
    [
      ($rule.name // .key),
      ($rule.variable // ""),
      ($rule.placeholder // $rule.find_string // ""),
      $entry."template-path",
      $entry."output-path",
      "",
      ($rule.replacement_with // ""),
      "false"
    ] |
    join("|")
  ' "$JSON_FILE"
)

[[ ${#ENTRIES[@]} -eq 0 ]] && { echo -e "${YELLOW}WARN:${RESET} No entries found"; exit 0; }

# --------------------------------------------------------------------------- #
# PHASE 1 — Environment Variable Validation
# --------------------------------------------------------------------------- #
echo -e "\n${BOLD}━━ PHASE 1 — Environment Variable Validation ━━${RESET}\n"
echo -e "$SEP"

mapfile -t UNIQUE_VARS < <(
  jq -r --argjson selected_dts "$selected_dts_json" '
    to_entries[] |
    .value as $entry |
    $entry."deployment-type" as $dts |
    (if ($dts | type == "array") then $dts else [$dts] end) as $file_dts |
    select( any( $file_dts[] ; . as $fdt | ($fdt == "configuration") or ($selected_dts | index($fdt) != null) ) ) |

    (
      ($entry.configuration // {}) +
      ($entry.licenseserver // {}) +
      (if ($selected_dts | index("llm") != null) then ($entry.llm // {}) else {} end) +
      (if ($selected_dts | index("basic-idol") != null) then ($entry["basic-idol"] // {}) else {} end) +
      (if ($selected_dts | index("data-admin") != null) then ($entry["data-admin"] // {}) else {} end) +
      (if ($selected_dts | index("rich-media") != null) then ($entry["rich-media"] // {}) else {} end)
    ) |
    to_entries[] |
    .value as $rule |
    $rule.name as $rname |
    (if $rule | has("variable") and $rule.variable != "" then "\($rname)|\($rule.variable)" else empty end),
    ( ($rule.replacement_with // "") | scan("\\$\\{([^}]+)\\}")[] | "\($rname)|\(.)" )
  ' "$JSON_FILE" | sort -t'|' -k2,2 -u
)

ok_count=0
warn_count=0
declare -A VAR_STATUS

for uv in "${UNIQUE_VARS[@]}"; do
  name="${uv%%|*}"
  var="${uv##*|}"
  value="${!var:-}"
  if [[ -z "$value" ]]; then
    echo -e " ${YELLOW}⚠ WARNING${RESET} ${CYAN}${var}${RESET} ${DIM}Name:${RESET} ${name} ${DIM}Status:${RESET} ${RED}not set — skipped${RESET}"
    VAR_STATUS["$var"]="missing"
    warn_count=$(( warn_count + 1 ))
  else
    echo -e " ${GREEN}✔ OK${RESET} ${CYAN}${var}${RESET} ${DIM}Name:${RESET} ${name} ${DIM}Value:${RESET} ${value}"
    VAR_STATUS["$var"]="ok"
    ok_count=$(( ok_count + 1 ))
  fi
  echo -e "$SEP"
done

echo -e "\n ${GREEN}Set: ${ok_count}${RESET} ${YELLOW}Missing: ${warn_count}${RESET} Total: ${#UNIQUE_VARS[@]}\n"

if [[ $warn_count -ne 0 ]]; then
  echo -e "${RED}ERROR:${RESET} Some required environment variables are missing."
  echo -e "${RED}Aborting — skipping copy and substitution phases.${RESET}\n"
  exit 1
fi

# --------------------------------------------------------------------------- #
# PHASE 2 — Template → Output Copy (now using "template-path")
# --------------------------------------------------------------------------- #
echo -e "${BOLD}━━ PHASE 2 — Template → Output Copy ━━${RESET}\n"

declare -A INITIALIZED_FILES
for entry in "${ENTRIES[@]}"; do
  IFS='|' read -r name var placeholder template output placeholder_override replacement_value init_from_template <<< "$entry"
  output="$(envsubst <<< "$output")"
  template="$(envsubst <<< "$template")"

  [[ -n "${INITIALIZED_FILES[$output]+_}" ]] && continue
  INITIALIZED_FILES["$output"]=1

  if [[ -f "$output" ]]; then
    if [[ "$output" == *[Dd]ockerfile* || "$output" == *start-licenseserver.sh* ]]; then
      rm -f "$output"
      echo -e " ${YELLOW}RECREATE${RESET} [${output}] - already exists — removed and recreated from template"
      if [[ -f "$template" ]]; then
        mkdir -p "$(dirname "$output")"
        cp -f "$template" "$output"
        echo -e " ${GREEN}✔ CREATED${RESET} ${output} ${DIM}(from ${template##*/})${RESET}"
      else
        echo -e " ${YELLOW}WARN${RESET} Template not found: ${template}"
      fi
    else
      echo -e " ${YELLOW}EXISTS${RESET} ${output}"
    fi
  elif [[ -f "$template" ]]; then
    mkdir -p "$(dirname "$output")"
    cp -f "$template" "$output"
    echo -e " ${GREEN}✔ CREATED${RESET} ${output} ${DIM}(from ${template##*/})${RESET}"
  else
    echo -e " ${YELLOW}WARN${RESET} Template not found: ${template}"
  fi
done
echo -e "\n${GREEN}✓ ${#INITIALIZED_FILES[@]} file(s) processed.${RESET}\n"

# --------------------------------------------------------------------------- #
# PHASE 3 — Placeholder Substitution
# --------------------------------------------------------------------------- #
echo -e "${BOLD}━━ PHASE 3 — Placeholder Substitution ━━${RESET}\n"

declare -A vf_valid vf_invalid
declare -a combo_order var_order
declare -A seen_combo seen_var

_record() {
  local var="${1:-}"
  local output="${2}"
  local status="${3}"
  [[ -z "$var" ]] && return
  local key="${var}|${output}"
  if [[ -z "${seen_var[$var]-}" ]]; then
    var_order+=("$var")
    seen_var["$var"]=1
  fi
  if [[ -z "${seen_combo[$key]-}" ]]; then
    combo_order+=("$key")
    seen_combo["$key"]=1
    vf_valid["$key"]=0
    vf_invalid["$key"]=0
  fi
  [[ "$status" == "valid" ]] && vf_valid["$key"]=$(( vf_valid["$key"] + 1 )) || vf_invalid["$key"]=$(( vf_invalid["$key"] + 1 ))
}

for entry in "${ENTRIES[@]}"; do
  IFS='|' read -r name var placeholder template output placeholder_override replacement_value init_from_template <<< "$entry"
  output="$(envsubst <<< "$output")"
  replacement_value="$(envsubst <<< "$replacement_value")"
  effective_placeholder="${placeholder_override:-$placeholder}"

  if [[ -n "$replacement_value" ]]; then
    value="$replacement_value"
  elif [[ -n "$var" ]]; then
    value="${!var:-}"
  else
    value=""
  fi

  if [[ -z "$value" || ! -f "$output" ]]; then
    _record "$var" "$output" "invalid"
  else
    escaped_value="$(printf '%s' "$value" | sed 's/[\/&]/\\&/g')"
    if sed -i "s/${effective_placeholder}/${escaped_value}/g" "$output" 2>/dev/null; then
      _record "$var" "$output" "valid"
    else
      _record "$var" "$output" "invalid"
    fi
  fi
done

# Summary table (unchanged)
COL_VAR=8 COL_FILE=4 COL_V=5 COL_I=7
for key in "${combo_order[@]}"; do
  v="${key%%|*}"
  f="$(basename "${key##*|}")"
  [[ ${#v} -gt $COL_VAR ]] && COL_VAR=${#v}
  [[ ${#f} -gt $COL_FILE ]] && COL_FILE=${#f}
done
RULE_W=$(( COL_VAR + COL_FILE + COL_V + COL_I + 10 ))
RULE="$(printf '─%.0s' $(seq 1 $RULE_W))"

printf " ${BOLD}%-${COL_VAR}s %-${COL_FILE}s %${COL_V}s %${COL_I}s${RESET}\n" "Variable" "File" "Valid" "Invalid"
printf " %s\n" "$RULE"

total_valid=0 total_invalid=0 prev_var=""
for key in "${combo_order[@]}"; do
  var="${key%%|*}"
  out_path="${key##*|}"
  file_name="$(basename "$out_path")"
  v="${vf_valid[$key]:-0}"
  i="${vf_invalid[$key]:-0}"
  total_valid=$(( total_valid + v ))
  total_invalid=$(( total_invalid + i ))
  display_var="$var"
  [[ "$var" == "$prev_var" ]] && display_var=""
  prev_var="$var"
  if [[ $i -eq 0 && $v -gt 0 ]]; then row_color="$GREEN"
  elif [[ $v -eq 0 ]]; then row_color="$RED"
  else row_color="$YELLOW"; fi
  printf " ${row_color}%-${COL_VAR}s${RESET} %-${COL_FILE}s ${GREEN}%${COL_V}s${RESET} ${RED}%${COL_I}s${RESET}\n" \
    "$display_var" "$file_name" "$v" "$i"
done
printf " %s\n" "$RULE"
printf " ${BOLD}%-${COL_VAR}s${RESET} %-${COL_FILE}s ${GREEN}${BOLD}%${COL_V}s${RESET} ${RED}${BOLD}%${COL_I}s${RESET}\n\n" \
  "TOTAL" "" "$total_valid" "$total_invalid"

# --------------------------------------------------------------------------- #
# Change Owner User 
# --------------------------------------------------------------------------- # 
TARGET_USER="${SUDO_USER:-$USER}"
if [[ "$TARGET_USER" != "root" && -d "${basic_idol_toolkit_path}" ]]; then
  chown -R "$TARGET_USER:$TARGET_USER" "${basic_idol_toolkit_path}"
fi
if [[ "$TARGET_USER" != "root" && -d "${data_admin_toolkit_path}" ]]; then
  chown -R "$TARGET_USER:$TARGET_USER" "${data_admin_toolkit_path}"
fi
if [[ "$TARGET_USER" != "root" && -d "${rich_media_toolkit_path}" ]]; then
  chown -R "$TARGET_USER:$TARGET_USER" "${rich_media_toolkit_path}"
fi

# --------------------------------------------------------------------------- #
# Final status
# --------------------------------------------------------------------------- #
if [[ $total_invalid -gt 0 || $warn_count -gt 0 ]]; then
  echo -e "${YELLOW}Completed with warnings.${RESET}"
  exit 1
fi
echo -e "${GREEN}All variables set and placeholders substituted successfully.${RESET}\n"
