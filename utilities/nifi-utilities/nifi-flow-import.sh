#!/bin/bash

# NiFi Flow Import Script
# Enhanced with master script styling and functionality

# Color codes for better readability
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color
BOLD='\033[1m'
DIM='\033[2m'
ORANGE='\033[0;38;5;214m'
PURPLE='\033[0;35m'

# ================ DEPENDENCY CHECK ================
check_dependencies() {
    local missing_deps=()
    
    # Check for curl (essential)
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${RED}✗ Error:${NC} Missing required dependencies:"
        for dep in "${missing_deps[@]}"; do
            echo -e "  ${RED}-${NC} $dep"
        done
        echo -e "\n${CYAN}Please install missing dependencies and try again.${NC}"
        echo -e "${GRAY}Install curl with:${NC}"
        echo -e "  ${GRAY}Debian/Ubuntu: sudo apt-get install curl${NC}"
        echo -e "  ${GRAY}RHEL/CentOS:   sudo yum install curl${NC}"
        echo -e "  ${GRAY}macOS:         brew install curl${NC}"
        exit 1
    fi
    
    # Check for jq (recommended but not required)
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}⚠ Warning:${NC} ${BOLD}jq${NC} is not installed. Some features may be limited."
        echo -e "${GRAY}   Install with: sudo apt-get install jq (Debian/Ubuntu)${NC}"
        echo -e "${GRAY}                sudo yum install jq (RHEL/CentOS)${NC}"
        echo -e "${GRAY}                brew install jq (macOS)${NC}"
        echo ""
    fi
}

# Check dependencies early
check_dependencies

# ================ VERBOSE LOGGING ================
log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${GRAY}[VERBOSE]${NC} $*"
    fi
}

# ================ USAGE FUNCTION ================
# Function to display usage
usage() {
    echo -e "${BOLD}${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                   NiFi Flow Import Manager                                 ║"
    echo "║                              Help Documentation                            ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    
    echo -e "${BOLD}${CYAN}SYNOPSIS${NC}"
    echo -e "  $0 [OPTIONS] <flow_file_path> <flow_name>"
    echo -e "  $0 [OPTIONS] --file <flow_file_path> --name <flow_name>\n"
    
    echo -e "${BOLD}${CYAN}DESCRIPTION${NC}"
    echo -e "  Imports JSON flow templates to Apache NiFi with intelligent duplicate handling,"
    echo -e "  automatic renaming, and optional flow disabling. Perfect for CI/CD pipelines.\n"
    
    echo -e "${BOLD}${CYAN}OPTIONS${NC}"
    echo -e "  ${YELLOW}--help, -h${NC}              Display this help message and exit"
    echo -e "  ${YELLOW}--file, -f${NC} FILE         Path to JSON flow template file (required)"
    echo -e "  ${YELLOW}--name, -n${NC} NAME         Name for the imported flow (required)"
    echo -e "  ${YELLOW}--url, -u${NC} URL           NiFi URL (default: https://idol-docker-host:8443)"
    echo -e "  ${YELLOW}--auth, -a${NC} METHOD       Authentication method: ${WHITE}password${NC}|${WHITE}token${NC}|${WHITE}none${NC}"
    echo -e "  ${YELLOW}--username, -U${NC} USER     Username for password authentication (default: admin)"
    echo -e "  ${YELLOW}--password, -P${NC} PASS     Password for password authentication (default: Nifi-Admin1!)"
    echo -e "  ${YELLOW}--token, -t${NC} TOKEN       Bearer token for token authentication"
    echo -e "  ${YELLOW}--disable, -d${NC}           Disable the imported flow (default: true)"
    echo -e "  ${YELLOW}--no-disable${NC}            Do NOT disable the imported flow"
    echo -e "  ${YELLOW}--overwrite, -o${NC}         Overwrite existing flow if name conflicts"
    echo -e "  ${YELLOW}--rename, -r${NC}            Auto-rename if name conflicts (default: true)"
    echo -e "  ${YELLOW}--position-x, -x${NC} NUM    X position for flow placement (default: 100)"
    echo -e "  ${YELLOW}--position-y, -y${NC} NUM    Y position for flow placement (default: 100)"
    echo -e "  ${YELLOW}--comments, -c${NC} TEXT     Comments for the imported flow"
    echo -e "  ${YELLOW}--client-id, -C${NC} ID      Custom client ID for the upload"
    echo -e "  ${YELLOW}--yes, -Y${NC}               Skip all confirmation prompts"
    echo -e "  ${YELLOW}--verbose, -v${NC}           Enable verbose output"
    echo -e "  ${YELLOW}--quiet, -q${NC}             Suppress non-essential output\n"
    
    echo -e "${BOLD}${CYAN}ARGUMENTS${NC}"
    echo -e "  flow_file_path          Path to the JSON flow template file"
    echo -e "  flow_name               Name for the imported flow"
    echo -e "                          Note: Positional arguments override --file and --name options\n"
    
    echo -e "${BOLD}${CYAN}DUPLICATE HANDLING STRATEGIES${NC}\n"
    
    echo -e "  When a flow with the same name already exists, you can choose:\n"
    
    echo -e "  ${YELLOW}1. Delete Existing (--overwrite)${NC}"
    echo -e "     Deletes the existing flow and uploads the new one\n"
    
    echo -e "  ${YELLOW}2. Auto-Rename (--rename, DEFAULT)${NC}"
    echo -e "     Automatically renames the new flow with a suffix:"
    echo -e "     Example: 'MyFlow' → 'MyFlow_1', 'MyFlow_2', etc.\n"
    
    echo -e "  ${YELLOW}3. Interactive Prompt${NC}"
    echo -e "     Prompts you to choose an action (when not using --yes)\n"
    
    echo -e "  ${YELLOW}4. Skip (manual)${NC}"
    echo -e "     Cancel the upload and keep existing flow\n"
    
    echo -e "${BOLD}${CYAN}USAGE MODES${NC}\n"
    
    echo -e "${BOLD}${YELLOW}1. Basic Import (Interactive)${NC}"
    echo -e "  Simple import with prompts for missing information:\n"
    echo -e "  ${GRAY}\$ $0 ./flow.json \"My Flow\"${NC}\n"
    
    echo -e "${BOLD}${YELLOW}2. Automated Import (Non-interactive)${NC}"
    echo -e "  Fully automated import for scripts/CI/CD:\n"
    echo -e "  ${GRAY}\$ $0 -f ./flow.json -n \"My Flow\" -Y -r${NC}\n"
    
    echo -e "${BOLD}${YELLOW}3. Overwrite Mode${NC}"
    echo -e "  Replace existing flow with same name:\n"
    echo -e "  ${GRAY}\$ $0 -f ./flow.json -n \"My Flow\" -o -Y${NC}\n"
    
    echo -e "${BOLD}${YELLOW}4. Token Authentication${NC}"
    echo -e "  Import with pre-generated token:\n"
    echo -e "  ${GRAY}\$ $0 -u https://idol-docker-host:8443 -a token -t <token> \\"
    echo -e "        -f ./flow.json -n \"My Flow\"${NC}\n"
    
    echo -e "${BOLD}${YELLOW}5. Custom Configuration${NC}"
    echo -e "  Import with custom settings:\n"
    echo -e "  ${GRAY}\$ $0 -x 200 -y 300 -c \"Production Import\" \\"
    echo -e "        --client-id \"ci-pipeline-123\" \\"
    echo -e "        -f ./flow.json -n \"Production Flow\"${NC}\n"
    
    echo -e "${BOLD}${CYAN}FLOW FILE FORMAT${NC}\n"
    
    echo -e "  The flow file must be a valid JSON export from NiFi:\n"
    echo -e "  ${GRAY}{"
    echo -e "    \"flow\": {"
    echo -e "      \"processors\": [ ... ],"
    echo -e "      \"connections\": [ ... ],"
    echo -e "      \"processGroups\": [ ... ],"
    echo -e "      \"remoteProcessGroups\": [ ... ],"
    echo -e "      \"inputPorts\": [ ... ],"
    echo -e "      \"outputPorts\": [ ... ],"
    echo -e "      \"funnels\": [ ... ],"
    echo -e "      \"labels\": [ ... ]"
    echo -e "    }"
    echo -e "  }${NC}\n"
    
    echo -e "  ${YELLOW}Note:${NC} The file can be exported from NiFi UI via:"
    echo -e "        ${CYAN}Right-click process group → Download flow${NC}\n"
    
    echo -e "${BOLD}${CYAN}EXAMPLES${NC}\n"
    
    echo -e "  ${GRAY}# Basic import with prompts${NC}"
    echo -e "  $0 ./templates/basic.json \"Basic Flow\"\n"
    
    echo -e "  ${GRAY}# Import with custom authentication${NC}"
    echo -e "  $0 -u https://idol-docker-host:8443 -U customuser -P custompass \\"
    echo -e "     -f ./flow.json -n \"Custom Flow\"\n"
    
    echo -e "  ${GRAY}# Overwrite existing flow${NC}"
    echo -e "  $0 --overwrite --yes \\"
    echo -e "     --file ./templates/updated.json \\"
    echo -e "     --name \"Production Flow\"\n"
    
    echo -e "  ${GRAY}# Import multiple flows with custom positions${NC}"
    echo -e "  $0 -f flow1.json -n \"Flow1\" -x 100 -y 100 -Y"
    echo -e "  $0 -f flow2.json -n \"Flow2\" -x 100 -y 500 -Y"
    echo -e "  $0 -f flow3.json -n \"Flow3\" -x 100 -y 900 -Y\n"
    
    echo -e "  ${GRAY}# CI/CD pipeline example${NC}"
    echo -e "  $0 -f \${WORKSPACE}/flow.json \\"
    echo -e "     -n \"\${JOB_NAME}-\${BUILD_NUMBER}\" \\"
    echo -e "     -c \"Automated deploy from Jenkins\" \\"
    echo -e "     --client-id \"jenkins-\${BUILD_TAG}\" \\"
    echo -e "     -Y -r -u \${NIFI_URL}\n"
    
    echo -e "  ${GRAY}# Verbose debugging${NC}"
    echo -e "  $0 -f ./flow.json -n \"Debug Flow\" -v\n"
    
    echo -e "${BOLD}${CYAN}CONFIGURATION${NC}\n"
    
    echo -e "  Default NiFi connection settings:\n"
    echo -e "  ${CYAN}NIFI_URL${NC}      = https://idol-docker-host:8443"
    echo -e "  ${CYAN}USERNAME${NC}      = admin"
    echo -e "  ${CYAN}PASSWORD${NC}      = Nifi-Admin1!"
    echo -e "  ${CYAN}POSITION_X${NC}    = 100"
    echo -e "  ${CYAN}POSITION_Y${NC}    = 100"
    echo -e "  ${CYAN}DISABLE_FLOW${NC}  = true"
    echo -e "  ${CYAN}AUTO_RENAME${NC}   = true\n"
    
    echo -e "${BOLD}${CYAN}AUTHENTICATION METHODS${NC}\n"
    
    echo -e "  ${YELLOW}1. Password Authentication (DEFAULT)${NC}"
    echo -e "     Uses username/password to generate a token\n"
    
    echo -e "  ${YELLOW}2. Token Authentication${NC}"
    echo -e "     Use pre-generated bearer token:\n"
    echo -e "     ${GRAY}--auth token --token <your-token>${NC}\n"
    
    echo -e "  ${YELLOW}3. No Authentication${NC}"
    echo -e "     Use for unsecured NiFi instances:\n"
    echo -e "     ${GRAY}--auth none${NC}\n"
    
    echo -e "${BOLD}${CYAN}FLOW STATES${NC}\n"
    
    echo -e "  After import, the flow can be in these states:\n"
    echo -e "  ${GREEN}DISABLED${NC}  - Flow is disabled (default, recommended for imports)"
    echo -e "  ${YELLOW}STOPPED${NC}   - Flow is stopped but enabled"
    echo -e "  ${RED}RUNNING${NC}  - Flow is running (use --no-disable to allow)"
    echo -e "  ${ORANGE}UNKNOWN${NC}  - Could not determine state\n"
    
    echo -e "${BOLD}${CYAN}TROUBLESHOOTING${NC}\n"
    
    echo -e "  ${YELLOW}Issue:${NC} \"Flow file not found\""
    echo -e "  ${CYAN}Solution:${NC} Use absolute paths or verify file exists\n"
    
    echo -e "  ${YELLOW}Issue:${NC} \"Unable to access NiFi API\""
    echo -e "  ${CYAN}Solution:${NC} Check URL, network connectivity, and authentication\n"
    
    echo -e "  ${YELLOW}Issue:${NC} \"Duplicate flow detected\""
    echo -e "  ${CYAN}Solution:${NC} Use --overwrite, --rename, or choose interactively\n"
    
    echo -e "  ${YELLOW}Issue:${NC} \"Failed to disable flow\""
    echo -e "  ${CYAN}Solution:${NC} Flow may be in invalid state, check NiFi UI\n"
    
    echo -e "${BOLD}${CYAN}REQUIREMENTS${NC}\n"
    
    echo -e "  - ${WHITE}curl${NC} (required for API calls)"
    echo -e "  - ${WHITE}jq${NC} (recommended for JSON parsing, not required)"
    echo -e "  - ${WHITE}Valid NiFi JSON flow template${NC}"
    echo -e "  - ${WHITE}Network access to NiFi instance${NC}"
    
    echo -e "\n${BOLD}${CYAN}EXIT CODES${NC}\n"
    
    echo -e "  ${GREEN}0${NC}  - Success"
    echo -e "  ${RED}1${NC}  - General error"
    echo -e "  ${RED}2${NC}  - Invalid arguments"
    echo -e "  ${RED}3${NC}  - File not found"
    echo -e "  ${RED}4${NC}  - Authentication failed"
    echo -e "  ${RED}5${NC}  - API connection failed"
    echo -e "  ${RED}6${NC}  - Upload failed"
    echo -e "  ${RED}7${NC}  - Duplicate flow conflict\n"
    
    echo -e "${BOLD}${CYAN}AUTHOR${NC}\n"
    echo -e "  NiFi Flow Import Manager"
    echo -e "  Enhanced version with master script styling\n"
    
    exit 1
}

# Default values
NIFI_URL=""
AUTH_METHOD=""
USERNAME=""
PASSWORD=""
TOKEN=""
INTERACTIVE=true
DISABLE_FLOW=true
OVERWRITE=false
AUTO_RENAME=true
POSITION_X=100
POSITION_Y=100
COMMENTS="Imported via API - Created as DISABLED"
CLIENT_ID=""
SKIP_CONFIRM=false
VERBOSE=false
QUIET=false
FLOW_FILE_PATH=""
FLOW_NAME=""
ORIGINAL_FLOW_NAME=""

# Parse command line arguments
log_verbose "Starting argument parsing..."
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file)
            FLOW_FILE_PATH="$2"
            INTERACTIVE=false
            log_verbose "Set FLOW_FILE_PATH to: $FLOW_FILE_PATH"
            shift 2
            ;;
        -n|--name)
            ORIGINAL_FLOW_NAME="$2"
            INTERACTIVE=false
            log_verbose "Set ORIGINAL_FLOW_NAME to: $ORIGINAL_FLOW_NAME"
            shift 2
            ;;
        -u|--url)
            NIFI_URL="$2"
            INTERACTIVE=false
            log_verbose "Set NIFI_URL to: $NIFI_URL"
            shift 2
            ;;
        -a|--auth)
            AUTH_METHOD="$2"
            log_verbose "Set AUTH_METHOD to: $AUTH_METHOD"
            shift 2
            ;;
        -U|--username)
            USERNAME="$2"
            log_verbose "Set USERNAME to: $USERNAME"
            shift 2
            ;;
        -P|--password)
            PASSWORD="$2"
            log_verbose "Set PASSWORD (hidden for security)"
            shift 2
            ;;
        -t|--token)
            TOKEN="$2"
            log_verbose "Set TOKEN (hidden for security)"
            shift 2
            ;;
        -d|--disable)
            DISABLE_FLOW=true
            log_verbose "Set DISABLE_FLOW to: true"
            shift
            ;;
        --no-disable)
            DISABLE_FLOW=false
            log_verbose "Set DISABLE_FLOW to: false"
            shift
            ;;
        -o|--overwrite)
            OVERWRITE=true
            AUTO_RENAME=false
            log_verbose "Set OVERWRITE to: true, AUTO_RENAME to: false"
            shift
            ;;
        -r|--rename)
            AUTO_RENAME=true
            OVERWRITE=false
            log_verbose "Set AUTO_RENAME to: true, OVERWRITE to: false"
            shift
            ;;
        -x|--position-x)
            POSITION_X="$2"
            log_verbose "Set POSITION_X to: $POSITION_X"
            shift 2
            ;;
        -y|--position-y)
            POSITION_Y="$2"
            log_verbose "Set POSITION_Y to: $POSITION_Y"
            shift 2
            ;;
        -c|--comments)
            COMMENTS="$2"
            log_verbose "Set COMMENTS to: $COMMENTS"
            shift 2
            ;;
        -C|--client-id)
            CLIENT_ID="$2"
            log_verbose "Set CLIENT_ID to: $CLIENT_ID"
            shift 2
            ;;
        -Y|--yes)
            SKIP_CONFIRM=true
            log_verbose "Set SKIP_CONFIRM to: true"
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            log_verbose "Verbose mode enabled"
            shift
            ;;
        -q|--quiet)
            QUIET=true
            log_verbose "Quiet mode enabled"
            shift
            ;;
        -h|--help)
            log_verbose "Help requested, showing usage..."
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
            # Positional arguments (backward compatibility)
            if [ -z "$FLOW_FILE_PATH" ]; then
                FLOW_FILE_PATH="$1"
                log_verbose "Set FLOW_FILE_PATH (positional) to: $FLOW_FILE_PATH"
            elif [ -z "$ORIGINAL_FLOW_NAME" ]; then
                ORIGINAL_FLOW_NAME="$1"
                log_verbose "Set ORIGINAL_FLOW_NAME (positional) to: $ORIGINAL_FLOW_NAME"
            else
                echo -e "${RED}✗ Error:${NC} Too many positional arguments: $1"
                echo -e "Expected at most 2 arguments: <flow_file_path> <flow_name>"
                usage
            fi
            shift
            ;;
    esac
done

log_verbose "Finished argument parsing"
log_verbose "FLOW_FILE_PATH: $FLOW_FILE_PATH"
log_verbose "ORIGINAL_FLOW_NAME: $ORIGINAL_FLOW_NAME"
log_verbose "INTERACTIVE: $INTERACTIVE"
log_verbose "AUTH_METHOD: $AUTH_METHOD"

# Validate required parameters
if [ -z "$FLOW_FILE_PATH" ] && [ -z "$ORIGINAL_FLOW_NAME" ]; then
    echo -e "${RED}✗ Error:${NC} No flow file or name specified."
    echo -e "Use: $0 <flow_file_path> <flow_name>"
    echo -e "Or:  $0 -f <flow_file_path> -n <flow_name>"
    echo -e "     $0 --help for detailed usage"
    exit 2
fi

if [ -z "$FLOW_FILE_PATH" ]; then
    echo -e "${RED}✗ Error:${NC} Flow file path is required."
    echo -e "Use --file <path> or provide as first argument"
    exit 2
fi

if [ -z "$ORIGINAL_FLOW_NAME" ]; then
    echo -e "${RED}✗ Error:${NC} Flow name is required."
    echo -e "Use --name <name> or provide as second argument"
    exit 2
fi

# Validate file exists
if [ ! -f "$FLOW_FILE_PATH" ]; then
    echo -e "${RED}✗ Error:${NC} Flow file not found: $FLOW_FILE_PATH"
    exit 3
fi

# Validate file is readable
if [ ! -r "$FLOW_FILE_PATH" ]; then
    echo -e "${RED}✗ Error:${NC} Flow file is not readable: $FLOW_FILE_PATH"
    exit 3
fi

# Validate file extension
if [[ ! "$FLOW_FILE_PATH" =~ \.json$ ]]; then
    echo -e "${YELLOW}⚠ Warning:${NC} Flow file doesn't have .json extension"
    if [ "$SKIP_CONFIRM" = false ]; then
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

# Validate JSON format if jq is available
if command -v jq &> /dev/null; then
    log_verbose "Validating JSON format of flow file..."
    if ! jq empty "$FLOW_FILE_PATH" 2>/dev/null; then
        echo -e "${YELLOW}⚠ Warning:${NC} Flow file may not be valid JSON"
        if [ "$SKIP_CONFIRM" = false ]; then
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    else
        log_verbose "JSON validation passed"
    fi
fi

# Set operation mode
FLOW_NAME="$ORIGINAL_FLOW_NAME"

# Only show banner if not quiet
if [ "$QUIET" = false ]; then
    # Display operation banner
    echo -e "${BOLD}${BLUE}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║         NiFi Flow Import Mode                          ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
fi

# Interactive mode if no URL provided
if [ "$INTERACTIVE" = true ]; then
    echo -e "${CYAN}${BOLD}Configuration:${NC}"
    read -p "$(echo -e ${WHITE}Enter NiFi URL ${GRAY}[default: https://idol-docker-host:8443]${NC}: )" NIFI_URL
    NIFI_URL=${NIFI_URL:-https://idol-docker-host:8443}
else
    # Set default URL if not provided
    NIFI_URL=${NIFI_URL:-https://idol-docker-host:8443}
fi

log_verbose "Using NiFi URL: $NIFI_URL"
echo -e "${GREEN}✓${NC} Using NiFi URL: ${BLUE}${NIFI_URL}${NC}\n"

# Handle authentication
if [ "$INTERACTIVE" = true ] && [ -z "$AUTH_METHOD" ]; then
    echo -e "${CYAN}${BOLD}Authentication Method:${NC}"
    echo -e "  ${YELLOW}1)${NC} Generate token using username/password"
    echo -e "  ${YELLOW}2)${NC} Provide existing token"
    read -p "$(echo -e ${WHITE}Enter choice ${GRAY}[1 or 2]${NC}: )" AUTH_CHOICE
    
    case $AUTH_CHOICE in
        1)
            AUTH_METHOD="password"
            ;;
        2)
            AUTH_METHOD="token"
            ;;
        *)
            echo -e "\n${RED}✗ Invalid choice.${NC} Exiting."
            exit 1
            ;;
    esac
fi

# Validate auth method
if [ -n "$AUTH_METHOD" ] && [ "$AUTH_METHOD" != "password" ] && [ "$AUTH_METHOD" != "token" ] && [ "$AUTH_METHOD" != "none" ]; then
    echo -e "${RED}✗ Error:${NC} Invalid authentication method: ${AUTH_METHOD}"
    echo -e "Valid options: ${WHITE}password${NC}, ${WHITE}token${NC}, ${WHITE}none${NC}"
    exit 1
fi

# Process authentication
case $AUTH_METHOD in
    password)
        if [ "$INTERACTIVE" = true ]; then
            echo -e "\n${CYAN}${BOLD}Credentials:${NC}"
            read -p "$(echo -e ${WHITE}Enter username ${GRAY}[default: admin]${NC}: )" USERNAME
            USERNAME=${USERNAME:-admin}
            
            read -sp "$(echo -e ${WHITE}Enter password ${GRAY}[default: Nifi-Admin1!]${NC}: )" PASSWORD
            echo ""
            PASSWORD=${PASSWORD:-Nifi-Admin1!}
        else
            USERNAME=${USERNAME:-admin}
            PASSWORD=${PASSWORD:-Nifi-Admin1!}
        fi
        
        log_verbose "Generating token with username: $USERNAME"
        echo -e "\n${YELLOW}⟳${NC} Generating authentication token..."
        
        TOKEN=$(curl -k -s --max-time 30 -X POST "${NIFI_URL}/nifi-api/access/token" \
          -H "Content-Type: application/x-www-form-urlencoded" \
          -d "username=${USERNAME}&password=${PASSWORD}")
        
        TOKEN=$(echo "$TOKEN" | tr -d '\n')
        
        if [ -z "$TOKEN" ] || [[ "$TOKEN" == *"Unable to generate access token"* ]]; then
            echo -e "${RED}✗ Error:${NC} Failed to generate token. Please check your credentials."
            exit 4
        fi
        
        log_verbose "Token generated successfully"
        echo -e "${GREEN}✓${NC} Token generated successfully!"
        ;;
        
    token)
        if [ "$INTERACTIVE" = true ] && [ -z "$TOKEN" ]; then
            echo -e "\n${CYAN}${BOLD}Token:${NC}"
            read -p "$(echo -e ${WHITE}Enter Authorization Token${NC}: )" TOKEN
        fi
        
        if [ -z "$TOKEN" ]; then
            echo -e "${RED}✗ Error:${NC} Token cannot be empty!"
            exit 1
        fi
        
        log_verbose "Using provided token"
        echo -e "${GREEN}✓${NC} Token accepted"
        ;;
        
    none)
        echo -e "\n${YELLOW}⚠${NC} Proceeding without authentication..."
        TOKEN=""
        ;;
        
    *)
        # Default to password authentication
        USERNAME=${USERNAME:-admin}
        PASSWORD=${PASSWORD:-Nifi-Admin1!}
        
        log_verbose "Defaulting to password authentication"
        echo -e "${YELLOW}⟳${NC} Generating authentication token..."
        
        TOKEN=$(curl -k -s --max-time 30 -X POST "${NIFI_URL}/nifi-api/access/token" \
          -H "Content-Type: application/x-www-form-urlencoded" \
          -d "username=${USERNAME}&password=${PASSWORD}")
        
        TOKEN=$(echo "$TOKEN" | tr -d '\n')
        
        if [ -z "$TOKEN" ] || [[ "$TOKEN" == *"Unable to generate access token"* ]]; then
            echo -e "${RED}✗ Error:${NC} Failed to generate token."
            exit 4
        fi
        
        echo -e "${GREEN}✓${NC} Token generated"
        ;;
esac

# Function to print step header
print_step() {
    local step_num="$1"
    local total_steps="$2"
    local message="$3"
    if [ "$QUIET" = false ]; then
        echo -e "${PURPLE}╔════════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║ [Step $step_num/$total_steps] $message${NC}"
        echo -e "${PURPLE}╚════════════════════════════════════════╝${NC}"
        echo ""
    fi
}

# Function to get revision number
get_revision() {
    local pg_id="$1"
    log_verbose "Getting revision for process group: $pg_id"
    
    local pg_details=$(curl -k -s --max-time 30 -H "Authorization: Bearer $TOKEN" \
      "${NIFI_URL}/nifi-api/process-groups/${pg_id}")
    
    local revision=$(echo "$pg_details" | grep -o '"version":[0-9]*' | head -1 | cut -d':' -f2)
    
    if [ -z "$revision" ]; then
        revision=0
    fi
    
    log_verbose "Revision for $pg_id: $revision"
    echo "$revision"
}

# Function to check if process group name exists
check_pg_name_exists() {
    local name_to_check="$1"
    log_verbose "Checking if process group exists with name: $name_to_check"
    
    local root_pg=$(curl -k -s --max-time 30 -H "Authorization: Bearer $TOKEN" \
      "${NIFI_URL}/nifi-api/flow/process-groups/root")
    
    if command -v jq &> /dev/null; then
        local pg_id=$(echo "$root_pg" | jq -r --arg name "$name_to_check" '.processGroupFlow.flow.processGroups[] | select(.component.name == $name) | .id' | head -1)
        log_verbose "jq result for $name_to_check: $pg_id"
        echo "$pg_id"
    else
        local pg_id=$(echo "$root_pg" | grep -o "\"component\":{[^}]*\"name\":\"${name_to_check}\"[^}]*\"id\":\"[^\"]*\"" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | head -1)
        log_verbose "grep result for $name_to_check: $pg_id"
        echo "$pg_id"
    fi
}

# Function to find available flow name
find_available_flow_name() {
    local base_name="$1"
    local new_name="$base_name"
    local counter=1
    
    log_verbose "Finding available name for: $base_name"
    
    while [ -n "$(check_pg_name_exists "$new_name")" ]; do
        new_name="${base_name}_${counter}"
        counter=$((counter + 1))
    done
    
    log_verbose "Available name found: $new_name"
    echo "$new_name"
}

# Display flow details
if [ "$QUIET" = false ]; then
    echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           NiFi Flow Import Process                ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}┌────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ Flow Details                                   │${NC}"
    echo -e "${CYAN}├────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│ Flow File:   ${YELLOW}$FLOW_FILE_PATH${NC}"
    echo -e "${CYAN}│ Flow Name:   ${YELLOW}$ORIGINAL_FLOW_NAME${NC}"
    echo -e "${CYAN}│ Disable:     ${YELLOW}$DISABLE_FLOW${NC}"
    echo -e "${CYAN}│ Position:    ${YELLOW}($POSITION_X, $POSITION_Y)${NC}"
    echo -e "${CYAN}│ NiFi Host:   ${YELLOW}$NIFI_URL${NC}"
    echo -e "${CYAN}└────────────────────────────────────────────────┘${NC}"
    echo ""
fi

# Step 1: Check if flow file exists
print_step "1" "7" "Checking if flow file exists..."
if [ ! -f "$FLOW_FILE_PATH" ]; then
    echo -e "${RED}✗${NC} Flow file not found at $FLOW_FILE_PATH"
    exit 3
fi
echo -e "${GREEN}✓${NC} Flow file found"
echo ""

# Step 2: Validate NiFi API is accessible
print_step "2" "7" "Validating NiFi API accessibility..."
log_verbose "Checking NiFi API at: ${NIFI_URL}/nifi-api/flow/about"
API_CHECK=$(curl -k -s --max-time 30 -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $TOKEN" \
  "${NIFI_URL}/nifi-api/flow/about")

log_verbose "API check HTTP code: $API_CHECK"

if [ "$API_CHECK" != "200" ]; then
    echo -e "${RED}✗${NC} Unable to access NiFi API (HTTP $API_CHECK)"
    if [ "$API_CHECK" = "000" ]; then
        echo -e "  ${RED}Possible causes:${NC}"
        echo -e "  • NiFi server is down"
        echo -e "  • Network connectivity issues"
        echo -e "  • Invalid URL: $NIFI_URL"
        echo -e "  • SSL certificate issues (try with -k flag if using self-signed cert)"
    elif [ "$API_CHECK" = "401" ]; then
        echo -e "  ${RED}Authentication failed${NC}"
        echo -e "  • Check your credentials/token"
        echo -e "  • Verify authentication method"
    fi
    exit 5
fi
echo -e "${GREEN}✓${NC} NiFi API is accessible"
echo ""

# Step 3: Check if a process group with the same name already exists
print_step "3" "7" "Checking for existing flow with the same name..."
EXISTING_PG_ID=$(check_pg_name_exists "$ORIGINAL_FLOW_NAME")
log_verbose "Existing PG ID for '$ORIGINAL_FLOW_NAME': $EXISTING_PG_ID"

DELETE_EXISTING=false
FLOW_NAME_UPDATED=false
if [ -n "$EXISTING_PG_ID" ]; then
    if [ "$QUIET" = false ]; then
        echo -e "${ORANGE}╔════════════════════════════════════════════════════╗${NC}"
        echo -e "${ORANGE}║                Duplicate Flow Detected              ║${NC}"
        echo -e "${ORANGE}╚════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${ORANGE}A process group named '${RED}$ORIGINAL_FLOW_NAME${ORANGE}' already exists!${NC}"
        echo -e "${ORANGE}Process Group ID: ${RED}$EXISTING_PG_ID${NC}"
        echo ""
    else
        echo -e "${ORANGE}⚠ Duplicate flow detected: $ORIGINAL_FLOW_NAME${NC}"
    fi
    
    if [ "$OVERWRITE" = true ] && [ "$SKIP_CONFIRM" = true ]; then
        DELETE_EXISTING=true
        log_verbose "Overwrite mode enabled, will delete existing flow"
        echo -e "${YELLOW}⚠${NC} Overwrite mode enabled - will delete existing flow"
    elif [ "$AUTO_RENAME" = true ] && [ "$SKIP_CONFIRM" = true ]; then
        NEW_FLOW_NAME=$(find_available_flow_name "$ORIGINAL_FLOW_NAME")
        FLOW_NAME="$NEW_FLOW_NAME"
        FLOW_NAME_UPDATED=true
        log_verbose "Auto-rename enabled, new name: $FLOW_NAME"
        echo -e "${YELLOW}⚠${NC} Auto-rename enabled - will import as: $FLOW_NAME"
    elif [ "$SKIP_CONFIRM" = false ]; then
        echo -e "${YELLOW}What would you like to do?${NC}"
        echo -e "${CYAN}1) Delete the existing flow and upload the new one${NC}"
        echo -e "${CYAN}2) Keep the existing flow and upload alongside it${NC}"
        echo -e "${CYAN}3) Cancel the upload${NC}"
        echo ""
        
        read -p "Enter your choice (1-3): " CHOICE
        
        case $CHOICE in
            1)
                DELETE_EXISTING=true
                log_verbose "User chose to delete existing flow"
                echo -e "${YELLOW}⟳${NC} Will delete existing process group before upload..."
                ;;
            2)
                log_verbose "User chose to keep existing flow"
                echo -e "${YELLOW}⟳${NC} Keeping existing flow and finding available name..."
                NEW_FLOW_NAME=$(find_available_flow_name "$ORIGINAL_FLOW_NAME")
                FLOW_NAME="$NEW_FLOW_NAME"
                FLOW_NAME_UPDATED=true
                echo -e "${GREEN}✓${NC} Flow name updated to: $FLOW_NAME"
                ;;
            3)
                log_verbose "User cancelled upload"
                echo -e "${GREEN}✓${NC} Upload cancelled by user."
                exit 0
                ;;
            *)
                echo -e "${RED}✗${NC} Invalid choice. Defaulting to keep existing flow."
                NEW_FLOW_NAME=$(find_available_flow_name "$ORIGINAL_FLOW_NAME")
                FLOW_NAME="$NEW_FLOW_NAME"
                FLOW_NAME_UPDATED=true
                echo -e "${GREEN}✓${NC} Flow name updated to: $FLOW_NAME"
                ;;
        esac
    else
        # Default behavior if skip confirm is true but no mode specified
        NEW_FLOW_NAME=$(find_available_flow_name "$ORIGINAL_FLOW_NAME")
        FLOW_NAME="$NEW_FLOW_NAME"
        FLOW_NAME_UPDATED=true
        log_verbose "Default auto-rename to: $FLOW_NAME"
        echo -e "${YELLOW}⚠${NC} Auto-renaming to: $FLOW_NAME"
    fi
else
    log_verbose "No existing flow found with name: $ORIGINAL_FLOW_NAME"
    echo -e "${GREEN}✓${NC} No existing flow with this name found"
fi
echo ""

# Step 4: Delete existing flow if requested
if [ "$DELETE_EXISTING" = true ] && [ -n "$EXISTING_PG_ID" ]; then
    print_step "4" "7" "Deleting existing process group..."
    
    REVISION=$(get_revision "$EXISTING_PG_ID")
    echo -e "${CYAN}Current revision: ${YELLOW}$REVISION${NC}"
    
    log_verbose "Deleting process group $EXISTING_PG_ID with revision $REVISION"
    DELETE_RESPONSE=$(curl -k -s --max-time 30 -w "\n%{http_code}" -X DELETE \
      "${NIFI_URL}/nifi-api/process-groups/${EXISTING_PG_ID}?version=${REVISION}&disconnectedNodeAcknowledged=false" \
      -H "Authorization: Bearer $TOKEN")
    
    DELETE_HTTP_CODE="${DELETE_RESPONSE##*$'\n'}"
    DELETE_BODY="${DELETE_RESPONSE%$'\n'*}"
    
    log_verbose "Delete response code: $DELETE_HTTP_CODE"
    
    if [ "$DELETE_HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}✓${NC} Existing process group deleted successfully"
    else
        echo -e "${RED}✗${NC} Failed to delete existing process group (HTTP $DELETE_HTTP_CODE)"
        echo "Response: $DELETE_BODY"
        exit 1
    fi
    echo ""
fi

# Step 5: Upload flow
STEP_NUM=$([ "$DELETE_EXISTING" = true ] && echo "5" || echo "4")
print_step "$STEP_NUM" "7" "Uploading flow to NiFi..."

if [ "$FLOW_NAME_UPDATED" = true ]; then
    echo -e "${CYAN}Original name:${NC} $ORIGINAL_FLOW_NAME"
    echo -e "${CYAN}Uploading as:${NC} $FLOW_NAME"
else
    echo -e "${CYAN}Uploading as:${NC} $FLOW_NAME"
fi

# Generate client ID if not provided
if [ -z "$CLIENT_ID" ]; then
    CLIENT_ID="nifi-upload-$(date +%s%N | cut -c1-13)"
fi

echo -e "${CYAN}Client ID: ${YELLOW}$CLIENT_ID${NC}"
echo -e "${YELLOW}⟳${NC} Starting upload process..."

log_verbose "Uploading file $FLOW_FILE_PATH with name $FLOW_NAME"
log_verbose "Position: ($POSITION_X, $POSITION_Y), Comments: $COMMENTS"

UPLOAD_RESPONSE=$(curl -k -s --max-time 60 -w "\n%{http_code}" -X POST \
  "${NIFI_URL}/nifi-api/process-groups/root/process-groups/upload" \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@${FLOW_FILE_PATH}" \
  -F "groupName=${FLOW_NAME}" \
  -F "comments=${COMMENTS}" \
  -F "positionX=${POSITION_X}" \
  -F "positionY=${POSITION_Y}" \
  -F "clientId=${CLIENT_ID}")

UPLOAD_HTTP_CODE="${UPLOAD_RESPONSE##*$'\n'}"
UPLOAD_BODY="${UPLOAD_RESPONSE%$'\n'*}"

log_verbose "Upload response code: $UPLOAD_HTTP_CODE"

if [ "$UPLOAD_HTTP_CODE" != "201" ] && [ "$UPLOAD_HTTP_CODE" != "200" ]; then
    echo -e "${RED}✗${NC} Failed to upload flow (HTTP $UPLOAD_HTTP_CODE)"
    echo "Response: $UPLOAD_BODY"
    exit 6
fi

PROCESS_GROUP_ID=$(echo "$UPLOAD_BODY" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$PROCESS_GROUP_ID" ]; then
    echo -e "${RED}✗${NC} Could not extract process group ID from response"
    exit 6
fi

log_verbose "Process Group ID: $PROCESS_GROUP_ID"
echo -e "${GREEN}✓${NC} Flow uploaded successfully"
echo -e "${CYAN}Process Group ID: ${YELLOW}$PROCESS_GROUP_ID${NC}"
echo ""

# Wait for process group to initialize
echo -e "${YELLOW}⟳${NC} Waiting for process group initialization..."
sleep 3

# Step 6: Disable the process group if requested
if [ "$DISABLE_FLOW" = true ]; then
    STEP_NUM=$([ "$DELETE_EXISTING" = true ] && echo "6" || echo "5")
    print_step "$STEP_NUM" "7" "Disabling the imported process group..."
    
    REVISION=$(get_revision "$PROCESS_GROUP_ID")
    echo -e "${CYAN}Current revision: ${YELLOW}$REVISION${NC}"
    
    # Method 1: Try to disable using process-groups API
    echo -e "${YELLOW}⟳${NC} Attempting to disable process group..."
    
    log_verbose "Disabling process group $PROCESS_GROUP_ID with revision $REVISION"
    DISABLE_RESPONSE=$(curl -k -s --max-time 30 -w "\n%{http_code}" -X PUT \
      "${NIFI_URL}/nifi-api/process-groups/${PROCESS_GROUP_ID}" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "{
        \"revision\": {
          \"clientId\": \"${CLIENT_ID}-disable\",
          \"version\": ${REVISION}
        },
        \"component\": {
          \"id\": \"${PROCESS_GROUP_ID}\",
          \"state\": \"DISABLED\"
        }
      }")
    
    DISABLE_HTTP_CODE="${DISABLE_RESPONSE##*$'\n'}"
    DISABLE_BODY="${DISABLE_RESPONSE%$'\n'*}"
    
    log_verbose "Disable response code: $DISABLE_HTTP_CODE"
    
    if [ "$DISABLE_HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}✓${NC} Disable request accepted"
        
        sleep 2
        
        PG_DETAILS=$(curl -k -s --max-time 30 -H "Authorization: Bearer $TOKEN" \
          "${NIFI_URL}/nifi-api/process-groups/${PROCESS_GROUP_ID}")
        
        CURRENT_STATE=$(echo "$PG_DETAILS" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
        
        log_verbose "Current state after disable attempt: $CURRENT_STATE"
        
        if [ "$CURRENT_STATE" = "DISABLED" ]; then
            echo -e "${GREEN}✓${NC} Verified: Process group is DISABLED"
        else
            echo -e "${YELLOW}⚠${NC} Process group state is: $CURRENT_STATE"
            
            echo -e "${YELLOW}⟳${NC} Trying alternative disable method..."
            ALT_RESPONSE=$(curl -k -s --max-time 30 -w "\n%{http_code}" -X PUT \
              "${NIFI_URL}/nifi-api/flow/process-groups/${PROCESS_GROUP_ID}" \
              -H "Authorization: Bearer $TOKEN" \
              -H "Content-Type: application/json" \
              -d "{
                \"id\": \"${PROCESS_GROUP_ID}\",
                \"state\": \"DISABLED\",
                \"disconnectedNodeAcknowledged\": false
              }")
            
            ALT_HTTP_CODE="${ALT_RESPONSE##*$'\n'}"
            
            log_verbose "Alternative disable response code: $ALT_HTTP_CODE"
            
            if [ "$ALT_HTTP_CODE" = "200" ]; then
                echo -e "${GREEN}✓${NC} Disabled using alternative method"
            else
                echo -e "${YELLOW}⚠${NC} Could not disable using alternative method"
            fi
        fi
    else
        echo -e "${YELLOW}⚠${NC} Could not disable process group (HTTP $DISABLE_HTTP_CODE)"
        
        echo -e "${YELLOW}⟳${NC} Trying direct flow API method..."
        
        ALT2_RESPONSE=$(curl -k -s --max-time 30 -w "\n%{http_code}" -X PUT \
          "${NIFI_URL}/nifi-api/flow/process-groups/${PROCESS_GROUP_ID}" \
          -H "Authorization: Bearer $TOKEN" \
          -H "Content-Type: application/json" \
          -d "{
            \"id\": \"${PROCESS_GROUP_ID}\",
            \"state\": \"DISABLED\",
            \"disconnectedNodeAcknowledged\": false
          }")
        
        ALT2_HTTP_CODE="${ALT2_RESPONSE##*$'\n'}"
        
        log_verbose "Direct flow API disable response code: $ALT2_HTTP_CODE"
        
        if [ "$ALT2_HTTP_CODE" = "200" ]; then
            echo -e "${GREEN}✓${NC} Disabled using direct flow API method"
        else
            echo -e "${YELLOW}⚠${NC} All disable methods failed"
            echo -e "${YELLOW}⚠${NC} You may need to disable it manually from the NiFi UI"
        fi
    fi
    echo ""
fi

# Step 7: Final verification
STEP_NUM=$([ "$DELETE_EXISTING" = true ] && [ "$DISABLE_FLOW" = true ] && echo "7" || \
          [ "$DELETE_EXISTING" = true ] && echo "6" || \
          [ "$DISABLE_FLOW" = true ] && echo "6" || echo "5")

print_step "$STEP_NUM" "7" "Performing final verification..."

PG_DETAILS=$(curl -k -s --max-time 30 -H "Authorization: Bearer $TOKEN" \
  "${NIFI_URL}/nifi-api/process-groups/${PROCESS_GROUP_ID}")

FINAL_STATE=$(echo "$PG_DETAILS" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
FINAL_STATE=${FINAL_STATE:-"UNKNOWN"}

log_verbose "Final process group state: $FINAL_STATE"

# Summary
if [ "$QUIET" = false ]; then
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         Flow Import Summary                        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}┌────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ Import Details                                 │${NC}"
    echo -e "${CYAN}├────────────────────────────────────────────────┤${NC}"
    if [ "$FLOW_NAME_UPDATED" = true ]; then
        echo -e "${CYAN}│ ${YELLOW}Original Name:${NC}  $ORIGINAL_FLOW_NAME"
        echo -e "${CYAN}│ ${YELLOW}Uploaded As:${NC}    $FLOW_NAME"
    else
        echo -e "${CYAN}│ ${YELLOW}Flow Name:${NC}      $FLOW_NAME"
    fi
    echo -e "${CYAN}│ ${YELLOW}Flow File:${NC}       $FLOW_FILE_PATH"
    echo -e "${CYAN}│ ${YELLOW}Process Group ID:${NC} $PROCESS_GROUP_ID"
    echo -e "${CYAN}│ ${YELLOW}Final State:${NC}     $FINAL_STATE"
    echo -e "${CYAN}│ ${YELLOW}NiFi URL:${NC}        ${NIFI_URL}/nifi/"
    echo -e "${CYAN}└────────────────────────────────────────────────┘${NC}"
    echo ""
    
    # Direct access link
    echo -e "${BLUE}Direct Access Link:${NC}"
    echo -e "${YELLOW}${NIFI_URL}/nifi/?processGroupId=${PROCESS_GROUP_ID}${NC}"
    echo ""
    
    # Final message based on state
    if [ "$FINAL_STATE" = "DISABLED" ]; then
        echo -e "${GREEN}✅ SUCCESS: The flow was imported and is DISABLED${NC}"
        echo "The imported flow is disabled and ready for configuration."
    elif [ "$FINAL_STATE" = "STOPPED" ]; then
        echo -e "${YELLOW}⚠ NOTE: The flow was imported and is STOPPED${NC}"
        echo "The flow is stopped but not disabled. You may want to disable it from the NiFi UI."
    else
        echo -e "${ORANGE}⚠ ATTENTION: The flow was imported but is in '$FINAL_STATE' state${NC}"
        if [ "$FINAL_STATE" != "DISABLED" ]; then
            echo "You may need to disable it manually from the NiFi UI."
        fi
    fi
    
    # Show warning if name was changed
    if [ "$FLOW_NAME_UPDATED" = true ]; then
        echo ""
        echo -e "${YELLOW}────────────────────────────────────────────────────${NC}"
        echo -e "${YELLOW}⚠ NOTE: Flow name was changed to avoid conflict${NC}"
        echo -e "${YELLOW}   Original: $ORIGINAL_FLOW_NAME${NC}"
        echo -e "${YELLOW}   Uploaded as: $FLOW_NAME${NC}"
        echo -e "${YELLOW}────────────────────────────────────────────────────${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}            Import Process Complete                   ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
else
    # Quiet mode output
    echo -e "${GREEN}✓${NC} Flow import completed: $FLOW_NAME -> $PROCESS_GROUP_ID ($FINAL_STATE)"
fi

log_verbose "Script execution completed successfully"
exit 0