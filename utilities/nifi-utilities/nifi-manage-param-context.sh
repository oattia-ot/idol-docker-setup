#!/bin/bash

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

# Function to display usage
usage() {
    echo -e "${BOLD}${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                   NiFi Parameter Context Manager                           ║"
    echo "║                              Help Documentation                            ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    
    echo -e "${BOLD}${CYAN}SYNOPSIS${NC}"
    echo -e "  $0 [OPTIONS]"
    echo -e "  $0 [OPTIONS] <context_name> [description] [json_file]\n"
    
    echo -e "${BOLD}${CYAN}DESCRIPTION${NC}"
    echo -e "  Creates, deletes, or lists parameter contexts in Apache NiFi."
    echo -e "  Supports both interactive parameter entry and bulk import from JSON files.\n"
    
    echo -e "${BOLD}${CYAN}OPTIONS${NC}"
    echo -e "  ${YELLOW}--help, -h${NC}              Display this help message and exit"
    echo -e "  ${YELLOW}--url, -u${NC} URL           NiFi URL (default: https://idol-docker-host:8443)"
    echo -e "  ${YELLOW}--auth, -a${NC} METHOD       Authentication method: ${WHITE}password${NC}|${WHITE}token${NC}|${WHITE}none${NC}"
    echo -e "  ${YELLOW}--username, -U${NC} USER     Username for password authentication (default: admin)"
    echo -e "  ${YELLOW}--password, -P${NC} PASS     Password for password authentication (default: OpenText2026!)"
    echo -e "  ${YELLOW}--token, -t${NC} TOKEN       Bearer token for token authentication"
    echo -e "  ${YELLOW}--list, -l${NC}              List all parameter contexts and exit"
    echo -e "  ${YELLOW}--output, -o${NC} FORMAT     Output format for list: ${WHITE}table${NC}|${WHITE}json${NC}|${WHITE}csv${NC} (default: table)"
    echo -e "  ${YELLOW}--create, -C${NC}            Create parameter context in batch mode"
    echo -e "  ${YELLOW}--delete, -D${NC}            Delete parameter context(s) in batch mode"
    echo -e "  ${YELLOW}--delete-all${NC}            Delete ALL parameter contexts (use with caution!)"
    echo -e "  ${YELLOW}--context-id${NC} ID         Specific context ID to delete (use with -D)"
    echo -e "  ${YELLOW}--name, -n${NC} NAME         Context name for create mode (use with -C)"
    echo -e "  ${YELLOW}--description, -d${NC} DESC  Description for create mode (use with -C)"
    echo -e "  ${YELLOW}--file, -f${NC} FILE         File containing:"
    echo -e "                        • Context names/IDs for delete (with -D)"
    echo -e "                        • JSON parameters for create (with -C)"
    echo -e "  ${YELLOW}--yes, -y${NC}               Skip confirmation prompts in batch mode\n"
    
    echo -e "${BOLD}${CYAN}ARGUMENTS${NC}"
    echo -e "  context_name        (Alternative to --name) Name of parameter context to create"
    echo -e "  description         (Alternative to --description) Description of parameter context"
    echo -e "                      Default: \"Parameter context created via API\""
    echo -e "  json_file           (Alternative to --file) Path to JSON file containing parameters"
    echo -e "                      If not provided, enters interactive mode\n"
    
    echo -e "${BOLD}${CYAN}USAGE MODES${NC}\n"
    
    echo -e "${BOLD}${YELLOW}1. Interactive Create Mode${NC}"
    echo -e "  Prompts you to enter parameters one by one:\n"
    echo -e "  ${GRAY}\$ $0 \"Database Config\" \"DB connection parameters\"${NC}"
    echo -e "  ${GRAY}\$ $0 -C -n \"Database Config\" -d \"DB connection parameters\"${NC}\n"
    echo -e "  You will be prompted for each parameter's:"
    echo -e "    - Name"
    echo -e "    - Description"
    echo -e "    - Value"
    echo -e "    - Sensitivity (y/n)\n"
    
    echo -e "${BOLD}${YELLOW}2. JSON File Create Mode${NC}"
    echo -e "  Loads parameters from a JSON file:\n"
    echo -e "  ${GRAY}\$ $0 \"Database Config\" \"DB params\" ./params.json${NC}"
    echo -e "  ${GRAY}\$ $0 -C -n \"Database Config\" -d \"DB params\" -f ./params.json${NC}\n"
    
    echo -e "${BOLD}${YELLOW}3. List Mode${NC}"
    echo -e "  List all parameter contexts:\n"
    echo -e "  ${GRAY}\$ $0 -l${NC}"
    echo -e "  ${GRAY}\$ $0 -l -o json${NC}"
    echo -e "  ${GRAY}\$ $0 -l -o csv${NC}\n"
    
    echo -e "${BOLD}${YELLOW}4. Delete Mode${NC}"
    echo -e "  Delete specific context(s):\n"
    echo -e "  ${GRAY}\$ $0 -D --context-id \"context-id-here\"${NC}"
    echo -e "  ${GRAY}\$ $0 -D -f contexts_to_delete.txt${NC}"
    echo -e "  ${GRAY}\$ $0 --delete-all${NC}\n"
    
    echo -e "${BOLD}${CYAN}JSON FILE FORMAT${NC}\n"
    
    echo -e "  The JSON file must contain an array of parameter objects:\n"
    echo -e "  ${GRAY}["
    echo -e "    {"
    echo -e "      \"parameter\": {"
    echo -e "        \"name\": \"database_url\","
    echo -e "        \"description\": \"Database connection URL\","
    echo -e "        \"sensitive\": false,"
    echo -e "        \"value\": \"jdbc:postgresql://localhost:5432/mydb\""
    echo -e "      }"
    echo -e "    },"
    echo -e "    {"
    echo -e "      \"parameter\": {"
    echo -e "        \"name\": \"database_password\","
    echo -e "        \"description\": \"Database password\","
    echo -e "        \"sensitive\": true,"
    echo -e "        \"value\": \"secretPassword123\""
    echo -e "      }"
    echo -e "    }"
    echo -e "  ]${NC}\n"
    
    echo -e "${BOLD}${CYAN}EXAMPLES${NC}\n"
    
    echo -e "  ${GRAY}# Interactive mode with default description${NC}"
    echo -e "  $0 \"My Parameters\"\n"
    
    echo -e "  ${GRAY}# Interactive mode with custom description${NC}"
    echo -e "  $0 \"Database Config\" \"Production database settings\"\n"
    
    echo -e "  ${GRAY}# JSON file mode${NC}"
    echo -e "  $0 \"API Config\" \"API keys and endpoints\" ./api_params.json\n"
    
    echo -e "  ${GRAY}# Using --create option${NC}"
    echo -e "  $0 -C -n \"MyConfig\" -d \"My description\" -f ./params.json\n"
    
    echo -e "  ${GRAY}# List all contexts in table format${NC}"
    echo -e "  $0 -l\n"
    
    echo -e "  ${GRAY}# List all contexts in JSON format${NC}"
    echo -e "  $0 -l -o json\n"
    
    echo -e "  ${GRAY}# List all contexts in CSV format${NC}"
    echo -e "  $0 -l -o csv\n"
    
    echo -e "  ${GRAY}# Delete specific context by ID${NC}"
    echo -e "  $0 -D --context-id \"abc123-xyz456\"\n"
    
    echo -e "  ${GRAY}# Delete contexts from file${NC}"
    echo -e "  $0 -D -f contexts_to_delete.txt\n"
    
    echo -e "  ${GRAY}# Delete ALL contexts (caution!)${NC}"
    echo -e "  $0 --delete-all -y\n"
    
    echo -e "  ${GRAY}# Using password authentication${NC}"
    echo -e "  $0 -u https://idol-docker-host:8443 -a password -U admin -P OpenText2026! -l\n"
    
    echo -e "  ${GRAY}# Using token authentication${NC}"
    echo -e "  $0 -u https://idol-docker-host:8443 -a token -t eyJhbGc... -D --context-id \"abc123\"\n"
    
    echo -e "${BOLD}${CYAN}CONFIGURATION${NC}\n"
    
    echo -e "  Default NiFi connection settings:\n"
    echo -e "  ${CYAN}NIFI_URL${NC}      = https://idol-docker-host:8443"
    echo -e "  ${CYAN}USERNAME${NC}      = admin"
    echo -e "  ${CYAN}PASSWORD${NC}      = OpenText2026!\n"
    
    echo -e "${BOLD}${CYAN}REQUIREMENTS${NC}\n"
    
    echo -e "  - ${WHITE}curl${NC} (required)"
    echo -e "  - ${WHITE}jq${NC} (recommended for JSON validation and parsing)"
    
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
CREATE_MODE=false
DELETE_MODE=false
DELETE_ALL=false
OUTPUT_FORMAT="table"
CONTEXT_ID=""
CONTEXT_NAME=""
CONTEXT_DESCRIPTION=""
CONTEXT_FILE=""
SKIP_CONFIRM=false
JSON_FILE=""
ORIGINAL_CONTEXT_NAME=""
ORIGINAL_CONTEXT_DESCRIPTION=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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
        -l|--list)
            LIST_ONLY=true
            INTERACTIVE=false
            shift
            ;;
        -o|--output)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -C|--create)
            CREATE_MODE=true
            INTERACTIVE=false
            shift
            ;;
        -D|--delete)
            DELETE_MODE=true
            INTERACTIVE=false
            shift
            ;;
        --delete-all)
            DELETE_ALL=true
            DELETE_MODE=true
            INTERACTIVE=false
            shift
            ;;
        --context-id)
            CONTEXT_ID="$2"
            shift 2
            ;;
        -n|--name)
            CONTEXT_NAME="$2"
            shift 2
            ;;
        -d|--description)
            CONTEXT_DESCRIPTION="$2"
            shift 2
            ;;
        -f|--file)
            CONTEXT_FILE="$2"
            shift 2
            ;;
        -y|--yes)
            SKIP_CONFIRM=true
            shift
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
            # Positional arguments (backward compatibility)
            if [ -z "$ORIGINAL_CONTEXT_NAME" ]; then
                ORIGINAL_CONTEXT_NAME="$1"
            elif [ -z "$ORIGINAL_CONTEXT_DESCRIPTION" ]; then
                ORIGINAL_CONTEXT_DESCRIPTION="$1"
            elif [ -z "$JSON_FILE" ]; then
                JSON_FILE="$1"
            fi
            shift
            ;;
    esac
done

# CHECK 1: Prevent execution without any operation specified
if [ "$LIST_ONLY" = false ] && [ "$CREATE_MODE" = false ] && [ "$DELETE_MODE" = false ] && [ -z "$ORIGINAL_CONTEXT_NAME" ] && [ -z "$CONTEXT_NAME" ]; then
    echo -e "${RED}✗ Error:${NC} No operation specified."
    echo -e "Please specify an operation: --list, --create, --delete, or provide a context name."
    echo -e "Use $0 --help for usage information."
    exit 1
fi

# Validate output format
if [ "$OUTPUT_FORMAT" != "table" ] && [ "$OUTPUT_FORMAT" != "json" ] && [ "$OUTPUT_FORMAT" != "csv" ]; then
    echo -e "${RED}✗ Error:${NC} Invalid output format: ${OUTPUT_FORMAT}"
    echo -e "Valid options: ${WHITE}table${NC}, ${WHITE}json${NC}, ${WHITE}csv${NC}"
    exit 1
fi

# Validate mode combinations
if [ "$CREATE_MODE" = true ] && [ "$DELETE_MODE" = true ]; then
    echo -e "${RED}✗ Error:${NC} Cannot use both --create and --delete options together"
    exit 1
fi

if [ "$CREATE_MODE" = true ] && [ "$LIST_ONLY" = true ]; then
    echo -e "${RED}✗ Error:${NC} Cannot use both --create and --list options together"
    exit 1
fi

if [ "$DELETE_MODE" = true ] && [ "$LIST_ONLY" = true ]; then
    echo -e "${RED}✗ Error:${NC} Cannot use both --delete and --list options together"
    exit 1
fi

if [ "$DELETE_ALL" = true ] && [ -n "$CONTEXT_ID" ]; then
    echo -e "${RED}✗ Error:${NC} Cannot specify --context-id with --delete-all"
    exit 1
fi

if [ "$DELETE_ALL" = true ] && [ -n "$CONTEXT_FILE" ]; then
    echo -e "${RED}✗ Error:${NC} Cannot specify --file with --delete-all"
    exit 1
fi

if [ "$CREATE_MODE" = true ] && [ -n "$CONTEXT_ID" ]; then
    echo -e "${RED}✗ Error:${NC} Cannot specify --context-id with --create"
    exit 1
fi

# Determine operation mode
if [ "$LIST_ONLY" = true ]; then
    OPERATION_MODE="list"
elif [ "$DELETE_MODE" = true ]; then
    OPERATION_MODE="delete"
elif [ "$CREATE_MODE" = true ] || [ -n "$ORIGINAL_CONTEXT_NAME" ] || [ -n "$CONTEXT_NAME" ] || [ -n "$JSON_FILE" ] || [ -n "$CONTEXT_DESCRIPTION" ] || [ -n "$ORIGINAL_CONTEXT_DESCRIPTION" ]; then
    OPERATION_MODE="create"
else
    OPERATION_MODE="interactive"
fi

# Merge positional and option arguments for create mode
if [ "$OPERATION_MODE" = "create" ]; then
    # Use command line options if provided, otherwise use positional arguments
    if [ -n "$CONTEXT_NAME" ]; then
        ORIGINAL_CONTEXT_NAME="$CONTEXT_NAME"
    fi
    
    if [ -n "$CONTEXT_DESCRIPTION" ]; then
        ORIGINAL_CONTEXT_DESCRIPTION="$CONTEXT_DESCRIPTION"
    fi
    
    if [ -n "$CONTEXT_FILE" ]; then
        JSON_FILE="$CONTEXT_FILE"
    fi
    
    # Set description
    if [ -n "$ORIGINAL_CONTEXT_DESCRIPTION" ]; then
        CONTEXT_DESCRIPTION="$ORIGINAL_CONTEXT_DESCRIPTION"
    fi
fi

# Display operation banner
case "$OPERATION_MODE" in
    create)
        echo -e "${BOLD}${GREEN}"
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║         CREATE Parameter Context Mode                  ║"
        echo "╚════════════════════════════════════════════════════════╝"
        echo -e "${NC}\n"
        ;;
    delete)
        echo -e "${BOLD}${RED}"
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║         DELETE Parameter Context Mode                  ║"
        echo "╚════════════════════════════════════════════════════════╝"
        echo -e "${NC}\n"
        ;;
    list)
        echo -e "${BOLD}${BLUE}"
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║         LIST Parameter Context Mode                    ║"
        echo "╚════════════════════════════════════════════════════════╝"
        echo -e "${NC}\n"
        ;;
    interactive)
        echo -e "${BOLD}${CYAN}"
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║         INTERACTIVE Parameter Context Mode             ║"
        echo "╚════════════════════════════════════════════════════════╝"
        echo -e "${NC}\n"
        ;;
esac

# Validate operation requirements
if [ "$OPERATION_MODE" = "create" ] && [ -z "$ORIGINAL_CONTEXT_NAME" ]; then
    echo -e "${RED}✗ Error:${NC} Context name is required for create mode"
    echo -e "Use: $0 <context_name> [description] [json_file]"
    echo -e "Or:  $0 -C -n <context_name> [-d description] [-f json_file]"
    echo -e "     $0 --help for more options"
    exit 1
fi

# Interactive mode if no URL provided and not in list/delete modes
if [ "$INTERACTIVE" = true ] && [ "$OPERATION_MODE" != "list" ] && [ "$OPERATION_MODE" != "delete" ]; then
    echo -e "${CYAN}${BOLD}Configuration:${NC}"
    read -p "$(echo -e ${WHITE}Enter NiFi URL ${GRAY}[default: https://idol-docker-host:8443]${NC}: )" NIFI_URL
    NIFI_URL=${NIFI_URL:-https://idol-docker-host:8443}
else
    # Set default URL if not provided
    NIFI_URL=${NIFI_URL:-https://idol-docker-host:8443}
fi

# Only show URL message if not in list-only mode with json/csv output
if [ "$OPERATION_MODE" != "list" ] || [ "$OUTPUT_FORMAT" = "table" ]; then
    echo -e "${GREEN}✓${NC} Using NiFi URL: ${BLUE}${NIFI_URL}${NC}\n"
fi

# Handle authentication based on method or interactive mode
# For ALL modes, we need authentication (including list mode)
if [ "$OPERATION_MODE" = "create" ] || [ "$OPERATION_MODE" = "delete" ] || [ "$OPERATION_MODE" = "interactive" ] || [ "$OPERATION_MODE" = "list" ]; then
    if [ "$INTERACTIVE" = true ] && [ -z "$AUTH_METHOD" ] && [ "$OPERATION_MODE" != "list" ]; then
        # Interactive authentication selection (only for non-list modes)
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
            if [ "$INTERACTIVE" = true ] && [ "$OPERATION_MODE" != "list" ]; then
                echo -e "\n${CYAN}${BOLD}Credentials:${NC}"
                read -p "$(echo -e ${WHITE}Enter username ${GRAY}[default: admin]${NC}: )" USERNAME
                USERNAME=${USERNAME:-admin}
                
                read -sp "$(echo -e ${WHITE}Enter password ${GRAY}[default: OpenText2026!]${NC}: )" PASSWORD
                echo ""
                PASSWORD=${PASSWORD:-OpenText2026!}
            else
                # Set defaults for command-line mode
                USERNAME=${USERNAME:-admin}
                PASSWORD=${PASSWORD:-OpenText2026!}
            fi
            
            # Only show auth messages if not in list-only mode with json/csv output
            if [ "$OPERATION_MODE" != "list" ] || [ "$OUTPUT_FORMAT" = "table" ]; then
                echo -e "\n${YELLOW}⟳${NC} Generating authentication token..."
            fi
            
            # Generate token
            TOKEN=$(curl -k -s -X POST "${NIFI_URL}/nifi-api/access/token" \
              -H "Content-Type: application/x-www-form-urlencoded" \
              -d "username=${USERNAME}&password=${PASSWORD}")
            
            # Clean up the token (remove newlines)
            TOKEN=$(echo "$TOKEN" | tr -d '\n')
            
            if [ -z "$TOKEN" ] || [[ "$TOKEN" == *"Unable to generate access token"* ]]; then
                echo -e "${RED}✗ Error:${NC} Failed to generate token. Please check your credentials."
                exit 1
            fi
            
            # Only show success message if not in list-only mode with json/csv output
            if [ "$OPERATION_MODE" != "list" ] || [ "$OUTPUT_FORMAT" = "table" ]; then
                echo -e "${GREEN}✓${NC} Token generated successfully!"
            fi
            ;;
            
        token)
            if [ "$INTERACTIVE" = true ] && [ "$OPERATION_MODE" != "list" ] && [ -z "$TOKEN" ]; then
                echo -e "\n${CYAN}${BOLD}Token:${NC}"
                read -p "$(echo -e ${WHITE}Enter Authorization Token${NC}: )" TOKEN
            fi
            
            if [ -z "$TOKEN" ]; then
                echo -e "${RED}✗ Error:${NC} Token cannot be empty!"
                exit 1
            fi
            
            # Only show success message if not in list-only mode with json/csv output
            if [ "$OPERATION_MODE" != "list" ] || [ "$OUTPUT_FORMAT" = "table" ]; then
                echo -e "${GREEN}✓${NC} Token accepted"
            fi
            ;;
            
        none)
            # Only show message if not in list-only mode with json/csv output
            if [ "$OPERATION_MODE" != "list" ] || [ "$OUTPUT_FORMAT" = "table" ]; then
                echo -e "\n${YELLOW}⚠${NC} Proceeding without authentication..."
            fi
            TOKEN=""
            ;;
            
        *)
            # If no auth method specified but we have a token, assume token auth
            if [ -n "$TOKEN" ]; then
                # Only show message if not in list-only mode with json/csv output
                if [ "$OPERATION_MODE" != "list" ] || [ "$OUTPUT_FORMAT" = "table" ]; then
                    echo -e "${GREEN}✓${NC} Using provided token"
                fi
            else
                # For ALL modes including list, use password auth by default
                USERNAME=${USERNAME:-admin}
                PASSWORD=${PASSWORD:-OpenText2026!}
                
                if [ "$OUTPUT_FORMAT" = "table" ]; then
                    echo -e "${YELLOW}⟳${NC} Generating authentication token..."
                fi
                
                # Use the exact curl format you specified
                TOKEN=$(curl -k -s -X POST "${NIFI_URL}/nifi-api/access/token" \
                  -H "Content-Type: application/x-www-form-urlencoded" \
                  -d "username=${USERNAME}&password=${PASSWORD}")
                
                TOKEN=$(echo "$TOKEN" | tr -d '\n')
                
                if [ -z "$TOKEN" ] || [[ "$TOKEN" == *"Unable to generate access token"* ]]; then
                    echo -e "${RED}✗ Error:${NC} Failed to generate token."
                    exit 1
                fi
                
                if [ "$OUTPUT_FORMAT" = "table" ]; then
                    echo -e "${GREEN}✓${NC} Token generated"
                fi
            fi
            ;;
    esac
fi

# Check if jq is available (recommended but not required)
if ! command -v jq &> /dev/null; then
    echo -e "\n${YELLOW}⚠ Warning:${NC} ${BOLD}jq${NC} is not installed. JSON operations will be limited."
    echo -e "${YELLOW}Install with:${NC}"
    echo -e "  • Ubuntu/Debian: ${CYAN}sudo apt-get install jq${NC}"
    echo -e "  • macOS: ${CYAN}brew install jq${NC}"
    echo ""
fi

# Arrays to store parameter contexts
declare -a CONTEXT_IDS
declare -a CONTEXT_NAMES
declare -a CONTEXT_DESCRIPTIONS
declare -a CONTEXT_PARAM_COUNTS
declare -a CONTEXT_INHERITED_COUNTS

# Function to get all parameter contexts
get_all_contexts() {
    local url="${NIFI_URL}/nifi-api/flow/parameter-contexts"
    
    local response
    if [ -n "$TOKEN" ]; then
        response=$(curl -k -s -X GET "${url}" \
          -H "Accept: application/json" \
          -H "Authorization: Bearer ${TOKEN}")
    else
        response=$(curl -k -s -X GET "${url}" \
          -H "Accept: application/json")
    fi
    
    # Check for HTTP errors
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Error:${NC} Failed to connect to NiFi API"
        return 1
    fi
    
    # Check if we got a valid JSON response
    if [[ ! "$response" =~ ^\{.*\} ]] && [[ ! "$response" =~ ^\[.*\] ]]; then
        echo -e "${RED}✗ Error:${NC} Invalid response from NiFi API"
        echo -e "${YELLOW}Response preview:${NC} ${response:0:200}..."
        return 1
    fi
    
    # Clear arrays
    CONTEXT_IDS=()
    CONTEXT_NAMES=()
    CONTEXT_DESCRIPTIONS=()
    CONTEXT_PARAM_COUNTS=()
    CONTEXT_INHERITED_COUNTS=()
    
    # Parse response
    if command -v jq &> /dev/null; then
        local contexts_json=$(echo "${response}" | jq -r '.parameterContexts[]? | "\(.id)|\(.component.name)|\(.component.description // "No description")|\(.component.parameters? | length // 0)|\(.component.inheritedParameterContexts? | length // 0)"' 2>/dev/null)
        
        if [ -n "$contexts_json" ]; then
            while IFS='|' read -r id name description param_count inherited_count; do
                CONTEXT_IDS+=("$id")
                CONTEXT_NAMES+=("$name")
                CONTEXT_DESCRIPTIONS+=("$description")
                CONTEXT_PARAM_COUNTS+=("$param_count")
                CONTEXT_INHERITED_COUNTS+=("$inherited_count")
            done <<< "$contexts_json"
        else
            # Try alternative JSON structure
            contexts_json=$(echo "${response}" | jq -r '.[]? | "\(.id)|\(.name)|\(.description // "No description")|\(.parameters? | length // 0)|\(.inheritedParameterContexts? | length // 0)"' 2>/dev/null)
            
            if [ -n "$contexts_json" ]; then
                while IFS='|' read -r id name description param_count inherited_count; do
                    CONTEXT_IDS+=("$id")
                    CONTEXT_NAMES+=("$name")
                    CONTEXT_DESCRIPTIONS+=("$description")
                    CONTEXT_PARAM_COUNTS+=("$param_count")
                    CONTEXT_INHERITED_COUNTS+=("$inherited_count")
                done <<< "$contexts_json"
            fi
        fi
    else
        # Fallback parsing without jq
        local raw_contexts=$(echo "${response}" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
        for id in $raw_contexts; do
            # Extract name and description using grep/sed
            local context_block=$(echo "${response}" | sed -n "/\"id\":\"$id\"/,/},/p")
            local name=$(echo "$context_block" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
            local description=$(echo "$context_block" | grep -o '"description":"[^"]*"' | head -1 | cut -d'"' -f4)
            description=${description:-"No description"}
            
            # Count parameters (rough estimate)
            local param_count=$(echo "$context_block" | grep -o '"parameters"' | wc -l)
            local inherited_count=$(echo "$context_block" | grep -o '"inheritedParameterContexts"' | wc -l)
            
            CONTEXT_IDS+=("$id")
            CONTEXT_NAMES+=("$name")
            CONTEXT_DESCRIPTIONS+=("$description")
            CONTEXT_PARAM_COUNTS+=("$param_count")
            CONTEXT_INHERITED_COUNTS+=("$inherited_count")
        done
    fi
    
    # Debug: Check if we got any contexts
    if [ ${#CONTEXT_IDS[@]} -eq 0 ]; then
        echo -e "${YELLOW}⚠ Warning:${NC} No parameter contexts found or unable to parse response"
        # Check if response might be an error
        if [[ "$response" =~ "error" ]] || [[ "$response" =~ "Error" ]]; then
            echo -e "${YELLOW}Response may contain error:${NC} ${response:0:200}..."
        fi
    fi
}

# Function to output parameter contexts in different formats
output_contexts() {
    local format=$1
    
    case $format in
        json)
            if command -v jq &> /dev/null; then
                echo "["
                for i in "${!CONTEXT_IDS[@]}"; do
                    local comma=","
                    if [ $i -eq $((${#CONTEXT_IDS[@]} - 1)) ]; then
                        comma=""
                    fi
                    cat <<EOF
  {
    "id": "${CONTEXT_IDS[$i]}",
    "name": "${CONTEXT_NAMES[$i]}",
    "description": "${CONTEXT_DESCRIPTIONS[$i]}",
    "parameter_count": ${CONTEXT_PARAM_COUNTS[$i]},
    "inherited_contexts": ${CONTEXT_INHERITED_COUNTS[$i]}
  }${comma}
EOF
                done
                echo "]"
            else
                # Simple JSON without jq
                echo "["
                for i in "${!CONTEXT_IDS[@]}"; do
                    local comma=","
                    if [ $i -eq $((${#CONTEXT_IDS[@]} - 1)) ]; then
                        comma=""
                    fi
                    echo "  {\"id\":\"${CONTEXT_IDS[$i]}\",\"name\":\"${CONTEXT_NAMES[$i]}\",\"description\":\"${CONTEXT_DESCRIPTIONS[$i]}\",\"parameter_count\":${CONTEXT_PARAM_COUNTS[$i]},\"inherited_contexts\":${CONTEXT_INHERITED_COUNTS[$i]}}${comma}"
                done
                echo "]"
            fi
            ;;
            
        csv)
            echo "ID,Name,Description,Parameter Count,Inherited Contexts"
            for i in "${!CONTEXT_IDS[@]}"; do
                echo "\"${CONTEXT_IDS[$i]}\",\"${CONTEXT_NAMES[$i]}\",\"${CONTEXT_DESCRIPTIONS[$i]}\",\"${CONTEXT_PARAM_COUNTS[$i]}\",\"${CONTEXT_INHERITED_COUNTS[$i]}\""
            done
            ;;
            
        table)
            echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${BOLD}${CYAN}║                      Available Parameter Contexts                              ║${NC}"
            echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════════════════════════╝${NC}\n"
            
            if [ ${#CONTEXT_IDS[@]} -eq 0 ]; then
                echo -e "${YELLOW}No parameter contexts found.${NC}\n"
                return
            fi
            
            for i in "${!CONTEXT_IDS[@]}"; do
                local param_color="${GREEN}"
                if [ "${CONTEXT_PARAM_COUNTS[$i]}" -eq 0 ]; then
                    param_color="${YELLOW}"
                fi
                
                local inherited_color="${GRAY}"
                if [ "${CONTEXT_INHERITED_COUNTS[$i]}" -gt 0 ]; then
                    inherited_color="${CYAN}"
                fi
                
                echo -e "${YELLOW}${BOLD}$((i+1)).${NC} ${WHITE}${CONTEXT_NAMES[$i]}${NC}"
                echo -e "   ${CYAN}├─${NC} ${DIM}Description:${NC} ${GRAY}${CONTEXT_DESCRIPTIONS[$i]}${NC}"
                echo -e "   ${CYAN}├─${NC} ${DIM}Parameters:${NC} ${param_color}${CONTEXT_PARAM_COUNTS[$i]}${NC}"
                if [ "${CONTEXT_INHERITED_COUNTS[$i]}" -gt 0 ]; then
                    echo -e "   ${CYAN}├─${NC} ${DIM}Inherited Contexts:${NC} ${inherited_color}${CONTEXT_INHERITED_COUNTS[$i]}${NC}"
                fi
                echo -e "   ${CYAN}└─${NC} ${DIM}ID:${NC} ${GRAY}${CONTEXT_IDS[$i]}${NC}"
                echo ""
            done
            
            echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}\n"
            
            # Summary statistics
            local total_params=0
            for count in "${CONTEXT_PARAM_COUNTS[@]}"; do
                total_params=$((total_params + count))
            done
            
            local total_inherited=0
            for count in "${CONTEXT_INHERITED_COUNTS[@]}"; do
                total_inherited=$((total_inherited + count))
            done
            
            echo -e "${BOLD}${CYAN}Summary:${NC}"
            echo -e "  ${WHITE}Total Contexts:${NC} ${BOLD}${#CONTEXT_IDS[@]}${NC}"
            echo -e "  ${WHITE}Total Parameters:${NC} ${BOLD}${total_params}${NC}"
            if [ $total_inherited -gt 0 ]; then
                echo -e "  ${WHITE}Total Inherited Contexts:${NC} ${BOLD}${total_inherited}${NC}"
            fi
            ;;
    esac
}

# Function to delete parameter context
delete_context() {
    local context_id=$1
    local context_name=$2
    local url="${NIFI_URL}/nifi-api/parameter-contexts/${context_id}?version=0"
    
    local response
    if [ -n "$TOKEN" ]; then
        response=$(curl -k -s -w "\n%{http_code}" -X DELETE "${url}" \
          -H "Accept: application/json" \
          -H "Authorization: Bearer ${TOKEN}")
    else
        response=$(curl -k -s -w "\n%{http_code}" -X DELETE "${url}" \
          -H "Accept: application/json")
    fi
    
    local http_code="${response##*$'\n'}"
    local body="${response%$'\n'*}"
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "204" ]; then
        echo -e "  ${GREEN}✓${NC} Deleted: ${context_name}"
        return 0
    else
        echo -e "  ${RED}✗${NC} Failed to delete ${context_name}"
        if command -v jq &> /dev/null; then
            local error=$(echo "$body" | jq -r '.message // .error // "Unknown error"' 2>/dev/null)
            if [ -n "$error" ] && [ "$error" != "null" ]; then
                echo -e "     ${RED}Error:${NC} $error"
            fi
        fi
        return 1
    fi
}

# Function to delete all parameter contexts
delete_all_contexts() {
    echo -e "\n${RED}${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║         DELETE ALL PARAMETER CONTEXTS                  ║${NC}"
    echo -e "${RED}${BOLD}╚════════════════════════════════════════════════════════╝${NC}\n"
    
    if [ "$SKIP_CONFIRM" = false ]; then
        echo -e "${RED}⚠ WARNING:${NC} This will delete ${BOLD}ALL${NC} parameter contexts!"
        echo -e "${RED}This action cannot be undone!${NC}\n"
        
        echo -e "Contexts to be deleted:"
        for i in "${!CONTEXT_IDS[@]}"; do
            echo -e "  ${RED}•${NC} ${CONTEXT_NAMES[$i]} (${CONTEXT_IDS[$i]})"
        done
        
        echo ""
        read -p "$(echo -e ${WHITE}Are you ABSOLUTELY sure? ${RED}Type 'DELETE ALL' to confirm${NC}: )" confirm
        
        if [ "$confirm" != "DELETE ALL" ]; then
            echo -e "${YELLOW}✗ Operation cancelled.${NC}"
            exit 0
        fi
    fi
    
    local deleted_count=0
    local failed_count=0
    
    echo ""
    for i in "${!CONTEXT_IDS[@]}"; do
        if delete_context "${CONTEXT_IDS[$i]}" "${CONTEXT_NAMES[$i]}"; then
            ((deleted_count++))
        else
            ((failed_count++))
        fi
    done
    
    echo -e "\n${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                     Summary Report                     ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo -e "${WHITE}Total contexts:${NC} ${BOLD}${#CONTEXT_IDS[@]}${NC}"
    echo -e "${GREEN}Successfully deleted:${NC} ${BOLD}${deleted_count}${NC}"
    echo -e "${RED}Failed to delete:${NC} ${BOLD}${failed_count}${NC}"
    
    if [ $failed_count -gt 0 ]; then
        return 1
    fi
    return 0
}

# Function to delete specific context
delete_specific_context() {
    local context_id=$1
    
    # Find context by ID
    local found_index=-1
    for i in "${!CONTEXT_IDS[@]}"; do
        if [ "${CONTEXT_IDS[$i]}" = "$context_id" ]; then
            found_index=$i
            break
        fi
    done
    
    # If not found by ID, try by name or number
    if [ $found_index -eq -1 ]; then
        if [[ "$context_id" =~ ^[0-9]+$ ]]; then
            # It's a number
            local index=$((context_id - 1))
            if [ $index -ge 0 ] && [ $index -lt ${#CONTEXT_IDS[@]} ]; then
                found_index=$index
                context_id="${CONTEXT_IDS[$index]}"
            fi
        else
            # Try to find by name
            for i in "${!CONTEXT_NAMES[@]}"; do
                if [ "${CONTEXT_NAMES[$i]}" = "$context_id" ]; then
                    found_index=$i
                    context_id="${CONTEXT_IDS[$i]}"
                    break
                fi
            done
        fi
    fi
    
    if [ $found_index -eq -1 ]; then
        echo -e "${RED}✗ Context not found: ${context_id}${NC}"
        return 1
    fi
    
    local context_name="${CONTEXT_NAMES[$found_index]}"
    local param_count="${CONTEXT_PARAM_COUNTS[$found_index]}"
    
    echo -e "\n${RED}${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║         DELETE PARAMETER CONTEXT                       ║${NC}"
    echo -e "${RED}${BOLD}╚════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${CYAN}Context Details:${NC}"
    echo -e "  ${YELLOW}Name:${NC} ${WHITE}${context_name}${NC}"
    echo -e "  ${YELLOW}ID:${NC} ${GRAY}${context_id}${NC}"
    echo -e "  ${YELLOW}Parameters:${NC} ${param_count}"
    
    if [ "$SKIP_CONFIRM" = false ]; then
        echo ""
        read -p "$(echo -e ${WHITE}Delete this context? ${RED}[y/N]${NC}: )" confirm
        
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}✗ Operation cancelled.${NC}"
            return 0
        fi
    fi
    
    echo ""
    if delete_context "$context_id" "$context_name"; then
        return 0
    else
        return 1
    fi
}

# Function to delete contexts from file
delete_contexts_from_file() {
    local file_path=$1
    
    if [ ! -f "$file_path" ]; then
        echo -e "${RED}✗ Error:${NC} File not found: ${file_path}"
        return 1
    fi
    
    echo -e "\n${RED}${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║         DELETE CONTEXTS FROM FILE                      ║${NC}"
    echo -e "${RED}${BOLD}╚════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${CYAN}Reading from file:${NC} ${file_path}"
    
    if [ "$SKIP_CONFIRM" = false ]; then
        local line_count=$(wc -l < "$file_path" | tr -d ' ')
        echo -e "${CYAN}Found ${line_count} context(s) to delete${NC}"
        echo ""
        read -p "$(echo -e ${WHITE}Continue with deletion? ${RED}[y/N]${NC}: )" confirm
        
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}✗ Operation cancelled.${NC}"
            return 0
        fi
    fi
    
    local deleted_count=0
    local failed_count=0
    local not_found_count=0
    
    echo ""
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        line=$(echo "$line" | sed 's/#.*//' | xargs)
        if [ -z "$line" ]; then
            continue
        fi
        
        echo -e "${YELLOW}Processing:${NC} ${line}"
        if delete_specific_context "$line" > /tmp/delete_output.txt 2>&1; then
            ((deleted_count++))
            echo -e "  ${GREEN}✓ Success${NC}\n"
        else
            if grep -q "Context not found" /tmp/delete_output.txt; then
                ((not_found_count++))
                echo -e "  ${RED}✗ Context not found${NC}\n"
            else
                ((failed_count++))
                echo -e "  ${RED}✗ Failed${NC}\n"
            fi
        fi
    done < "$file_path"
    
    rm -f /tmp/delete_output.txt
    
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                     Summary Report                     ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo -e "${WHITE}Total lines in file:${NC} ${BOLD}$(wc -l < "$file_path" | tr -d ' ')${NC}"
    echo -e "${GREEN}Successfully deleted:${NC} ${BOLD}${deleted_count}${NC}"
    echo -e "${RED}Failed to delete:${NC} ${BOLD}${failed_count}${NC}"
    echo -e "${YELLOW}Not found:${NC} ${BOLD}${not_found_count}${NC}"
    
    if [ $failed_count -gt 0 ]; then
        return 1
    fi
    return 0
}

# Function to check if parameter context exists
check_context_exists() {
    local name_to_check="$1"
    local contexts
    
    if [ -n "$TOKEN" ]; then
        contexts=$(curl -k -s -H "Authorization: Bearer $TOKEN" \
          "${NIFI_URL}/nifi-api/flow/parameter-contexts")
    else
        contexts=$(curl -k -s "${NIFI_URL}/nifi-api/flow/parameter-contexts")
    fi
    
    if command -v jq &> /dev/null; then
        echo "$contexts" | jq -r --arg name "$name_to_check" '.parameterContexts[] | select(.component.name == $name) | .id' | head -1
    else
        echo "$contexts" | grep -o "\"component\":{[^}]*\"name\":\"${name_to_check}\"[^}]*\"id\":\"[^\"]*\"" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | head -1
    fi
}

# Function to find available context name
find_available_context_name() {
    local base_name="$1"
    local new_name="$base_name"
    local counter=1
    
    while [ -n "$(check_context_exists "$new_name")" ]; do
        new_name="${base_name}_${counter}"
        counter=$((counter + 1))
    done
    
    echo "$new_name"
}

# Function to create parameter context
create_parameter_context() {
    CONTEXT_NAME="$ORIGINAL_CONTEXT_NAME"
    CONTEXT_DESCRIPTION=${CONTEXT_DESCRIPTION:-"Parameter context created via API"}
    
    # Check if JSON file mode
    USE_JSON_FILE=false
    if [ -n "$JSON_FILE" ]; then
        if [ ! -f "$JSON_FILE" ]; then
            echo -e "${RED}✗ Error:${NC} JSON file not found: $JSON_FILE"
            exit 1
        fi
        USE_JSON_FILE=true
    fi
    
    # Display creation banner
    echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      NiFi Parameter Context Creation Process       ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}┌────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ Context Details                                │${NC}"
    echo -e "${CYAN}├────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│ Context Name: ${YELLOW}$ORIGINAL_CONTEXT_NAME${NC}"
    echo -e "${CYAN}│ Description:  ${YELLOW}$CONTEXT_DESCRIPTION${NC}"
    if [ "$USE_JSON_FILE" = true ]; then
        echo -e "${CYAN}│ Input Mode:   ${YELLOW}JSON File${NC}"
        echo -e "${CYAN}│ JSON File:    ${YELLOW}$JSON_FILE${NC}"
    else
        echo -e "${CYAN}│ Input Mode:   ${YELLOW}Interactive${NC}"
    fi
    echo -e "${CYAN}│ NiFi Host:    ${YELLOW}$NIFI_URL${NC}"
    echo -e "${CYAN}└────────────────────────────────────────────────┘${NC}"
    echo ""
    
    # Step 1: Check if parameter context already exists
    echo -e "${CYAN}${BOLD}Step 1/5:${NC} Checking for existing parameter context..."
    EXISTING_CONTEXT_ID=$(check_context_exists "$ORIGINAL_CONTEXT_NAME")
    
    CONTEXT_NAME_UPDATED=false
    if [ -n "$EXISTING_CONTEXT_ID" ]; then
        echo -e "${ORANGE}╔════════════════════════════════════════════════════╗${NC}"
        echo -e "${ORANGE}║           Duplicate Context Detected               ║${NC}"
        echo -e "${ORANGE}╚════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${ORANGE}A parameter context named '${RED}$ORIGINAL_CONTEXT_NAME${ORANGE}' already exists!${NC}"
        echo -e "${ORANGE}Context ID: ${RED}$EXISTING_CONTEXT_ID${NC}"
        echo ""
        
        echo -e "${YELLOW}What would you like to do?${NC}"
        echo -e "${CYAN}1) Cancel and use existing context${NC}"
        echo -e "${CYAN}2) Create with a different name${NC}"
        echo ""
        
        read -p "Enter your choice (1-2): " CHOICE
        
        case $CHOICE in
            1)
                echo -e "${GREEN}✓${NC} Operation cancelled. Using existing context."
                echo ""
                echo -e "${CYAN}Existing Context ID: ${YELLOW}$EXISTING_CONTEXT_ID${NC}"
                echo -e "${CYAN}Context URL: ${YELLOW}${NIFI_URL}/nifi/?componentIds=${EXISTING_CONTEXT_ID}${NC}"
                exit 0
                ;;
            2)
                echo -e "${YELLOW}⟳${NC} Finding available context name..."
                NEW_CONTEXT_NAME=$(find_available_context_name "$ORIGINAL_CONTEXT_NAME")
                CONTEXT_NAME="$NEW_CONTEXT_NAME"
                CONTEXT_NAME_UPDATED=true
                echo -e "${GREEN}✓${NC} Context name updated to: $CONTEXT_NAME"
                ;;
            *)
                echo -e "${RED}✗${NC} Invalid choice. Operation cancelled."
                exit 1
                ;;
        esac
    else
        echo -e "${GREEN}✓${NC} No existing context with this name found"
    fi
    echo ""
    
    # Step 2: Collect parameters
    echo -e "${CYAN}${BOLD}Step 2/5:${NC} Collecting parameters for the context..."
    
    PARAMETERS_JSON="[]"
    PARAM_COUNT=0
    
    if [ "$USE_JSON_FILE" = true ]; then
        # Load parameters from JSON file
        echo -e "${YELLOW}⟳${NC} Loading parameters from JSON file: $JSON_FILE"
        
        # Validate JSON file
        if command -v jq &> /dev/null; then
            # Validate with jq
            if ! jq empty "$JSON_FILE" 2>/dev/null; then
                echo -e "${RED}✗${NC} Invalid JSON file"
                exit 1
            fi
            echo -e "${GREEN}✓${NC} JSON file validated"
        else
            echo -e "${YELLOW}⚠${NC} Cannot validate JSON (jq not found)"
            echo -e "${YELLOW}⚠${NC} Proceeding with file content as-is..."
        fi
        
        # Read the JSON file
        PARAMETERS_JSON=$(cat "$JSON_FILE")
        
        # Try to count parameters
        if command -v jq &> /dev/null; then
            PARAM_COUNT=$(echo "$PARAMETERS_JSON" | jq '. | length')
        else
            # Rough count by counting "parameter" objects
            PARAM_COUNT=$(echo "$PARAMETERS_JSON" | grep -o '"parameter"' | wc -l)
        fi
        
        echo -e "${GREEN}✓${NC} Loaded $PARAM_COUNT parameter(s) from JSON file"
        
        # Display parameters if jq is available
        if command -v jq &> /dev/null; then
            echo ""
            echo -e "${CYAN}Parameters to be created:${NC}"
            echo "$PARAMETERS_JSON" | jq -r '.[] | .parameter | "  - \(.name) (\(if .sensitive then "sensitive" else "non-sensitive" end))"'
        fi
    else
        # Interactive mode
        echo -e "${CYAN}Enter parameters for the context (press Enter with empty name to finish):${NC}"
        echo ""

        while true; do
            echo -e "${YELLOW}Parameter $((PARAM_COUNT + 1)):${NC}"
            
            read -p "  Name (or press Enter to finish): " PARAM_NAME
            
            # Exit loop if name is empty
            if [ -z "$PARAM_NAME" ]; then
                break
            fi
            
            read -p "  Description: " PARAM_DESC
            read -p "  Value: " PARAM_VALUE
            read -p "  Is sensitive? (y/n): " IS_SENSITIVE
            
            # Convert y/n to true/false
            if [ "$IS_SENSITIVE" = "y" ] || [ "$IS_SENSITIVE" = "Y" ]; then
                SENSITIVE="true"
            else
                SENSITIVE="false"
            fi
            
            # Build parameter JSON (escaping quotes in values)
            PARAM_NAME_ESC=$(echo "$PARAM_NAME" | sed 's/"/\\"/g')
            PARAM_DESC_ESC=$(echo "$PARAM_DESC" | sed 's/"/\\"/g')
            PARAM_VALUE_ESC=$(echo "$PARAM_VALUE" | sed 's/"/\\"/g')
            
            if [ $PARAM_COUNT -eq 0 ]; then
                PARAMETERS_JSON="[{\"parameter\":{\"name\":\"$PARAM_NAME_ESC\",\"description\":\"$PARAM_DESC_ESC\",\"sensitive\":$SENSITIVE,\"value\":\"$PARAM_VALUE_ESC\"}}]"
            else
                PARAMETERS_JSON=$(echo "$PARAMETERS_JSON" | sed "s/]$/,{\"parameter\":{\"name\":\"$PARAM_NAME_ESC\",\"description\":\"$PARAM_DESC_ESC\",\"sensitive\":$SENSITIVE,\"value\":\"$PARAM_VALUE_ESC\"}}]/")
            fi
            
            PARAM_COUNT=$((PARAM_COUNT + 1))
            echo -e "${GREEN}✓${NC} Parameter added"
            echo ""
        done

        echo -e "${GREEN}✓${NC} Collected $PARAM_COUNT parameter(s)"
    fi
    
    echo ""
    
    # Step 3: Create parameter context
    echo -e "${CYAN}${BOLD}Step 3/5:${NC} Creating parameter context..."
    
    if [ "$CONTEXT_NAME_UPDATED" = true ]; then
        echo -e "${CYAN}Original name:${NC} $ORIGINAL_CONTEXT_NAME"
        echo -e "${CYAN}Creating as:${NC} $CONTEXT_NAME"
    else
        echo -e "${CYAN}Creating as:${NC} $CONTEXT_NAME"
    fi
    
    # Escape context name and description for JSON
    CONTEXT_NAME_ESC=$(echo "$CONTEXT_NAME" | sed 's/"/\\"/g')
    CONTEXT_DESC_ESC=$(echo "$CONTEXT_DESCRIPTION" | sed 's/"/\\"/g')
    
    CREATE_RESPONSE=$(curl -k -s -w "\n%{http_code}" -X POST \
      "${NIFI_URL}/nifi-api/parameter-contexts" \
      -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' \
      -d "{
        \"revision\": {
          \"version\": 0
        },
        \"component\": {
          \"name\": \"$CONTEXT_NAME_ESC\",
          \"description\": \"$CONTEXT_DESC_ESC\",
          \"parameters\": $PARAMETERS_JSON
        }
      }")
    
    # Extract HTTP status code
    CREATE_HTTP_CODE="${CREATE_RESPONSE##*$'\n'}"
    CREATE_BODY="${CREATE_RESPONSE%$'\n'*}"
    
    if [ "$CREATE_HTTP_CODE" != "201" ] && [ "$CREATE_HTTP_CODE" != "200" ]; then
        echo -e "${RED}✗${NC} Failed to create parameter context (HTTP $CREATE_HTTP_CODE)"
        echo "Response: $CREATE_BODY"
        exit 1
    fi
    
    # Extract context ID
    CONTEXT_ID=$(echo "$CREATE_BODY" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -z "$CONTEXT_ID" ]; then
        echo -e "${RED}✗${NC} Could not extract context ID from response"
        exit 1
    fi
    
    echo -e "${GREEN}✓${NC} Parameter context created successfully"
    echo -e "${CYAN}Context ID:${NC} ${YELLOW}$CONTEXT_ID${NC}"
    echo ""
    
    # Summary
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      Parameter Context Creation Summary            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}┌────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ Creation Details                               │${NC}"
    echo -e "${CYAN}├────────────────────────────────────────────────┤${NC}"
    if [ "$CONTEXT_NAME_UPDATED" = true ]; then
        echo -e "${CYAN}│ ${YELLOW}Original Name:${NC}  $ORIGINAL_CONTEXT_NAME"
        echo -e "${CYAN}│ ${YELLOW}Created As:${NC}     $CONTEXT_NAME"
    else
        echo -e "${CYAN}│ ${YELLOW}Context Name:${NC}   $CONTEXT_NAME"
    fi
    echo -e "${CYAN}│ ${YELLOW}Description:${NC}    $CONTEXT_DESCRIPTION"
    echo -e "${CYAN}│ ${YELLOW}Context ID:${NC}     $CONTEXT_ID"
    echo -e "${CYAN}│ ${YELLOW}Parameters:${NC}     $PARAM_COUNT"
    echo -e "${CYAN}│ ${YELLOW}NiFi URL:${NC}       ${NIFI_URL}/nifi/"
    echo -e "${CYAN}└────────────────────────────────────────────────┘${NC}"
    echo ""
    
    # Direct access link
    echo -e "${BLUE}Direct Access Link:${NC}"
    echo -e "${YELLOW}${NIFI_URL}/nifi/?componentIds=${CONTEXT_ID}${NC}"
    echo ""
    
    # Show warning if name was changed
    if [ "$CONTEXT_NAME_UPDATED" = true ]; then
        echo ""
        echo -e "${YELLOW}────────────────────────────────────────────────────${NC}"
        echo -e "${YELLOW}⚠ NOTE: Context name was changed to avoid conflict${NC}"
        echo -e "${YELLOW}   Original: $ORIGINAL_CONTEXT_NAME${NC}"
        echo -e "${YELLOW}   Created as: $CONTEXT_NAME${NC}"
        echo -e "${YELLOW}────────────────────────────────────────────────────${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}          Creation Process Complete                   ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
}

# Main execution

# First, get all contexts if we need them for list or delete operations
if [ "$LIST_ONLY" = true ] || [ "$DELETE_MODE" = true ]; then
    # Get all parameter contexts
    if [ "$OUTPUT_FORMAT" = "table" ]; then
        echo -e "\n${YELLOW}⟳${NC} Fetching parameter contexts from NiFi..."
    fi
    
    if ! get_all_contexts; then
        echo -e "${RED}✗ Error:${NC} Failed to fetch parameter contexts."
        exit 1
    fi
    
    if [ "$OUTPUT_FORMAT" = "table" ]; then
        echo -e "${GREEN}✓${NC} Found ${BOLD}${#CONTEXT_IDS[@]}${NC} parameter context(s)\n"
    fi
fi

# Execute based on mode
if [ "$LIST_ONLY" = true ]; then
    # FIX: Ensure output_contexts is called with the correct format
    output_contexts "$OUTPUT_FORMAT"
    exit 0
elif [ "$DELETE_MODE" = true ]; then
    if [ "$DELETE_ALL" = true ]; then
        delete_all_contexts
        exit $?
    elif [ -n "$CONTEXT_ID" ]; then
        delete_specific_context "$CONTEXT_ID"
        exit $?
    elif [ -n "$CONTEXT_FILE" ]; then
        delete_contexts_from_file "$CONTEXT_FILE"
        exit $?
    else
        # Interactive delete mode
        if [ ${#CONTEXT_IDS[@]} -eq 0 ]; then
            echo -e "${YELLOW}No parameter contexts found to delete.${NC}"
            exit 0
        fi
        
        output_contexts "table"
        
        echo -e "${CYAN}${BOLD}Delete Options:${NC}"
        echo -e "  ${RED}1)${NC} Delete specific context by number"
        echo -e "  ${RED}2)${NC} Delete specific context by ID"
        echo -e "  ${RED}3)${NC} Delete contexts from file"
        echo -e "  ${RED}4)${NC} Delete ALL contexts (danger!)"
        echo -e "  ${GRAY}5)${NC} Cancel"
        echo ""
        
        read -p "$(echo -e ${WHITE}Enter choice ${GRAY}[1-5]${NC}: )" DELETE_CHOICE
        
        case $DELETE_CHOICE in
            1)
                read -p "$(echo -e ${WHITE}Enter context number to delete${NC}: )" CONTEXT_NUM
                delete_specific_context "$CONTEXT_NUM"
                ;;
            2)
                read -p "$(echo -e ${WHITE}Enter context ID to delete${NC}: )" CONTEXT_ID_INPUT
                delete_specific_context "$CONTEXT_ID_INPUT"
                ;;
            3)
                read -p "$(echo -e ${WHITE}Enter file path containing context IDs${NC}: )" FILE_PATH
                delete_contexts_from_file "$FILE_PATH"
                ;;
            4)
                DELETE_ALL=true
                delete_all_contexts
                ;;
            5)
                echo -e "${GREEN}✓${NC} Operation cancelled."
                exit 0
                ;;
            *)
                echo -e "${RED}✗${NC} Invalid choice. Exiting."
                exit 1
                ;;
        esac
        exit $?
    fi
else
    # Create mode
    create_parameter_context
fi

exit 0