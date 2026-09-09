#!/bin/bash

# Color codes for better readability
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
CYAN='\033[0;36m'

# Function to display usage
usage() {
    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════════════════════╗"
    echo "║                      NiFi Controller Services Manager                                ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    
    echo -e "${BOLD}${CYAN}SYNOPSIS${NC}"
    echo -e "  $0 [OPTIONS]"
    echo -e "\n"
    
    echo -e "${BOLD}${CYAN}DESCRIPTION${NC}"
    echo -e "  Lists, enables, disables, or updates controller services in Apache NiFi."
    echo -e "  RECURSIVELY searches all process groups at all nesting levels."
    echo -e "  Supports both interactive selection and batch operations.\n"
    
    echo -e "${BOLD}${CYAN}OPTIONS${NC}"
    echo -e "  --help, -h                        Display this help message and exit"
    echo -e "  --url, -u URL                     NiFi URL (default: https://idol-docker-host:8443)"
    echo -e "  --auth, -a METHOD                 Authentication method: ${WHITE}password${NC}|${WHITE}token${NC}|${WHITE}none${NC}"
    echo -e "  --username, -U USER               Username for password authentication (default: admin)"
    echo -e "  --password, -P PASS               Password for password authentication (default: OpenText2026!)"
    echo -e "  --token, -t TOKEN                 Bearer token for token authentication"
    echo -e "\n"
    
    echo -e "${BOLD}${CYAN}LISTING OPTIONS${NC}"
    echo -e "  --list, -l                        List all controller services and exit"
    echo -e "  --output, -o FORMAT               Output format for list: ${WHITE}table${NC}|${WHITE}json${NC}|${WHITE}csv${NC} (default: table)"
    echo -e "\n"
    
    echo -e "${BOLD}${CYAN}BATCH OPERATION OPTIONS${NC}"
    echo -e "  --enable, -e                      Enable controller services in batch mode"
    echo -e "  --disable, -d                     Disable controller services in batch mode"
    echo -e "  --update-properties, -p           Update controller service properties in batch mode"
    echo -e "  --service, -s ID/NUM              Specific service ID or number to operate on"
    echo -e "  --file, -f FILE                   File containing service IDs or numbers (one per line)"
    echo -e "  --all                             Apply operation to ALL controller services"
    echo -e "  --yes, -y                         Skip confirmation prompts in batch mode"
    echo -e "\n"
    
    echo -e "${BOLD}${CYAN}PROPERTY UPDATE OPTIONS${NC}"
    echo -e "  --property KEY=VALUE              Set a specific property (can be used multiple times)"
    echo -e "  --properties-file FILE            JSON file containing properties to update"
    echo -e "  --properties-json JSON            JSON string containing properties to update"
    echo -e "\n"
    
    echo -e "${BOLD}${CYAN}FILTERING OPTIONS${NC}"
    echo -e "  --filter-state STATE              Filter services by state: ${WHITE}ENABLED${NC}|${WHITE}DISABLED${NC}|${WHITE}ENABLING${NC}|${WHITE}DISABLING${NC}"
    echo -e "  --filter-name PATTERN             Filter services by name (case-insensitive regex)"
    echo -e "  --filter-type PATTERN             Filter services by type (case-insensitive regex)"
    echo -e "  --filter-location PATTERN         Filter services by location/path (case-insensitive regex)"
    echo -e "\n"
    
    echo -e "${BOLD}${CYAN}USAGE MODES${NC}\n"
    
    echo -e "${BOLD}${YELLOW}1. Interactive Mode${NC}"
    echo -e "  Prompts you to enter configuration and choose actions:\n"
    echo -e "  ${GRAY}\$ $0${NC}\n"
    
    echo -e "${BOLD}${YELLOW}2. List Controller Services${NC}"
    echo -e "  List all controller services from ALL process groups:\n"
    echo -e "  ${GRAY}\$ $0 -l${NC}"
    echo -e "  ${GRAY}\$ $0 -l -o json${NC}"
    echo -e "  ${GRAY}\$ $0 -l --filter-state DISABLED${NC}"
    echo -e "  ${GRAY}\$ $0 -l --filter-name 'database'${NC}\n"
    
    echo -e "${BOLD}${YELLOW}3. Batch Enable/Disable${NC}"
    echo -e "  Enable or disable services in batch:\n"
    echo -e "  ${GRAY}\$ $0 -e --all -y${NC}                    # Enable all services"
    echo -e "  ${GRAY}\$ $0 -d --all -y${NC}                    # Disable all services"
    echo -e "  ${GRAY}\$ $0 -e -s 3${NC}                        # Enable service #3"
    echo -e "  ${GRAY}\$ $0 -d -f services.txt${NC}             # Disable services from file"
    echo -e "  ${GRAY}\$ $0 -e --filter-state DISABLED -y${NC}  # Enable all disabled services\n"
    
    echo -e "${BOLD}${YELLOW}4. Batch Update Properties${NC}"
    echo -e "  Update service properties in batch:\n"
    echo -e "  ${GRAY}\$ $0 -p -s 3 --property 'db.url=jdbc:mysql://localhost/db'${NC}"
    echo -e "  ${GRAY}\$ $0 -p -f services.txt --properties-file props.json${NC}"
    echo -e "  ${GRAY}\$ $0 -p --all --property 'timeout=30'${NC}\n"
    
    echo -e "${BOLD}${CYAN}CONFIGURATION${NC}\n"
    echo -e "  Default NiFi connection settings:\n"
    echo -e "  ${CYAN}NIFI_URL${NC}      = https://idol-docker-host:8443"
    echo -e "  ${CYAN}USERNAME${NC}      = admin"
    echo -e "  ${CYAN}PASSWORD${NC}      = OpenText2026!\n"
    
    echo -e "${BOLD}${CYAN}EXAMPLES${NC}\n"
    echo -e "  ${GRAY}# List all disabled services as JSON${NC}"
    echo -e "  $0 -l --filter-state DISABLED -o json\n"
    echo -e "  ${GRAY}# Enable all disabled database-related services${NC}"
    echo -e "  $0 -e --filter-state DISABLED --filter-name 'database' -y\n"
    echo -e "  ${GRAY}# Update connection pool properties for all matching services${NC}"
    echo -e "  $0 -p --filter-type 'DBCPConnectionPool' --property 'Max Total Connections=50' -y\n"
    echo -e "  ${GRAY}# Disable specific services from a file${NC}"
    echo -e "  $0 -d -f disabled_services.txt -y\n"
    
    echo -e "${BOLD}${CYAN}REQUIREMENTS${NC}\n"
    echo -e "  - ${WHITE}curl${NC} (required)"
    echo -e "  - ${WHITE}jq${NC} (required for JSON parsing)\n"
    
    exit 1
}

# Check for help flag IMMEDIATELY - FIRST LINE OF CODE
case "$1" in
    --help|-h)
        usage
        ;;
esac

# Default values
NIFI_URL=""
AUTH_METHOD=""
USERNAME=""
PASSWORD=""
TOKEN=""
INTERACTIVE=true
LIST_ONLY=false
OUTPUT_FORMAT="table"
BATCH_ENABLE=false
BATCH_DISABLE=false
BATCH_UPDATE=false
SERVICE_ID=""
SERVICE_FILE=""
SKIP_CONFIRM=false
APPLY_TO_ALL=false

# Filter options
FILTER_STATE=""
FILTER_NAME=""
FILTER_TYPE=""
FILTER_LOCATION=""

# Property update options
declare -a PROPERTIES
PROPERTIES_FILE=""
PROPERTIES_JSON=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        # Connection options
        -u|--url)
            NIFI_URL="$2"
            INTERACTIVE=false
            shift 2
            ;;
        -a|--auth)
            AUTH_METHOD="$2"
            shift 2
            ;;
        -U|--username)
            USERNAME="$2"
            shift 2
            ;;
        -P|--password)
            PASSWORD="$2"
            shift 2
            ;;
        -t|--token)
            TOKEN="$2"
            shift 2
            ;;
            
        # Listing options
        -l|--list)
            LIST_ONLY=true
            INTERACTIVE=false
            shift
            ;;
        -o|--output)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
            
        # Batch operation options
        -e|--enable)
            BATCH_ENABLE=true
            INTERACTIVE=false
            shift
            ;;
        -d|--disable)
            BATCH_DISABLE=true
            INTERACTIVE=false
            shift
            ;;
        -p|--update-properties)
            BATCH_UPDATE=true
            INTERACTIVE=false
            shift
            ;;
        -s|--service)
            SERVICE_ID="$2"
            shift 2
            ;;
        -f|--file)
            SERVICE_FILE="$2"
            shift 2
            ;;
        --all)
            APPLY_TO_ALL=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRM=true
            shift
            ;;
            
        # Property update options
        --property)
            PROPERTIES+=("$2")
            shift 2
            ;;
        --properties-file)
            PROPERTIES_FILE="$2"
            shift 2
            ;;
        --properties-json)
            PROPERTIES_JSON="$2"
            shift 2
            ;;
            
        # Filter options
        --filter-state)
            FILTER_STATE="$2"
            shift 2
            ;;
        --filter-name)
            FILTER_NAME="$2"
            shift 2
            ;;
        --filter-type)
            FILTER_TYPE="$2"
            shift 2
            ;;
        --filter-location)
            FILTER_LOCATION="$2"
            shift 2
            ;;
            
        -h|--help)
            usage
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo -e "${RED}✗ Error:${NC} Unknown option: $1"
            usage
            ;;
        *)
            echo -e "${RED}✗ Error:${NC} Unexpected argument: $1"
            usage
            ;;
    esac
done

# CHECK 1: Prevent execution without any operation specified
if [ "$LIST_ONLY" = false ] && [ "$BATCH_ENABLE" = false ] && [ "$BATCH_DISABLE" = false ] && \
   [ "$BATCH_UPDATE" = false ] && [ -z "$SERVICE_ID" ] && [ -z "$SERVICE_FILE" ] && \
   [ "$APPLY_TO_ALL" = false ]; then
    # If no options specified, we'll run in interactive mode
    INTERACTIVE=true
fi

# Validate output format
if [ "$OUTPUT_FORMAT" != "table" ] && [ "$OUTPUT_FORMAT" != "json" ] && [ "$OUTPUT_FORMAT" != "csv" ]; then
    echo -e "${RED}✗ Error:${NC} Invalid output format: ${OUTPUT_FORMAT}"
    echo -e "Valid options: ${WHITE}table${NC}, ${WHITE}json${NC}, ${WHITE}csv${NC}"
    exit 1
fi

# Validate mode combinations
mode_count=0
[ "$BATCH_ENABLE" = true ] && ((mode_count++))
[ "$BATCH_DISABLE" = true ] && ((mode_count++))
[ "$BATCH_UPDATE" = true ] && ((mode_count++))

if [ $mode_count -gt 1 ]; then
    echo -e "${RED}✗ Error:${NC} Cannot use multiple operation modes together (--enable, --disable, --update-properties)"
    exit 1
fi

# Validate filter-state value
if [ -n "$FILTER_STATE" ]; then
    case "$FILTER_STATE" in
        ENABLED|DISABLED|ENABLING|DISABLING) ;;
        *)
            echo -e "${RED}✗ Error:${NC} Invalid filter-state: ${FILTER_STATE}"
            echo -e "Valid options: ${WHITE}ENABLED${NC}, ${WHITE}DISABLED${NC}, ${WHITE}ENABLING${NC}, ${WHITE}DISABLING${NC}"
            exit 1
            ;;
    esac
fi

# Determine operation mode
if [ "$LIST_ONLY" = true ]; then
    OPERATION_MODE="list"
elif [ "$BATCH_ENABLE" = true ]; then
    OPERATION_MODE="enable"
elif [ "$BATCH_DISABLE" = true ]; then
    OPERATION_MODE="disable"
elif [ "$BATCH_UPDATE" = true ]; then
    OPERATION_MODE="update"
else
    OPERATION_MODE="interactive"
fi

# Display operation banner (suppress for JSON/CSV list mode)
if [ "$OPERATION_MODE" = "list" ] && [ "$OUTPUT_FORMAT" != "table" ]; then
    : # No banner for JSON/CSV output
else
    case "$OPERATION_MODE" in
        enable)
            echo -e "${BOLD}${GREEN}"
            echo "╔════════════════════════════════════════════════════════╗"
            echo "║         ENABLE Controller Services Mode                ║"
            echo "╚════════════════════════════════════════════════════════╝"
            echo -e "${NC}\n"
            ;;
        disable)
            echo -e "${BOLD}${RED}"
            echo "╔════════════════════════════════════════════════════════╗"
            echo "║         DISABLE Controller Services Mode               ║"
            echo "╚════════════════════════════════════════════════════════╝"
            echo -e "${NC}\n"
            ;;
        update)
            echo -e "${BOLD}${YELLOW}"
            echo "╔════════════════════════════════════════════════════════╗"
            echo "║         UPDATE Properties Mode                         ║"
            echo "╚════════════════════════════════════════════════════════╝"
            echo -e "${NC}\n"
            ;;
        list)
            echo -e "${BOLD}${BLUE}"
            echo "╔════════════════════════════════════════════════════════╗"
            echo "║         LIST Controller Services Mode                  ║"
            echo "║            (Recursive - All Process Groups)            ║"
            echo "╚════════════════════════════════════════════════════════╝"
            echo -e "${NC}\n"
            ;;
        interactive)
            echo -e "${BOLD}${CYAN}"
            echo "╔════════════════════════════════════════════════════════╗"
            echo "║         INTERACTIVE NiFi Services Manager              ║"
            echo "║                (Controller Services)                   ║"
            echo "╚════════════════════════════════════════════════════════╝"
            echo -e "${NC}\n"
            ;;
    esac
fi

# Interactive mode if no URL provided and not in batch modes
if [ "$INTERACTIVE" = true ] && [ "$OPERATION_MODE" = "interactive" ]; then
    echo -e "${CYAN}${BOLD}Configuration:${NC}"
    read -p "$(echo -e "${WHITE}Enter NiFi URL ${GRAY}[default: https://idol-docker-host:8443]${NC}: ")" NIFI_URL
    NIFI_URL=${NIFI_URL:-https://idol-docker-host:8443}
else
    # Set default URL if not provided
    NIFI_URL=${NIFI_URL:-https://idol-docker-host:8443}
fi

# Only show URL message if not in list-only mode with json/csv output
if [[ "$OPERATION_MODE" == "list" ]] && [ "$OUTPUT_FORMAT" != "table" ]; then
    : # Suppress for JSON/CSV
else
    echo -e "${GREEN}✓${NC} Using NiFi URL: ${BLUE}${NIFI_URL}${NC}\n"
fi

# Handle authentication based on method or interactive mode
if [ "$OPERATION_MODE" != "interactive" ] || [ -n "$OPERATION_MODE" ]; then
    if [ "$INTERACTIVE" = true ] && [ -z "$AUTH_METHOD" ] && [ "$OPERATION_MODE" != "list" ]; then
        # Interactive authentication selection
        echo -e "${CYAN}${BOLD}Authentication Method:${NC}"
        echo -e "  ${YELLOW}1)${NC} Generate token using username/password"
        echo -e "  ${YELLOW}2)${NC} Provide existing token"
        read -p "$(echo -e "${WHITE}Enter choice ${GRAY}[1-2, default: 1]${NC}: ")" AUTH_CHOICE
        echo
        case $AUTH_CHOICE in
            2)
                AUTH_METHOD="token"
                ;;
            *)
                AUTH_METHOD="password"
                ;;
        esac
    fi

    # Validate auth method
    if [ -n "$AUTH_METHOD" ] && [ "$AUTH_METHOD" != "password" ] && [ "$AUTH_METHOD" != "token" ] && [ "$AUTH_METHOD" != "none" ]; then
        echo -e "${RED}✗ Error:${NC} Invalid authentication method: ${AUTH_METHOD}"
        echo -e "Valid options: ${WHITE}password${NC}, ${WHITE}token${NC}, ${WHITE}none${NC}"
        exit 1
    fi

    # Determine if we should show auth messages
    SHOW_AUTH_MESSAGES=true
    if [[ "$OPERATION_MODE" == "list" ]] && [ "$OUTPUT_FORMAT" != "table" ]; then
        SHOW_AUTH_MESSAGES=false
    fi

    # Process authentication
    case $AUTH_METHOD in
        password)
            if [ "$INTERACTIVE" = true ] && [ "$OPERATION_MODE" != "list" ]; then
                echo -e "\n${CYAN}${BOLD}Credentials:${NC}"
                read -p "$(echo -e "${WHITE}Enter username ${GRAY}[default: admin]${NC}: ")" USERNAME
                USERNAME=${USERNAME:-admin}
                
                read -sp "$(echo -e "${WHITE}Enter password ${GRAY}[default: OpenText2026!]${NC}: ")" PASSWORD
                echo ""
                PASSWORD=${PASSWORD:-OpenText2026!}
            else
                # Set defaults for command-line mode
                USERNAME=${USERNAME:-admin}
                PASSWORD=${PASSWORD:-OpenText2026!}
            fi
            
            if [ "$SHOW_AUTH_MESSAGES" = true ]; then
                echo -e "\n${YELLOW}⟳${NC} Generating authentication token..."
            fi
            
            TOKEN=$(curl -k -s -X POST "${NIFI_URL}/nifi-api/access/token" \
              -H "Content-Type: application/x-www-form-urlencoded" \
              -d "username=${USERNAME}&password=${PASSWORD}")
            
            TOKEN=$(echo "$TOKEN" | tr -d '\n')
            
            if [ -z "$TOKEN" ] || [[ "$TOKEN" == *"Unable to generate access token"* ]]; then
                echo -e "${RED}✗ Error:${NC} Failed to generate token. Please check your credentials."
                exit 1
            fi
            
            if [ "$SHOW_AUTH_MESSAGES" = true ]; then
                echo -e "${GREEN}✓${NC} Token generated successfully!"
            fi
            ;;
            
        token)
            if [ "$INTERACTIVE" = true ] && [ "$OPERATION_MODE" != "list" ] && [ -z "$TOKEN" ]; then
                echo -e "\n${CYAN}${BOLD}Token:${NC}"
                read -p "$(echo -e "${WHITE}Enter Authorization Token${NC}: ")" TOKEN
            fi
            
            if [ -z "$TOKEN" ]; then
                echo -e "${RED}✗ Error:${NC} Token cannot be empty!"
                exit 1
            fi
            
            if [ "$SHOW_AUTH_MESSAGES" = true ]; then
                echo -e "${GREEN}✓${NC} Token accepted"
            fi
            ;;
            
        none)
            if [ "$SHOW_AUTH_MESSAGES" = true ]; then
                echo -e "\n${YELLOW}⚠${NC} Proceeding without authentication..."
            fi
            TOKEN=""
            ;;
            
        *)
            # If no auth method specified but we have a token, assume token auth
            if [ -n "$TOKEN" ]; then
                if [ "$SHOW_AUTH_MESSAGES" = true ]; then
                    echo -e "${GREEN}✓${NC} Using provided token"
                fi
            else
                # For ALL modes including list, use password auth by default
                USERNAME=${USERNAME:-admin}
                PASSWORD=${PASSWORD:-OpenText2026!}
                
                if [ "$SHOW_AUTH_MESSAGES" = true ]; then
                    echo -e "${YELLOW}⟳${NC} Generating authentication token..."
                fi
                
                TOKEN=$(curl -k -s -X POST "${NIFI_URL}/nifi-api/access/token" \
                  -H "Content-Type: application/x-www-form-urlencoded" \
                  -d "username=${USERNAME}&password=${PASSWORD}")
                
                TOKEN=$(echo "$TOKEN" | tr -d '\n')
                
                if [ -z "$TOKEN" ] || [[ "$TOKEN" == *"Unable to generate access token"* ]]; then
                    echo -e "${RED}✗ Error:${NC} Failed to generate token."
                    exit 1
                fi
                
                if [ "$SHOW_AUTH_MESSAGES" = true ]; then
                    echo -e "${GREEN}✓${NC} Token generated"
                fi
            fi
            ;;
    esac
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo -e "\n${YELLOW}⚠ Warning:${NC} ${BOLD}jq${NC} is not installed. JSON operations will be limited."
    echo -e "${YELLOW}Install with:${NC}"
    echo -e "  • Ubuntu/Debian: ${CYAN}sudo apt-get install jq${NC}"
    echo -e "  • macOS: ${CYAN}brew install jq${NC}"
    echo ""
    if [ "$OPERATION_MODE" != "interactive" ] || [ "$OUTPUT_FORMAT" = "json" ]; then
        echo -e "${RED}✗ Error:${NC} jq is required for this operation."
        exit 1
    fi
fi

# Arrays to store process groups and controller services
declare -a PG_IDS
declare -a PG_NAMES
declare -a PG_PATHS
declare -a CS_IDS
declare -a CS_NAMES
declare -a CS_STATES
declare -a CS_PG_IDS
declare -a CS_PG_NAMES
declare -a CS_TYPES

# Function to recursively list all process groups
list_process_groups_recursive() {
    local parent_id=$1
    local parent_path=${2:-"NiFi Flow"}
    
    local url="${NIFI_URL}/nifi-api/flow/process-groups/${parent_id}"
    
    local response
    if [ -n "$TOKEN" ]; then
        response=$(curl -k -f -s -X GET "${url}" \
          -H "Accept: application/json" \
          -H "Authorization: Bearer ${TOKEN}")
    else
        response=$(curl -k -f -s -X GET "${url}" \
          -H "Accept: application/json")
    fi
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Error:${NC} Failed to connect to NiFi API at ${url}"
        return 1
    fi
    
    local error_message=$(echo "${response}" | jq -r '.error // empty' 2>/dev/null)
    if [ -n "$error_message" ]; then
        echo -e "${RED}✗ Error:${NC} ${error_message}"
        return 1
    fi
    
    local pg_id=$(echo "${response}" | jq -r '.processGroupFlow.id // empty' 2>/dev/null)
    local pg_name=$(echo "${response}" | jq -r '.processGroupFlow.breadcrumb.breadcrumb.name // "NiFi Flow"' 2>/dev/null)
    
    if [ -z "$pg_id" ] || [ "$pg_id" = "null" ]; then
        return 1
    fi
    
    PG_IDS+=("$pg_id")
    PG_NAMES+=("$pg_name")
    PG_PATHS+=("$parent_path")
    
    local child_groups=$(echo "${response}" | jq -r '.processGroupFlow.flow.processGroups[]? | "\(.id)|\(.component.name)"' 2>/dev/null)
    
    if [ -n "$child_groups" ]; then
        while IFS='|' read -r child_id child_name; do
            [ -z "$child_id" ] && continue
            list_process_groups_recursive "$child_id" "${parent_path} > ${child_name}"
        done <<< "$child_groups"
    fi
    
    return 0
}

# Function to collect controller services from a specific process group
collect_controller_services_from_pg() {
    local pg_id=$1
    local pg_path=$2
    
    local url="${NIFI_URL}/nifi-api/flow/process-groups/${pg_id}/controller-services"
    
    local response
    if [ -n "$TOKEN" ]; then
        response=$(curl -k -f -s -X GET "${url}" \
          -H "Accept: application/json" \
          -H "Authorization: Bearer ${TOKEN}")
    else
        response=$(curl -k -f -s -X GET "${url}" \
          -H "Accept: application/json")
    fi
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Error:${NC} Failed to fetch controller services from ${url}"
        return 1
    fi
    
    local error_message=$(echo "${response}" | jq -r '.error // empty' 2>/dev/null)
    if [ -n "$error_message" ]; then
        echo -e "${RED}✗ Error:${NC} ${error_message}"
        return 1
    fi
    
    local services=$(echo "${response}" | jq -r '.controllerServices[]? | "\(.id)|\(.component.name)|\(.component.state)|\(.component.type)"' 2>/dev/null)
    
    if [ -n "$services" ]; then
        while IFS='|' read -r cs_id cs_name cs_state cs_type; do
            [ -z "$cs_id" ] && continue
            CS_IDS+=("$cs_id")
            CS_NAMES+=("$cs_name")
            CS_STATES+=("$cs_state")
            CS_PG_IDS+=("$pg_id")
            CS_PG_NAMES+=("$pg_path")
            CS_TYPES+=("$cs_type")
        done <<< "$services"
    fi
}

# Function to apply filters to collected services
apply_filters() {
    if [ -z "$FILTER_STATE" ] && [ -z "$FILTER_NAME" ] && [ -z "$FILTER_TYPE" ] && [ -z "$FILTER_LOCATION" ]; then
        return 0  # No filters to apply
    fi
    
    declare -a FILTERED_CS_IDS
    declare -a FILTERED_CS_NAMES
    declare -a FILTERED_CS_STATES
    declare -a FILTERED_CS_PG_IDS
    declare -a FILTERED_CS_PG_NAMES
    declare -a FILTERED_CS_TYPES
    
    for i in "${!CS_IDS[@]}"; do
        local include=true
        
        # Apply state filter
        if [ -n "$FILTER_STATE" ] && [ "${CS_STATES[$i]}" != "$FILTER_STATE" ]; then
            include=false
        fi
        
        # Apply name filter (case-insensitive regex)
        if [ -n "$FILTER_NAME" ]; then
            if ! echo "${CS_NAMES[$i]}" | grep -iq "$FILTER_NAME"; then
                include=false
            fi
        fi
        
        # Apply type filter (case-insensitive regex)
        if [ -n "$FILTER_TYPE" ]; then
            if ! echo "${CS_TYPES[$i]}" | grep -iq "$FILTER_TYPE"; then
                include=false
            fi
        fi
        
        # Apply location filter (case-insensitive regex)
        if [ -n "$FILTER_LOCATION" ]; then
            if ! echo "${CS_PG_NAMES[$i]}" | grep -iq "$FILTER_LOCATION"; then
                include=false
            fi
        fi
        
        if [ "$include" = true ]; then
            FILTERED_CS_IDS+=("${CS_IDS[$i]}")
            FILTERED_CS_NAMES+=("${CS_NAMES[$i]}")
            FILTERED_CS_STATES+=("${CS_STATES[$i]}")
            FILTERED_CS_PG_IDS+=("${CS_PG_IDS[$i]}")
            FILTERED_CS_PG_NAMES+=("${CS_PG_NAMES[$i]}")
            FILTERED_CS_TYPES+=("${CS_TYPES[$i]}")
        fi
    done
    
    # Replace arrays with filtered results
    CS_IDS=("${FILTERED_CS_IDS[@]}")
    CS_NAMES=("${FILTERED_CS_NAMES[@]}")
    CS_STATES=("${FILTERED_CS_STATES[@]}")
    CS_PG_IDS=("${FILTERED_CS_PG_IDS[@]}")
    CS_PG_NAMES=("${FILTERED_CS_PG_NAMES[@]}")
    CS_TYPES=("${FILTERED_CS_TYPES[@]}")
}

# Function to output controller services in different formats
output_controller_services() {
    local format=$1
    
    case $format in
        json)
            printf '['
            local first=true
            for i in "${!CS_IDS[@]}"; do
                if [ "$first" = false ]; then printf ','; fi
                first=false
                local esc_id=$(echo "${CS_IDS[$i]}" | jq -Rs .)
                local esc_name=$(echo "${CS_NAMES[$i]}" | jq -Rs .)
                local esc_state=$(echo "${CS_STATES[$i]}" | jq -Rs .)
                local esc_type=$(echo "${CS_TYPES[$i]}" | jq -Rs .)
                local esc_location=$(echo "${CS_PG_NAMES[$i]}" | jq -Rs .)
                printf '{\n    "id": %s,\n    "name": %s,\n    "state": %s,\n    "type": %s,\n    "location": %s\n  }' \
                    "$esc_id" "$esc_name" "$esc_state" "$esc_type" "$esc_location"
            done
            printf ']\n'
            ;;
            
        csv)
            echo "ID,Name,State,Type,Location"
            for i in "${!CS_IDS[@]}"; do
                local id="${CS_IDS[$i]}"
                local esc_name=$(echo "${CS_NAMES[$i]}" | sed 's/"/""/g')
                local esc_state=$(echo "${CS_STATES[$i]}" | sed 's/"/""/g')
                local esc_type=$(echo "${CS_TYPES[$i]}" | sed 's/"/""/g')
                local esc_location=$(echo "${CS_PG_NAMES[$i]}" | sed 's/"/""/g')
                echo "\"${id}\",\"${esc_name}\",\"${esc_state}\",\"${esc_type}\",\"${esc_location}\""
            done
            ;;
            
        table)
            echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${BOLD}${CYAN}║                      Available Controller Services                             ║${NC}"
            echo -e "${BOLD}${CYAN}║                    (From All Process Groups)                                   ║${NC}"
            echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════════════════════════╝${NC}\n"
            
            local displayed_count=0
            for i in "${!CS_IDS[@]}"; do
                ((displayed_count++))
                local state_color="${RED}"
                local state_icon="○"
                if [ "${CS_STATES[$i]}" = "ENABLED" ]; then
                    state_color="${GREEN}"
                    state_icon="●"
                elif [ "${CS_STATES[$i]}" = "ENABLING" ]; then
                    state_color="${YELLOW}"
                    state_icon="◐"
                elif [ "${CS_STATES[$i]}" = "DISABLING" ]; then
                    state_color="${YELLOW}"
                    state_icon="◑"
                fi
                
                echo -e "${YELLOW}${BOLD}$((i+1)).${NC} ${WHITE}${CS_NAMES[$i]}${NC} ${state_color}${state_icon} [${CS_STATES[$i]}]${NC}"
                echo -e "   ${CYAN}├─${NC} ${GRAY}Type:${NC} ${CS_TYPES[$i]}"
                echo -e "   ${CYAN}├─${NC} ${GRAY}Location:${NC} ${CS_PG_NAMES[$i]}"
                echo -e "   ${CYAN}└─${NC} ${GRAY}ID:${NC} ${CS_IDS[$i]}"
                echo ""
            done
            
            if [ $displayed_count -eq 0 ]; then
                echo -e "${YELLOW}No controller services found matching the filters.${NC}\n"
                return
            fi
            
            echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}\n"
            
            # Summary statistics
            local enabled_count=0
            local disabled_count=0
            local enabling_count=0
            local disabling_count=0
            
            for i in "${!CS_IDS[@]}"; do
                local state="${CS_STATES[$i]}"
                case $state in
                    "ENABLED") ((enabled_count++)) ;;
                    "DISABLED") ((disabled_count++)) ;;
                    "ENABLING") ((enabling_count++)) ;;
                    "DISABLING") ((disabling_count++)) ;;
                esac
            done
            
            echo -e "${BOLD}${CYAN}Summary:${NC}"
            echo -e "  ${WHITE}Total Services:${NC} ${BOLD}${#CS_IDS[@]}${NC}"
            echo -e "  ${GREEN}Enabled:${NC} ${BOLD}${enabled_count}${NC}"
            echo -e "  ${RED}Disabled:${NC} ${BOLD}${disabled_count}${NC}"
            if [ $enabling_count -gt 0 ]; then
                echo -e "  ${YELLOW}Enabling:${NC} ${BOLD}${enabling_count}${NC}"
            fi
            if [ $disabling_count -gt 0 ]; then
                echo -e "  ${YELLOW}Disabling:${NC} ${BOLD}${disabling_count}${NC}"
            fi
            ;;
    esac
}

# Function to change controller service state (enable or disable)
change_controller_service_state() {
    local service_id=$1
    local revision_version=$2
    local new_state=$3  # "ENABLED" or "DISABLED"
    local url="${NIFI_URL}/nifi-api/controller-services/${service_id}"
    
    local client_id=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 32 | head -n 1)
    
    local payload=$(cat <<EOF
{
  "revision": {
    "clientId": "${client_id}",
    "version": ${revision_version}
  },
  "component": {
    "id": "${service_id}",
    "state": "${new_state}"
  },
  "disconnectedNodeAcknowledged": false
}
EOF
)
    
    local response
    if [ -n "$TOKEN" ]; then
        response=$(curl -k -f -s -w "\n%{http_code}" -X PUT "${url}" \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer ${TOKEN}" \
          -d "${payload}")
    else
        response=$(curl -k -f -s -w "\n%{http_code}" -X PUT "${url}" \
          -H "Content-Type: application/json" \
          -d "${payload}")
    fi
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Error:${NC} Failed to connect to ${url}"
        return 1
    fi
    
    local http_code="${response##*$'\n'}"
    local body="${response%$'\n'*}"
    
    echo "$body"
}

# Function to get controller service details
get_controller_service() {
    local service_id=$1
    local url="${NIFI_URL}/nifi-api/controller-services/${service_id}"
    
    local response
    if [ -n "$TOKEN" ]; then
        response=$(curl -k -f -s -w "\n%{http_code}" -X GET "${url}" \
          -H "Accept: application/json" \
          -H "Authorization: Bearer ${TOKEN}")
    else
        response=$(curl -k -f -s -w "\n%{http_code}" -X GET "${url}" \
          -H "Accept: application/json")
    fi
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Error:${NC} Failed to connect to ${url}"
        return 1
    fi
    
    local http_code="${response##*$'\n'}"
    local body="${response%$'\n'*}"
    
    echo "$body"
}

# Function to update controller service properties
update_controller_service_properties() {
    local service_id=$1
    local revision_version=$2
    local properties_json=$3
    
    local url="${NIFI_URL}/nifi-api/controller-services/${service_id}"
    
    local client_id=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 32 | head -n 1)
    
    local payload=$(cat <<EOF
{
  "revision": {
    "clientId": "${client_id}",
    "version": ${revision_version}
  },
  "component": {
    "id": "${service_id}",
    "properties": ${properties_json}
  },
  "disconnectedNodeAcknowledged": false
}
EOF
)
    
    local response
    if [ -n "$TOKEN" ]; then
        response=$(curl -k -f -s -w "\n%{http_code}" -X PUT "${url}" \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer ${TOKEN}" \
          -d "${payload}")
    else
        response=$(curl -k -f -s -w "\n%{http_code}" -X PUT "${url}" \
          -H "Content-Type: application/json" \
          -d "${payload}")
    fi
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Error:${NC} Failed to connect to ${url}"
        return 1
    fi
    
    local http_code="${response##*$'\n'}"
    local body="${response%$'\n'*}"
    
    echo "$body"
}

# Function to build properties JSON from command-line args and merge with existing
build_properties_json() {
    local service_id=$1
    
    # Step 1: Get ALL current properties
    current_properties=$(get_controller_service "$service_id" | jq '.component.properties')
    
    # Step 2: Start with current properties as the base
    merged_properties="$current_properties"
    
    # Step 3: Apply each update (overwrite if exists, add if new)
    for prop in "${PROPERTIES[@]}"; do
        key=$(echo "$prop" | cut -d'=' -f1)
        value=$(echo "$prop" | cut -d'=' -f2-)
        # This OVERWRITES the property if it exists, or ADDS it if new
        merged_properties=$(echo "$merged_properties" | jq --arg k "$key" --arg v "$value" '.[$k] = $v')
    done
    
    # Step 4: Return complete properties object
    echo "$merged_properties"
}


# Function to enable/disable all controller services
change_all_services_state() {
    local target_state=$1  # "ENABLED" or "DISABLED"
    local action_verb="Enabling"
    local action_past="Enabled"
    local action_color="${GREEN}"
    
    if [ "$target_state" = "DISABLED" ]; then
        action_verb="Disabling"
        action_past="Disabled"
        action_color="${RED}"
    fi
    
    echo -e "\n${CYAN}${BOLD}${action_verb} Controller Services:${NC}\n"
    
    local changed_count=0
    local skipped_count=0
    local failed_count=0
    
    for i in "${!CS_IDS[@]}"; do
        local cs_id="${CS_IDS[$i]}"
        local cs_name="${CS_NAMES[$i]}"
        local cs_state="${CS_STATES[$i]}"
        local cs_pg_name="${CS_PG_NAMES[$i]}"
        
        echo -e "${BOLD}${CYAN}Service:${NC} ${WHITE}${cs_name}${NC}"
        echo -e "  ${CYAN}Location:${NC} ${GRAY}${cs_pg_name}${NC}"
        echo -e "  ${CYAN}ID:${NC} ${GRAY}${cs_id}${NC}"
        echo -e "  ${CYAN}Current State:${NC} ${YELLOW}${cs_state}${NC}"
        
        if [ "$cs_state" = "$target_state" ] || [ "$cs_state" = "${target_state}ING" ]; then
            echo -e "  ${GREEN}✓ Already ${target_state} or ${target_state}ING${NC}, skipping...\n"
            ((skipped_count++))
        else
            local response=$(get_controller_service "$cs_id")
            if [ $? -ne 0 ]; then
                ((failed_count++))
                continue
            fi
            local revision=$(echo "${response}" | jq -r '.revision.version' 2>/dev/null)
            
            if [ -z "$revision" ] || [ "$revision" = "null" ]; then
                echo -e "  ${RED}✗ Failed to get revision${NC}\n"
                ((failed_count++))
                continue
            fi
            
            echo -e "  ${CYAN}Revision:${NC} ${GRAY}${revision}${NC}"
            echo -e "  ${YELLOW}⟳ ${action_verb}...${NC}"
            
            local change_response=$(change_controller_service_state "$cs_id" "$revision" "$target_state")
            if [ $? -ne 0 ]; then
                ((failed_count++))
                continue
            fi
            local error=$(echo "${change_response}" | jq -r '.error // empty' 2>/dev/null)
            
            if [ -n "$error" ]; then
                echo -e "  ${RED}✗ Failed:${NC} ${error}\n"
                ((failed_count++))
            else
                echo -e "  ${action_color}✓ ${action_past} successfully!${NC}\n"
                ((changed_count++))
            fi
        fi
    done
    
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                     Summary Report                     ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo -e "${WHITE}Total services:${NC} ${BOLD}${#CS_IDS[@]}${NC}"
    echo -e "${action_color}${action_past}:${NC} ${BOLD}${changed_count}${NC}"
    echo -e "${YELLOW}Already in target state (skipped):${NC} ${BOLD}${skipped_count}${NC}"
    echo -e "${RED}Failed:${NC} ${BOLD}${failed_count}${NC}"
}

# Function to change specific controller service state
change_specific_service_state() {
    local cs_number=$1
    local target_state=$2
    
    local action_verb="Enabling"
    local action_past="Enabled"
    local action_color="${GREEN}"
    
    if [ "$target_state" = "DISABLED" ]; then
        action_verb="Disabling"
        action_past="Disabled"
        action_color="${RED}"
    fi
    
    if [[ "$cs_number" =~ ^[0-9]+$ ]]; then
        INDEX=$((cs_number-1))
        if [ $INDEX -ge 0 ] && [ $INDEX -lt ${#CS_IDS[@]} ]; then
            CS_ID="${CS_IDS[$INDEX]}"
            CS_NAME="${CS_NAMES[$INDEX]}"
            CS_CURRENT_STATE="${CS_STATES[$INDEX]}"
            CS_LOCATION="${CS_PG_NAMES[$INDEX]}"
            CS_TYPE="${CS_TYPES[$INDEX]}"
            
            echo -e "\n${CYAN}${BOLD}${action_verb} Controller Service:${NC}\n"
            echo -e "  ${BOLD}${CYAN}Service:${NC} ${WHITE}${CS_NAME}${NC}"
            echo -e "  ${CYAN}Location:${NC} ${GRAY}${CS_LOCATION}${NC}"
            echo -e "  ${CYAN}Current State:${NC} ${YELLOW}${CS_CURRENT_STATE}${NC}"
            
            if [ "$CS_CURRENT_STATE" = "$target_state" ] || [ "$CS_CURRENT_STATE" = "${target_state}ING" ]; then
                echo -e "\n  ${GREEN}✓ Service is already ${CS_CURRENT_STATE}${NC}"
                return 0
            fi
            
            local response=$(get_controller_service "$CS_ID")
            if [ $? -ne 0 ]; then
                return 1
            fi
            local revision=$(echo "${response}" | jq -r '.revision.version' 2>/dev/null)
            
            if [ -z "$revision" ] || [ "$revision" = "null" ]; then
                echo -e "\n  ${RED}✗ Failed to get revision${NC}"
                return 1
            fi
            
            echo -e "  ${CYAN}Revision:${NC} ${GRAY}${revision}${NC}"
            echo -e "\n  ${YELLOW}⟳ ${action_verb}...${NC}"
            
            local change_response=$(change_controller_service_state "$CS_ID" "$revision" "$target_state")
            if [ $? -ne 0 ]; then
                return 1
            fi
            local error=$(echo "${change_response}" | jq -r '.error // empty' 2>/dev/null)
            
            if [ -n "$error" ]; then
                echo -e "\n  ${RED}✗ Failed:${NC} ${error}"
                return 1
            else
                echo -e "\n  ${action_color}✓ ${action_past} successfully!${NC}"
                return 0
            fi
        else
            echo -e "${RED}✗ Invalid service number: ${cs_number}${NC}"
            return 1
        fi
    else
        # Try to find service by ID
        for i in "${!CS_IDS[@]}"; do
            if [ "${CS_IDS[$i]}" = "$cs_number" ]; then
                CS_ID="${CS_IDS[$i]}"
                CS_NAME="${CS_NAMES[$i]}"
                CS_CURRENT_STATE="${CS_STATES[$i]}"
                CS_LOCATION="${CS_PG_NAMES[$i]}"
                CS_TYPE="${CS_TYPES[$i]}"
                
                echo -e "\n${CYAN}${BOLD}${action_verb} Controller Service:${NC}\n"
                echo -e "  ${BOLD}${CYAN}Service:${NC} ${WHITE}${CS_NAME}${NC}"
                echo -e "  ${CYAN}Location:${NC} ${GRAY}${CS_LOCATION}${NC}"
                echo -e "  ${CYAN}Current State:${NC} ${YELLOW}${CS_CURRENT_STATE}${NC}"
                
                if [ "$CS_CURRENT_STATE" = "$target_state" ] || [ "$CS_CURRENT_STATE" = "${target_state}ING" ]; then
                    echo -e "\n  ${GREEN}✓ Service is already ${CS_CURRENT_STATE}${NC}"
                    return 0
                fi
                
                local response=$(get_controller_service "$CS_ID")
                if [ $? -ne 0 ]; then
                    return 1
                fi
                local revision=$(echo "${response}" | jq -r '.revision.version' 2>/dev/null)
                
                if [ -z "$revision" ] || [ "$revision" = "null" ]; then
                    echo -e "\n  ${RED}✗ Failed to get revision${NC}"
                    return 1
                fi
                
                echo -e "  ${CYAN}Revision:${NC} ${GRAY}${revision}${NC}"
                echo -e "\n  ${YELLOW}⟳ ${action_verb}...${NC}"
                
                local change_response=$(change_controller_service_state "$CS_ID" "$revision" "$target_state")
                if [ $? -ne 0 ]; then
                    return 1
                fi
                local error=$(echo "${change_response}" | jq -r '.error // empty' 2>/dev/null)
                
                if [ -n "$error" ]; then
                    echo -e "\n  ${RED}✗ Failed:${NC} ${error}"
                    return 1
                else
                    echo -e "\n  ${action_color}✓ ${action_past} successfully!${NC}"
                    return 0
                fi
            fi
        done
        
        echo -e "${RED}✗ Service not found: ${cs_number}${NC}"
        return 1
    fi
}

# Function to update specific controller service properties
update_specific_service_properties() {
    local cs_number=$1
    local properties_json=$2
    
    if [[ "$cs_number" =~ ^[0-9]+$ ]]; then
        INDEX=$((cs_number-1))
        if [ $INDEX -ge 0 ] && [ $INDEX -lt ${#CS_IDS[@]} ]; then
            CS_ID="${CS_IDS[$INDEX]}"
            CS_NAME="${CS_NAMES[$INDEX]}"
            CS_CURRENT_STATE="${CS_STATES[$INDEX]}"
            CS_LOCATION="${CS_PG_NAMES[$INDEX]}"
            CS_TYPE="${CS_TYPES[$INDEX]}"
        else
            echo -e "${RED}✗ Invalid service number: ${cs_number}${NC}"
            return 1
        fi
    else
        # Try to find service by ID
        local found=false
        for i in "${!CS_IDS[@]}"; do
            if [ "${CS_IDS[$i]}" = "$cs_number" ]; then
                CS_ID="${CS_IDS[$i]}"
                CS_NAME="${CS_NAMES[$i]}"
                CS_CURRENT_STATE="${CS_STATES[$i]}"
                CS_LOCATION="${CS_PG_NAMES[$i]}"
                CS_TYPE="${CS_TYPES[$i]}"
                found=true
                break
            fi
        done
        
        if [ "$found" = false ]; then
            echo -e "${RED}✗ Service not found: ${cs_number}${NC}"
            return 1
        fi
    fi
    
    echo -e "\n${CYAN}${BOLD}Update Controller Service Properties:${NC}\n"
    echo -e "  ${BOLD}${CYAN}Service:${NC} ${WHITE}${CS_NAME}${NC}"
    echo -e "  ${CYAN}Location:${NC} ${GRAY}${CS_LOCATION}${NC}"
    echo -e "  ${CYAN}Current State:${NC} ${YELLOW}${CS_CURRENT_STATE}${NC}"
    echo -e "  ${CYAN}Type:${NC} ${GRAY}${CS_TYPE}${NC}"
    
    local response=$(get_controller_service "$CS_ID")
    if [ $? -ne 0 ]; then
        echo -e "\n  ${RED}✗ Failed to get service details${NC}"
        return 1
    fi
    
    local revision=$(echo "${response}" | jq -r '.revision.version' 2>/dev/null)
    if [ -z "$revision" ] || [ "$revision" = "null" ]; then
        echo -e "\n  ${RED}✗ Failed to get revision${NC}"
        return 1
    fi
    
    # Show current properties
    local current_properties=$(echo "${response}" | jq -c '.component.properties // {}' 2>/dev/null)
    echo -e "\n${YELLOW}Current Properties:${NC}"
    echo "$current_properties" | jq -r 'to_entries[] | "  \(.key) = \(.value)"' 2>/dev/null || echo "  (Unable to parse properties)"
    
    echo -e "\n${YELLOW}Properties to update (will be merged):${NC}"
    echo "$properties_json" | jq -r 'to_entries[] | "  \(.key) = \(.value)"' 2>/dev/null || echo "$properties_json"
    
    echo -e "\n  ${CYAN}Revision:${NC} ${GRAY}${revision}${NC}"
    echo -e "  ${YELLOW}⟳ Updating properties...${NC}"
    
    local update_response=$(update_controller_service_properties "$CS_ID" "$revision" "$properties_json")
    if [ $? -ne 0 ]; then
        echo -e "\n  ${RED}✗ Failed to update properties${NC}"
        return 1
    fi
    
    local error=$(echo "${update_response}" | jq -r '.error // empty' 2>/dev/null)
    
    if [ -n "$error" ]; then
        echo -e "\n  ${RED}✗ Failed:${NC} ${error}"
        return 1
    else
        echo -e "\n  ${GREEN}✓ Properties updated successfully!${NC}"
        
        # Show updated properties
        local updated_response=$(get_controller_service "$CS_ID")
        local updated_properties=$(echo "${updated_response}" | jq -c '.component.properties // {}' 2>/dev/null)
        echo -e "\n${GREEN}Updated Properties:${NC}"
        echo "$updated_properties" | jq -r 'to_entries[] | "  \(.key) = \(.value)"' 2>/dev/null || echo "  (Unable to parse properties)"
        
        return 0
    fi
}

# Function to update all controller services properties
update_all_services_properties() {
    echo -e "\n${CYAN}${BOLD}Updating Properties for All Services:${NC}\n"
    echo -e "${YELLOW}Properties to update (will be merged with existing):${NC}"
    
    # Show what properties we're going to update
    if [ ${#PROPERTIES[@]} -gt 0 ]; then
        for prop in "${PROPERTIES[@]}"; do
            echo -e "  ${prop}"
        done
    fi
    if [ -n "$PROPERTIES_FILE" ]; then
        echo -e "  From file: ${PROPERTIES_FILE}"
    fi
    if [ -n "$PROPERTIES_JSON" ]; then
        echo -e "  From JSON: ${PROPERTIES_JSON}"
    fi
    echo ""
    
    local changed_count=0
    local skipped_count=0
    local failed_count=0
    
    for i in "${!CS_IDS[@]}"; do
        local cs_id="${CS_IDS[$i]}"
        local cs_name="${CS_NAMES[$i]}"
        local cs_state="${CS_STATES[$i]}"
        local cs_pg_name="${CS_PG_NAMES[$i]}"
        
        echo -e "${BOLD}${CYAN}Service:${NC} ${WHITE}${cs_name}${NC}"
        echo -e "  ${CYAN}Location:${NC} ${GRAY}${cs_pg_name}${NC}"
        echo -e "  ${CYAN}ID:${NC} ${GRAY}${cs_id}${NC}"
        
        # Build merged properties JSON for this specific service
        local merged_properties=$(build_properties_json "$cs_id")
        if [ $? -ne 0 ]; then
            echo -e "  ${RED}✗ Failed to build properties${NC}\n"
            ((failed_count++))
            continue
        fi
        
        local response=$(get_controller_service "$cs_id")
        if [ $? -ne 0 ]; then
            echo -e "  ${RED}✗ Failed to get service details${NC}\n"
            ((failed_count++))
            continue
        fi
        
        local revision=$(echo "${response}" | jq -r '.revision.version' 2>/dev/null)
        if [ -z "$revision" ] || [ "$revision" = "null" ]; then
            echo -e "  ${RED}✗ Failed to get revision${NC}\n"
            ((failed_count++))
            continue
        fi
        
        echo -e "  ${CYAN}Revision:${NC} ${GRAY}${revision}${NC}"
        echo -e "  ${YELLOW}⟳ Updating properties...${NC}"
        
        local update_response=$(update_controller_service_properties "$cs_id" "$revision" "$merged_properties")
        if [ $? -ne 0 ]; then
            ((failed_count++))
            continue
        fi
        
        local error=$(echo "${update_response}" | jq -r '.error // empty' 2>/dev/null)
        if [ -n "$error" ]; then
            echo -e "  ${RED}✗ Failed:${NC} ${error}\n"
            ((failed_count++))
        else
            echo -e "  ${GREEN}✓ Properties updated successfully!${NC}\n"
            ((changed_count++))
        fi
    done
    
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                     Summary Report                     ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo -e "${WHITE}Total services:${NC} ${BOLD}${#CS_IDS[@]}${NC}"
    echo -e "${GREEN}Updated:${NC} ${BOLD}${changed_count}${NC}"
    echo -e "${RED}Failed:${NC} ${BOLD}${failed_count}${NC}"
}

# Function to change services from a file
change_services_from_file() {
    local file_path=$1
    local target_state=$2
    
    if [ ! -f "$file_path" ]; then
        echo -e "${RED}✗ Error:${NC} File not found: ${file_path}"
        return 1
    fi
    
    local action_verb="Enabling"
    local action_past="Enabled"
    local action_color="${GREEN}"
    
    if [ "$target_state" = "DISABLED" ]; then
        action_verb="Disabling"
        action_past="Disabled"
        action_color="${RED}"
    fi
    
    echo -e "\n${CYAN}${BOLD}${action_verb} Services from File:${NC}"
    echo -e "${GRAY}Reading from: ${file_path}${NC}\n"
    
    local changed_count=0
    local skipped_count=0
    local failed_count=0
    local not_found_count=0
    
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        line=$(echo "$line" | sed 's/#.*//' | xargs)
        if [ -z "$line" ]; then
            continue
        fi
        
        echo -e "${YELLOW}Processing:${NC} ${line}"
        
        if change_specific_service_state "$line" "$target_state" > /tmp/service_change_output.txt 2>&1; then
            ((changed_count++))
        else
            if grep -q "Service not found" /tmp/service_change_output.txt; then
                ((not_found_count++))
                echo -e "  ${RED}✗ Service not found${NC}\n"
            elif grep -iq "already" /tmp/service_change_output.txt; then
                ((skipped_count++))
                echo -e "  ${GREEN}✓ Already in target state${NC}\n"
            else
                ((failed_count++))
                echo -e "  ${RED}✗ Failed${NC}\n"
            fi
        fi
    done < "$file_path"
    
    rm -f /tmp/service_change_output.txt
    
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                     Summary Report                     ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "${WHITE}Total lines in file:${NC} ${BOLD}$(wc -l < "$file_path" | tr -d ' ')${NC}"
    echo -e "${action_color}${action_past}:${NC} ${BOLD}${changed_count}${NC}"
    echo -e "${YELLOW}Skipped (already in state):${NC} ${BOLD}${skipped_count}${NC}"
    echo -e "${RED}Not found:${NC} ${BOLD}${not_found_count}${NC}"
    echo -e "${RED}Failed:${NC} ${BOLD}${failed_count}${NC}"
}

# Function to update services from a file
update_services_from_file() {
    local file_path=$1
    
    if [ ! -f "$file_path" ]; then
        echo -e "${RED}✗ Error:${NC} File not found: ${file_path}"
        return 1
    fi
    
    echo -e "\n${CYAN}${BOLD}Updating Services from File:${NC}"
    echo -e "${GRAY}Reading from: ${file_path}${NC}\n"
    echo -e "${YELLOW}Properties to update (will be merged with existing):${NC}"
    
    if [ ${#PROPERTIES[@]} -gt 0 ]; then
        for prop in "${PROPERTIES[@]}"; do
            echo -e "  ${prop}"
        done
    fi
    if [ -n "$PROPERTIES_FILE" ]; then
        echo -e "  From file: ${PROPERTIES_FILE}"
    fi
    if [ -n "$PROPERTIES_JSON" ]; then
        echo -e "  From JSON: ${PROPERTIES_JSON}"
    fi
    echo ""
    
    local changed_count=0
    local failed_count=0
    local not_found_count=0
    
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        line=$(echo "$line" | sed 's/#.*//' | xargs)
        if [ -z "$line" ]; then
            continue
        fi
        
        echo -e "${YELLOW}Processing:${NC} ${line}"
        
        # Get the actual service ID
        local actual_service_id=""
        if [[ "$line" =~ ^[0-9]+$ ]]; then
            INDEX=$((line-1))
            if [ $INDEX -ge 0 ] && [ $INDEX -lt ${#CS_IDS[@]} ]; then
                actual_service_id="${CS_IDS[$INDEX]}"
            fi
        else
            # Try to find by ID
            for i in "${!CS_IDS[@]}"; do
                if [ "${CS_IDS[$i]}" = "$line" ]; then
                    actual_service_id="$line"
                    break
                fi
            done
        fi
        
        if [ -z "$actual_service_id" ]; then
            ((not_found_count++))
            echo -e "  ${RED}✗ Service not found${NC}\n"
            continue
        fi
        
        # Build merged properties for this specific service
        local properties_json=$(build_properties_json "$actual_service_id")
        if [ $? -ne 0 ]; then
            ((failed_count++))
            echo -e "  ${RED}✗ Failed to build properties${NC}\n"
            continue
        fi
        
        if update_specific_service_properties "$line" "$properties_json" > /tmp/service_update_output.txt 2>&1; then
            ((changed_count++))
        else
            if grep -q "Service not found" /tmp/service_update_output.txt; then
                ((not_found_count++))
                echo -e "  ${RED}✗ Service not found${NC}\n"
            else
                ((failed_count++))
                echo -e "  ${RED}✗ Failed${NC}\n"
            fi
        fi
    done < "$file_path"
    
    rm -f /tmp/service_update_output.txt
    
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                     Summary Report                     ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "${WHITE}Total lines in file:${NC} ${BOLD}$(wc -l < "$file_path" | tr -d ' ')${NC}"
    echo -e "${GREEN}Updated:${NC} ${BOLD}${changed_count}${NC}"
    echo -e "${RED}Not found:${NC} ${BOLD}${not_found_count}${NC}"
    echo -e "${RED}Failed:${NC} ${BOLD}${failed_count}${NC}"
}

# Function to execute batch mode for controller services
execute_batch_mode() {
    local target_state=""
    local action_name=""
    
    if [ "$BATCH_ENABLE" = true ]; then
        target_state="ENABLED"
        action_name="enable"
    elif [ "$BATCH_DISABLE" = true ]; then
        target_state="DISABLED"
        action_name="disable"
    elif [ "$BATCH_UPDATE" = true ]; then
        action_name="update properties"
    fi
    
    # Build properties JSON if updating
    if [ "$BATCH_UPDATE" = true ]; then
        if [ ${#PROPERTIES[@]} -eq 0 ] && [ -z "$PROPERTIES_FILE" ] && [ -z "$PROPERTIES_JSON" ]; then
            echo -e "${RED}✗ Error:${NC} No properties specified for update operation"
            echo -e "Use ${WHITE}--property${NC}, ${WHITE}--properties-file${NC}, or ${WHITE}--properties-json${NC}"
            exit 1
        fi
        # Note: Properties will be merged with existing properties for each service individually
    fi
    
    # Display filters if any are active
    if [ -n "$FILTER_STATE" ] || [ -n "$FILTER_NAME" ] || [ -n "$FILTER_TYPE" ] || [ -n "$FILTER_LOCATION" ]; then
        echo -e "${CYAN}${BOLD}Active Filters:${NC}"
        [ -n "$FILTER_STATE" ] && echo -e "  ${WHITE}State:${NC} ${FILTER_STATE}"
        [ -n "$FILTER_NAME" ] && echo -e "  ${WHITE}Name:${NC} ${FILTER_NAME}"
        [ -n "$FILTER_TYPE" ] && echo -e "  ${WHITE}Type:${NC} ${FILTER_TYPE}"
        [ -n "$FILTER_LOCATION" ] && echo -e "  ${WHITE}Location:${NC} ${FILTER_LOCATION}"
        echo ""
    fi
    
    # Check if we have specific service or file
    if [ -n "$SERVICE_ID" ]; then
        echo -e "${CYAN}${BOLD}Batch ${action_name} single service:${NC}"
        if [ "$BATCH_UPDATE" = true ]; then
            # For single service update, we need to get the actual service ID first
            local actual_service_id=""
            if [[ "$SERVICE_ID" =~ ^[0-9]+$ ]]; then
                INDEX=$((SERVICE_ID-1))
                if [ $INDEX -ge 0 ] && [ $INDEX -lt ${#CS_IDS[@]} ]; then
                    actual_service_id="${CS_IDS[$INDEX]}"
                fi
            else
                # Assume it's already a service ID
                actual_service_id="$SERVICE_ID"
            fi
            
            if [ -z "$actual_service_id" ]; then
                echo -e "${RED}✗ Error:${NC} Invalid service ID or number: ${SERVICE_ID}"
                exit 1
            fi
            
            # Build merged properties for this specific service
            properties_json=$(build_properties_json "$actual_service_id")
            if [ $? -ne 0 ]; then
                exit 1
            fi
            
            update_specific_service_properties "$SERVICE_ID" "$properties_json"
        else
            change_specific_service_state "$SERVICE_ID" "$target_state"
        fi
    elif [ -n "$SERVICE_FILE" ]; then
        if [ "$SKIP_CONFIRM" = false ]; then
            echo -e "${YELLOW}⚠ Warning:${NC} This will attempt to ${BOLD}${action_name}${NC} services from file: ${SERVICE_FILE}"
            read -p "$(echo -e "${WHITE}Are you sure? ${GRAY}[y/n]${NC}: ")" confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}✗ Operation cancelled.${NC}"
                exit 0
            fi
        fi
        
        if [ "$BATCH_UPDATE" = true ]; then
            update_services_from_file "$SERVICE_FILE"
        else
            change_services_from_file "$SERVICE_FILE" "$target_state"
        fi
    elif [ "$APPLY_TO_ALL" = true ]; then
        # Apply to all services (with filters if specified)
        if [ ${#CS_IDS[@]} -eq 0 ]; then
            echo -e "${YELLOW}No services match the specified filters.${NC}"
            exit 0
        fi
        
        if [ "$SKIP_CONFIRM" = false ]; then
            echo -e "${YELLOW}⚠ Warning:${NC} This will attempt to ${BOLD}${action_name}${NC} ${BOLD}${#CS_IDS[@]}${NC} controller service(s)."
            read -p "$(echo -e "${WHITE}Are you sure? ${GRAY}[y/n]${NC}: ")" confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}✗ Operation cancelled.${NC}"
                exit 0
            fi
        fi
        
        if [ "$BATCH_UPDATE" = true ]; then
            update_all_services_properties
        else
            change_all_services_state "$target_state"
        fi
    else
        echo -e "${RED}✗ Error:${NC} Must specify ${WHITE}--service${NC}, ${WHITE}--file${NC}, or ${WHITE}--all${NC}"
        exit 1
    fi
}

# ============================================================================
# MAIN EXECUTION LOGIC
# ============================================================================

# Get all contexts if we need them
if [ "$LIST_ONLY" = true ] || [ "$BATCH_ENABLE" = true ] || [ "$BATCH_DISABLE" = true ] || \
   [ "$BATCH_UPDATE" = true ] || [ "$INTERACTIVE" = true ]; then
    
    # Determine if we should show progress messages
    SHOW_PROGRESS=true
    if [[ "$OPERATION_MODE" == "list" ]] && [ "$OUTPUT_FORMAT" != "table" ]; then
        SHOW_PROGRESS=false
    fi

    # Get root process group ID
    root_url="${NIFI_URL}/nifi-api/flow/process-groups/root"
    if [ -n "$TOKEN" ]; then
        ROOT_RESPONSE=$(curl -k -f -s -X GET "${root_url}" \
          -H "Accept: application/json" \
          -H "Authorization: Bearer ${TOKEN}")
    else
        ROOT_RESPONSE=$(curl -k -f -s -X GET "${root_url}" \
          -H "Accept: application/json")
    fi

    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Error:${NC} Failed to connect to NiFi at ${root_url}."
        echo -e "${YELLOW}Please check:${NC}"
        echo -e "  • NiFi URL is correct: ${BLUE}${NIFI_URL}${NC}"
        echo -e "  • NiFi is running and accessible"
        echo -e "  • Network connectivity"
        exit 1
    fi

    ROOT_ID=$(echo "${ROOT_RESPONSE}" | jq -r '.processGroupFlow.id // empty' 2>/dev/null)

    if [ -z "$ROOT_ID" ] || [ "$ROOT_ID" = "null" ]; then
        echo -e "${RED}✗ Error:${NC} Failed to get root process group ID."
        echo -e "${YELLOW}Please check:${NC}"
        echo -e "  • Authentication credentials are valid"
        echo -e "  • User has appropriate permissions"
        
        error_msg=$(echo "${ROOT_RESPONSE}" | jq -r '.error // empty' 2>/dev/null)
        if [ -n "$error_msg" ]; then
            echo -e "  • Server error: ${error_msg}"
        fi
        exit 1
    fi

    # Recursively list all process groups
    if [ "$SHOW_PROGRESS" = true ] && [ "$OPERATION_MODE" != "list" ]; then
        echo -e "\n${YELLOW}⟳${NC} Recursively fetching all process groups from NiFi..."
    fi

    if ! list_process_groups_recursive "$ROOT_ID"; then
        echo -e "${RED}✗ Error:${NC} Failed to fetch process groups."
        exit 1
    fi

    if [ "$SHOW_PROGRESS" = true ] && [ "$OPERATION_MODE" != "list" ]; then
        echo -e "${GREEN}✓${NC} Found ${BOLD}${#PG_IDS[@]}${NC} process group(s)"
        echo -e "\n${YELLOW}⟳${NC} Collecting controller services from all process groups..."
    fi

    # Collect all controller services from all process groups
    collect_failed=0
    for i in "${!PG_IDS[@]}"; do
        if ! collect_controller_services_from_pg "${PG_IDS[$i]}" "${PG_PATHS[$i]}"; then
            ((collect_failed++))
        fi
    done

    if [ $collect_failed -gt 0 ] && [ "$SHOW_PROGRESS" = true ]; then
        echo -e "${YELLOW}⚠ Failed to collect from ${collect_failed} process groups.${NC}"
    fi
    
    # Apply filters if any are specified
    apply_filters

    if [ ${#CS_IDS[@]} -eq 0 ]; then
        if [ "$LIST_ONLY" = true ]; then
            case $OUTPUT_FORMAT in
                json) 
                    echo '[]'
                    ;;
                csv) 
                    echo "ID,Name,State,Type,Location"
                    ;;
                table) 
                    echo -e "${YELLOW}No controller services found matching the filters.${NC}"
                    ;;
            esac
        else
            echo -e "${YELLOW}No controller services found matching the filters.${NC}"
        fi
        exit 0
    fi
    
    if [ "$SHOW_PROGRESS" = true ] && [ "$OPERATION_MODE" != "list" ]; then
        echo -e "${GREEN}✓${NC} Found ${BOLD}${#CS_IDS[@]}${NC} controller service(s) across ${BOLD}${#PG_IDS[@]}${NC} process group(s)\n"
    fi
fi

# ============================================================================
# EXECUTE REQUESTED OPERATION
# ============================================================================

# If list-only mode, output and exit
if [ "$LIST_ONLY" = true ]; then
    output_controller_services "$OUTPUT_FORMAT"
    exit 0
fi

# If batch mode for controller services, execute and exit
if [ "$BATCH_ENABLE" = true ] || [ "$BATCH_DISABLE" = true ] || [ "$BATCH_UPDATE" = true ]; then
    execute_batch_mode
    exit 0
fi

# ============================================================================
# INTERACTIVE MODE
# ============================================================================

if [ "$INTERACTIVE" = true ]; then
    echo -e "\n${CYAN}${BOLD}Controller Services Management:${NC}"
    echo -e "  ${YELLOW}1)${NC} List all controller services"
    echo -e "  ${YELLOW}2)${NC} Modify services (enable/disable/update)"
    echo -e "  ${RED}3)${NC} Exit"
    read -p "$(echo -e "${WHITE}Enter choice ${GRAY}[1, 2, or 3]${NC}: ")" CS_CHOICE
    
    case $CS_CHOICE in
        1)
            echo -e "\n${CYAN}${BOLD}Choose output format:${NC}"
            echo -e "  ${YELLOW}1)${NC} Table (colored, formatted)"
            echo -e "  ${YELLOW}2)${NC} JSON"
            echo -e "  ${YELLOW}3)${NC} CSV"
            read -p "$(echo -e "${WHITE}Enter choice ${GRAY}[1-3]${NC}: ")" FORMAT_CHOICE
            
            case $FORMAT_CHOICE in
                1) output_controller_services "table" ;;
                2) output_controller_services "json" ;;
                3) output_controller_services "csv" ;;
                *) 
                    echo -e "${YELLOW}Invalid choice, showing table format${NC}"
                    output_controller_services "table"
                    ;;
            esac
            ;;
            
        2)
            echo -e "\n${CYAN}${BOLD}Choose Action:${NC}"
            echo -e "  ${YELLOW}1)${NC} ${BOLD}Enable${NC} ALL controller services"
            echo -e "  ${YELLOW}2)${NC} ${BOLD}Disable${NC} ALL controller services"
            echo -e "  ${YELLOW}3)${NC} ${BOLD}Enable${NC} a specific controller service"
            echo -e "  ${YELLOW}4)${NC} ${BOLD}Disable${NC} a specific controller service"
            echo -e "  ${YELLOW}5)${NC} ${BOLD}Update${NC} specific controller service properties"
            echo -e "  ${RED}6)${NC} Back to main menu"
            read -p "$(echo -e "${WHITE}Enter choice ${GRAY}[1-6]${NC}: ")" ACTION_CHOICE
            
            case $ACTION_CHOICE in
                1)
                    echo -e "\n${YELLOW}⚠ Warning:${NC} This will attempt to ${BOLD}${GREEN}ENABLE${NC} ${BOLD}ALL${NC} controller services."
                    read -p "$(echo -e "${WHITE}Are you sure? ${GRAY}[y/n]${NC}: ")" confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        change_all_services_state "ENABLED"
                    else
                        echo -e "${YELLOW}✗ Operation cancelled.${NC}"
                    fi
                    ;;
                    
                2)
                    echo -e "\n${RED}⚠ Warning:${NC} This will attempt to ${BOLD}${RED}DISABLE${NC} ${BOLD}ALL${NC} controller services."
                    read -p "$(echo -e "${WHITE}Are you sure? ${GRAY}[y/n]${NC}: ")" confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        change_all_services_state "DISABLED"
                    else
                        echo -e "${YELLOW}✗ Operation cancelled.${NC}"
                    fi
                    ;;
                    
                3)
                    read -p "$(echo -e "${WHITE}Enter controller service number to enable${NC}: ")" CS_NUMBER
                    change_specific_service_state "$CS_NUMBER" "ENABLED"
                    ;;
                    
                4)
                    read -p "$(echo -e "${WHITE}Enter controller service number to disable${NC}: ")" CS_NUMBER
                    change_specific_service_state "$CS_NUMBER" "DISABLED"
                    ;;
                    
                5)
                    read -p "$(echo -e "${WHITE}Enter controller service number to update${NC}: ")" CS_NUMBER
                    
                    # Get service details first
                    if [[ "$CS_NUMBER" =~ ^[0-9]+$ ]]; then
                        INDEX=$((CS_NUMBER-1))
                        if [ $INDEX -ge 0 ] && [ $INDEX -lt ${#CS_IDS[@]} ]; then
                            CS_ID="${CS_IDS[$INDEX]}"
                        else
                            echo -e "${RED}✗ Invalid service number${NC}"
                            continue
                        fi
                    else
                        CS_ID="$CS_NUMBER"
                    fi
                    
                    # Get current properties
                    response=$(get_controller_service "$CS_ID")
                    current_properties=$(echo "${response}" | jq -r '.component.properties' 2>/dev/null)
                    
                    echo -e "\n${YELLOW}Current Properties:${NC}"
                    echo "${current_properties}" | jq -r 'to_entries[] | "  \(.key): \(.value // "null")"' 2>/dev/null || echo "  (Unable to parse properties)"
                    
                    echo -e "\n${YELLOW}Enter new property values (will be merged with existing):${NC}"
                    echo -e "  ${YELLOW}Format:${NC} property_name=property_value (one per line, empty line to finish)"
                    
                    declare -a INTERACTIVE_PROPERTIES
                    while true; do
                        read -p "$(echo -e "${WHITE}Enter property (name=value) or empty to finish${NC}: ")" prop_input
                        if [ -z "$prop_input" ]; then
                            break
                        fi
                        INTERACTIVE_PROPERTIES+=("$prop_input")
                    done
                    
                    if [ ${#INTERACTIVE_PROPERTIES[@]} -eq 0 ]; then
                        echo -e "${YELLOW}⚠ No properties changed.${NC}"
                        continue
                    fi
                    
                    # Build merged properties JSON
                    PROPERTIES=("${INTERACTIVE_PROPERTIES[@]}")
                    properties_json=$(build_properties_json "$CS_ID")
                    
                    update_specific_service_properties "$CS_NUMBER" "$properties_json"
                    ;;
                    
                6)
                    echo -e "${GREEN}✓ Exiting.${NC}"
                    exit 0
                    ;;
                    
                *)
                    echo -e "${RED}✗ Invalid choice.${NC}"
                    ;;
            esac
            ;;
            
        3)
            echo -e "${GREEN}✓ Exiting.${NC}"
            exit 0
            ;;
            
        *)
            echo -e "${RED}✗ Invalid choice.${NC} Exiting."
            exit 1
            ;;
    esac
fi

exit 0