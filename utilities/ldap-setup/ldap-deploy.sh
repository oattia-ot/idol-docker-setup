#!/usr/bin/env bash
# =============================================================================
# ldap-deploy.sh — Deploy OpenLDAP + phpLDAPadmin via Docker Compose
# =============================================================================
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

# ── Configuration (override via env vars or edit here) ───────────────────────
LDAP_ORGANISATION="${LDAP_ORGANISATION:-Example Organisation}"
LDAP_DOMAIN="${LDAP_DOMAIN:-example.com}"
LDAP_ADMIN_PASSWORD="${LDAP_ADMIN_PASSWORD:-Admin1234!}"
LDAP_CONFIG_PASSWORD="${LDAP_CONFIG_PASSWORD:-Config1234!}"
LDAP_TLS="${LDAP_TLS:-false}"

LDAP_PORT="${LDAP_PORT:-389}"
LDAPS_PORT="${LDAPS_PORT:-636}"
PHPLDAPADMIN_PORT="${PHPLDAPADMIN_PORT:-7777}"

COMPOSE_FILE="ldap-docker-compose.yml"
COMPOSE_PROJECT=${IDOL_DEPLOYMENT_TYPE:-idol-demo}

# Derive base DN from domain (e.g. example.com → dc=example,dc=com)
LDAP_BASE_DN="dc=$(echo "$LDAP_DOMAIN" | sed 's/\./,dc=/g')"

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║         LDAP Docker Deployment           ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${RESET}"

# ── 1. Preflight checks ───────────────────────────────────────────────────────
info "Running preflight checks..."

command -v docker &>/dev/null       || error "Docker is not installed. Visit https://docs.docker.com/get-docker/"
docker info &>/dev/null             || error "Docker daemon is not running. Start it and retry."
docker compose version &>/dev/null  || error "Docker Compose v2 is not installed."

success "Docker $(docker --version | awk '{print $3}' | tr -d ',') found"
success "Docker Compose $(docker compose version --short) found"

# Check for port conflicts
for PORT in "$LDAP_PORT" "$LDAPS_PORT" "$PHPLDAPADMIN_PORT"; do
  if ss -tlnp 2>/dev/null | grep -q ":${PORT} " || \
     netstat -tlnp 2>/dev/null | grep -q ":${PORT} "; then
    warn "Port ${PORT} appears to be in use — this may cause conflicts."
  fi
done

# ── 2. Pull images ────────────────────────────────────────────────────────────
info "Pulling Docker images..."
docker compose -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE" pull
success "Images pulled"

# ── 3. Start services ─────────────────────────────────────────────────────────
info "Starting services..."
docker compose -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE" up -d
success "Containers started"

# ── 4. Wait for OpenLDAP to become healthy ────────────────────────────────────
info "Waiting for OpenLDAP to become healthy (up to 60s)..."
RETRIES=12
HEALTHY=false
for i in $(seq 1 $RETRIES); do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' openldap 2>/dev/null || echo "unknown")
  if [[ "$STATUS" == "healthy" ]]; then
    HEALTHY=true
    break
  fi
  echo -ne "  Attempt ${i}/${RETRIES}: status=${STATUS}...\r"
  sleep 5
done
echo ""

if [[ "$HEALTHY" == "false" ]]; then
  warn "OpenLDAP did not reach healthy state in time."
  warn "Check logs with: docker logs openldap"
else
  success "OpenLDAP is healthy"
fi

# ── 5. Verify connectivity ────────────────────────────────────────────────────
info "Testing LDAP connectivity..."
if docker exec openldap ldapsearch -x \
    -H ldap://localhost:389 \
    -b "$LDAP_BASE_DN" \
    -D "cn=admin,${LDAP_BASE_DN}" \
    -w "$LDAP_ADMIN_PASSWORD" &>/dev/null; then
  success "LDAP query succeeded"
else
  warn "LDAP query failed — server may still be initializing. Retry in a few seconds."
fi

# ── 6. Summary ────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  Deployment complete!${RESET}"
echo -e "${BOLD}════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${BOLD}LDAP Server${RESET}"
echo -e "    Host:      ldap://localhost:${LDAP_PORT}"
echo -e "    Base DN:   ${LDAP_BASE_DN}"
echo -e "    Admin DN:  cn=admin,${LDAP_BASE_DN}"
echo -e "    Password:  ${LDAP_ADMIN_PASSWORD}"
echo ""
echo -e "  ${BOLD}phpLDAPadmin UI${RESET}"
echo -e "    URL:       http://localhost:${PHPLDAPADMIN_PORT}"
echo -e "    Login DN:  cn=admin,${LDAP_BASE_DN}"
echo -e "    Password:  ${LDAP_ADMIN_PASSWORD}"
echo ""
echo -e "  ${BOLD}Useful commands${RESET}"
echo -e "    View logs:   docker logs openldap"
echo -e "    Status:      docker compose -f ${COMPOSE_FILE} ps"
echo -e "    Stop:        docker compose -f ${COMPOSE_FILE} down"
echo -e "    Destroy all: docker compose -f ${COMPOSE_FILE} down -v"
echo ""