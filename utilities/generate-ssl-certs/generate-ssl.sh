#!/usr/bin/env bash
# ==============================================================================
# generate-ssl.sh — IDOL SSL Certificate Generation
#
# Builds a full CA hierarchy (Root → Intermediate → Service certs) with
# proper Subject Alternative Names, Java keystores, and system trust store
# installation.
#
# Usage:
#   ./generate-ssl.sh              Interactive (prompts for all inputs)
#   ./generate-ssl.sh --auto       Non-interactive: auto-generate passwords,
#                                  use built-in subject defaults
#   ./generate-ssl.sh --help       Show usage
#
# Environment variables:
#   SSL_SERVICE_USER   OS user that IDOL processes run as   (e.g. idol)
#   SSL_SERVICE_GROUP  OS group for private key read access (e.g. idol)
#   EXTRA_IP_SANS_ENV  Comma-separated IPs for --auto mode  (e.g. 172.25.125.123,10.0.0.5)
#   NIFI_CONTAINER     Docker container name for NiFi        (default: idol-demo-idol-nifi-1)
#   IDOL_NET_HOST_IP   Default value for Extra DNS/IP SANs in interactive mode
# ==============================================================================
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# COLOURS
# ==============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly ORANGE='\033[38;5;214m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# ==============================================================================
# PATHS & CONSTANTS
# ==============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

readonly DAYS_ROOT=7300          # 20 years — Root CA
readonly DAYS_INTERMEDIATE=3650  # 10 years — Intermediate CA
readonly DAYS_CERT=825           #  ~2 years — Service certs

readonly SSL_ROOT="${SCRIPT_DIR}/ssl"
readonly CA_DIR="${SSL_ROOT}/intermediate"
readonly CERTS_DIR="${CA_DIR}/certs"
readonly PRIVATE_DIR="${CA_DIR}/private"
readonly NIFI_DIR="${CA_DIR}/nifi"
readonly LOG_DIR="${SCRIPT_DIR}/logs"

readonly DEPLOY_BASIC_IDOL="${REPO_ROOT}/idol-containers-toolkit/basic-idol/ssl"
readonly DEPLOY_DATA_ADMIN="${REPO_ROOT}/idol-containers-toolkit/data-admin/ssl"
readonly DEPLOY_RICH_MEDIA="${REPO_ROOT}/idol-containers-toolkit/rich-media/ssl"
readonly DEPLOY_LICENSESERVER="${REPO_ROOT}/idol-licenseserver/ssl"

readonly SSL_PASSWORDS_ENV="${REPO_ROOT}/env/.idol-ssl-passwords.env"

# External hostname embedded in every service cert SAN
readonly EXTERNAL_HOSTNAME="idol-docker-host"

# ==============================================================================
# NEW: Automatic Hostname + FQDN SAN Injection (lower + UPPER case)
# The script now auto-detects your machine's hostname (short + FQDN if different)
# and always injects both lowercase and UPPERCASE versions into every cert.
# No manual typing needed in the "Extra DNS SANs" prompt anymore.
# ==============================================================================

# NiFi Docker container name — override via env if yours differs
NIFI_CONTAINER="${NIFI_CONTAINER:-idol-demo-idol-nifi-1}"

# ==============================================================================
# SERVICE ACCOUNT — controls private key ownership after generation/deployment
# ==============================================================================
SSL_SERVICE_USER="${SSL_SERVICE_USER:-}"
SSL_SERVICE_GROUP="${SSL_SERVICE_GROUP:-}"

# Comma-separated extra IPs for --auto mode (e.g. EXTRA_IP_SANS_ENV="10.0.0.5,192.168.1.1")
EXTRA_IP_SANS_ENV="${EXTRA_IP_SANS_ENV:-}"

readonly -a SERVICES=(
    idol-docker-host
    obsidian
    idol-agentstore
    idol-category
    idol-categorisation-agentstore
    idol-community
    idol-content
    idol-find
    idol-httpd-reverse-proxy
    idol-licenseserver
    idol-nifi
    idol-view
    idol-dataadmin
    idol-dataadmin-community
    idol-dataadmin-viewserver
    idol-dataadmin-statsserver
    idol-dataadmin-find
    idol-qms
    idol-qms-agentstore
    idol-answerserver
    idol-passageextractor-agentstore
    idol-passageextractor-content
    idol-factbank-postgres
    idol-answerbank-agentstore
    idol-mediaserver
    idol-mmap-playlistserver
    idol-mmap-app
)

readonly -a HEALTH_CHECKS=(
    "Community:9030"
    "ViewServer:9080"
    "Content:9100"
    "AnswerServer:12000"
    "QMS:16000"
    "StatsServer:19870"
    "Agentstore:20050"
)

# ==============================================================================
# RUNTIME STATE  (mutable globals)
# ==============================================================================
AUTO_MODE=false
SKIP_GENERATION=false
LOG_FILE=""
KEYSTORE_PASS=""
TRUSTSTORE_PASS=""
HEALTH_FAIL_COUNT=0

# Certificate subject fields — populated by collect_subject_info()
CERT_COUNTRY="US"
CERT_STATE="State"
CERT_CITY="City"
CERT_ORG="Organization"
CERT_OU="IT"

# FIX: both arrays declared globally so write_service_cnf() can always see them
EXTRA_DNS_SANS=()   # Additional DNS SANs beyond the four defaults
EXTRA_IP_SANS=()    # Additional IP SANs beyond 127.0.0.1

declare -A CERT_STATUS=()
CERT_FAILURES=0

# ==============================================================================
# AUTO-DETECTED HOSTNAME + FQDN (lower + UPPER case) — always injected automatically
# ==============================================================================
DETECTED_HOSTNAME="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo 'localhost')"
DETECTED_FQDN="$(hostname -f 2>/dev/null || echo '')"

HOSTNAME_LOWER="$(echo "${DETECTED_HOSTNAME}" | tr '[:upper:]' '[:lower:]')"
HOSTNAME_UPPER="$(echo "${DETECTED_HOSTNAME}" | tr '[:lower:]' '[:upper:]')"

FQDN_LOWER=""
FQDN_UPPER=""
if [[ -n "${DETECTED_FQDN}" && "${DETECTED_FQDN}" != "${DETECTED_HOSTNAME}" ]]; then
    FQDN_LOWER="$(echo "${DETECTED_FQDN}" | tr '[:upper:]' '[:lower:]')"
    FQDN_UPPER="$(echo "${DETECTED_FQDN}" | tr '[:lower:]' '[:upper:]')"
fi

readonly DETECTED_HOSTNAME HOSTNAME_LOWER HOSTNAME_UPPER DETECTED_FQDN FQDN_LOWER FQDN_UPPER

# ==============================================================================
# LOGGING
# ==============================================================================
setup_logging() {
    mkdir -p "${LOG_DIR}"
    LOG_FILE="${LOG_DIR}/generate-ssl-$(date +%Y%m%d_%H%M%S).log"
    exec 3>>"${LOG_FILE}"
    exec > >(tee >(sed 's/\x1b\[[0-9;]*m//g' >> "${LOG_FILE}")) 2>&1
    log_info "Log: ${LOG_FILE}"
}

log_only()    { "$@" >&3 2>&3; }
log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_ok()      { echo -e "  ${GREEN}✓${NC}  $*"; }
log_fail()    { echo -e "  ${RED}✗${NC}  $*"; }
log_skip()    { echo -e "  ${ORANGE}↷${NC}  $*"; }

log_section() {
    local title="$1" width=65
    local border; border=$(printf '═%.0s' $(seq 1 "${width}"))
    echo ""
    echo -e "${BLUE}${border}${NC}"
    printf "${BLUE}  %-$((width-2))s${NC}\n" "${title}"
    echo -e "${BLUE}${border}${NC}"
    echo ""
}

# ==============================================================================
# ERROR HANDLING
# ==============================================================================
on_error() {
    local exit_code=$? line="${1:-unknown}"
    log_error "Failed at line ${line} (exit ${exit_code})"
    log_error "Full trace: bash -x ${SCRIPT_NAME}"
    exit "${exit_code}"
}
trap 'on_error ${LINENO}' ERR

# ==============================================================================
# USAGE
# ==============================================================================
usage() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  ${BOLD}IDOL SSL Certificate Generator${NC}                                   ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Usage:${NC}  ${CYAN}${SCRIPT_NAME}${NC} [OPTIONS]"
    echo ""
    echo -e "  ${BOLD}Options:${NC}"
    echo -e "    ${GREEN}-a, --auto${NC}     Non-interactive mode (auto-generate passwords + defaults)"
    echo -e "    ${GREEN}-h, --help${NC}     Show this help message"
    echo ""
    echo -e "  ${BOLD}Key Paths:${NC}"
    echo -e "    Repo root:     ${YELLOW}${REPO_ROOT}${NC}"
    echo -e "    SSL output:    ${YELLOW}${SSL_ROOT}${NC}"
    echo -e "    Password file: ${YELLOW}${SSL_PASSWORDS_ENV}${NC}"
    echo ""
    echo -e "  ${BOLD}Environment Variables:${NC}"
    echo -e "    ${CYAN}SSL_SERVICE_USER${NC}     OS user for IDOL processes (e.g. idol)"
    echo -e "    ${CYAN}SSL_SERVICE_GROUP${NC}    Group for private key access (e.g. idol)"
    echo -e "    ${CYAN}EXTRA_IP_SANS_ENV${NC}    Extra IPs for --auto mode (CSV)"
    echo -e "    ${CYAN}NIFI_CONTAINER${NC}       Docker container name for NiFi"
    echo -e "    ${CYAN}IDOL_NET_HOST_IP${NC}     Default IP shown in Extra IP SANs prompt"
    echo ""
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--auto)
                AUTO_MODE=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_warn "Unknown argument ignored: $1"
                shift
                ;;
        esac
    done
}

# ==============================================================================
# PREREQUISITES
# ==============================================================================
check_prerequisites() {
    log_section "Checking Prerequisites"
    local missing=()
    for tool in openssl keytool curl sudo docker; do
        if command -v "${tool}" &>/dev/null; then
            log_ok "${tool}"
        else
            log_fail "${tool} — not found"
            missing+=("${tool}")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        exit 1
    fi
}

# ==============================================================================
# CERTIFICATE SUBJECT INFORMATION
# ==============================================================================
collect_subject_info() {
    log_section "Certificate Subject Information"

    # ── Auto mode: use defaults + parse env-var IPs ───────────────────────────
    if [[ "${AUTO_MODE}" == true ]]; then
        # Parse EXTRA_IP_SANS_ENV into the global array
        if [[ -n "${EXTRA_IP_SANS_ENV}" ]]; then
            IFS=',' read -ra EXTRA_IP_SANS <<< "${EXTRA_IP_SANS_ENV}"
            # Trim whitespace from each entry
            local _cleaned=()
            for _ip in "${EXTRA_IP_SANS[@]}"; do
                _ip="${_ip//[[:space:]]/}"
                [[ -n "${_ip}" ]] && _cleaned+=("${_ip}")
            done
            EXTRA_IP_SANS=("${_cleaned[@]}")
        fi

        log_info "Auto mode — using default subject values."
        echo ""
        echo -e "  ${BOLD}Subject DN (all certs):${NC}"
        echo -e "    C  = ${CERT_COUNTRY}"
        echo -e "    ST = ${CERT_STATE}"
        echo -e "    L  = ${CERT_CITY}"
        echo -e "    O  = ${CERT_ORG}"
        echo -e "    OU = ${CERT_OU}"
        echo -e "    CN = <per-service name>"
        echo ""
        echo -e "  ${BOLD}SANs per cert:${NC}"
        echo -e "    DNS.1 = <service-name>"
        echo -e "    DNS.2 = ${EXTERNAL_HOSTNAME}"
        echo -e "    DNS.3 = localhost"
        echo -e "    IP.1  = 127.0.0.1"
        echo -e "    ${CYAN}+ auto-injected (always, deduplicated):${NC}"
        echo -e "        DNS.x = ${HOSTNAME_LOWER}   (hostname lower)"
        echo -e "        DNS.y = ${HOSTNAME_UPPER}   (hostname UPPER)"
        if [[ -n "${FQDN_LOWER}" ]]; then
            echo -e "        DNS.x = ${FQDN_LOWER}   (FQDN lower)"
            echo -e "        DNS.y = ${FQDN_UPPER}   (FQDN UPPER)"
        fi
        if [[ ${#EXTRA_IP_SANS[@]} -gt 0 ]]; then
            local _i=2
            for _ip in "${EXTRA_IP_SANS[@]}"; do
                echo -e "    IP.${_i} = ${_ip}"
                _i=$((_i + 1))
            done
        fi
        return 0
    fi

    # ── Interactive mode ──────────────────────────────────────────────────────
    echo -e "  These values are embedded in ${BOLD}every${NC} generated certificate."
    echo -e "  Press ${CYAN}Enter${NC} to accept the default shown in [brackets]."
    echo ""

    echo -e "  ${BOLD}${YELLOW}Subject Distinguished Name${NC}"
    echo -e "${YELLOW}"

    local _in
    read -r -p "  Country Name (2-letter ISO code)    [${CERT_COUNTRY}]: " _in
    CERT_COUNTRY="${_in:-${CERT_COUNTRY}}"
    while [[ ! "${CERT_COUNTRY}" =~ ^[A-Za-z]{2}$ ]]; do
        log_warn "Country must be exactly 2 letters (e.g. US, GB, IL)."
        read -r -p "  Country Name (2-letter ISO code)    [US]: " _in
        CERT_COUNTRY="${_in:-US}"
    done
    CERT_COUNTRY="${CERT_COUNTRY^^}"

    read -r -p "  State / Province Name               [${CERT_STATE}]: " _in
    CERT_STATE="${_in:-${CERT_STATE}}"

    read -r -p "  Locality / City                     [${CERT_CITY}]: " _in
    CERT_CITY="${_in:-${CERT_CITY}}"

    read -r -p "  Organization Name                   [${CERT_ORG}]: " _in
    CERT_ORG="${_in:-${CERT_ORG}}"

    read -r -p "  Organizational Unit                 [${CERT_OU}]: " _in
    CERT_OU="${_in:-${CERT_OU}}"

    echo ""
    echo -e "  ${BOLD}Common Name${NC}"
    echo -e "  ${CYAN}  CN is set automatically per service${NC}"
    echo ""

    # ── SAN collection ─────────────────────────────────────────────────────────
    echo -e "  ${BOLD}Subject Alternative Names (SANs)${NC}"
    echo ""
    echo -e "  Added to ${BOLD}every${NC} cert automatically:"
    echo -e "    ${CYAN}DNS.1 = <service-name>${NC}  (Docker-internal hostname)"
    echo -e "    ${CYAN}DNS.2 = ${EXTERNAL_HOSTNAME}${NC}"
    echo -e "    ${CYAN}DNS.3 = localhost${NC}"
    echo -e "    ${CYAN}IP.1  = 127.0.0.1${NC}"
    echo ""
    echo -e "  ${GREEN}Automatically added to every cert (no need to type anything):${NC}"
    echo -e "    DNS.x = ${HOSTNAME_LOWER}   (hostname lower)"
    echo -e "    DNS.y = ${HOSTNAME_UPPER}   (hostname UPPER)"
    if [[ -n "${FQDN_LOWER}" ]]; then
        echo -e "    DNS.x = ${FQDN_LOWER}   (FQDN lower)"
        echo -e "    DNS.y = ${FQDN_UPPER}   (FQDN UPPER)"
    fi
    echo ""

    # =====================================================
    # Extra DNS SANs (OPTIONAL — only add more if you really need them)
    # Note: idol-docker-host + your hostname (both cases) are already included above.
    # =====================================================
    echo -e "  ${CYAN}Additional DNS SANs (comma-separated, or Enter to skip)."
    echo -e "  Example: myserver.example.com, *.internal.corp${YELLOW}"
    local _san_input
    read -r -p "  Extra DNS SANs []: " _san_input
    echo -e "${NC}"

    EXTRA_DNS_SANS=()
    if [[ -n "${_san_input}" ]]; then
        IFS=',' read -ra _raw_sans <<< "${_san_input}"
        for _san in "${_raw_sans[@]}"; do
            _san="${_san//[[:space:]]/}"
            [[ -n "${_san}" ]] && EXTRA_DNS_SANS+=("${_san}")
        done
    fi

    # =====================================================
    # Extra IP SANs — defaults to IDOL_NET_HOST_IP if set
    # =====================================================
    local _ip_default="${EXTRA_IP_SANS_ENV:-}"
    echo -e "  ${CYAN}Additional IP SANs (comma-separated, or Enter to skip)."
    echo -e "  ${RED}WARNING: If using a remote hyperscaler (e,g, Azure) Linux environment, please enter the remote hyperscaler IP address here.${YELLOW}"
    local _ip_input
    read -r -p "  Extra IP SANs [${_ip_default:-none}]: " _ip_input
    _ip_input="${_ip_input:-${_ip_default}}"
    echo -e "${NC}"

    EXTRA_IP_SANS=()
    if [[ -n "${_ip_input}" ]]; then
        IFS=',' read -ra _raw_ips <<< "${_ip_input}"
        for _ip in "${_raw_ips[@]}"; do
            _ip="${_ip//[[:space:]]/}"
            [[ -n "${_ip}" ]] && EXTRA_IP_SANS+=("${_ip}")
        done
    fi

    # ── Review block ───────────────────────────────────────────────────────────
    local border; border=$(printf '─%.0s' $(seq 1 55))
    echo ""
    echo -e "  ${CYAN}${border}${NC}"
    echo -e "  ${BOLD}Review certificate settings${NC}"
    echo -e "  ${CYAN}${border}${NC}"
    echo ""
    echo -e "  ${BOLD}Subject DN:${NC}"
    echo -e "    C  = ${CERT_COUNTRY}"
    echo -e "    ST = ${CERT_STATE}"
    echo -e "    L  = ${CERT_CITY}"
    echo -e "    O  = ${CERT_ORG}"
    echo -e "    OU = ${CERT_OU}"
    echo -e "    CN = <per-service name>"
    echo ""
    echo -e "  ${BOLD}SANs per cert:${NC}"
    echo -e "    DNS.1 = <service-name>"
    echo -e "    DNS.2 = ${EXTERNAL_HOSTNAME}"
    echo -e "    DNS.3 = localhost"
    echo -e "    IP.1  = 127.0.0.1"
    echo -e "    ${CYAN}+ auto-injected (if not duplicate):${NC}"
    echo -e "        DNS.x = ${HOSTNAME_LOWER}   (hostname lower)"
    echo -e "        DNS.y = ${HOSTNAME_UPPER}   (hostname UPPER)"
    if [[ -n "${FQDN_LOWER}" ]]; then
        echo -e "        DNS.x = ${FQDN_LOWER}   (FQDN lower)"
        echo -e "        DNS.y = ${FQDN_UPPER}   (FQDN UPPER)"
    fi

    if [[ ${#EXTRA_DNS_SANS[@]} -gt 0 ]]; then
        local _di=4
        for _san in "${EXTRA_DNS_SANS[@]}"; do
            echo -e "    DNS.${_di} = ${_san}"
            _di=$((_di + 1))
        done
    fi

    if [[ ${#EXTRA_IP_SANS[@]} -gt 0 ]]; then
        local _ii=2
        for _ip in "${EXTRA_IP_SANS[@]}"; do
            echo -e "    IP.${_ii} = ${_ip}"
            _ii=$((_ii + 1))
        done
    fi

    echo ""
    echo -e "  ${BOLD}Validity:${NC}"
    echo -e "    Root CA:        ${DAYS_ROOT} days  (~$((DAYS_ROOT / 365)) years)"
    echo -e "    Intermediate:   ${DAYS_INTERMEDIATE} days  (~$((DAYS_INTERMEDIATE / 365)) years)"
    echo -e "    Service certs:  ${DAYS_CERT} days   (~$((DAYS_CERT / 365)) years)"
    echo ""
    echo -e "  ${CYAN}${border}${NC}"
    echo -e "${YELLOW}"
    read -r -p "  Confirm and continue? [Enter / Ctrl+C to abort]: " _
    echo -e "${NC}"
}

# ==============================================================================
# PASSWORD MANAGEMENT
# ==============================================================================
generate_random_password() {
    openssl rand -base64 48 2>/dev/null | tr -d '\n=/+' | cut -c1-43
}

prompt_password() {
    local label="$1" pass1 pass2
    while true; do
        read -r -s -p "  Enter ${label}: " pass1; echo
        read -r -s -p "  Confirm ${label}: " pass2; echo
        [[ "${pass1}" == "${pass2}" ]] && { echo "${pass1}"; return 0; }
        log_warn "Passwords do not match — try again."
    done
}

setup_passwords() {
    log_section "KeyStore / TrustStore Passwords"

    if [[ "${AUTO_MODE}" == true ]]; then
        KEYSTORE_PASS=$(generate_random_password)
        TRUSTSTORE_PASS=$(generate_random_password)
        log_ok "Auto-generated KeyStore password:   ${KEYSTORE_PASS}"
        log_ok "Auto-generated TrustStore password: ${TRUSTSTORE_PASS}"
    else
        echo -e "  ${YELLOW}Generate random passwords?${NC}"
        echo -e "    ${CYAN}1)${NC} Yes — auto-generate  ${GREEN}(recommended)${NC}"
        echo -e "    ${CYAN}2)${NC} No  — enter manually${YELLOW}"
        local _pw_choice
        read -r -p "  Choice [1/2] (default: 1): " _pw_choice
        _pw_choice="${_pw_choice:-1}"
        echo ""

        if [[ "${_pw_choice}" == "1" ]]; then
            KEYSTORE_PASS=$(generate_random_password)
            TRUSTSTORE_PASS=$(generate_random_password)
            log_ok "KeyStore password:   ${KEYSTORE_PASS}"
            log_ok "TrustStore password: ${TRUSTSTORE_PASS}"
        else
            KEYSTORE_PASS=$(prompt_password "KeyStore password")
            TRUSTSTORE_PASS=$(prompt_password "TrustStore password")
        fi
    fi

    export IDOL_CERT_KEYSTORE_PASS="${KEYSTORE_PASS}"
    export IDOL_CERT_TRUSTSTORE_PASS="${TRUSTSTORE_PASS}"

    mkdir -p "$(dirname "${SSL_PASSWORDS_ENV}")"
    cat > "${SSL_PASSWORDS_ENV}" <<EOF
export IDOL_CERT_KEYSTORE_PASS="${KEYSTORE_PASS}"
export IDOL_CERT_TRUSTSTORE_PASS="${TRUSTSTORE_PASS}"
EOF
    chmod 600 "${SSL_PASSWORDS_ENV}"
    log_ok "Credentials saved: ${SSL_PASSWORDS_ENV}"

    sed -i '/^source .*\.idol-ssl-passwords\.env"$/d' ~/.bashrc
    echo "source \"${SSL_PASSWORDS_ENV}\"" >> ~/.bashrc
    log_ok "Added to ~/.bashrc"
}

# ==============================================================================
# CONFIRM BEFORE WIPING EXISTING SSL
# ==============================================================================
confirm_regeneration() {
    [[ ! -d "${SSL_ROOT}" ]] && return 0

    if [[ "${AUTO_MODE}" == true ]]; then
        log_warn "Existing SSL directory found — auto mode: regenerating."
        sudo rm -rf "${SSL_ROOT}"
        return 0
    fi

    log_warn "Existing SSL directory found: ${SSL_ROOT}"
    echo ""
    echo -e "  ${BOLD}What would you like to do?${NC}"
    echo -e "    ${CYAN}s)${NC} Skip generation — redeploy + fix permissions on existing certs  ${GREEN}(fast)${NC}"
    echo -e "    ${CYAN}r)${NC} Regenerate       — delete everything and create new certs"
    echo -e "    ${CYAN}a)${NC} Abort"
    echo ""

    local _answer
    while true; do
        echo -e "${YELLOW}"
        read -r -p "  Choice [s/r/a]: " _answer
        echo -e "${NC}"
        case "${_answer,,}" in
            s|skip)
                SKIP_GENERATION=true
                log_info "Skipping generation — existing certs will be redeployed."
                return 0 ;;
            r|regen|regenerate)
                log_warn "Deleting ${SSL_ROOT} …"
                sudo rm -rf "${SSL_ROOT}"
                log_ok "Deleted. Fresh certificates will be generated."
                return 0 ;;
            a|abort)
                log_info "Aborted."
                exit 0 ;;
            *)
                log_warn "Enter 's' to skip, 'r' to regenerate, or 'a' to abort." ;;
        esac
    done
}

# ==============================================================================
# CA DIRECTORY & CONFIG INITIALISATION
# ==============================================================================
init_ca_directory() {
    log_section "Initialising CA Directory Structure"

    mkdir -p "${CERTS_DIR}" "${PRIVATE_DIR}" "${NIFI_DIR}" "${CA_DIR}/issued"
    chmod 700 "${PRIVATE_DIR}"
    touch "${CA_DIR}/index.txt"
    echo 1000 > "${CA_DIR}/serial"
    echo 1000 > "${CA_DIR}/crlnumber"

    log_ok "Directories created under ${CA_DIR}"

    # ── Root CA config ─────────────────────────────────────────────────────────
    cat > "${CA_DIR}/openssl-root-ca.cnf" <<ROOTCNF
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = ${CA_DIR}
certs             = \$dir/certs
new_certs_dir     = \$dir/issued
database          = \$dir/index.txt
serial            = \$dir/serial
RANDFILE          = \$dir/private/.rand
private_key       = \$dir/private/ca.key.pem
certificate       = \$dir/certs/ca.cert.pem
crlnumber         = \$dir/crlnumber
default_crl_days  = 30
default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_loose

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 4096
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha256
x509_extensions     = v3_ca

[ req_distinguished_name ]
countryName             = Country Name (2 letter code)
stateOrProvinceName     = State or Province Name
localityName            = Locality Name
0.organizationName      = Organization Name
organizationalUnitName  = Organizational Unit Name
commonName              = Common Name

[ v3_ca ]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints       = critical, CA:true
keyUsage               = critical, digitalSignature, cRLSign, keyCertSign

[ v3_intermediate_ca ]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints       = critical, CA:true, pathlen:0
keyUsage               = critical, digitalSignature, cRLSign, keyCertSign

[ crl_ext ]
authorityKeyIdentifier = keyid:always
ROOTCNF

    # ── Intermediate CA config ─────────────────────────────────────────────────
    cat > "${CA_DIR}/openssl-ca.cnf" <<INTCNF
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = ${CA_DIR}
certs             = \$dir/certs
new_certs_dir     = \$dir/issued
database          = \$dir/index.txt
serial            = \$dir/serial
RANDFILE          = \$dir/private/.rand
private_key       = \$dir/private/intermediate.key.pem
certificate       = \$dir/certs/intermediate.cert.pem
crlnumber         = \$dir/crlnumber
default_crl_days  = 30
default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_loose
copy_extensions   = copy

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 2048
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha256

[ req_distinguished_name ]
countryName             = Country Name (2 letter code)
stateOrProvinceName     = State or Province Name
localityName            = Locality Name
0.organizationName      = Organization Name
organizationalUnitName  = Organizational Unit Name
commonName              = Common Name

[ server_cert ]
basicConstraints       = CA:FALSE
nsCertType             = server
nsComment              = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always
keyUsage               = critical, digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth

[ crl_ext ]
authorityKeyIdentifier = keyid:always
INTCNF

    log_ok "OpenSSL CA configs written"
}

# ==============================================================================
# HELPER: Write per-service CNF with SANs to a temp file
# Uses globals: EXTRA_DNS_SANS, EXTRA_IP_SANS, EXTERNAL_HOSTNAME
# ==============================================================================
write_service_cnf() {
    local service="$1"
    local cnf_file; cnf_file="$(mktemp /tmp/idol-ssl-XXXXXX.cnf)"

    # Build alt_names block — start with the four fixed entries
    # + ALWAYS auto-inject detected hostname in lower + UPPER case (deduplicated)
    local -a alt_lines=()
    alt_lines+=("DNS.1 = ${service}")
    alt_lines+=("DNS.2 = ${EXTERNAL_HOSTNAME}")
    alt_lines+=("DNS.3 = localhost")
    alt_lines+=("IP.1  = 127.0.0.1")

    local next_dns_idx=4

    # Local helper: add DNS SAN only if not already present (exact value match)
    _add_dns_san() {
        local val="$1"
        local existing
        for existing in "${alt_lines[@]}"; do
            if [[ "${existing}" == *"= ${val}" ]]; then
                return 0   # duplicate — skip
            fi
        done
        alt_lines+=("DNS.${next_dns_idx} = ${val}")
        ((next_dns_idx++))
    }

    # === AUTO-INJECT: hostname + FQDN (lower + upper) — always, with deduplication ===
    if [[ -n "${HOSTNAME_LOWER}" ]]; then
        _add_dns_san "${HOSTNAME_LOWER}"
    fi
    if [[ -n "${HOSTNAME_UPPER}" && "${HOSTNAME_UPPER}" != "${HOSTNAME_LOWER}" ]]; then
        _add_dns_san "${HOSTNAME_UPPER}"
    fi

    # FQDN (only if different from short hostname)
    if [[ -n "${FQDN_LOWER}" ]]; then
        _add_dns_san "${FQDN_LOWER}"
    fi
    if [[ -n "${FQDN_UPPER}" && "${FQDN_UPPER}" != "${FQDN_LOWER}" ]]; then
        _add_dns_san "${FQDN_UPPER}"
    fi

    # Append any EXTRA_DNS_SANS provided by user in interactive mode (still supported)
    for _san in "${EXTRA_DNS_SANS[@]+"${EXTRA_DNS_SANS[@]}"}"; do
        [[ -z "${_san}" ]] && continue
        _add_dns_san "${_san}"
    done

    # Rebuild alt_block string from the array (includes auto + extras)
    local alt_block=""
    for line in "${alt_lines[@]}"; do
        alt_block+="${line}
"
    done

    # Append extra IP SANs (global array, always visible here) — start at IP.2
    local _ip_idx=2
    for _ip in "${EXTRA_IP_SANS[@]+"${EXTRA_IP_SANS[@]}"}"; do
        [[ -z "${_ip}" ]] && continue
        alt_block+="IP.${_ip_idx} = ${_ip}
"
        _ip_idx=$((_ip_idx + 1))
    done

    cat > "${cnf_file}" <<SVCCNF
[ req ]
default_bits        = 2048
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha256
req_extensions      = v3_req

[ req_distinguished_name ]
countryName             = Country Name (2 letter code)
stateOrProvinceName     = State or Province Name
localityName            = Locality Name
0.organizationName      = Organization Name
organizationalUnitName  = Organizational Unit Name
commonName              = Common Name

[ v3_req ]
basicConstraints     = CA:FALSE
keyUsage             = critical, digitalSignature, keyEncipherment
extendedKeyUsage     = serverAuth
subjectAltName       = @alt_names

[ alt_names ]
${alt_block}

[ server_cert ]
basicConstraints       = CA:FALSE
nsCertType             = server
nsComment              = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always
keyUsage               = critical, digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth
subjectAltName         = @alt_names
SVCCNF

    echo "${cnf_file}"
}

# ==============================================================================
# HELPER: Build PKCS12 + JKS for a named service cert
# ==============================================================================
build_keystore() {
    local service="$1"
    local cert="${CERTS_DIR}/${service}.cert.pem"
    local key="${CERTS_DIR}/${service}.key.pem"
    local chain="${CERTS_DIR}/ca-chain.cert.pem"
    local p12="${CERTS_DIR}/${service}.pkcs12"
    local jks="${CERTS_DIR}/${service}.jks"

    log_only openssl pkcs12 -export \
        -in "${cert}" -inkey "${key}" -certfile "${chain}" \
        -out "${p12}" -name "${service}" \
        -passout "pass:${KEYSTORE_PASS}"
    chmod 644 "${p12}"

    log_only keytool -importkeystore \
        -srckeystore  "${p12}"  -srcstoretype  PKCS12 -srcstorepass  "${KEYSTORE_PASS}" \
        -destkeystore "${jks}"  -deststoretype JKS    -deststorepass "${KEYSTORE_PASS}" \
        -destkeypass  "${KEYSTORE_PASS}" -noprompt

    local _alias_exists
    _alias_exists=$(keytool -list -keystore "${jks}" \
        -storepass "${KEYSTORE_PASS}" 2>/dev/null | grep -c "ca-chain" || true)
    if [[ "${_alias_exists}" -eq 0 ]]; then
        log_only keytool -importcert \
            -file "${chain}" -alias ca-chain \
            -keystore "${jks}" -storepass "${KEYSTORE_PASS}" -noprompt
    fi

    chmod 644 "${jks}"
    log_ok "${service}.pkcs12  +  ${service}.jks"
}

# ==============================================================================
# STEP 1: Root CA
# ==============================================================================
step_root_ca() {
    log_section "Step 1 — Root CA"

    local subj="/C=${CERT_COUNTRY}/ST=${CERT_STATE}/L=${CERT_CITY}/O=${CERT_ORG}/OU=${CERT_OU}/CN=IDOL Root CA"

    log_only openssl genrsa -out "${PRIVATE_DIR}/ca.key.pem" 4096
    chmod 640 "${PRIVATE_DIR}/ca.key.pem"

    log_only openssl req -config "${CA_DIR}/openssl-root-ca.cnf" \
        -key "${PRIVATE_DIR}/ca.key.pem" \
        -new -x509 -days "${DAYS_ROOT}" -sha256 -extensions v3_ca \
        -out "${CERTS_DIR}/ca.cert.pem" \
        -subj "${subj}"
    chmod 444 "${CERTS_DIR}/ca.cert.pem"

    log_ok "Root CA cert: ${CERTS_DIR}/ca.cert.pem"
    echo -e "  ${CYAN}$(openssl x509 -in "${CERTS_DIR}/ca.cert.pem" -noout -subject 2>/dev/null)${NC}"
    echo -e "  ${CYAN}$(openssl x509 -in "${CERTS_DIR}/ca.cert.pem" -noout -dates   2>/dev/null)${NC}"
}

# ==============================================================================
# STEP 2: Intermediate CA + CA chain bundle
# ==============================================================================
step_intermediate_ca() {
    log_section "Step 2 — Intermediate CA"

    local subj="/C=${CERT_COUNTRY}/ST=${CERT_STATE}/L=${CERT_CITY}/O=${CERT_ORG}/OU=${CERT_OU}/CN=IDOL Intermediate CA"

    log_only openssl genrsa -out "${PRIVATE_DIR}/intermediate.key.pem" 4096
    chmod 640 "${PRIVATE_DIR}/intermediate.key.pem"

    log_only openssl req -config "${CA_DIR}/openssl-root-ca.cnf" -new -sha256 \
        -key "${PRIVATE_DIR}/intermediate.key.pem" \
        -out "${CERTS_DIR}/intermediate.csr.pem" \
        -subj "${subj}"

    log_only openssl ca -config "${CA_DIR}/openssl-root-ca.cnf" \
        -extensions v3_intermediate_ca \
        -days "${DAYS_INTERMEDIATE}" -notext -md sha256 -batch \
        -in  "${CERTS_DIR}/intermediate.csr.pem" \
        -out "${CERTS_DIR}/intermediate.cert.pem"
    chmod 444 "${CERTS_DIR}/intermediate.cert.pem"

    cat "${CERTS_DIR}/intermediate.cert.pem" \
        "${CERTS_DIR}/ca.cert.pem" \
        > "${CERTS_DIR}/ca-chain.cert.pem"
    chmod 444 "${CERTS_DIR}/ca-chain.cert.pem"

    if log_only openssl verify \
            -CAfile "${CERTS_DIR}/ca.cert.pem" \
            "${CERTS_DIR}/intermediate.cert.pem"; then
        log_ok "Intermediate CA verified against Root CA"
    else
        log_error "Intermediate CA verification failed"
        exit 1
    fi

    log_only openssl pkcs12 -export \
        -in    "${CERTS_DIR}/intermediate.cert.pem" \
        -inkey "${PRIVATE_DIR}/intermediate.key.pem" \
        -certfile "${CERTS_DIR}/ca.cert.pem" \
        -out   "${CERTS_DIR}/intermediate.pkcs12" \
        -name  "intermediate-ca" \
        -passout "pass:${KEYSTORE_PASS}"
    chmod 644 "${CERTS_DIR}/intermediate.pkcs12"

    log_ok "Intermediate cert + PKCS12 created"
    echo -e "  ${CYAN}$(openssl x509 -in "${CERTS_DIR}/intermediate.cert.pem" -noout -subject 2>/dev/null)${NC}"
    echo -e "  ${CYAN}$(openssl x509 -in "${CERTS_DIR}/intermediate.cert.pem" -noout -dates   2>/dev/null)${NC}"

    sleep 2
}

# ==============================================================================
# STEP 3: Service certificates
# ==============================================================================
step_service_certs() {
    log_section "Step 3 — Service Certificates  (${#SERVICES[@]} services)"
    echo -e "  ${CYAN}Default SANs: <service>, ${EXTERNAL_HOSTNAME}, localhost, 127.0.0.1${NC}"
    echo -e "  ${GREEN}Auto-injected (always):${NC}  ${HOSTNAME_LOWER} + ${HOSTNAME_UPPER} (hostname)"
    if [[ -n "${FQDN_LOWER}" ]]; then
        echo -e "                           + ${FQDN_LOWER} + ${FQDN_UPPER} (FQDN)"
    fi
    if [[ ${#EXTRA_DNS_SANS[@]} -gt 0 ]]; then
        echo -e "  ${CYAN}Extra DNS SANs (user): ${EXTRA_DNS_SANS[*]}${NC}"
    fi
    if [[ ${#EXTRA_IP_SANS[@]} -gt 0 ]]; then
        echo -e "  ${CYAN}Extra IP  SANs: ${EXTRA_IP_SANS[*]}${NC}"
    fi
    echo ""

    local service cnf key csr cert fullchain subj
    for service in "${SERVICES[@]}"; do
        cnf=$(write_service_cnf "${service}")
        key="${CERTS_DIR}/${service}.key.pem"
        csr="${CERTS_DIR}/${service}.csr.pem"
        cert="${CERTS_DIR}/${service}.cert.pem"
        fullchain="${CERTS_DIR}/${service}-fullchain.cert.pem"
        subj="/C=${CERT_COUNTRY}/ST=${CERT_STATE}/L=${CERT_CITY}/O=${CERT_ORG}/OU=${CERT_OU}/CN=${service}"

        log_only openssl genrsa -out "${key}" 2048
        chmod 640 "${key}"

        log_only openssl req -config "${cnf}" \
            -key "${key}" -new -sha256 -out "${csr}" -subj "${subj}"

        log_only openssl ca -config "${CA_DIR}/openssl-ca.cnf" \
            -extfile "${cnf}" \
            -extensions server_cert \
            -startdate "$(date -u +%Y%m%d%H%M%SZ)" \
            -days "${DAYS_CERT}" -notext -md sha256 -batch \
            -in  "${csr}" -out "${cert}"
        chmod 444 "${cert}"

        cat "${cert}" \
            "${CERTS_DIR}/intermediate.cert.pem" \
            "${CERTS_DIR}/ca.cert.pem" \
            > "${fullchain}"
        chmod 444 "${fullchain}"

        rm -f "${cnf}"

        if log_only openssl verify \
                -CAfile "${CERTS_DIR}/ca-chain.cert.pem" "${cert}"; then
            CERT_STATUS["${service}"]="PASS"
            local sans
            sans=$(openssl x509 -in "${cert}" -noout -text 2>/dev/null \
                | awk '/Subject Alternative Name/{getline; gsub(/^ +/,""); print}')
            log_ok "${service}"
            echo -e "     ${CYAN}Subject: ${subj}${NC}"
            echo -e "     ${CYAN}SANs:    ${sans}${NC}"
        else
            CERT_STATUS["${service}"]="FAIL"
            log_fail "${service} — chain verification FAILED"
            CERT_FAILURES=$((CERT_FAILURES + 1))
        fi
    done
}

# ==============================================================================
# STEP 4: NiFi PKCS12 KeyStore & TrustStore
# ==============================================================================
step_nifi_keystores() {
    log_section "Step 4 — NiFi PKCS12 KeyStore & TrustStore"

    # ── keystore.p12 : private key + cert + full CA chain ─────────────────────
    log_only openssl pkcs12 -export \
        -in       "${CERTS_DIR}/idol-nifi.cert.pem" \
        -inkey    "${CERTS_DIR}/idol-nifi.key.pem" \
        -certfile "${CERTS_DIR}/ca-chain.cert.pem" \
        -out      "${NIFI_DIR}/keystore.p12" \
        -name     "nifi-key" \
        -passout  "pass:${KEYSTORE_PASS}"
    chmod 640 "${NIFI_DIR}/keystore.p12"
    log_ok "keystore.p12  → ${NIFI_DIR}/keystore.p12"

    # ── truststore.p12 : CA chain (no private key) ────────────────────────────
    log_only openssl pkcs12 -export \
        -nokeys \
        -in      "${CERTS_DIR}/ca-chain.cert.pem" \
        -out     "${NIFI_DIR}/truststore.p12" \
        -passout "pass:${TRUSTSTORE_PASS}"
    chmod 644 "${NIFI_DIR}/truststore.p12"
    log_ok "truststore.p12 → ${NIFI_DIR}/truststore.p12"

    # Verify the keystore contains our cert
    local _ks_info
    _ks_info=$(openssl pkcs12 -in "${NIFI_DIR}/keystore.p12" \
        -passin "pass:${KEYSTORE_PASS}" -nokeys -info 2>/dev/null \
        | grep -c "subject" || true)
    if [[ "${_ks_info}" -gt 0 ]]; then
        log_ok "keystore.p12 verified — contains certificate"
    else
        log_warn "keystore.p12 verification inconclusive — check manually"
    fi
}

# ==============================================================================
# STEP 4b: Inject NiFi PKCS12 files into the running Docker container
#          + always update the persistent volume (bind-mount)
# ==============================================================================
step_nifi_inject() {
    log_section "Step 4b — Injecting NiFi Certs into Container + Persistent Volume"

    local NIFI_CONF="/opt/nifi/nifi-current/conf"
    # Persistent volume that the container bind-mounts (this is the real source of truth)
    local PERSISTENT_NIFI_CONF="${REPO_ROOT}/persistent-data/nifi-data/conf"

    # ── 1. Always update the persistent volume on the host ────────────────────
    if [[ -d "${PERSISTENT_NIFI_CONF}" ]]; then
        cp "${NIFI_DIR}/keystore.p12"   "${PERSISTENT_NIFI_CONF}/keystore.p12"
        cp "${NIFI_DIR}/truststore.p12" "${PERSISTENT_NIFI_CONF}/truststore.p12"
        log_ok "Copied keystores → ${PERSISTENT_NIFI_CONF}"

        # Also patch passwords in the persistent nifi.properties
        if [[ -f "${PERSISTENT_NIFI_CONF}/nifi.properties" ]]; then
            sed -i \
                -e "s|^nifi.security.keystoreType=.*|nifi.security.keystoreType=PKCS12|" \
                -e "s|^nifi.security.keystorePasswd=.*|nifi.security.keystorePasswd=${KEYSTORE_PASS}|" \
                -e "s|^nifi.security.keyPasswd=.*|nifi.security.keyPasswd=${KEYSTORE_PASS}|" \
                -e "s|^nifi.security.truststore=.*|nifi.security.truststore=./conf/truststore.p12|" \
                -e "s|^nifi.security.truststoreType=.*|nifi.security.truststoreType=PKCS12|" \
                -e "s|^nifi.security.truststorePasswd=.*|nifi.security.truststorePasswd=${TRUSTSTORE_PASS}|" \
                "${PERSISTENT_NIFI_CONF}/nifi.properties"
            log_ok "Patched passwords in persistent nifi.properties"
        else
            log_warn "nifi.properties not found in ${PERSISTENT_NIFI_CONF} — passwords not updated"
        fi
    else
        log_warn "Persistent NiFi conf directory not found: ${PERSISTENT_NIFI_CONF}"
        log_warn "Skipping host-side copy (container may still receive files via docker cp)"
    fi

    # ── 2. Inject into running container (if it exists) ───────────────────────
    if ! docker inspect --format '{{.State.Running}}' "${NIFI_CONTAINER}" \
            2>/dev/null | grep -q "true"; then
        log_warn "Container '${NIFI_CONTAINER}' not running — skipping live inject."
        log_warn "The persistent volume has been updated; new certs will be used on next start."
        return 0
    fi

    # Back up existing files inside the container
    docker exec "${NIFI_CONTAINER}" bash -c "
        ts=\$(date +%Y%m%d_%H%M%S)
        for f in keystore.p12 truststore.p12 nifi.properties; do
            src=\"${NIFI_CONF}/\${f}\"
            bak=\"${NIFI_CONF}/\${f}.\${ts}.bak\"
            [ -f \"\${src}\" ] && cp \"\${src}\" \"\${bak}\" && echo \"  backed up \${f} → \${f}.\${ts}.bak\"
        done
    " 2>/dev/null || true
    log_ok "Existing conf files backed up inside container"

    # Copy new PKCS12 files into the container
    docker cp "${NIFI_DIR}/keystore.p12"   "${NIFI_CONTAINER}:${NIFI_CONF}/keystore.p12"
    log_ok "Copied keystore.p12  → ${NIFI_CONTAINER}:${NIFI_CONF}/keystore.p12"

    docker cp "${NIFI_DIR}/truststore.p12" "${NIFI_CONTAINER}:${NIFI_CONF}/truststore.p12"
    log_ok "Copied truststore.p12 → ${NIFI_CONTAINER}:${NIFI_CONF}/truststore.p12"

    # Patch nifi.properties inside the container
    docker exec "${NIFI_CONTAINER}" bash -c "
        props=\"${NIFI_CONF}/nifi.properties\"
        sed -i \
            -e 's|^nifi.security.keystoreType=.*|nifi.security.keystoreType=PKCS12|' \
            -e 's|^nifi.security.keystorePasswd=.*|nifi.security.keystorePasswd=${KEYSTORE_PASS}|' \
            -e 's|^nifi.security.keyPasswd=.*|nifi.security.keyPasswd=${KEYSTORE_PASS}|' \
            -e 's|^nifi.security.truststore=.*|nifi.security.truststore=./conf/truststore.p12|' \
            -e 's|^nifi.security.truststoreType=.*|nifi.security.truststoreType=PKCS12|' \
            -e 's|^nifi.security.truststorePasswd=.*|nifi.security.truststorePasswd=${TRUSTSTORE_PASS}|' \
            \"\${props}\"
        echo 'nifi.properties patched'
    "
    log_ok "nifi.properties updated with new passwords and PKCS12 types"

    # Restart NiFi
    log_info "Restarting ${NIFI_CONTAINER} …"
    docker restart "${NIFI_CONTAINER}" >/dev/null
    log_ok "Container restarted"

    # Wait for TLS port
    log_info "Waiting for NiFi TLS port 8443 to respond …"
    local _waited=0
    while [[ "${_waited}" -lt 90 ]]; do
        if openssl s_client -connect "127.0.0.1:8443" \
                -servername "127.0.0.1" </dev/null 2>/dev/null \
                | grep -q "CONNECTED"; then
            log_ok "NiFi is accepting TLS connections"
            break
        fi
        sleep 5
        _waited=$((_waited + 5))
    done

    if [[ "${_waited}" -ge 90 ]]; then
        log_warn "NiFi did not respond on 8443 within 90 s — check logs:"
        log_warn "  docker logs ${NIFI_CONTAINER} 2>&1 | grep -i 'ssl\\|tls\\|error' | tail -20"
        return 0
    fi

    # Final verification
    log_info "Verifying deployed certificate SANs …"
    local _sans
    _sans=$(openssl s_client -connect "127.0.0.1:8443" \
        -servername "127.0.0.1" </dev/null 2>/dev/null \
        | openssl x509 -noout -text 2>/dev/null \
        | awk '/Subject Alternative Name/{getline; gsub(/^ +/,""); print}')

    if [[ -n "${_sans}" ]]; then
        log_ok "Certificate SANs: ${_sans}"
        if echo "${_sans}" | grep -q "IP Address"; then
            log_ok "IP SAN confirmed in deployed certificate ✅"
        else
            log_warn "No IP SAN detected — check EXTRA_IP_SANS_ENV was set correctly"
        fi
    else
        log_warn "Could not read SANs from live cert — verify manually"
    fi
}

# ==============================================================================
# STEP 5–6: IDOL Find PKCS12 + JKS
# ==============================================================================
step_find_keystores() {
    log_section "Step 5–6 — IDOL Find KeyStores"

    log_only openssl pkcs12 -export \
        -in "${CERTS_DIR}/idol-find.cert.pem" \
        -inkey "${CERTS_DIR}/idol-find.key.pem" \
        -certfile "${CERTS_DIR}/ca-chain.cert.pem" \
        -out "${CERTS_DIR}/idol-find.pkcs12" -name "idol-find" \
        -passout "pass:${KEYSTORE_PASS}"

    log_only keytool -importkeystore \
        -srckeystore  "${CERTS_DIR}/idol-find.pkcs12" -srcstoretype  PKCS12 \
        -srcstorepass "${KEYSTORE_PASS}" \
        -destkeystore "${CERTS_DIR}/idol-find.jks"    -deststoretype JKS \
        -deststorepass "${KEYSTORE_PASS}" -destkeypass "${KEYSTORE_PASS}" -noprompt

    local _found
    _found=$(keytool -list -keystore "${CERTS_DIR}/idol-find.jks" \
        -storepass "${KEYSTORE_PASS}" 2>/dev/null | grep -c "ca-chain" || true)
    if [[ "${_found}" -eq 0 ]]; then
        log_only keytool -importcert \
            -file "${CERTS_DIR}/ca-chain.cert.pem" -alias ca-chain \
            -keystore "${CERTS_DIR}/idol-find.jks" \
            -storepass "${KEYSTORE_PASS}" -noprompt
    fi
    chmod 644 "${CERTS_DIR}/idol-find.pkcs12" "${CERTS_DIR}/idol-find.jks"
    log_ok "idol-find.pkcs12  +  idol-find.jks"
}

# ==============================================================================
# STEP 6b: IDOL DataAdmin PKCS12 + JKS
# ==============================================================================
step_dataadmin_keystores() {
    log_section "Step 6b — IDOL DataAdmin KeyStores"
    build_keystore "idol-dataadmin"
}

# ==============================================================================
# STEP 6c: MMAP self-signed keystore
# ==============================================================================
step_mmap_keystore() {
    log_section "Step 6c — MMAP KeyStore (self-signed)"
    mkdir -p "${CERTS_DIR}"
    log_only keytool -genkeypair -alias mmap -keyalg RSA -keysize 2048 \
        -storetype PKCS12 -keystore "${CERTS_DIR}/idol-mmap-app.pkcs12" -validity 365 \
        -storepass "${KEYSTORE_PASS}" -keypass "${KEYSTORE_PASS}" \
        -dname "CN=mmap, OU=${CERT_OU}, O=${CERT_ORG}, L=${CERT_CITY}, ST=${CERT_STATE}, C=${CERT_COUNTRY}"
    chmod 644 "${CERTS_DIR}/idol-mmap-app.pkcs12"
    log_ok "mmap.pkcs12 created (self-signed, validity 365 days)"
}

# ==============================================================================
# STEP 7: Cleanup
# ==============================================================================
step_cleanup() {
    log_section "Step 7 — Organising CA Database Files"
    mv "${CA_DIR}/index.txt"* "${CA_DIR}/issued/" 2>/dev/null || true
    mv "${CA_DIR}/serial"*    "${CA_DIR}/issued/" 2>/dev/null || true
    mv "${CA_DIR}/crlnumber"* "${CA_DIR}/issued/" 2>/dev/null || true
    log_ok "CA database archived to ${CA_DIR}/issued/"
}

# ==============================================================================
# STEP 8: Deploy SSL artefacts to all deployment targets
# ==============================================================================
step_deploy() {
    log_section "Step 8 — Deploying SSL Artefacts"
    local -a targets=("${DEPLOY_BASIC_IDOL}" "${DEPLOY_DATA_ADMIN}" "${DEPLOY_RICH_MEDIA}" "${DEPLOY_LICENSESERVER}")
    local target
    for target in "${targets[@]}"; do
        sudo rm -rf "${target}"
        cp -r "${SSL_ROOT}" "${target}"
        log_ok "→ ${target}"
    done
}

# ==============================================================================
# STEP 8b: Fix SSL file permissions
# ==============================================================================
step_fix_permissions() {
    log_section "Step 8b — Fixing SSL File Permissions"

    local -a all_dirs=("${SSL_ROOT}")
    local _t
    for _t in "${DEPLOY_BASIC_IDOL}" "${DEPLOY_DATA_ADMIN}" \
               "${DEPLOY_RICH_MEDIA}" "${DEPLOY_LICENSESERVER}"; do
        [[ -d "${_t}" ]] && all_dirs+=("${_t}")
    done

    local _dir _sudo
    for _dir in "${all_dirs[@]}"; do
        _sudo=""
        [[ "${_dir}" != "${SSL_ROOT}"* ]] && _sudo="sudo"

        ${_sudo} find "${_dir}" -type f -name "*.key.pem" \
            -exec chmod 640 {} +
        log_ok "${_dir}: *.key.pem → 640"

        ${_sudo} find "${_dir}" -type f \( \
            -name "*.cert.pem"              \
            -o -name "*-fullchain.cert.pem" \
            -o -name "*.pkcs12"             \
            -o -name "*.p12"                \
            -o -name "*.jks"                \
            -o -name "*.crt"                \
        \) -exec chmod 644 {} +
        log_ok "${_dir}: certs / keystores → 644"

        if [[ -n "${SSL_SERVICE_USER}" && -n "${SSL_SERVICE_GROUP}" ]]; then
            ${_sudo} find "${_dir}" -type f -name "*.key.pem" \
                -exec chown "${SSL_SERVICE_USER}:${SSL_SERVICE_GROUP}" {} +
            log_ok "${_dir}: *.key.pem owner → ${SSL_SERVICE_USER}:${SSL_SERVICE_GROUP}"
        elif [[ -n "${SSL_SERVICE_GROUP}" ]]; then
            ${_sudo} find "${_dir}" -type f -name "*.key.pem" \
                -exec chgrp "${SSL_SERVICE_GROUP}" {} +
            log_ok "${_dir}: *.key.pem group → ${SSL_SERVICE_GROUP}"
        fi
    done

    if [[ -z "${SSL_SERVICE_USER}" && -z "${SSL_SERVICE_GROUP}" ]]; then
        log_warn "SSL_SERVICE_USER / SSL_SERVICE_GROUP not set — skipping chown."
        log_warn "Re-run with: SSL_SERVICE_USER=idol SSL_SERVICE_GROUP=idol ./generate-ssl.sh"
    fi
}

# ==============================================================================
# STEP 9: Export Root CA for client distribution
# ==============================================================================
step_export_root_ca() {
    log_section "Step 9 — Exporting Root CA for Client Distribution"
    cp "${CERTS_DIR}/ca.cert.pem" "${SSL_ROOT}/idol-root-ca.crt"
    chmod 644 "${SSL_ROOT}/idol-root-ca.crt"
    log_ok "Root CA (distribute to clients): ${SSL_ROOT}/idol-root-ca.crt"
}

# ==============================================================================
# STEP 10: Install CAs into system trust store
# ==============================================================================
step_install_trust_store() {
    log_section "Step 10 — Installing CAs into System Trust Store"
    set +e

    local root_dest="/usr/local/share/ca-certificates/idol-root-ca.crt"
    local inter_dest="/usr/local/share/ca-certificates/idol-intermediate-ca.crt"

    if sudo cp "${CERTS_DIR}/ca.cert.pem"          "${root_dest}"  &&
       sudo cp "${CERTS_DIR}/intermediate.cert.pem" "${inter_dest}"; then
        log_ok "Root CA         → ${root_dest}"
        log_ok "Intermediate CA → ${inter_dest}"
    else
        log_error "Failed to copy CA files — check sudo permissions."
        set -e; return 1
    fi

    local update_out
    update_out=$(sudo update-ca-certificates 2>&1)
    echo "${update_out}" >&3

    if echo "${update_out}" | grep -q "^[1-9][0-9]* added"; then
        local added; added=$(echo "${update_out}" | grep -o '[0-9]* added')
        log_ok "System trust store updated (${added} CAs)"
    elif echo "${update_out}" | grep -q "^0 added"; then
        log_warn "'0 added' — CAs may already be installed or files are malformed."
    else
        log_ok "update-ca-certificates completed."
    fi

    local found
    found=$(ls /etc/ssl/certs/ 2>/dev/null | grep -c "idol" || echo "0")
    if [[ "${found}" -gt 0 ]]; then
        log_ok "Confirmed in /etc/ssl/certs/:"
        ls /etc/ssl/certs/ | grep "idol" | while read -r _f; do
            echo -e "    ${CYAN}${_f}${NC}"
        done
    else
        log_warn "Not yet visible in /etc/ssl/certs/ — may require re-login."
    fi

    set -e
}

# ==============================================================================
# HEALTH CHECK
# ==============================================================================
run_health_check() {
    HEALTH_FAIL_COUNT=0
    local _pass=0 _svc _port _body _entry

    set +e
    for _entry in "${HEALTH_CHECKS[@]}"; do
        _svc="${_entry%%:*}"
        _port="${_entry##*:}"
        _body=$(curl -sf --max-time 10 \
            "https://${EXTERNAL_HOSTNAME}:${_port}/a=GetStatus" 2>/dev/null || true)
        if echo "${_body}" | grep -q "<response>SUCCESS</response>"; then
            log_ok "${_svc} (port ${_port})"
            _pass=$((_pass + 1))
        else
            log_fail "${_svc} (port ${_port})"
            HEALTH_FAIL_COUNT=$((HEALTH_FAIL_COUNT + 1))
        fi
    done
    set -e

    echo ""
    if [[ "${HEALTH_FAIL_COUNT}" -eq 0 ]]; then
        log_ok "All ${_pass}/${#HEALTH_CHECKS[@]} services responding over verified HTTPS."
    else
        log_warn "${_pass}/${#HEALTH_CHECKS[@]} passed, ${HEALTH_FAIL_COUNT} failed."
    fi
}

# ==============================================================================
# SUMMARY REPORT
# ==============================================================================
print_summary() {
    log_section "Summary Report"

    echo -e "  ${BOLD}Service Certificates (${#SERVICES[@]} total):${NC}"
    local service
    for service in "${SERVICES[@]}"; do
        if [[ "${CERT_STATUS[${service}]:-UNKNOWN}" == "PASS" ]]; then
            log_ok "${service}"
        else
            log_fail "${service}"
        fi
    done

    echo ""
    echo -e "  ${BOLD}Keystore Files:${NC}"
    local -a ks_files=(
        "${CERTS_DIR}/intermediate.pkcs12"
        "${CERTS_DIR}/idol-find.pkcs12"
        "${CERTS_DIR}/idol-find.jks"
        "${CERTS_DIR}/idol-dataadmin.pkcs12"
        "${CERTS_DIR}/idol-dataadmin.jks"
        "${NIFI_DIR}/keystore.p12"
        "${NIFI_DIR}/truststore.p12"
    )
    local ks
    for ks in "${ks_files[@]}"; do
        if [[ -f "${ks}" ]]; then
            log_ok "$(basename "${ks}")"
        else
            log_fail "$(basename "${ks}") — MISSING"
        fi
    done

    echo ""
    if [[ "${CERT_FAILURES}" -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}✅  All ${#SERVICES[@]} certificates verified successfully.${NC}"
    else
        echo -e "  ${RED}${BOLD}❌  ${CERT_FAILURES} of ${#SERVICES[@]} certificate(s) FAILED.${NC}"
    fi

    local border; border=$(printf '═%.0s' $(seq 1 65))
    echo ""
    echo -e "${BLUE}${border}${NC}"
    echo -e "  ${BOLD}Credentials & Key Files${NC}"
    echo -e "${BLUE}${border}${NC}"
    echo ""
    echo -e "  ${YELLOW}KeyStore password:${NC}    ${KEYSTORE_PASS}"
    echo -e "  ${YELLOW}TrustStore password:${NC}  ${TRUSTSTORE_PASS}"
    echo -e "  ${YELLOW}Saved to:${NC}             ${SSL_PASSWORDS_ENV}"
    echo ""
    echo -e "  Root CA (distribute):  ${ORANGE}${SSL_ROOT}/idol-root-ca.crt${NC}"
    echo -e "  CA Chain:              ${ORANGE}${CERTS_DIR}/ca-chain.cert.pem${NC}"
    echo -e "  Full log:              ${ORANGE}${LOG_FILE}${NC}"
    echo ""
    echo -e "  ${BOLD}Expiry dates:${NC}"
    echo -e "    Root CA:        ~$(date -d "+${DAYS_ROOT} days"        +%Y-%m-%d 2>/dev/null || echo 'N/A')"
    echo -e "    Intermediate:   ~$(date -d "+${DAYS_INTERMEDIATE} days" +%Y-%m-%d 2>/dev/null || echo 'N/A')"
    echo -e "    Service certs:  ~$(date -d "+${DAYS_CERT} days"        +%Y-%m-%d 2>/dev/null || echo 'N/A')"
    echo ""
    if [[ ${#EXTRA_IP_SANS[@]} -gt 0 ]]; then
        echo -e "  ${BOLD}Extra IP SANs embedded in all certs:${NC}"
        for _ip in "${EXTRA_IP_SANS[@]}"; do
            echo -e "    ${CYAN}${_ip}${NC}"
        done
        echo ""
    fi
    echo -e "  ${RED}⚠  Update passwords and DN values for production deployments.${NC}"
    echo ""
    echo -e "${BLUE}${border}${NC}"
    echo ""
}

# ==============================================================================
# MAIN
# ==============================================================================
main() {
    parse_args "$@"
    setup_logging

    log_section "IDOL SSL Certificate Generation"
    log_info "Repo root:   ${REPO_ROOT}"
    log_info "Script dir:  ${SCRIPT_DIR}"
    log_info "SSL output:  ${SSL_ROOT}"
    [[ "${AUTO_MODE}" == true ]] && log_info "Mode: non-interactive (--auto)"

    check_prerequisites
    confirm_regeneration

    if [[ "${SKIP_GENERATION}" == false ]]; then
        collect_subject_info
        setup_passwords

        init_ca_directory
        step_root_ca
        step_intermediate_ca
        step_service_certs
        step_nifi_keystores
        step_nifi_inject
        step_find_keystores
        step_dataadmin_keystores
        step_mmap_keystore
        step_cleanup
    else
        log_info "Loading existing passwords from ${SSL_PASSWORDS_ENV}"
        # shellcheck source=/dev/null
        [[ -f "${SSL_PASSWORDS_ENV}" ]] && source "${SSL_PASSWORDS_ENV}" \
            && KEYSTORE_PASS="${IDOL_CERT_KEYSTORE_PASS}" \
            && TRUSTSTORE_PASS="${IDOL_CERT_TRUSTSTORE_PASS}" \
            || log_warn "Password file not found — keystore operations may fail."
    fi

    step_deploy
    step_fix_permissions
    step_export_root_ca
    step_install_trust_store

    print_summary
    log_section "Complete"
}

main "$@"
