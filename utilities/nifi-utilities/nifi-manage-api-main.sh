#!/bin/bash

# ==============================================================================
# NiFi GitHub Flow Registry Client - Master Script Edition
# ==============================================================================
# Enhanced with master script styling, color formatting, and comprehensive features
# ==============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ==============================================================================
# COLOR DEFINITIONS
# ==============================================================================

# Primary colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Special colors
BOLD='\033[1m'
DIM='\033[2m'
ORANGE='\033[0;38;5;214m'
PURPLE='\033[0;35m'
LIGHT_BLUE='\033[38;5;117m'
LIGHT_GREEN='\033[38;5;120m'
LIGHT_RED='\033[38;5;203m'
LIGHT_YELLOW='\033[38;5;228m'

# ==============================================================================
# DEPENDENCY CHECK
# ==============================================================================

check_dependencies() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          Dependency Check                               ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local missing_deps=()
    
    # Check for curl (essential)
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    # Check for jq (essential for this script)
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${RED}✗ Error:${NC} Missing required dependencies:"
        for dep in "${missing_deps[@]}"; do
            echo -e "  ${RED}-${NC} $dep"
        done
        echo -e "\n${CYAN}Please install missing dependencies and try again.${NC}"
        echo -e "${GRAY}Install commands:${NC}"
        echo -e "  ${GRAY}Debian/Ubuntu: sudo apt-get install curl jq${NC}"
        echo -e "  ${GRAY}RHEL/CentOS:   sudo yum install curl jq${NC}"
        echo -e "  ${GRAY}macOS:         brew install curl jq${NC}"
        echo -e "  ${GRAY}Alpine:        apk add curl jq${NC}"
        exit 1
    fi
    
    # Check for openssl (optional but recommended)
    if ! command -v openssl &> /dev/null; then
        echo -e "${YELLOW}⚠ Warning:${NC} ${BOLD}openssl${NC} is not installed. SSL certificate export will not work."
        echo -e "${GRAY}   Install with: sudo apt-get install openssl (Debian/Ubuntu)${NC}"
    fi
    
    echo -e "${GREEN}✓${NC} All dependencies satisfied"
    echo ""
}

# Check dependencies early
check_dependencies

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Default Configuration
NIFI_API_URL="${NIFI_API_URL:-https://idol-docker-host:8443/nifi-api}"
NIFI_USERNAME="${NIFI_USERNAME:-admin}"
NIFI_PASSWORD="${NIFI_PASSWORD:-Nifi-Admin1!}"
SSL_VERIFY="${SSL_VERIFY:-false}"

# GitHub Configuration
GITHUB_REPO_URL="${GITHUB_REPO_URL:-https://github.com/your-org/your-repo.git}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
GITHUB_FLOW_DIR="${GITHUB_FLOW_DIR:-nifi-flows}"

# Global variables
AUTH_HEADER=""
TOKEN=""
REGISTRY_ID=""
INTERACTIVE=false
VERBOSE=false
QUIET=false
NIFI_VERSION=""

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Enhanced logging functions
log_info() {
    if [ "$QUIET" = false ]; then
        echo -e "${BLUE}[INFO]${NC} $1" >&2
    fi
}

log_success() {
    if [ "$QUIET" = false ]; then
        echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
    fi
}

log_warning() {
    if [ "$QUIET" = false ]; then
        echo -e "${YELLOW}[WARNING]${NC} $1" >&2
    fi
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${GRAY}[VERBOSE]${NC} $1" >&2
    fi
}

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

# Function to print section header
print_section() {
    local title="$1"
    if [ "$QUIET" = false ]; then
        echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║ $(printf "%-56s" "$title") ║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
        echo ""
    fi
}

# Function to print configuration
print_config() {
    if [ "$QUIET" = false ]; then
        echo -e "${CYAN}┌────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│ Current Configuration                         │${NC}"
        echo -e "${CYAN}├────────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│ NiFi URL:      ${WHITE}${NIFI_API_URL}${NC}"
        echo -e "${CYAN}│ Username:      ${WHITE}${NIFI_USERNAME}${NC}"
        echo -e "${CYAN}│ GitHub Repo:   ${WHITE}${GITHUB_REPO_URL}${NC}"
        echo -e "${CYAN}│ GitHub Branch: ${WHITE}${GITHUB_BRANCH}${NC}"
        echo -e "${CYAN}│ SSL Verify:    ${WHITE}${SSL_VERIFY}${NC}"
        echo -e "${CYAN}│ Interactive:   ${WHITE}${INTERACTIVE}${NC}"
        echo -e "${CYAN}└────────────────────────────────────────────────┘${NC}"
        echo ""
    fi
}

# Make authenticated API call with enhanced error handling
api_call() {
    local method=$1
    local endpoint=$2
    local data=${3:-}
    local extra_headers=${4:-}
    local debug=${5:-false}
    
    local url="${NIFI_API_URL}${endpoint}"
    
    if [ "$debug" = "true" ] || [ "$VERBOSE" = true ]; then
        log_verbose "API Call: ${method} ${url}"
        if [ -n "$data" ]; then
            log_verbose "Request Data: ${data:0:500}..."
        fi
    fi
    
    # Build curl arguments
    local curl_args=("-s" "-S" "-w" "\n%{http_code}" "-X" "$method" "$url")
    
    # Add SSL options
    if [ "$SSL_VERIFY" = "false" ]; then
        curl_args+=("-k")
    fi
    
    # Add authentication header if available
    if [ -n "$AUTH_HEADER" ]; then
        curl_args+=("-H" "$AUTH_HEADER")
    fi
    
    # Add data if provided
    if [ -n "$data" ]; then
        curl_args+=("-H" "Content-Type: application/json" "-d" "$data")
    fi
    
    # Add extra headers
    if [ -n "$extra_headers" ]; then
        curl_args+=("-H" "$extra_headers")
    fi
    
    # Make the API call
    local full_response=$(curl "${curl_args[@]}" 2>&1)
    local exit_code=$?
    
    # Extract HTTP code and response body
    local http_code=$(echo "$full_response" | tail -n1)
    local response=$(echo "$full_response" | sed '$d')
    
    if [ $exit_code -ne 0 ]; then
        log_error "Curl command failed with exit code: $exit_code"
        log_error "Response: $full_response"
        return 1
    fi
    
    if [ "$debug" = "true" ] || [ "$VERBOSE" = true ]; then
        log_verbose "HTTP Response Code: $http_code"
        log_verbose "Response: ${response:0:1000}..."
    fi
    
    # Check HTTP status code
    if [[ ! $http_code =~ ^2 ]]; then
        log_error "API call failed with HTTP code: $http_code"
        
        # Provide helpful error messages based on status code
        case $http_code in
            000)
                log_error "Cannot connect to NiFi. Please check:"
                log_error "  1. NiFi URL is correct: $NIFI_API_URL"
                log_error "  2. NiFi is running and accessible"
                log_error "  3. Network connectivity"
                ;;
            401|403)
                log_error "Authentication failed. Please check credentials."
                ;;
            404)
                log_error "Resource not found. Please check endpoint: $endpoint"
                ;;
            500|502|503|504)
                log_error "NiFi server error. Please check NiFi logs."
                ;;
        esac
        
        if [ -n "$response" ]; then
            log_error "Error details:"
            echo "$response" | jq -r '.message // .error // .' 2>/dev/null || echo "$response"
        fi
        return 1
    fi
    
    echo "$response"
    return 0
}

# ==============================================================================
# AUTHENTICATION FUNCTIONS
# ==============================================================================

authenticate() {
    print_step "1" "3" "Authenticating with NiFi"
    
    log_info "URL: ${NIFI_API_URL}"
    log_info "Username: ${NIFI_USERNAME}"
    
    # Check if we already have a valid token
    if [ -n "$AUTH_HEADER" ]; then
        log_info "Already authenticated, checking token validity..."
        if verify_token; then
            log_success "Token is still valid"
            return 0
        else
            log_warning "Token expired or invalid, re-authenticating..."
        fi
    fi
    
    # Authenticate with NiFi
    local full_response=$(curl -s -S -w "\n%{http_code}" \
        ${SSL_VERIFY:+-k} \
        -X POST "${NIFI_API_URL}/access/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${NIFI_USERNAME}&password=${NIFI_PASSWORD}" 2>&1)
    
    local http_code=$(echo "$full_response" | tail -n1)
    local body=$(echo "$full_response" | sed '$d')
    
    if [[ ! $http_code =~ ^2 ]]; then
        log_error "Authentication failed with HTTP code: $http_code"
        
        case $http_code in
            000)
                log_error "Cannot connect to NiFi. Please check:"
                log_error "  1. NiFi URL is correct: $NIFI_API_URL"
                log_error "  2. NiFi is running and accessible"
                log_error "  3. SSL certificate issues (try with SSL_VERIFY=false)"
                ;;
            401)
                log_error "Invalid credentials. Please check username and password."
                ;;
            *)
                log_error "Unexpected error: $body"
                ;;
        esac
        exit 1
    fi
    
    if [ -z "$body" ]; then
        log_error "Empty token received from NiFi"
        exit 1
    fi
    
    # Check if response is an error JSON
    if [[ "$body" == "{"* ]]; then
        if echo "$body" | jq -e '.status' > /dev/null 2>&1; then
            log_error "Authentication failed: $(echo "$body" | jq -r '.message // .error // "Invalid credentials"')"
            exit 1
        fi
    fi
    
    TOKEN="$body"
    AUTH_HEADER="Authorization: Bearer ${TOKEN}"
    log_success "Authentication successful"
    log_info "Token: ${TOKEN:0:20}..."
    
    # Get NiFi version after authentication
    print_step "2" "3" "Getting NiFi Version"
    NIFI_VERSION=$(get_nifi_version)
    if [ -z "$NIFI_VERSION" ]; then
        log_warning "Could not retrieve NiFi version. Defaulting to 2.0.0"
        NIFI_VERSION="2.0.0"
    fi
    log_info "NiFi Version: ${NIFI_VERSION}"
    
    print_step "3" "3" "Verifying API Access"
    if verify_api_access; then
        log_success "NiFi API is fully accessible"
    else
        log_error "Cannot access NiFi API after authentication"
        exit 1
    fi
}

# Verify token validity
verify_token() {
    local response=$(api_call "GET" "/flow/about" "" "" "false" 2>/dev/null)
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Verify API access
verify_api_access() {
    local response=$(api_call "GET" "/flow/about" "" "" "false")
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Get NiFi version
get_nifi_version() {
    local response=$(api_call "GET" "/flow/about")
    if [ $? -ne 0 ]; then
        return 1
    fi
    echo "$response" | jq -r '.about.version'
}

# ==============================================================================
# REGISTRY CLIENT MANAGEMENT
# ==============================================================================

list_registry_types() {
    print_section "Registry Client Types"
    
    if ! verify_token; then
        authenticate
    fi
    
    log_info "Fetching available registry client types..."
    local response=$(api_call "GET" "/controller/registry-types")
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo ""
    echo -e "${CYAN}Available Registry Types:${NC}"
    echo -e "${CYAN}=========================${NC}"
    
    # Check if response contains Git registry types
    local git_registries=$(echo "$response" | jq -r '.registryClientTypes[] | select(.type | contains("Git")) | .type')
    
    if [ -n "$git_registries" ]; then
        echo "$response" | jq -r '.registryClientTypes[] | select(.type | contains("Git")) | "  • \(.type)\n    Bundle: \(.bundle.group):\(.bundle.artifact):\(.bundle.version)\n"' | \
        while IFS= read -r line; do
            if [[ "$line" == "  • "* ]]; then
                echo -e "${GREEN}${line}${NC}"
            elif [[ "$line" == "    Bundle:"* ]]; then
                echo -e "${GRAY}${line}${NC}"
            else
                echo "$line"
            fi
        done
    else
        echo -e "${YELLOW}No Git registry types found. Showing all registry types:${NC}"
        echo "$response" | jq -r '.registryClientTypes[] | "  • \(.type)\n    Bundle: \(.bundle.group):\(.bundle.artifact):\(.bundle.version)\n"' | \
        while IFS= read -r line; do
            if [[ "$line" == "  • "* ]]; then
                echo -e "${GREEN}${line}${NC}"
            elif [[ "$line" == "    Bundle:"* ]]; then
                echo -e "${GRAY}${line}${NC}"
            else
                echo "$line"
            fi
        done
    fi
    
    log_success "Registry types retrieved"
}

create_github_registry() {
    print_section "Create GitHub Flow Registry"
    
    if ! verify_token; then
        authenticate
    fi
    
    if [ -z "$GITHUB_TOKEN" ]; then
        echo -e "${YELLOW}GitHub Token is not set.${NC}"
        echo -e "${CYAN}Please enter your GitHub Personal Access Token:${NC}"
        echo -e "${GRAY}(Token will not be displayed for security)${NC}"
        read -sp "Token: " GITHUB_TOKEN
        echo ""
        
        if [ -z "$GITHUB_TOKEN" ]; then
            log_error "GitHub Token is required"
            return 1
        fi
    fi
    
    # Parse GitHub repo URL
    local repo_path="${GITHUB_REPO_URL#https://github.com/}"
    repo_path="${repo_path%.git}"
    local repository_owner="${repo_path%/*}"
    local repository_name="${repo_path#*/}"
    
    log_info "Creating GitHub Flow Registry Client..."
    log_info "Repository: ${repository_owner}/${repository_name}"
    log_info "Branch: ${GITHUB_BRANCH}"
    log_info "Flow Directory: ${GITHUB_FLOW_DIR}"
    
    local data=$(cat <<EOF
{
  "revision": {
    "version": 0
  },
  "component": {
    "name": "GitHub Flow Registry",
    "type": "org.apache.nifi.github.GitHubFlowRegistryClient",
    "bundle": {
      "group": "org.apache.nifi",
      "artifact": "nifi-github-nar",
      "version": "${NIFI_VERSION}"
    },
    "properties": {
      "API URL": "https://api.github.com",
      "Repository Owner": "${repository_owner}",
      "Repository Name": "${repository_name}",
      "Default Branch": "${GITHUB_BRANCH}",
      "Authentication Type": "Personal Access Token",
      "Personal Access Token": "${GITHUB_TOKEN}",
      "Repository Path": "${GITHUB_FLOW_DIR}"
    },
    "description": "GitHub-based Flow Registry for version control"
  }
}
EOF
    )
    
    local response=$(api_call "POST" "/controller/registry-clients" "$data")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create registry client"
        return 1
    fi
    
    REGISTRY_ID=$(echo "$response" | jq -r '.id')
    
    if [ -n "$REGISTRY_ID" ] && [ "$REGISTRY_ID" != "null" ]; then
        log_success "Registry Client created successfully"
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║        Registry Client Created                         ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${CYAN}┌────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│ Registry Details                              │${NC}"
        echo -e "${CYAN}├────────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│ ID:          ${WHITE}${REGISTRY_ID}${NC}"
        echo -e "${CYAN}│ Name:        ${WHITE}GitHub Flow Registry${NC}"
        echo -e "${CYAN}│ Type:        ${WHITE}GitHub Flow Registry Client${NC}"
        echo -e "${CYAN}│ Repository:  ${WHITE}${repository_owner}/${repository_name}${NC}"
        echo -e "${CYAN}│ Branch:      ${WHITE}${GITHUB_BRANCH}${NC}"
        echo -e "${CYAN}│ Directory:   ${WHITE}${GITHUB_FLOW_DIR}${NC}"
        echo -e "${CYAN}└────────────────────────────────────────────────┘${NC}"
        echo ""
        
        # Test the registry connection
        log_info "Testing registry connection..."
        sleep 2
        if list_buckets "$REGISTRY_ID" > /dev/null 2>&1; then
            log_success "Registry connection test successful"
        else
            log_warning "Registry created but connection test failed"
            log_info "Please verify GitHub token permissions and repository access"
        fi
        
        echo "$REGISTRY_ID"
    else
        log_error "Failed to extract registry ID from response"
        return 1
    fi
}

list_all_registries() {
    print_section "All Registry Clients"
    
    if ! verify_token; then
        authenticate
    fi
    
    log_info "Listing all registry clients..."
    local response=$(api_call "GET" "/controller/registry-clients")
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local count=$(echo "$response" | jq '.registryClients | length')
    
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}No registry clients found${NC}"
    else
        echo ""
        echo -e "${CYAN}Registry Clients (${count} found):${NC}"
        echo -e "${CYAN}==============================${NC}"
        echo "$response" | jq -r '.registryClients[] | "  • \(.id)\n    Name: \(.component.name)\n    Type: \(.component.type)\n"' | \
        while IFS= read -r line; do
            if [[ "$line" == "  • "* ]]; then
                echo -e "${GREEN}${line}${NC}"
            elif [[ "$line" == "    Name:"* ]]; then
                echo -e "${WHITE}${line}${NC}"
            elif [[ "$line" == "    Type:"* ]]; then
                echo -e "${GRAY}${line}${NC}"
            else
                echo "$line"
            fi
        done
        log_success "Registries listed"
    fi
}

get_registry_client() {
    local registry_id=${1:-$REGISTRY_ID}
    
    if [ -z "$registry_id" ]; then
        log_error "Registry ID is required"
        return 1
    fi
    
    print_section "Registry Client Details"
    
    if ! verify_token; then
        authenticate
    fi
    
    log_info "Fetching registry client: ${registry_id}"
    local response=$(api_call "GET" "/controller/registry-clients/${registry_id}")
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo ""
    echo -e "${CYAN}Registry Client Details:${NC}"
    echo -e "${CYAN}========================${NC}"
    
    # Extract basic info with colors
    local id=$(echo "$response" | jq -r '.id')
    local name=$(echo "$response" | jq -r '.component.name')
    local type=$(echo "$response" | jq -r '.component.type')
    local group=$(echo "$response" | jq -r '.component.bundle.group')
    local artifact=$(echo "$response" | jq -r '.component.bundle.artifact')
    local version=$(echo "$response" | jq -r '.component.bundle.version')
    local description=$(echo "$response" | jq -r '.component.description // "None"')
    
    echo -e "  ${GREEN}ID:${NC}          $id"
    echo -e "  ${GREEN}Name:${NC}        ${WHITE}$name${NC}"
    echo -e "  ${GREEN}Type:${NC}        $type"
    echo -e "  ${GREEN}Bundle:${NC}      ${GRAY}$group:$artifact:$version${NC}"
    echo -e "  ${GREEN}Description:${NC} $description"
    echo -e "  ${GREEN}Properties:${NC}"
    
    # Display properties in a readable format
    echo "$response" | jq -r '.component.properties | to_entries[] | 
        "    \(.key): \(if .key | contains("Token") or contains("Password") then "********" else .value end)"'
    
    log_success "Registry client retrieved"
}

# ==============================================================================
# FLOW REGISTRY OPERATIONS
# ==============================================================================

list_buckets() {
    local registry_id=${1:-$REGISTRY_ID}
    
    if [ -z "$registry_id" ]; then
        log_error "Registry ID is required"
        return 1
    fi
    
    print_section "Registry Buckets"
    
    if ! verify_token; then
        authenticate
    fi
    
    log_info "Listing buckets for registry: ${registry_id}"
    local response=$(api_call "GET" "/flow/registries/${registry_id}/buckets")
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local count=$(echo "$response" | jq '.buckets | length')
    
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}No buckets found in registry${NC}"
        log_info "You may need to create buckets in your GitHub repository"
        log_info "Expected directory structure: ${GITHUB_FLOW_DIR}/<bucket-name>/"
    else
        echo ""
        echo -e "${CYAN}Buckets (${count} found):${NC}"
        echo -e "${CYAN}=====================${NC}"
        echo "$response" | jq -r '.buckets[] | "  • \(.id)\n    Name: \(.name)\n    Created: \(.createdTimestamp)\n    Description: \(.description // "None")\n"' | \
        while IFS= read -r line; do
            if [[ "$line" == "  • "* ]]; then
                echo -e "${GREEN}${line}${NC}"
            elif [[ "$line" == "    Name:"* ]]; then
                echo -e "${WHITE}${line}${NC}"
            elif [[ "$line" == "    Created:"* ]] || [[ "$line" == "    Description:"* ]]; then
                echo -e "${GRAY}${line}${NC}"
            else
                echo "$line"
            fi
        done
        log_success "Buckets retrieved"
    fi
}

list_flows() {
    local registry_id=${1:-$REGISTRY_ID}
    local bucket_id=$2
    
    if [ -z "$registry_id" ] || [ -z "$bucket_id" ]; then
        log_error "Registry ID and Bucket ID are required"
        return 1
    fi
    
    print_section "Bucket Flows"
    
    if ! verify_token; then
        authenticate
    fi
    
    log_info "Listing flows in bucket: ${bucket_id}"
    local response=$(api_call "GET" "/flow/registries/${registry_id}/buckets/${bucket_id}/flows")
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local count=$(echo "$response" | jq '.versionedFlows | length')
    
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}No flows found in bucket${NC}"
    else
        echo ""
        echo -e "${CYAN}Flows in Bucket (${count} found):${NC}"
        echo -e "${CYAN}=============================${NC}"
        echo "$response" | jq -r '.versionedFlows[] | "  • \(.identifier)\n    Name: \(.name)\n    Description: \(.description // "None")\n    Created: \(.createdTimestamp)\n    Modified: \(.modifiedTimestamp // "Never")\n"' | \
        while IFS= read -r line; do
            if [[ "$line" == "  • "* ]]; then
                echo -e "${GREEN}${line}${NC}"
            elif [[ "$line" == "    Name:"* ]]; then
                echo -e "${WHITE}${line}${NC}"
            elif [[ "$line" == "    Description:"* ]] || [[ "$line" == "    Created:"* ]] || [[ "$line" == "    Modified:"* ]]; then
                echo -e "${GRAY}${line}${NC}"
            else
                echo "$line"
            fi
        done
        log_success "Flows retrieved"
    fi
}

list_flow_versions() {
    local registry_id=${1:-$REGISTRY_ID}
    local bucket_id=$2
    local flow_id=$3
    
    if [ -z "$registry_id" ] || [ -z "$bucket_id" ] || [ -z "$flow_id" ]; then
        log_error "Registry ID, Bucket ID, and Flow ID are required"
        return 1
    fi
    
    print_section "Flow Versions"
    
    if ! verify_token; then
        authenticate
    fi
    
    log_info "Listing versions for flow: ${flow_id}"
    local response=$(api_call "GET" "/flow/registries/${registry_id}/buckets/${bucket_id}/flows/${flow_id}/versions")
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local count=$(echo "$response" | jq '.versionedFlowSnapshotMetadata | length')
    
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}No versions found for this flow${NC}"
    else
        echo ""
        echo -e "${CYAN}Flow Versions (${count} found):${NC}"
        echo -e "${CYAN}==========================${NC}"
        echo "$response" | jq -r '.versionedFlowSnapshotMetadata[] | "  • Version \(.version)\n    Comment: \(.comments // "No comment")\n    Author: \(.author // "Unknown")\n    Timestamp: \(.timestamp)\n"' | \
        while IFS= read -r line; do
            if [[ "$line" == "  • Version "* ]]; then
                echo -e "${GREEN}${line}${NC}"
            elif [[ "$line" == "    Comment:"* ]]; then
                echo -e "${WHITE}${line}${NC}"
            elif [[ "$line" == "    Author:"* ]] || [[ "$line" == "    Timestamp:"* ]]; then
                echo -e "${GRAY}${line}${NC}"
            else
                echo "$line"
            fi
        done
        log_success "Flow versions retrieved"
    fi
}

# ==============================================================================
# VERSION CONTROL OPERATIONS
# ==============================================================================

start_version_control() {
    local process_group_id=$1
    local bucket_id=$2
    local flow_name=$3
    local flow_description=${4:-""}
    local comments=${5:-"Initial version"}
    
    if [ -z "$process_group_id" ] || [ -z "$bucket_id" ] || [ -z "$flow_name" ]; then
        log_error "Process Group ID, Bucket ID, and Flow Name are required"
        return 1
    fi
    
    print_section "Start Version Control"
    
    if ! verify_token; then
        authenticate
    fi
    
    log_info "Starting version control for process group: ${process_group_id}"
    log_info "Bucket: ${bucket_id}"
    log_info "Flow Name: ${flow_name}"
    log_info "Description: ${flow_description}"
    
    local data=$(cat <<EOF
{
  "processGroupRevision": {
    "version": 0
  },
  "versionControlInformation": {
    "registryId": "${REGISTRY_ID}",
    "bucketId": "${bucket_id}",
    "flowName": "${flow_name}",
    "flowDescription": "${flow_description}",
    "comments": "${comments}"
  }
}
EOF
    )
    
    local response=$(api_call "POST" "/versions/process-groups/${process_group_id}" "$data")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to start version control"
        return 1
    fi
    
    log_success "Version control started successfully"
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     Version Control Started                           ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}┌────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│ Version Control Details                       │${NC}"
    echo -e "${CYAN}├────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│ Process Group: ${WHITE}${process_group_id}${NC}"
    echo -e "${CYAN}│ Flow Name:     ${WHITE}${flow_name}${NC}"
    echo -e "${CYAN}│ Bucket ID:     ${WHITE}${bucket_id}${NC}"
    echo -e "${CYAN}│ Registry ID:   ${WHITE}${REGISTRY_ID}${NC}"
    echo -e "${CYAN}│ Comment:       ${WHITE}${comments}${NC}"
    echo -e "${CYAN}└────────────────────────────────────────────────┘${NC}"
    echo ""
    echo "$response" | jq '.'
}

# ==============================================================================
# PARAMETER CONTEXT MANAGEMENT
# ==============================================================================

list_parameter_contexts() {
    print_section "Parameter Contexts"
    
    if ! verify_token; then
        authenticate
    fi
    
    log_info "Listing all Parameter Contexts..."
    local response=$(api_call "GET" "/flow/parameter-contexts")
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local count=$(echo "$response" | jq '.parameterContexts | length')
    
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}No parameter contexts found${NC}"
    else
        echo ""
        echo -e "${CYAN}Parameter Contexts (${count} found):${NC}"
        echo -e "${CYAN}===============================${NC}"
        echo "$response" | jq -r '.parameterContexts[] | "  • \(.id)\n    Name: \(.component.name)\n    Description: \(.component.description // "None")\n"' | \
        while IFS= read -r line; do
            if [[ "$line" == "  • "* ]]; then
                echo -e "${GREEN}${line}${NC}"
            elif [[ "$line" == "    Name:"* ]]; then
                echo -e "${WHITE}${line}${NC}"
            elif [[ "$line" == "    Description:"* ]]; then
                echo -e "${GRAY}${line}${NC}"
            else
                echo "$line"
            fi
        done
        log_success "Parameter contexts listed"
    fi
}

create_parameter_context() {
    local name=$1
    local desc=${2:-"Created via API"}
    local params_json=${3:-"[]"}
    
    if [ -z "$name" ]; then
        log_error "Parameter Context name is required"
        return 1
    fi
    
    print_section "Create Parameter Context"
    
    if ! verify_token; then
        authenticate
    fi
    
    log_info "Creating Parameter Context: ${name}"
    log_info "Description: ${desc}"
    
    # Validate JSON if provided
    if [ "$params_json" != "[]" ]; then
        if ! echo "$params_json" | jq empty 2>/dev/null; then
            log_error "Invalid JSON for parameters"
            return 1
        fi
    fi
    
    local data=$(cat <<EOF
{
  "revision": { "version": 0 },
  "component": {
    "name": "${name}",
    "description": "${desc}",
    "parameters": ${params_json}
  }
}
EOF
)
    
    local response=$(api_call "POST" "/parameter-contexts" "$data")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create parameter context"
        return 1
    fi
    
    local ctx_id=$(echo "$response" | jq -r '.id')
    
    if [ -n "$ctx_id" ] && [ "$ctx_id" != "null" ]; then
        log_success "Parameter context created successfully"
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║     Parameter Context Created                         ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${CYAN}┌────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│ Context Details                              │${NC}"
        echo -e "${CYAN}├────────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│ ID:          ${WHITE}${ctx_id}${NC}"
        echo -e "${CYAN}│ Name:        ${WHITE}${name}${NC}"
        echo -e "${CYAN}│ Description: ${WHITE}${desc}${NC}"
        echo -e "${CYAN}└────────────────────────────────────────────────┘${NC}"
        echo ""
    else
        log_error "Failed to create parameter context"
        return 1
    fi
}

# ==============================================================================
# SSL CERTIFICATE MANAGEMENT
# ==============================================================================

test_connection() {
    print_section "NiFi Connection Test"
    
    log_info "Testing connection to NiFi..."
    log_info "URL: $NIFI_API_URL"
    
    # Extract host and port from URL
    local url_pattern='https?://([^:/]+):?([0-9]+)?'
    if [[ $NIFI_API_URL =~ $url_pattern ]]; then
        local host="${BASH_REMATCH[1]}"
        local port="${BASH_REMATCH[2]:-8443}"
        
        echo -e "${CYAN}Connection Details:${NC}"
        echo -e "  ${GREEN}•${NC} Host: ${WHITE}$host${NC}"
        echo -e "  ${GREEN}•${NC} Port: ${WHITE}$port${NC}"
        echo -e "  ${GREEN}•${NC} SSL Verify: ${WHITE}$SSL_VERIFY${NC}"
        echo ""
        
        # Test basic connectivity
        print_step "1" "3" "Testing Network Connectivity"
        if timeout 5 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
            echo -e "${GREEN}✓${NC} Network connection successful"
        else
            echo -e "${RED}✗${NC} Cannot connect to $host:$port"
            log_error "Please check if NiFi is running and accessible"
            return 1
        fi
        
        # Test SSL certificate if using HTTPS
        if [[ $NIFI_API_URL == https* ]]; then
            print_step "2" "3" "Testing SSL Certificate"
            local ssl_test=$(echo | openssl s_client -connect "$host:$port" -servername "$host" 2>&1)
            if echo "$ssl_test" | grep -q "Verify return code: 0"; then
                echo -e "${GREEN}✓${NC} SSL certificate is valid"
            else
                echo -e "${YELLOW}⚠${NC} SSL certificate verification failed"
                local verify_result=$(echo "$ssl_test" | grep "Verify return code" | head -1)
                echo -e "  ${GRAY}${verify_result}${NC}"
                echo -e "${YELLOW}Tip:${NC} You may need to set SSL_VERIFY=false or export the certificate"
            fi
        fi
        
        # Test API endpoint
        print_step "3" "3" "Testing NiFi API"
        local full_response=$(curl -s -S -w "\n%{http_code}" ${SSL_VERIFY:+-k} -X GET "${NIFI_API_URL}/flow/about" 2>&1)
        local http_code=$(echo "$full_response" | tail -n1)
        local body=$(echo "$full_response" | sed '$d')
        
        if [ "$http_code" = "200" ]; then
            echo -e "${GREEN}✓${NC} NiFi API is accessible"
            if echo "$body" | jq -e '.about.version' > /dev/null 2>&1; then
                local version=$(echo "$body" | jq -r '.about.version')
                echo -e "  ${GREEN}•${NC} NiFi Version: ${WHITE}$version${NC}"
            fi
        elif [ "$http_code" = "401" ]; then
            echo -e "${YELLOW}⚠${NC} NiFi API is accessible but requires authentication"
        else
            echo -e "${RED}✗${NC} NiFi API test failed with HTTP code: $http_code"
            log_error "Response: $body"
            return 1
        fi
    else
        log_error "Invalid URL format: $NIFI_API_URL"
        return 1
    fi
    
    echo ""
    echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}           Connection Test Complete                    ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
}

# ==============================================================================
# MAIN MENU - ENHANCED WITH COLOR FORMATTING
# ==============================================================================

show_menu() {
    clear
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║               NiFi GitHub Registry & Parameter Context Manager            ║${NC}"
    echo -e "${BLUE}║                         Enhanced Master Edition                           ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${CYAN}${BOLD} Authentication & System${NC}"
    echo -e "${CYAN} ──────────────────────────${NC}"
    echo -e "  ${YELLOW}1)${NC} ${WHITE}Authenticate with NiFi${NC}"
    echo -e "  ${YELLOW}2)${NC} ${WHITE}Test NiFi Connection${NC}"
    echo -e "  ${YELLOW}3)${NC} ${WHITE}Get NiFi Version${NC}"
    echo -e "  ${YELLOW}4)${NC} ${WHITE}Show Configuration${NC}"
    echo ""
    
    echo -e "${CYAN}${BOLD} Registry Client Operations${NC}"
    echo -e "${CYAN} ─────────────────────────────${NC}"
    echo -e "  ${YELLOW}10)${NC} ${WHITE}List Registry Types${NC}"
    echo -e "  ${YELLOW}11)${NC} ${WHITE}Create GitHub Registry Client${NC}"
    echo -e "  ${YELLOW}12)${NC} ${WHITE}List All Registries${NC}"
    echo -e "  ${YELLOW}13)${NC} ${WHITE}Get Registry Client by ID${NC}"
    echo -e "  ${YELLOW}14)${NC} ${WHITE}Delete Registry Client${NC}"
    echo ""
    
    echo -e "${CYAN}${BOLD} Flow Registry Operations${NC}"
    echo -e "${CYAN} ──────────────────────────${NC}"
    echo -e "  ${YELLOW}20)${NC} ${WHITE}List Buckets${NC}"
    echo -e "  ${YELLOW}21)${NC} ${WHITE}List Flows in Bucket${NC}"
    echo -e "  ${YELLOW}22)${NC} ${WHITE}List Flow Versions${NC}"
    echo -e "  ${YELLOW}23)${NC} ${WHITE}Start Version Control${NC}"
    echo ""
    
    echo -e "${CYAN}${BOLD} Parameter Context Operations${NC}"
    echo -e "${CYAN} ───────────────────────────────${NC}"
    echo -e "  ${YELLOW}30)${NC} ${WHITE}List Parameter Contexts${NC}"
    echo -e "  ${YELLOW}31)${NC} ${WHITE}Get Parameter Context Details${NC}"
    echo -e "  ${YELLOW}32)${NC} ${WHITE}Create Parameter Context${NC}"
    echo ""
    
    echo -e "${CYAN}${BOLD} SSL & Certificate Management${NC}"
    echo -e "${CYAN} ───────────────────────────────${NC}"
    echo -e "  ${YELLOW}40)${NC} ${WHITE}Export NiFi SSL Certificate${NC}"
    echo ""
    
    echo -e "${CYAN}${BOLD} Script Options${NC}"
    echo -e "${CYAN} ────────────────${NC}"
    echo -e "  ${YELLOW}V)${NC} ${WHITE}Toggle Verbose Mode${NC} ${GRAY}[Current: $VERBOSE]${NC}"
    echo -e "  ${YELLOW}Q)${NC} ${WHITE}Toggle Quiet Mode${NC} ${GRAY}[Current: $QUIET]${NC}"
    echo ""
    
    echo -e "${RED}${BOLD}  0)${NC} ${WHITE}Exit${NC}"
    echo ""
    
    echo -e "${GRAY}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -n "Select an option: "
}

interactive_mode() {
    check_dependencies
    
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1) 
                print_section "Authentication"
                authenticate || echo -e "${RED}✗ Authentication failed${NC}"
                ;;
            2) 
                print_section "Connection Test"
                test_connection || echo -e "${RED}✗ Connection test failed${NC}"
                ;;
            3)
                print_section "NiFi Version"
                if [ -n "$NIFI_VERSION" ]; then
                    echo -e "${GREEN}✓${NC} NiFi Version: ${WHITE}$NIFI_VERSION${NC}"
                else
                    authenticate || true
                    echo -e "${GREEN}✓${NC} NiFi Version: ${WHITE}$NIFI_VERSION${NC}"
                fi
                ;;
            4)
                print_config
                ;;
            10) 
                print_section "Registry Types"
                list_registry_types || echo -e "${RED}✗ Failed to list registry types${NC}"
                ;;
            11)
                print_section "Create GitHub Registry"
                create_github_registry || echo -e "${RED}✗ Failed to create registry${NC}"
                ;;
            12)
                print_section "All Registries"
                list_all_registries || echo -e "${RED}✗ Failed to list registries${NC}"
                ;;
            13)
                print_section "Registry Details"
                read -p "Registry ID: " reg_id
                if [ -n "$reg_id" ]; then
                    get_registry_client "$reg_id" || echo -e "${RED}✗ Failed to get registry details${NC}"
                else
                    echo -e "${RED}✗ Registry ID is required${NC}"
                fi
                ;;
            14)
                print_section "Delete Registry"
                read -p "Registry ID: " reg_id
                if [ -n "$reg_id" ]; then
                    read -p "Are you sure you want to delete registry $reg_id? (yes/no): " confirm
                    if [ "$confirm" = "yes" ]; then
                        delete_registry_client "$reg_id" || echo -e "${RED}✗ Failed to delete registry${NC}"
                    else
                        echo -e "${YELLOW}⚠ Deletion cancelled${NC}"
                    fi
                else
                    echo -e "${RED}✗ Registry ID is required${NC}"
                fi
                ;;
            20)
                print_section "List Buckets"
                if [ -z "$REGISTRY_ID" ]; then
                    read -p "Registry ID: " reg_id
                    list_buckets "$reg_id" || echo -e "${RED}✗ Failed to list buckets${NC}"
                else
                    list_buckets || echo -e "${RED}✗ Failed to list buckets${NC}"
                fi
                ;;
            21)
                print_section "List Flows"
                read -p "Registry ID: " reg_id
                read -p "Bucket ID: " bucket_id
                if [ -n "$reg_id" ] && [ -n "$bucket_id" ]; then
                    list_flows "$reg_id" "$bucket_id" || echo -e "${RED}✗ Failed to list flows${NC}"
                else
                    echo -e "${RED}✗ Registry ID and Bucket ID are required${NC}"
                fi
                ;;
            22)
                print_section "List Flow Versions"
                read -p "Registry ID: " reg_id
                read -p "Bucket ID: " bucket_id
                read -p "Flow ID: " flow_id
                if [ -n "$reg_id" ] && [ -n "$bucket_id" ] && [ -n "$flow_id" ]; then
                    list_flow_versions "$reg_id" "$bucket_id" "$flow_id" || echo -e "${RED}✗ Failed to list flow versions${NC}"
                else
                    echo -e "${RED}✗ Registry ID, Bucket ID, and Flow ID are required${NC}"
                fi
                ;;
            23)
                print_section "Start Version Control"
                read -p "Process Group ID: " pg_id
                read -p "Bucket ID: " bucket_id
                read -p "Flow Name: " flow_name
                read -p "Description (optional): " desc
                read -p "Comments (optional): " comments
                if [ -n "$pg_id" ] && [ -n "$bucket_id" ] && [ -n "$flow_name" ]; then
                    start_version_control "$pg_id" "$bucket_id" "$flow_name" "$desc" "${comments:-Initial version}" || echo -e "${RED}✗ Failed to start version control${NC}"
                else
                    echo -e "${RED}✗ Process Group ID, Bucket ID, and Flow Name are required${NC}"
                fi
                ;;
            30)
                print_section "Parameter Contexts"
                list_parameter_contexts || echo -e "${RED}✗ Failed to list parameter contexts${NC}"
                ;;
            31)
                print_section "Parameter Context Details"
                read -p "Enter Parameter Context ID: " ctx_id
                if [ -n "$ctx_id" ]; then
                    get_parameter_context "$ctx_id" || echo -e "${RED}✗ Failed to get parameter context${NC}"
                else
                    echo -e "${RED}✗ Parameter Context ID is required${NC}"
                fi
                ;;
            32)
                print_section "Create Parameter Context"
                read -p "Enter new Parameter Context name: " name
                read -p "Description (optional): " desc
                if [ -n "$name" ]; then
                    create_parameter_context "$name" "${desc:-Created via API}" || echo -e "${RED}✗ Failed to create parameter context${NC}"
                else
                    echo -e "${RED}✗ Parameter Context name is required${NC}"
                fi
                ;;
            40)
                print_section "Export SSL Certificate"
                read -p "Host [localhost]: " host
                read -p "Port [8443]: " port
                read -p "Output file [nifi-cert.pem]: " output
                export_nifi_certificate "${host:-localhost}" "${port:-8443}" "${output:-nifi-cert.pem}" || echo -e "${RED}✗ Failed to export certificate${NC}"
                ;;
            V|v)
                if [ "$VERBOSE" = true ]; then
                    VERBOSE=false
                    echo -e "${YELLOW}⚠${NC} Verbose mode disabled"
                else
                    VERBOSE=true
                    echo -e "${GREEN}✓${NC} Verbose mode enabled"
                fi
                sleep 1
                ;;
            Q|q)
                if [ "$QUIET" = true ]; then
                    QUIET=false
                    echo -e "${GREEN}✓${NC} Quiet mode disabled"
                else
                    QUIET=true
                    echo -e "${YELLOW}⚠${NC} Quiet mode enabled"
                fi
                sleep 1
                ;;
            0)
                echo ""
                echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
                echo -e "${GREEN}              Thank you for using NiFi Manager         ${NC}"
                echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "${RED}✗ Invalid option. Please try again.${NC}"
                sleep 1
                ;;
        esac
        
        echo ""
        if [ "$choice" != "V" ] && [ "$choice" != "v" ] && [ "$choice" != "Q" ] && [ "$choice" != "q" ]; then
            read -p "Press Enter to continue..."
        fi
    done
}

# ==============================================================================
# MISSING FUNCTIONS (to be implemented)
# ==============================================================================

# These functions are referenced but not defined in the original code
# Adding placeholder implementations

get_parameter_context() {
    local ctx_id=$1
    
    if [ -z "$ctx_id" ]; then
        log_error "Parameter Context ID is required"
        return 1
    fi
    
    print_section "Parameter Context Details"
    
    if ! verify_token; then
        authenticate
    fi
    
    log_info "Fetching parameter context: ${ctx_id}"
    local response=$(api_call "GET" "/parameter-contexts/${ctx_id}")
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo "$response" | jq '.'
    log_success "Parameter context retrieved"
}

delete_registry_client() {
    local registry_id=${1:-$REGISTRY_ID}
    
    if [ -z "$registry_id" ]; then
        log_error "Registry ID is required"
        return 1
    fi
    
    print_section "Delete Registry Client"
    
    if ! verify_token; then
        authenticate
    fi
    
    log_warning "Deleting registry client: ${registry_id}"
    
    # Get current version
    local current=$(api_call "GET" "/controller/registry-clients/${registry_id}")
    if [ $? -ne 0 ]; then
        return 1
    fi
    local version=$(echo "$current" | jq -r '.revision.version')
    
    local full_response=$(curl -s -S ${SSL_VERIFY:+-k} -w "\n%{http_code}" -X DELETE \
        "${NIFI_API_URL}/controller/registry-clients/${registry_id}?version=${version}" \
        -H "${AUTH_HEADER}" 2>&1)
    
    local http_code=$(echo "$full_response" | tail -n1)
    local body=$(echo "$full_response" | sed '$d')
    
    if [[ ! $http_code =~ ^2 ]]; then
        log_error "Delete failed with HTTP code: $http_code"
        log_error "Response: $body"
        return 1
    fi
    
    log_success "Registry client deleted"
}

export_nifi_certificate() {
    local host=${1:-localhost}
    local port=${2:-8443}
    local output=${3:-nifi-cert.pem}
    
    print_section "Export SSL Certificate"
    
    log_info "Exporting certificate from ${host}:${port}"
    
    echo | openssl s_client -servername "$host" -connect "${host}:${port}" 2>/dev/null | \
        openssl x509 -outform PEM > "$output"
    
    if [ $? -eq 0 ] && [ -s "$output" ]; then
        log_success "Certificate exported to: ${output}"
        log_info "To use this certificate, set: CERT_PATH=${output} and SSL_VERIFY=true"
    else
        log_error "Failed to export certificate"
        return 1
    fi
}

# ==============================================================================
# USAGE FUNCTION - ENHANCED WITH COLOR FORMATTING
# ==============================================================================

show_usage() {
    echo -e "${BOLD}${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║          NiFi GitHub Registry & Parameter Context Manager                 ║"
    echo "║                              Help Documentation                           ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    
    echo -e "${BOLD}${CYAN}SYNOPSIS${NC}"
    echo -e "  $0 [OPTIONS] [COMMAND] [ARGS...]"
    echo -e "  $0 --interactive\n"
    
    echo -e "${BOLD}${CYAN}DESCRIPTION${NC}"
    echo -e "  Comprehensive management tool for NiFi GitHub Flow Registries and Parameter Contexts."
    echo -e "  Supports authentication, registry management, version control, and parameter context operations.\n"
    
    echo -e "${BOLD}${CYAN}OPTIONS${NC}"
    echo -e "  ${YELLOW}--help, -h${NC}              Display this help message and exit"
    echo -e "  ${YELLOW}--interactive, -i${NC}       Run in interactive mode"
    echo -e "  ${YELLOW}--url, -u${NC} URL           NiFi API URL (default: https://idol-docker-host:8443/nifi-api)"
    echo -e "  ${YELLOW}--username, -U${NC} USER     NiFi username (default: admin)"
    echo -e "  ${YELLOW}--password, -P${NC} PASS     NiFi password (default: Nifi-Admin1!)"
    echo -e "  ${YELLOW}--github-repo${NC} URL       GitHub repository URL"
    echo -e "  ${YELLOW}--github-token${NC} TOKEN    GitHub personal access token"
    echo -e "  ${YELLOW}--ssl-verify${NC} BOOL       Verify SSL (true/false, default: false)"
    echo -e "  ${YELLOW}--verbose, -v${NC}           Enable verbose output"
    echo -e "  ${YELLOW}--quiet, -q${NC}             Suppress non-essential output\n"
    
    echo -e "${BOLD}${CYAN}COMMANDS${NC}"
    echo -e "  ${YELLOW}auth${NC}                    Authenticate with NiFi"
    echo -e "  ${YELLOW}test-connection${NC}         Test NiFi Connection"
    echo -e "  ${YELLOW}get-version${NC}             Get NiFi Version"
    echo -e "  ${YELLOW}list-registry-types${NC}     List Registry Types"
    echo -e "  ${YELLOW}create-registry${NC}         Create GitHub Registry Client"
    echo -e "  ${YELLOW}list-registries${NC}         List All Registries"
    echo -e "  ${YELLOW}get-registry <id>${NC}       Get Registry Client by ID"
    echo -e "  ${YELLOW}list-buckets${NC}            List Buckets"
    echo -e "  ${YELLOW}list-flows <reg> <bucket>${NC}  List Flows in Bucket"
    echo -e "  ${YELLOW}list-parameter-contexts${NC} List Parameter Contexts"
    echo -e "  ${YELLOW}create-parameter-context <name>${NC} Create Parameter Context\n"
    
    echo -e "${BOLD}${CYAN}EXAMPLES${NC}"
    echo -e "  ${GRAY}# Interactive mode${NC}"
    echo -e "  $0 --interactive\n"
    
    echo -e "  ${GRAY}# Create GitHub registry${NC}"
    echo -e "  $0 --url https://nifi:8443/nifi-api \\"
    echo -e "     --username admin --password pass \\"
    echo -e "     --github-repo https://github.com/org/repo.git \\"
    echo -e "     --github-token ghp_xxxx \\"
    echo -e "     create-registry\n"
    
    echo -e "  ${GRAY}# List all registries${NC}"
    echo -e "  $0 -u https://nifi:8443/nifi-api list-registries\n"
    
    echo -e "  ${GRAY}# Export SSL certificate${NC}"
    echo -e "  $0 export-cert nifi.example.com 8443 nifi-cert.pem\n"
    
    echo -e "${BOLD}${CYAN}ENVIRONMENT VARIABLES${NC}"
    echo -e "  ${CYAN}NIFI_API_URL${NC}        NiFi API URL"
    echo -e "  ${CYAN}NIFI_USERNAME${NC}       NiFi username"
    echo -e "  ${CYAN}NIFI_PASSWORD${NC}       NiFi password"
    echo -e "  ${CYAN}GITHUB_REPO_URL${NC}     GitHub repository URL"
    echo -e "  ${CYAN}GITHUB_TOKEN${NC}        GitHub personal access token"
    echo -e "  ${CYAN}SSL_VERIFY${NC}          SSL verification flag\n"
    
    echo -e "${BOLD}${CYAN}REQUIREMENTS${NC}"
    echo -e "  - ${WHITE}curl${NC} (required for API calls)"
    echo -e "  - ${WHITE}jq${NC} (required for JSON parsing)"
    echo -e "  - ${WHITE}openssl${NC} (recommended for SSL certificate export)\n"
    
    echo -e "${BOLD}${CYAN}AUTHOR${NC}"
    echo -e "  NiFi GitHub Registry Client - Enhanced Master Edition"
    echo ""
    
    exit 0
}

# ==============================================================================
# COMMAND LINE ARGUMENT PARSING
# ==============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                ;;
            -i|--interactive)
                INTERACTIVE=true
                shift
                ;;
            -u|--url)
                NIFI_API_URL="$2"
                shift 2
                ;;
            -U|--username)
                NIFI_USERNAME="$2"
                shift 2
                ;;
            -P|--password)
                NIFI_PASSWORD="$2"
                shift 2
                ;;
            --github-repo)
                GITHUB_REPO_URL="$2"
                shift 2
                ;;
            --github-token)
                GITHUB_TOKEN="$2"
                shift 2
                ;;
            --ssl-verify)
                SSL_VERIFY="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            *)
                # Unknown option
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

# Display banner if not quiet
if [ "$QUIET" = false ]; then
    echo -e "${BOLD}${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║          NiFi GitHub Registry & Parameter Context Manager                 ║"
    echo "║                         Enhanced Master Edition                           ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
fi

# Parse command line arguments
parse_args "$@"

# Run interactive mode if specified
if [ "$INTERACTIVE" = true ] || [ $# -eq 0 ]; then
    interactive_mode
else
    # Non-interactive mode with commands (to be implemented based on requirements)
    echo -e "${YELLOW}⚠ Non-interactive command mode not fully implemented${NC}"
    echo -e "${CYAN}Please use --interactive flag or run without arguments${NC}"
    show_usage
fi