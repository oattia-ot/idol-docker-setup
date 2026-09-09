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
    echo -e "${BOLD}${MAGENTA}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         NiFi — ConnectorRouter Purge & Sync (Reingest)       ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${BOLD}${CYAN}SYNOPSIS${NC}"
    echo -e "  $0 [OPTIONS]\n"
    echo -e "${BOLD}${CYAN}DESCRIPTION${NC}"
    echo -e "  Recursively discovers all ConnectorGroupRouter and ConnectorRouter"
    echo -e "  processors in the NiFi flow, presents a selection menu, then"
    echo -e "  executes a Purge & Sync (RUN_ONCE) on the chosen processor(s).\n"
    echo -e "  Each selected processor is safely:"
    echo -e "    1. Stopped       (if currently RUNNING)"
    echo -e "    2. Triggered     RUN_ONCE  (Purge & Sync)"
    echo -e "    3. Restored      to its original state\n"
    echo -e "${BOLD}${CYAN}OPTIONS${NC}"
    echo -e "  ${YELLOW}--help,      -h${NC}          Show this help and exit"
    echo -e "  ${YELLOW}--url,       -u${NC} URL       NiFi base URL  (default: https://idol-docker-host:8443)"
    echo -e "  ${YELLOW}--auth,      -a${NC} METHOD    Auth method: ${WHITE}password${NC}|${WHITE}token${NC}|${WHITE}none${NC}  (default: password)"
    echo -e "  ${YELLOW}--username,  -U${NC} USER      Username  (default: admin)"
    echo -e "  ${YELLOW}--password,  -P${NC} PASS      Password  (default: OpenText2026!)"
    echo -e "  ${YELLOW}--token,     -t${NC} TOKEN     Bearer token"
    echo -e "  ${YELLOW}--select,    -s${NC} SEL       Non-interactive selection: ${WHITE}all${NC} | ${WHITE}none${NC} | space-separated numbers"
    echo -e "                            e.g. ${GRAY}--select all${NC}  or  ${GRAY}--select \"1 3\"${NC}\n"
    echo -e "${BOLD}${CYAN}EXAMPLES${NC}"
    echo -e "  ${GRAY}# Interactive (prompts for URL, credentials, and selection)${NC}"
    echo -e "  $0\n"
    echo -e "  ${GRAY}# Fully non-interactive — run Purge & Sync on ALL processors${NC}"
    echo -e "  $0 -u https://nifi-host:8443 -U admin -P secret -s all\n"
    echo -e "  ${GRAY}# Non-interactive — run only processor 1 and 3${NC}"
    echo -e "  $0 -u https://nifi-host:8443 -U admin -P secret -s \"1 3\"\n"
    echo -e "  ${GRAY}# Use an existing Bearer token, non-interactive${NC}"
    echo -e "  $0 -u https://nifi-host:8443 -a token -t <your-token> -s all\n"
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
NON_INTERACTIVE_SEL=""   # set via --select / -s
INTERACTIVE=true

# ============================================================
# Argument parsing
# ============================================================
case "$1" in --help|-h) usage ;; esac

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)      usage ;;
        -u|--url)       NIFI_URL="$2";              INTERACTIVE=false; shift 2 ;;
        -a|--auth)      AUTH_METHOD="$2";           shift 2 ;;
        -U|--username)  USERNAME="$2";              shift 2 ;;
        -P|--password)  PASSWORD="$2";              shift 2 ;;
        -t|--token)     TOKEN="$2";                 shift 2 ;;
        -s|--select)    NON_INTERACTIVE_SEL="$2";   shift 2 ;;
        --)             shift; break ;;
        -*) echo -e "${RED}✗ Unknown option:${NC} $1"; usage ;;
        *)  shift ;;
    esac
done

# If --select was supplied, force fully non-interactive mode
[ -n "$NON_INTERACTIVE_SEL" ] && INTERACTIVE=false

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
# Banner
# ============================================================
echo -e "${BOLD}${MAGENTA}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         NiFi — ConnectorRouter Purge & Sync (Reingest)       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================================
# Configuration
# ============================================================
echo -e "${CYAN}${BOLD}Configuration:${NC}"
if [ "$INTERACTIVE" = true ]; then
    read -p "$(echo -e "${WHITE}NiFi URL ${GRAY}[default: https://idol-docker-host:8443]${NC}: ")" NIFI_URL
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
    read -p "$(echo -e "${WHITE}Choice ${GRAY}[1-3, default: 1]${NC}: ")" _AUTH_CHOICE
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
            read -p "$(echo -e "\n${WHITE}Username ${GRAY}[default: admin]${NC}: ")" USERNAME
            read -sp "$(echo -e "${WHITE}Password ${GRAY}[default: OpenText2026!]${NC}: ")" PASSWORD
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
            read -p "$(echo -e "${WHITE}Enter Bearer token${NC}: ")" TOKEN
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
# Temp workspace
# ============================================================
TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT
TMP_HTTP="${TMPDIR_WORK}/http_code"

# ============================================================
# HTTP helper — nifi_get_file <url> <dest>  →  sets _HTTP
# ============================================================
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
# Revision helper — sets _REV_VERSION _REV_CLIENT _CURRENT_STATE
# ============================================================
fetch_revision() {
    local pid="$1" tmp="${TMPDIR_WORK}/rev_${pid}_$(date +%s%N).json"
    nifi_get_file "${NIFI_URL}/nifi-api/processors/${pid}" "$tmp"
    _REV_VERSION=$(jq -r '.revision.version  // 0'         "$tmp" 2>/dev/null)
    _REV_CLIENT=$(jq  -r '.revision.clientId // "shell"'   "$tmp" 2>/dev/null)
    _CURRENT_STATE=$(jq -r '.component.state // "STOPPED"' "$tmp" 2>/dev/null)
    [ "$_REV_CLIENT" = "null" ] && _REV_CLIENT="shell"
}

# ============================================================
# Run-status helper — sets _HTTP and _HTTP_ERR
# ============================================================
set_processor_state() {
    local pid="$1" state="$2" ver="$3" cid="$4"
    local payload tmp_resp="${TMPDIR_WORK}/state_${pid}_$(date +%s%N).json"
    payload=$(jq -n \
        --arg  st  "$state" \
        --argjson v  "$ver" \
        --arg  cid "$cid" \
        '{revision:{version:$v,clientId:$cid},state:$st}')

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

# ============================================================
# Recursive processor discovery
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
        local short_t
        short_t=$(echo "$type" | awk -F'.' '{print $NF}')
        if [[ "$short_t" == "ConnectorGroupRouter" || "$short_t" == "ConnectorRouter" ]]; then
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

    while IFS='|' read -r child_id child_name; do
        [ -z "$child_id" ] && continue
        collect_matching_processors "$child_id" "${pg_path} > ${child_name}"
    done < <(jq -r '
        .processGroupFlow.flow.processGroups[]?
        | [.id, .component.name]
        | join("|")' "$tmp_pg" 2>/dev/null)
}

# ============================================================
# Step 1: Discover processors
# ============================================================
echo -e "${CYAN}${BOLD}Step 1/2:${NC} Discovering ConnectorGroupRouter / ConnectorRouter processors...\n"

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
# ---- End dedup ----------------------------------------------

if [ ${#PROC_IDS[@]} -eq 0 ]; then
    echo -e "${YELLOW}⚠ No ConnectorGroupRouter or ConnectorRouter processors found.${NC}"; exit 0
fi
echo -e "${GREEN}✓${NC} Found ${BOLD}${#PROC_IDS[@]}${NC} matching processor(s)\n"

# ============================================================
# Step 2: Show available processors
# ============================================================
echo -e "${CYAN}${BOLD}Step 2/2:${NC} Select processors to Purge & Sync\n"

echo -e "${BOLD}${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${MAGENTA}║              Purge & Sync Execution                          ║${NC}"
echo -e "${BOLD}${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}\n"

echo -e "  ${YELLOW}⚠  Selected processors will be:${NC}"
echo -e "     ${CYAN}1.${NC} Stopped        (if currently RUNNING)"
echo -e "     ${CYAN}2.${NC} Triggered      RUN_ONCE  (Purge & Sync)"
echo -e "     ${CYAN}3.${NC} Restored       to their original state\n"

echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║            Available Processors for Purge & Sync             ║${NC}"
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
    echo -e "     ${CYAN}├─${NC} ${DIM}Location:${NC} ${MAGENTA}${PROC_PATHS[$i]}${NC}"
    echo -e "     ${CYAN}└─${NC} ${DIM}ID:${NC}       ${GRAY}${PROC_IDS[$i]}${NC}"

    TMP_CG="${TMPDIR_WORK}/cg_${PROC_IDS[$i]}.json"
    nifi_get_file "${NIFI_URL}/nifi-api/processors/${PROC_IDS[$i]}" "$TMP_CG"
    CG_VALS=$(jq -r '.component.config.properties | to_entries[]
        | select(.key | contains("ConnectorGroup"))
        | "\(.key) = \(.value // "null")"' "$TMP_CG" 2>/dev/null)
    if [ -n "$CG_VALS" ]; then
        while IFS= read -r line; do
            echo -e "        ${DIM}${CYAN}·${NC} ${DIM}${line}${NC}"
        done <<< "$CG_VALS"
    fi
    echo ""
done

echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}\n"

# ============================================================
# Selection — interactive (re-prompts on bad input)
#             or non-interactive (--select / -s flag)
# ============================================================
declare -a SELECTED_INDICES

# ---- Helper: parse and validate a selection string ----------
# Sets SELECTED_INDICES; returns 1 on invalid input
parse_selection() {
    local raw="$1"
    SELECTED_INDICES=()

    if [[ "${raw,,}" == "none" ]]; then
        return 0   # caller checks length == 0 → exit
    elif [[ "${raw,,}" == "all" ]]; then
        for i in "${!PROC_IDS[@]}"; do SELECTED_INDICES+=("$i"); done
        return 0
    else
        for tok in $raw; do
            if ! [[ "$tok" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}✗ '${tok}' is not valid — enter numbers, 'all', or 'none'.${NC}"
                return 1
            fi
            local idx=$(( tok - 1 ))
            if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#PROC_IDS[@]}" ]; then
                echo -e "${RED}✗ ${tok} is out of range (1–${#PROC_IDS[@]}).${NC}"
                return 1
            fi
            SELECTED_INDICES+=("$idx")
        done
        return 0
    fi
}

# ---- Non-interactive path -----------------------------------
if [ -n "$NON_INTERACTIVE_SEL" ]; then
    echo -e "${CYAN}ℹ${NC}  Non-interactive mode — selection: ${BOLD}${NON_INTERACTIVE_SEL}${NC}\n"
    if ! parse_selection "$NON_INTERACTIVE_SEL"; then
        echo -e "${RED}✗ Invalid --select value: '${NON_INTERACTIVE_SEL}'${NC}"
        echo -e "  Valid values: ${WHITE}all${NC} | ${WHITE}none${NC} | space-separated processor numbers  e.g. ${WHITE}\"1 3\"${NC}"
        exit 1
    fi
    if [ "${#SELECTED_INDICES[@]}" -eq 0 ]; then
        echo -e "${YELLOW}⚠${NC} Selection is 'none' — Purge & Sync cancelled.\n"; exit 0
    fi

# ---- Interactive path (re-prompts on bad input) -------------
else
    echo -e "  Enter the processor number(s) to Purge & Sync."
    echo -e "  ${GRAY}Examples:${NC}  ${WHITE}1${NC}        → only processor 1"
    echo -e "             ${WHITE}1 3 5${NC}    → processors 1, 3 and 5"
    echo -e "             ${WHITE}all${NC}      → all processors"
    echo -e "             ${WHITE}none${NC}     → cancel\n"

    while true; do
        read -p "$(echo -e "${WHITE}Selection ${GRAY}[number(s)/all/none]${NC}: ")" _RAW_SEL
        _RAW_SEL="${_RAW_SEL:-none}"

        if [[ "${_RAW_SEL,,}" == "none" ]]; then
            echo -e "\n${YELLOW}⚠${NC} Purge & Sync cancelled.\n"; exit 0
        fi

        if parse_selection "$_RAW_SEL"; then
            break
        fi
        # parse_selection already printed the error; loop again
    done

    if [ "${#SELECTED_INDICES[@]}" -eq 0 ]; then
        echo -e "\n${YELLOW}⚠${NC} No processors selected. Exiting.\n"; exit 0
    fi
fi

# ============================================================
# Execute Purge & Sync
# ============================================================
echo -e "\n${YELLOW}⟳${NC} Starting Purge & Sync on ${BOLD}${#SELECTED_INDICES[@]}${NC} processor(s)...\n"

PS_SUCCESS=0
PS_FAILED=0

for i in "${SELECTED_INDICES[@]}"; do
    PID="${PROC_IDS[$i]}"
    PNAME="${PROC_NAMES[$i]}"
    SHORT_TYPE=$(echo "${PROC_TYPES[$i]}" | awk -F'.' '{print $NF}')

    echo -e "${BOLD}${CYAN}▶${NC} ${WHITE}${PNAME}${NC}  ${GRAY}[${SHORT_TYPE}]${NC}"
    echo -e "  ${GRAY}ID: ${PID}${NC}"

    # -- Fetch current revision & state
    fetch_revision "$PID"
    ORIG_STATE="$_CURRENT_STATE"
    REV="$_REV_VERSION"
    CID="$_REV_CLIENT"
    echo -e "  ${DIM}Revision: ${REV}  |  State: ${ORIG_STATE}${NC}"

    # -- Step 1: Stop if RUNNING
    if [ "$ORIG_STATE" = "RUNNING" ]; then
        echo -e "  ${YELLOW}⟳${NC} Stopping processor..."
        set_processor_state "$PID" "STOPPED" "$REV" "$CID"
        if [ "$_HTTP" != "200" ]; then
            echo -e "  ${RED}✗ Failed to stop (HTTP ${_HTTP}) — skipping.${NC}"
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

    # -- Step 2: RUN_ONCE (Purge & Sync)
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
        echo -e "  ${YELLOW}⟳${NC} Restoring to RUNNING..."
        set_processor_state "$PID" "RUNNING" "$REV" "$CID"
        if [ "$_HTTP" != "200" ]; then
            echo -e "  ${YELLOW}⚠${NC} Could not restore to RUNNING (HTTP ${_HTTP}). Manual check needed."
            [ -n "$_HTTP_ERR" ] && echo -e "  ${YELLOW}  API: ${_HTTP_ERR}${NC}"
        else
            echo -e "  ${GREEN}✓${NC} Restored to RUNNING"
        fi
    fi

    echo -e "  ${GREEN}${BOLD}✓ Purge & Sync complete${NC}\n"
    PS_SUCCESS=$((PS_SUCCESS + 1))
done

# ============================================================
# Summary
# ============================================================
echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║                  Purge & Sync Summary                        ║${NC}"
echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}"
echo -e "  ${WHITE}Processors attempted:${NC}  ${BOLD}${#SELECTED_INDICES[@]}${NC}"
echo -e "  ${GREEN}✓ Succeeded:${NC}           ${BOLD}${PS_SUCCESS}${NC}"
if [ "$PS_FAILED" -gt 0 ]; then
    echo -e "  ${RED}✗ Failed:${NC}              ${BOLD}${PS_FAILED}${NC}"
fi
echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}\n"

exit 0