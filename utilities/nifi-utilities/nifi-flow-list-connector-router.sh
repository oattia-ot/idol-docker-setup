#!/bin/bash

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# ============================================================
# Usage / Help
# ============================================================
usage() {
    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║   NiFi — ConnectorGroupRouter / ConnectorRouter Fetcher      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${BOLD}${CYAN}SYNOPSIS${NC}"
    echo -e "  $0 [OPTIONS]\n"
    echo -e "${BOLD}${CYAN}DESCRIPTION${NC}"
    echo -e "  Recursively discovers all processors across the NiFi flow,"
    echo -e "  filters only those whose type matches ConnectorGroupRouter"
    echo -e "  or ConnectorRouter, then fetches each one's ConnectorGroup"
    echo -e "  properties and renders them.\n"
    echo -e "${BOLD}${CYAN}OPTIONS${NC}"
    echo -e "  ${YELLOW}--help,       -h${NC}         Show this help and exit"
    echo -e "  ${YELLOW}--url,        -u${NC} URL      NiFi base URL (default: https://idol-docker-host:8443)"
    echo -e "  ${YELLOW}--auth,       -a${NC} METHOD   Auth method: ${WHITE}password${NC}|${WHITE}token${NC}|${WHITE}none${NC} (default: password)"
    echo -e "  ${YELLOW}--username,   -U${NC} USER     Username (default: admin)"
    echo -e "  ${YELLOW}--password,   -P${NC} PASS     Password (default: OpenText2026!)"
    echo -e "  ${YELLOW}--token,      -t${NC} TOKEN    Bearer token"
    echo -e "  ${YELLOW}--filter,     -F${NC} KEYWORD  Property key filter (default: ConnectorGroup)"
    echo -e "  ${YELLOW}--all-props${NC}               Show ALL processor properties (ignores --filter)"
    echo -e "  ${YELLOW}--output,     -o${NC} FORMAT   Output format: ${WHITE}table${NC}|${WHITE}json${NC}|${WHITE}csv${NC} (default: table)"
    echo -e "  ${YELLOW}--output-file,-f${NC} FILE     Write output to FILE (stdout still shown for table)\n"
    echo -e "${BOLD}${CYAN}EXAMPLES${NC}"
    echo -e "  ${GRAY}# Run with defaults (interactive URL + credentials prompt)${NC}"
    echo -e "  $0\n"
    echo -e "  ${GRAY}# Fully non-interactive${NC}"
    echo -e "  $0 -u https://nifi-host:8443 -U admin -P secret\n"
    echo -e "  ${GRAY}# Output as JSON saved to file${NC}"
    echo -e "  $0 -u https://nifi-host:8443 -o json -f /tmp/connectors.json\n"
    echo -e "  ${GRAY}# Output as CSV saved to file${NC}"
    echo -e "  $0 -o csv -f /tmp/connectors.csv\n"
    echo -e "  ${GRAY}# Show ALL properties for each matching processor${NC}"
    echo -e "  $0 --all-props\n"
    exit 0
}

# ============================================================
# Defaults
# ============================================================
NIFI_URL=""
AUTH_METHOD=""
USERNAME=""
PASSWORD=""
TOKEN=""
FILTER_KEYWORD="ConnectorGroup"
OUTPUT_FORMAT="table"
OUTPUT_FILE=""
SHOW_ALL_PROPS=false
INTERACTIVE=true

# ============================================================
# Argument parsing
# ============================================================
case "$1" in --help|-h) usage ;; esac

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)        usage ;;
        -u|--url)         NIFI_URL="$2";       INTERACTIVE=false; shift 2 ;;
        -a|--auth)        AUTH_METHOD="$2";    shift 2 ;;
        -U|--username)    USERNAME="$2";       shift 2 ;;
        -P|--password)    PASSWORD="$2";       shift 2 ;;
        -t|--token)       TOKEN="$2";          shift 2 ;;
        -F|--filter)      FILTER_KEYWORD="$2"; shift 2 ;;
        -o|--output)      OUTPUT_FORMAT="$2";  shift 2 ;;
        -f|--output-file) OUTPUT_FILE="$2";    shift 2 ;;
        --all-props)      SHOW_ALL_PROPS=true; shift ;;
        --)               shift; break ;;
        -*) echo -e "${RED}✗ Unknown option:${NC} $1"; usage ;;
        *)  shift ;;
    esac
done

# ============================================================
# Validate options
# ============================================================
if [[ ! "$OUTPUT_FORMAT" =~ ^(table|json|csv)$ ]]; then
    echo -e "${RED}✗ Invalid --output:${NC} $OUTPUT_FORMAT  (valid: table, json, csv)"
    exit 1
fi

# Validate output file path is writable
if [ -n "$OUTPUT_FILE" ]; then
    touch "$OUTPUT_FILE" 2>/dev/null || {
        echo -e "${RED}✗ Cannot write to output file:${NC} $OUTPUT_FILE"; exit 1
    }
fi

# ============================================================
# Dependencies
# ============================================================
if ! command -v curl &>/dev/null; then
    echo -e "${RED}✗ 'curl' is required but not installed.${NC}"; exit 1
fi
if ! command -v jq &>/dev/null; then
    echo -e "${RED}✗ 'jq' is required but not installed.${NC}"
    echo -e "${YELLOW}Install:${NC}  Ubuntu/Debian: ${CYAN}sudo apt-get install jq${NC}  |  macOS: ${CYAN}brew install jq${NC}"
    exit 1
fi

# ============================================================
# Output helper
# Writes formatted data to file when --output-file is set.
# table mode: also echoes to stdout (progress interleaved).
# json/csv mode: writes ONLY to file (clean machine-readable output).
# ============================================================
_OUT_BUFFER=""

out_begin() {
    # Called once before the data loop
    _OUT_BUFFER=""
    [ "$OUTPUT_FORMAT" = "json" ] && _OUT_BUFFER="["$'\n'
}

out_append() {
    _OUT_BUFFER+="$1"$'\n'
}

out_end() {
    # Called once after the data loop
    [ "$OUTPUT_FORMAT" = "json" ] && _OUT_BUFFER+="]"$'\n'
    if [ -n "$OUTPUT_FILE" ]; then
        printf '%s' "$_OUT_BUFFER" > "$OUTPUT_FILE"
        echo -e "${GREEN}✓${NC} Output written to ${BOLD}${OUTPUT_FILE}${NC}\n"
    fi
}

# ============================================================
# Banner
# ============================================================
echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   NiFi — ConnectorGroupRouter / ConnectorRouter Fetcher      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================================
# Configuration
# ============================================================
echo -e "${CYAN}${BOLD}Configuration:${NC}"

if [ "$INTERACTIVE" = true ]; then
    read -p "$(echo -e ${WHITE}NiFi URL ${GRAY}[default: https://idol-docker-host:8443]${NC}: )" NIFI_URL
fi
NIFI_URL="${NIFI_URL:-https://idol-docker-host:8443}"
echo -e "${GREEN}✓${NC} NiFi URL: ${BLUE}${NIFI_URL}${NC}\n"

# ============================================================
# Authentication
# ============================================================
if [ "$INTERACTIVE" = true ] && [ -z "$AUTH_METHOD" ]; then
    echo -e "${CYAN}${BOLD}Authentication:${NC}"
    echo -e "  ${YELLOW}1)${NC} Username / password"
    echo -e "  ${YELLOW}2)${NC} Existing Bearer token"
    echo -e "  ${YELLOW}3)${NC} None"
    read -p "$(echo -e ${WHITE}Choice ${GRAY}[1-3, default: 1]${NC}: )" _AUTH_CHOICE
    case "$_AUTH_CHOICE" in
        2) AUTH_METHOD="token" ;;
        3) AUTH_METHOD="none"  ;;
        *) AUTH_METHOD="password" ;;
    esac
fi
AUTH_METHOD="${AUTH_METHOD:-password}"

if [[ ! "$AUTH_METHOD" =~ ^(password|token|none)$ ]]; then
    echo -e "${RED}✗ Invalid --auth:${NC} $AUTH_METHOD  (valid: password, token, none)"; exit 1
fi

case "$AUTH_METHOD" in
    password)
        if [ "$INTERACTIVE" = true ]; then
            read -p "$(echo -e "\n"${WHITE}Username ${GRAY}[default: admin]${NC}: )" USERNAME
            read -sp "$(echo -e ${WHITE}Password ${GRAY}[default: OpenText2026!]${NC}: )" PASSWORD
            echo ""
        fi
        USERNAME="${USERNAME:-admin}"
        PASSWORD="${PASSWORD:-OpenText2026!}"

        echo -e "\n${YELLOW}⟳${NC} Generating token for '${USERNAME}'..."
        TOKEN=$(curl -k -s -X POST "${NIFI_URL}/nifi-api/access/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "username=${USERNAME}&password=${PASSWORD}" | tr -d '\n')

        if [ -z "$TOKEN" ] || [[ "$TOKEN" == *"Unable to generate"* ]] || [[ "$TOKEN" == *"{"* ]]; then
            echo -e "${RED}✗ Failed to generate token. Check credentials or NiFi URL.${NC}"; exit 1
        fi
        echo -e "${GREEN}✓${NC} Token generated\n"
        ;;
    token)
        if [ -z "$TOKEN" ]; then
            read -p "$(echo -e ${WHITE}Enter Bearer token${NC}: )" TOKEN
        fi
        [ -z "$TOKEN" ] && echo -e "${RED}✗ Token cannot be empty.${NC}" && exit 1
        echo -e "${GREEN}✓${NC} Token accepted\n"
        ;;
    none)
        echo -e "${YELLOW}⚠${NC} Proceeding without authentication\n"
        TOKEN=""
        ;;
esac

# ============================================================
# Temp files
# ============================================================
TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

TMP_HTTP="${TMPDIR_WORK}/http_code"

# nifi_get_file <url> <dest_file>  →  sets _HTTP
nifi_get_file() {
    local url="$1" dest="$2"
    if [ -n "$TOKEN" ]; then
        curl -k -s \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Accept: application/json" \
            -o "$dest" -w "%{http_code}" "$url" > "$TMP_HTTP"
    else
        curl -k -s \
            -H "Accept: application/json" \
            -o "$dest" -w "%{http_code}" "$url" > "$TMP_HTTP"
    fi
    _HTTP=$(cat "$TMP_HTTP")
}

# ============================================================
# Recursive processor discovery
# Collects only ConnectorGroupRouter or ConnectorRouter types
# ============================================================
declare -a PROC_IDS PROC_NAMES PROC_TYPES PROC_STATES PROC_PATHS

collect_matching_processors() {
    local pg_id="$1"
    local pg_path="${2:-NiFi Flow}"
    local tmp_pg="${TMPDIR_WORK}/pg_${pg_id}.json"

    nifi_get_file "${NIFI_URL}/nifi-api/flow/process-groups/${pg_id}" "$tmp_pg"
    [ "$_HTTP" != "200" ] && return 1

    while IFS='|' read -r id name type state; do
        [ -z "$id" ] && continue
        SHORT_T=$(echo "$type" | awk -F'.' '{print $NF}')
        if [[ "$SHORT_T" == "ConnectorGroupRouter" || "$SHORT_T" == "ConnectorRouter" ]]; then
            PROC_IDS+=("$id")
            PROC_NAMES+=("$name")
            PROC_TYPES+=("$type")
            PROC_STATES+=("$state")
            PROC_PATHS+=("$pg_path")
        fi
    done < <(jq -r '
        .processGroupFlow.flow.processors[]?
        | [.id, .component.name, .component.type, .component.state]
        | join("|")' "$tmp_pg" 2>/dev/null)

    # Recurse into child groups
    while IFS='|' read -r child_id child_name; do
        [ -z "$child_id" ] && continue
        collect_matching_processors "$child_id" "${pg_path} > ${child_name}"
    done < <(jq -r '
        .processGroupFlow.flow.processGroups[]?
        | [.id, .component.name]
        | join("|")' "$tmp_pg" 2>/dev/null)
}

# ============================================================
# Step 1: Discover all matching processors
# ============================================================
echo -e "${CYAN}${BOLD}Step 1/3:${NC} Discovering ConnectorGroupRouter / ConnectorRouter processors..."

TMP_ROOT="${TMPDIR_WORK}/root.json"
nifi_get_file "${NIFI_URL}/nifi-api/flow/process-groups/root" "$TMP_ROOT"
if [ "$_HTTP" != "200" ]; then
    echo -e "${RED}✗ Failed to reach NiFi (HTTP ${_HTTP}).${NC}"; exit 1
fi
ROOT_ID=$(jq -r '.processGroupFlow.id // empty' "$TMP_ROOT")
if [ -z "$ROOT_ID" ] || [ "$ROOT_ID" = "null" ]; then
    echo -e "${RED}✗ Could not get root process group ID.${NC}"; exit 1
fi

collect_matching_processors "$ROOT_ID"

# ---- Deduplicate by processor ID (keep first occurrence) ----
declare -a _UIDS _UNAMES _UTYPES _USTATES _UPATHS
declare -A _SEEN_IDS
for i in "${!PROC_IDS[@]}"; do
    pid="${PROC_IDS[$i]}"
    if [[ -z "${_SEEN_IDS[$pid]}" ]]; then
        _SEEN_IDS[$pid]=1
        _UIDS+=("$pid")
        _UNAMES+=("${PROC_NAMES[$i]}")
        _UTYPES+=("${PROC_TYPES[$i]}")
        _USTATES+=("${PROC_STATES[$i]}")
        _UPATHS+=("${PROC_PATHS[$i]}")
    fi
done
PROC_IDS=("${_UIDS[@]}")
PROC_NAMES=("${_UNAMES[@]}")
PROC_TYPES=("${_UTYPES[@]}")
PROC_STATES=("${_USTATES[@]}")
PROC_PATHS=("${_UPATHS[@]}")
unset _UIDS _UNAMES _UTYPES _USTATES _UPATHS _SEEN_IDS
# ---- End dedup -----------------------------------------------

if [ ${#PROC_IDS[@]} -eq 0 ]; then
    echo -e "${YELLOW}⚠ No ConnectorGroupRouter or ConnectorRouter processors found.${NC}"; exit 0
fi
echo -e "${GREEN}✓${NC} Found ${BOLD}${#PROC_IDS[@]}${NC} matching processor(s)\n"

# ============================================================
# Step 2: Summary of matched processors
# ============================================================
echo -e "${CYAN}${BOLD}Step 2/3:${NC} Matched processors:\n"
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║          ConnectorGroupRouter / ConnectorRouter               ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\n"

for i in "${!PROC_IDS[@]}"; do
    case "${PROC_STATES[$i]}" in
        RUNNING)  SC="${GREEN}"  SI="●" ;;
        STOPPED)  SC="${RED}"    SI="○" ;;
        DISABLED) SC="${GRAY}"   SI="○" ;;
        *)        SC="${YELLOW}" SI="◑" ;;
    esac
    SHORT_TYPE=$(echo "${PROC_TYPES[$i]}" | awk -F'.' '{print $NF}')
    echo -e "${YELLOW}${BOLD}$((i+1)).${NC} ${WHITE}${PROC_NAMES[$i]}${NC}  ${SC}${SI} ${PROC_STATES[$i]}${NC}"
    echo -e "   ${CYAN}├─${NC} ${DIM}Type:${NC}     ${GRAY}${SHORT_TYPE}${NC}"
    echo -e "   ${CYAN}├─${NC} ${DIM}Location:${NC} ${MAGENTA}${PROC_PATHS[$i]}${NC}"
    echo -e "   ${CYAN}└─${NC} ${DIM}ID:${NC}       ${GRAY}${PROC_IDS[$i]}${NC}"
    echo ""
done
echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}\n"

# ============================================================
# Step 3: Fetch and render properties for each processor
# ============================================================
FILTER_LABEL="$FILTER_KEYWORD"
[ "$SHOW_ALL_PROPS" = true ] && FILTER_LABEL="ALL"

echo -e "${CYAN}${BOLD}Step 3/3:${NC} Fetching properties (filter: ${BOLD}${FILTER_LABEL}${NC}) for each processor...\n"

TOTAL_MATCH=0
out_begin

for i in "${!PROC_IDS[@]}"; do
    PID="${PROC_IDS[$i]}"
    PNAME="${PROC_NAMES[$i]}"
    PSTATE="${PROC_STATES[$i]}"
    SHORT_TYPE=$(echo "${PROC_TYPES[$i]}" | awk -F'.' '{print $NF}')

    TMP_PROC="${TMPDIR_WORK}/processor_${PID}.json"
    nifi_get_file "${NIFI_URL}/nifi-api/processors/${PID}" "$TMP_PROC"

    if [ "$_HTTP" != "200" ]; then
        echo -e "${RED}✗ Failed to fetch processor '${PNAME}' (HTTP ${_HTTP}) — skipping.${NC}\n"
        continue
    fi

    # Build jq filter
    if [ "$SHOW_ALL_PROPS" = true ]; then
        JQ_FILTER='.component.config.properties | to_entries[]'
    else
        JQ_FILTER=".component.config.properties | to_entries[] | select(.key | ascii_downcase | contains(\"$(echo "$FILTER_KEYWORD" | tr '[:upper:]' '[:lower:]')\"))"
    fi

    PROPS_RAW=$(jq -r "${JQ_FILTER} | \"\(.key)|\(.value // \"null\")\"" "$TMP_PROC" 2>/dev/null)

    # ---- JSON ------------------------------------------------
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        [ $i -gt 0 ] && out_append "  ,"
        out_append "  {"
        out_append "    \"processorId\": $(echo "$PID"        | jq -Rs .),"
        out_append "    \"processorName\": $(echo "$PNAME"    | jq -Rs .),"
        out_append "    \"processorType\": $(echo "$SHORT_TYPE" | jq -Rs .),"
        out_append "    \"state\": $(echo "$PSTATE"           | jq -Rs .),"
        out_append "    \"properties\": ["
        if [ -z "$PROPS_RAW" ]; then
            out_append "    ]"
        else
            mapfile -t _LINES <<< "$PROPS_RAW"
            LAST=$(( ${#_LINES[@]} - 1 ))
            for j in "${!_LINES[@]}"; do
                IFS='|' read -r key value <<< "${_LINES[$j]}"
                COMMA=","; [ $j -eq $LAST ] && COMMA=""
                out_append "$(printf '      { "key": %s, "value": %s }%s' \
                    "$(echo "$key"   | jq -Rs .)" \
                    "$(echo "$value" | jq -Rs .)" \
                    "$COMMA")"
            done
            out_append "    ]"
        fi
        out_append "  }"
        continue
    fi

    # ---- CSV -------------------------------------------------
    if [ "$OUTPUT_FORMAT" = "csv" ]; then
        [ $i -eq 0 ] && out_append "ProcessorName,ProcessorId,ProcessorType,Key,Value"
        if [ -z "$PROPS_RAW" ]; then
            out_append "\"${PNAME}\",\"${PID}\",\"${SHORT_TYPE}\",\"\",\"\""
        else
            while IFS='|' read -r key value; do
                out_append "\"${PNAME}\",\"${PID}\",\"${SHORT_TYPE}\",\"${key}\",\"${value}\""
            done <<< "$PROPS_RAW"
        fi
        continue
    fi

    # ---- TABLE (default) — also echoes to stdout -------------
    case "$PSTATE" in
        RUNNING)  SC="${GREEN}"  ;;
        STOPPED)  SC="${RED}"    ;;
        DISABLED) SC="${GRAY}"   ;;
        *)        SC="${YELLOW}" ;;
    esac

    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║  [$((i+1))/${#PROC_IDS[@]}] ${WHITE}${PNAME}${CYAN}$(printf '%*s' $((44 - ${#PNAME})) '') ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "  ${YELLOW}Type:${NC}  ${GRAY}${SHORT_TYPE}${NC}   ${YELLOW}State:${NC} ${SC}${PSTATE}${NC}"
    echo -e "  ${YELLOW}ID:${NC}    ${GRAY}${PID}${NC}"
    echo -e "  ${YELLOW}Path:${NC}  ${MAGENTA}${PROC_PATHS[$i]}${NC}\n"

    # table file output (plain, no ANSI)
    out_append "[$((i+1))/${#PROC_IDS[@]}] ${PNAME}"
    out_append "  Type:  ${SHORT_TYPE}   State: ${PSTATE}"
    out_append "  ID:    ${PID}"
    out_append "  Path:  ${PROC_PATHS[$i]}"

    if [ -z "$PROPS_RAW" ]; then
        echo -e "  ${YELLOW}⚠ No properties match filter '${FILTER_KEYWORD}'.${NC}"
        echo -e "  ${CYAN}Available keys:${NC}"
        jq -r '.component.config.properties | keys[]' "$TMP_PROC" 2>/dev/null | while read -r k; do
            echo -e "    ${GRAY}•${NC} $k"
        done
        out_append "  (no properties matched filter '${FILTER_KEYWORD}')"
        echo ""
    else
        declare -a KEYS VALUES
        KEYS=(); VALUES=()
        while IFS='|' read -r key value; do
            KEYS+=("$key")
            VALUES+=("$value")
        done <<< "$PROPS_RAW"

        for j in "${!KEYS[@]}"; do
            VC="${WHITE}"; [ "${VALUES[$j]}" = "null" ] && VC="${GRAY}"
            echo -e "  ${YELLOW}${BOLD}$((j+1)).${NC} ${CYAN}${KEYS[$j]}${NC}"
            echo -e "     ${CYAN}└─${NC} ${DIM}Value:${NC} ${VC}${VALUES[$j]}${NC}"
            out_append "  $((j+1)). ${KEYS[$j]}"
            out_append "     Value: ${VALUES[$j]}"
        done
        echo ""
        out_append ""
        TOTAL_MATCH=$((TOTAL_MATCH + ${#KEYS[@]}))
    fi
    echo -e "${DIM}────────────────────────────────────────────────────────────────${NC}\n"
    out_append "────────────────────────────────────────────────────────────────"
done

out_end   # flush buffer → file (if --output-file set); closes JSON array

# ============================================================
# Footer (table mode only)
# ============================================================
if [ "$OUTPUT_FORMAT" = "table" ]; then
    echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Done${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
    echo -e "  ${WHITE}Processors scanned:${NC}   ${BOLD}${#PROC_IDS[@]}${NC}"
    echo -e "  ${WHITE}Filter applied:${NC}        ${BOLD}${FILTER_LABEL}${NC}"
    echo -e "  ${WHITE}Total props matched:${NC}   ${BOLD}${TOTAL_MATCH}${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════${NC}\n"
fi

# ============================================================
# Purge & Sync
# ============================================================

fetch_revision() {
    local pid="$1" tmp="${TMPDIR_WORK}/rev_${pid}_$(date +%s%N).json"
    nifi_get_file "${NIFI_URL}/nifi-api/processors/${pid}" "$tmp"
    _REV_VERSION=$(jq -r '.revision.version // 0'          "$tmp" 2>/dev/null)
    _REV_CLIENT=$(jq  -r '.revision.clientId // "shell"'   "$tmp" 2>/dev/null)
    _CURRENT_STATE=$(jq -r '.component.state // "STOPPED"' "$tmp" 2>/dev/null)
    [ "$_REV_CLIENT" = "null" ] && _REV_CLIENT="shell"
}

set_processor_state() {
    local pid="$1" state="$2" ver="$3" cid="$4"
    local payload
    payload=$(jq -n \
        --arg  st  "$state" \
        --argjson v  "$ver" \
        --arg  cid "$cid" \
        '{revision:{version:$v,clientId:$cid},state:$st}')

    local tmp_resp="${TMPDIR_WORK}/state_resp_${pid}_$(date +%s%N).json"
    if [ -n "$TOKEN" ]; then
        curl -k -s -X PUT \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -d "$payload" \
            -o "$tmp_resp" -w "%{http_code}" \
            "${NIFI_URL}/nifi-api/processors/${pid}/run-status" > "$TMP_HTTP"
    else
        curl -k -s -X PUT \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -d "$payload" \
            -o "$tmp_resp" -w "%{http_code}" \
            "${NIFI_URL}/nifi-api/processors/${pid}/run-status" > "$TMP_HTTP"
    fi
    _HTTP=$(cat "$TMP_HTTP")
    _HTTP_ERR=$(jq -r '.message // .error // ""' "$tmp_resp" 2>/dev/null)
}

fetch_connector_group_values() {
    local pid="$1" tmp="${TMPDIR_WORK}/cg_${1}.json"
    nifi_get_file "${NIFI_URL}/nifi-api/processors/${pid}" "$tmp"
    jq -r '.component.config.properties | to_entries[] | select(.key | contains("ConnectorGroup")) | "\(.key) = \(.value // "null")"' \
        "$tmp" 2>/dev/null
}

echo -e "${BOLD}${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${MAGENTA}║              Purge & Sync Execution                          ║${NC}"
echo -e "${BOLD}${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}\n"

echo -e "  ${YELLOW}⚠  Selected processors will be:${NC}"
echo -e "     ${CYAN}1.${NC} Stopped        (if currently RUNNING)"
echo -e "     ${CYAN}2.${NC} Triggered      RUN_ONCE  (Purge & Sync)"
echo -e "     ${CYAN}3.${NC} Restored       to their original state\n"

echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║              Available Processors for Purge & Sync           ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\n"

for i in "${!PROC_IDS[@]}"; do
    SHORT_TYPE=$(echo "${PROC_TYPES[$i]}" | awk -F'.' '{print $NF}')
    case "${PROC_STATES[$i]}" in
        RUNNING)  SC="${GREEN}"  SI="●" ;;
        STOPPED)  SC="${RED}"    SI="○" ;;
        DISABLED) SC="${GRAY}"   SI="○" ;;
        *)        SC="${YELLOW}" SI="◑" ;;
    esac
    echo -e "  ${YELLOW}${BOLD}$((i+1)).${NC} ${WHITE}${PROC_NAMES[$i]}${NC}  ${SC}${SI} ${PROC_STATES[$i]}${NC}  ${GRAY}[${SHORT_TYPE}]${NC}"
    CG_VALS=$(fetch_connector_group_values "${PROC_IDS[$i]}")
    if [ -n "$CG_VALS" ]; then
        while IFS= read -r line; do
            echo -e "      ${CYAN}└─${NC} ${DIM}${line}${NC}"
        done <<< "$CG_VALS"
    fi
    echo ""
done

echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}\n"

echo -e "  Enter the processor number(s) to Purge & Sync."
echo -e "  ${GRAY}Examples:${NC}  ${WHITE}1${NC}        → only processor 1"
echo -e "             ${WHITE}1 3 5${NC}    → processors 1, 3 and 5"
echo -e "             ${WHITE}all${NC}      → all processors"
echo -e "             ${WHITE}none${NC}     → skip / exit\n"

# ---- SINGLE selection block (declare BEFORE the loop) --------
declare -a SELECTED_INDICES

while true; do
    read -p "$(echo -e "${WHITE}Selection ${GRAY}[number(s)/all/none]${NC}: ")" _RAW_SEL
    _RAW_SEL="${_RAW_SEL:-none}"

    if [[ "${_RAW_SEL,,}" == "none" ]]; then
        echo -e "\n${YELLOW}⚠${NC} Purge & Sync skipped.\n"
        exit 0
    elif [[ "${_RAW_SEL,,}" == "all" ]]; then
        for i in "${!PROC_IDS[@]}"; do SELECTED_INDICES+=("$i"); done
        break
    else
        VALID=true
        for tok in $_RAW_SEL; do
            if ! [[ "$tok" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}✗ '${tok}' is not valid — enter numbers, 'all', or 'none'.${NC}"
                VALID=false; break
            fi
            idx=$((tok - 1))
            if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#PROC_IDS[@]}" ]; then
                echo -e "${RED}✗ ${tok} is out of range (1–${#PROC_IDS[@]}).${NC}"
                VALID=false; break
            fi
            SELECTED_INDICES+=("$idx")
        done
        if [ "$VALID" = true ]; then
            break
        else
            SELECTED_INDICES=()   # reset before re-prompting
        fi
    fi
done
# ---- End selection block -------------------------------------

if [ "${#SELECTED_INDICES[@]}" -eq 0 ]; then
    echo -e "\n${YELLOW}⚠${NC} No processors selected. Purge & Sync skipped.\n"
    exit 0
fi

echo -e "\n${YELLOW}⟳${NC} Starting Purge & Sync on ${BOLD}${#SELECTED_INDICES[@]}${NC} processor(s)...\n"

PS_SUCCESS=0
PS_FAILED=0

for i in "${SELECTED_INDICES[@]}"; do
    PID="${PROC_IDS[$i]}"
    PNAME="${PROC_NAMES[$i]}"

    echo -e "${CYAN}▶${NC} ${WHITE}${PNAME}${NC}  ${GRAY}(${PID})${NC}"

    fetch_revision "$PID"
    ORIG_STATE="$_CURRENT_STATE"
    REV="$_REV_VERSION"
    CID="$_REV_CLIENT"

    # -- Step 1: Stop if RUNNING
    if [ "$ORIG_STATE" = "RUNNING" ]; then
        echo -e "  ${YELLOW}⟳${NC} Stopping processor..."
        set_processor_state "$PID" "STOPPED" "$REV" "$CID"
        if [ "$_HTTP" != "200" ]; then
            echo -e "  ${RED}✗ Failed to stop processor (HTTP ${_HTTP}) — skipping.${NC}"
            [ -n "$_HTTP_ERR" ] && echo -e "  ${RED}  API: ${_HTTP_ERR}${NC}"
            echo ""
            PS_FAILED=$((PS_FAILED + 1))
            continue
        fi
        echo -e "  ${GREEN}✓${NC} Stopped"
        sleep 1
        fetch_revision "$PID"
        REV="$_REV_VERSION"
        CID="$_REV_CLIENT"
    fi

    # -- Step 2: Trigger RUN_ONCE
    echo -e "  ${YELLOW}⟳${NC} Triggering RUN_ONCE (Purge & Sync)..."
    set_processor_state "$PID" "RUN_ONCE" "$REV" "$CID"
    if [ "$_HTTP" != "200" ]; then
        echo -e "  ${RED}✗ RUN_ONCE failed (HTTP ${_HTTP}).${NC}"
        [ -n "$_HTTP_ERR" ] && echo -e "  ${RED}  API: ${_HTTP_ERR}${NC}"
        fetch_revision "$PID"; REV="$_REV_VERSION"; CID="$_REV_CLIENT"
        set_processor_state "$PID" "$ORIG_STATE" "$REV" "$CID"
        echo -e "  ${YELLOW}⚠${NC} Attempted to restore state to ${ORIG_STATE}\n"
        PS_FAILED=$((PS_FAILED + 1))
        continue
    fi
    echo -e "  ${GREEN}✓${NC} RUN_ONCE triggered"
    sleep 2

    # -- Step 3: Restore original state
    if [ "$ORIG_STATE" = "RUNNING" ]; then
        fetch_revision "$PID"; REV="$_REV_VERSION"; CID="$_REV_CLIENT"
        echo -e "  ${YELLOW}⟳${NC} Restoring state to RUNNING..."
        set_processor_state "$PID" "RUNNING" "$REV" "$CID"
        if [ "$_HTTP" != "200" ]; then
            echo -e "  ${YELLOW}⚠${NC} Could not restore to RUNNING (HTTP ${_HTTP}). Manual action may be needed."
        else
            echo -e "  ${GREEN}✓${NC} Restored to RUNNING"
        fi
    fi

    echo -e "  ${GREEN}✓ Purge & Sync complete${NC}\n"
    PS_SUCCESS=$((PS_SUCCESS + 1))
done

echo -e "${MAGENTA}══════════════════════════════════════════════════════${NC}"
echo -e "${MAGENTA}  Purge & Sync Summary${NC}"
echo -e "${MAGENTA}══════════════════════════════════════════════════════${NC}"
echo -e "  ${WHITE}Processors attempted:${NC}  ${BOLD}${#SELECTED_INDICES[@]}${NC}"
echo -e "  ${GREEN}✓ Succeeded:${NC}           ${BOLD}${PS_SUCCESS}${NC}"
if [ "$PS_FAILED" -gt 0 ]; then
    echo -e "  ${RED}✗ Failed:${NC}              ${BOLD}${PS_FAILED}${NC}"
fi
echo -e "${MAGENTA}══════════════════════════════════════════════════════${NC}\n"

exit 0