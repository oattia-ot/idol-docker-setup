#!/bin/bash

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
LIGHTER_YELLOW='\033[38;5;228m'
BLUE='\033[0;34m'
ORANGE='\033[0;38;5;214m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Check for required tools
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed or not in PATH.${NC}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}jq is required but not installed. Please install jq and try again.${NC}"
    exit 1
fi

# All arguments are passed to docker compose
DOCKER_COMPOSE_ARGS="$@"

# Safely source the IDOL SSL passwords file (relative path)
PASSWORD_FILE="../../env/.idol-ssl-passwords.env"
if [[ ! -f "${PASSWORD_FILE}" ]]; then
    echo -e "\033[0;31m❌ Error:\033[0m Password file not found: ${PASSWORD_FILE}" >&2
    echo "   Run generate-ssl.sh first to create it." >&2
    exit 1
fi
# File exists → source it
source "${PASSWORD_FILE}"
echo -e "\033[0;32m✅ Sourced:\033[0m ${PASSWORD_FILE}"
echo -e "   🔑 IDOL_CERT_KEYSTORE_PASS  = ${IDOL_CERT_KEYSTORE_PASS:-(not set)}"
echo -e "   🔑 IDOL_CERT_TRUSTSTORE_PASS = ${IDOL_CERT_TRUSTSTORE_PASS:-(not set)}"


# ─────────────────────────────────────────────────────────────────────────
# Source pre-setup.sh to load IDOL environment variables into this shell.
#
# IMPORTANT CONTEXT:
#   - This file is expected to be populated by the IDOL Setup UI / prior
#     setup step before this script runs.
#   - After sourcing, the master copy of pre-setup.sh is truncated
#     (see STEP 2/5 self-cleanup) to prevent stale re-sourcing on re-run.
#   - A backup should exist at pre-setup-backup.sh if you need to restore
#     this file later (e.g. for per-subtype copies wiped during
#     prepare-env.sh --config).
# ─────────────────────────────────────────────────────────────────────────
if [[ -s ./pre-setup.sh ]]; then
    source ./pre-setup.sh
    echo -e "${GREEN}✅ Sourced pre-setup.sh — environment variables loaded.${NC}"
else
    echo -e "${RED}❌ pre-setup.sh is missing or empty — cannot load environment variables.${NC}"
    echo -e "${YELLOW}   If this was already truncated by a previous run, restore it from pre-setup-backup.sh first.${NC}"
    exit 1
fi


# Check if we're running a 'down' command
IS_DOWN_COMMAND=false
if echo "$DOCKER_COMPOSE_ARGS" | grep -qE '(^|[[:space:]])down([[:space:]]|$)'; then
    IS_DOWN_COMMAND=true
fi

# Check if we're running a 'up' command
IS_UP_COMMAND=false
if echo "$DOCKER_COMPOSE_ARGS" | grep -qE '(^|[[:space:]])up([[:space:]]|$)'; then
    IS_UP_COMMAND=true
fi

echo ""
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}${BOLD}  IDOL Deployment Script${NC}"
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}"
echo ""

# ── Docker Personal Access Token login ──────────────────────────────────────
# Skip authentication for teardown operations — no images need to be pulled
if [ "$IS_DOWN_COMMAND" = false ]; then
    echo -e "${CYAN}${BOLD}───────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}${BOLD}Docker Registry Authentication${NC}"
    echo ""

    # Info: IDOL images must be obtained from OpenText
    echo -e "${ORANGE}⚠️  During installation you must download the IDOL package directly from the official OpenText site using your credentials${NC}"
    echo -e "${ORANGE}⚠️     - Download from: ${CYAN}https://authenticate.microfocus.net/${NC}"
    echo ""

    # If IDOL_LICENSE_KEY_TOKEN is already set in the environment, try it first
    # before falling through to the interactive prompt loop
    DOCKER_LOGIN_SUCCESS=false
    if [ -n "$IDOL_LICENSE_KEY_TOKEN" ]; then
        echo -e "${BLUE}   ${YELLOW} IDOL_LICENSE_KEY_TOKEN ${ORANGE}env variable detected, attempting login..."
        for i in {5..1}; do
            echo -ne "${CYAN}  → ${i} seconds remaining...\r${NC}"
            sleep 1
        done         
        if echo "$IDOL_LICENSE_KEY_TOKEN" | docker login --username microfocusidolreadonly --password-stdin; then
            echo -e "${GREEN}${BOLD}✓${NC} Docker access token is ${GREEN}valid${NC}"
            echo -e "${BLUE}  →${NC} IDOL Docker access token: ${GREEN}[validated — dckr_pat_*************-*************]${NC}"
            DOCKER_LOGIN_SUCCESS=true
        else
            echo -e "${RED}${BOLD}✗${NC} Env variable token is invalid — please enter a valid token below.${NC}"
            echo ""
        fi
    fi

    # Prompt until a valid token is provided and docker login succeeds
    while [ "$DOCKER_LOGIN_SUCCESS" = false ]; do
        # Prompt for the token (input is read directly to avoid echoing the secret)
        echo -ne "${CYAN}Enter IDOL Docker Personal Access token to download images${NC} ${ORANGE}[dckr_pat_XXXXX]${NC}: "
        read -rs IDOL_LICENSE_KEY_TOKEN
        echo ""

        # Basic format validation before attempting login
        if ! echo "$IDOL_LICENSE_KEY_TOKEN" | grep -qE '^dckr[_A-Za-z0-9-]+$'; then
            echo -e "${RED}Token format is invalid. Expected format: dckr_pat_... — please try again.${NC}"
            continue
        fi

        echo -e "${BLUE}  →${NC} Token accepted (format valid), attempting Docker login..."
        echo -e "${MAGENTA}  [DO NOT SAVE IDOL docker KEY]${NC}"

        # Validate token against Docker Hub
        if echo "$IDOL_LICENSE_KEY_TOKEN" | docker login --username microfocusidolreadonly --password-stdin; then
            echo -e "${GREEN}${BOLD}✓${NC} Docker access token is ${GREEN}valid${NC}"
            echo -e "${BLUE}  →${NC} IDOL Docker access token: ${GREEN}[validated — dckr_pat_*************-*************]${NC}"
            DOCKER_LOGIN_SUCCESS=true
        else
            echo -e "${RED}${BOLD}✗${NC} Invalid Docker access token. Please try again.${NC}"
        fi
    done
fi
# ── End Docker PAT login ─────────────────────────────────────────────────────

echo ""
echo -e "${CYAN}${BOLD}───────────────────────────────────────────────────────${NC}"
echo -e "${YELLOW}${BOLD}Starting Docker Compose...${NC}"
echo -e "${MAGENTA}Compose files:${NC}"
echo -e "  ${BLUE}→${NC} docker-compose.yml"
echo -e "  ${BLUE}→${NC} docker-compose.ssl.yml"
echo -e "  ${BLUE}→${NC} docker-compose.expose-ports.yml"
echo -e "  ${BLUE}→${NC} docker-compose.bindmount.yml"
if [ -n "$DOCKER_COMPOSE_ARGS" ]; then
    echo -e "${MAGENTA}Additional arguments:${NC} ${GREEN}$DOCKER_COMPOSE_ARGS${NC}"
fi
echo ""
echo -e "${CYAN}${BOLD}───────────────────────────────────────────────────────${NC}"
echo -e "${YELLOW}${BOLD}DEPLOYMENT SUBTYPE BASIC-IDOL                        ${NC}"
echo -e "${CYAN}${BOLD}───────────────────────────────────────────────────────${NC}"
echo ""

# Execute docker compose command with all remaining passed arguments
SSL_COMPOSE=""
if [ "$IDOL_LICENSESERVER_PROTOCOL" = "https" ]; then
  SSL_COMPOSE="-f docker-compose.ssl.yml"
fi
echo ""
echo -e "${CYAN}${BOLD}───────────────────────────────────────────────────────${NC}"
echo -e "${YELLOW}${BOLD}Checking Docker network...${NC}"

DOCKER_NETWORK="idol-${IDOL_DEPLOYMENT_TYPE}-network"

if docker network inspect "$DOCKER_NETWORK" > /dev/null 2>&1; then
    echo -e "${GREEN}${BOLD}✓${NC} Network ${GREEN}$DOCKER_NETWORK${NC} already exists"
else
    echo -e "${YELLOW}  →${NC} Network ${YELLOW}$DOCKER_NETWORK${NC} not found, creating..."
    if docker network create "$DOCKER_NETWORK"; then
        echo -e "${GREEN}${BOLD}✓${NC} Network ${GREEN}$DOCKER_NETWORK${NC} created successfully"
    else
        echo -e "${RED}${BOLD}✗${NC} Failed to create network ${RED}$DOCKER_NETWORK${NC}"
        exit 1
    fi
fi

# ── Stale Volume Cleanup (WSL distro mismatch fix) ────────────────────────────
# When Docker Desktop switches WSL distros (e.g. PlatoKD-v2 → PlatoKD-v3),
# named volumes retain the old distro's bind-mount path and fail to mount.
# Detect and remove any stale volumes before compose runs.
if [ "$IS_DOWN_COMMAND" = false ] && [ "$IS_UP_COMMAND" = true ]; then
    echo -e "${CYAN}${BOLD}───────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}${BOLD}Checking for stale Docker volumes...${NC}"

    # Get current WSL distro name as Docker Desktop sees it
    CURRENT_DISTRO=$(docker info --format '{{json .}}' 2>/dev/null \
        | jq -r '.Labels[]? | select(startswith("desktop.docker.io/wsl-distro")) | split("=")[1]' \
        2>/dev/null || echo "")

    if [ -z "$CURRENT_DISTRO" ]; then
        echo -e "${YELLOW}  ⚠${NC} Could not detect current WSL distro name — skipping stale volume check"
    else
        echo -e "${BLUE}  →${NC} Current WSL distro: ${GREEN}$CURRENT_DISTRO${NC}"

        # Get the project name (same logic used by compose)
        COMPOSE_PROJECT="${IDOL_DEPLOYMENT_TYPE:+idol-${IDOL_DEPLOYMENT_TYPE}}"
        COMPOSE_PROJECT="${COMPOSE_PROJECT:-idol-demo}"

        # Find volumes belonging to this project
        PROJECT_VOLUMES=$(docker volume ls --format '{{.Name}}' \
            | grep "^${COMPOSE_PROJECT}_" || true)

        STALE_FOUND=false
        for VOL in $PROJECT_VOLUMES; do
            # Inspect the volume driver options to get the host device path
            VOL_DEVICE=$(docker volume inspect "$VOL" \
                --format '{{index .Options "device"}}' 2>/dev/null || echo "")

            # If the volume references a different distro → it is stale
            if echo "$VOL_DEVICE" | grep -q "docker-desktop-bind-mounts/" && \
               ! echo "$VOL_DEVICE" | grep -q "$CURRENT_DISTRO"; then

                OLD_DISTRO=$(echo "$VOL_DEVICE" \
                    | grep -oP 'docker-desktop-bind-mounts/\K[^/]+' || echo "unknown")

                echo -e "${RED}  ✗${NC} Stale volume detected: ${YELLOW}$VOL${NC}"
                echo -e "      Old distro: ${RED}$OLD_DISTRO${NC} → Current: ${GREEN}$CURRENT_DISTRO${NC}"
                echo -e "${BLUE}  →${NC} Removing stale volume: ${YELLOW}$VOL${NC}"

                if docker volume rm "$VOL" 2>/dev/null; then
                    echo -e "${GREEN}  ✓${NC} Removed: ${GREEN}$VOL${NC}"
                    STALE_FOUND=true
                else
                    echo -e "${RED}  ✗${NC} Failed to remove ${RED}$VOL${NC} — a container may still be using it"
                    echo -e "${YELLOW}  ⚠${NC} Run: ${CYAN}docker compose down${NC} first, then retry"
                    exit 1
                fi
            fi
        done

        if [ "$STALE_FOUND" = false ]; then
            echo -e "${GREEN}  ✓${NC} No stale volumes found — all volumes match current distro ${GREEN}$CURRENT_DISTRO${NC}"
        else
            echo -e "${GREEN}  ✓${NC} Stale volume cleanup complete — Docker will recreate them fresh"
        fi
    fi
fi

# ── Docker Compose ─────────────────────────────────────────────────────────────
echo -e "${YELLOW}Starting Docker Compose...${NC}"
echo ""
# Execute docker compose command with all remaining passed arguments
docker compose --progress=auto \
  -f docker-compose.yml \
  $SSL_COMPOSE \
  -f docker-compose.expose-ports.yml \
  -f docker-compose.bindmount.yml \
  $DOCKER_COMPOSE_ARGS

# Check docker compose exit status
COMPOSE_EXIT_CODE=$?

if [ $COMPOSE_EXIT_CODE -eq 0 ]; then
    echo ""
    echo -e "${GREEN}${BOLD}✓${NC} Docker Compose executed ${GREEN}successfully${NC}"

    # ── Copy NiFi connectors & rich-media packages into extensions ────────────
    if [ "$IS_UP_COMMAND" = true ]; then
        echo ""
        echo -e "${CYAN}${BOLD}───────────────────────────────────────────────────────${NC}"
        echo -e "${YELLOW}${BOLD}Copying NiFi files into extensions folder...${NC}"

        # Find the NiFi container (service name is idol-nifi)
        NIFI_CONTAINER=$(docker ps -a --format '{{.Names}}' | grep -iE 'idol-nifi' | head -n1)

        if [ -z "$NIFI_CONTAINER" ]; then
            echo -e "${RED}  ✗${NC} No NiFi container found – skipping copy"
        else
            echo -e "${BLUE}  →${NC} Found container: ${GREEN}${NIFI_CONTAINER}${NC}"
            echo -e "${BLUE}  →${NC} Waiting for it to become running (NiFi can take up to ~90 s)..."

            # Wait up to 90 seconds for the container to reach "running" state
            READY=false
            for i in $(seq 1 45); do
                STATUS=$(docker inspect -f '{{.State.Status}}' "$NIFI_CONTAINER" 2>/dev/null || echo "missing")
                if [ "$STATUS" = "running" ]; then
                    READY=true
                    break
                fi
                echo -ne "${CYAN}.${NC}"
                sleep 2
            done
            echo ""

            if [ "$READY" = false ]; then
                echo -e "${RED}  ✗${NC} Container never reached 'running' state (last status: ${STATUS})"
                echo -e "${YELLOW}  ⚠${NC} Check logs with:  docker logs ${NIFI_CONTAINER}"
            else
                echo -e "${GREEN}  ✓${NC} Container is running – proceeding with copy"

                # 1) tempfolder-nifi-connectors → extensions  (always)
                if docker exec "$NIFI_CONTAINER" test -d /opt/nifi/nifi-current/tempfolder-nifi-connectors; then
                    if docker exec "$NIFI_CONTAINER" \
                        sh -c 'cp -a /opt/nifi/nifi-current/tempfolder-nifi-connectors/. /opt/nifi/nifi-current/extensions/'; then
                        echo -e "${GREEN}  ✓${NC} Copied contents of tempfolder-nifi-connectors → extensions"
                    else
                        echo -e "${RED}  ✗${NC} Failed to copy tempfolder-nifi-connectors"
                    fi
                else
                    echo -e "${YELLOW}  ⚠${NC} /opt/nifi/nifi-current/tempfolder-nifi-connectors does not exist inside the container"
                fi

                # 2) tempfolder-richmedia-packages → extensions  (only when enabled)
                if [ "$IDOL_RICH_MEDIA_INSTALL" = "TRUE" ]; then
                    if docker exec "$NIFI_CONTAINER" test -d /opt/nifi/nifi-current/tempfolder-richmedia-packages; then
                        if docker exec "$NIFI_CONTAINER" \
                            sh -c 'cp -a /opt/nifi/nifi-current/tempfolder-richmedia-packages/. /opt/nifi/nifi-current/extensions/'; then
                            echo -e "${GREEN}  ✓${NC} Copied contents of tempfolder-richmedia-packages → extensions"
                        else
                            echo -e "${RED}  ✗${NC} Failed to copy tempfolder-richmedia-packages"
                        fi
                    else
                        echo -e "${YELLOW}  ⚠${NC} /opt/nifi/nifi-current/tempfolder-richmedia-packages does not exist inside the container"
                    fi
                else
                    echo -e "${BLUE}  →${NC} Skipping richmedia-packages copy (IDOL_RICH_MEDIA_INSTALL != TRUE)"
                fi

                # Restart NiFi so it loads the newly copied extensions
                echo -e "${BLUE}  →${NC} Restarting ${GREEN}${NIFI_CONTAINER}${NC} to load new extensions..."
                if docker restart "$NIFI_CONTAINER" > /dev/null; then
                    echo -e "${GREEN}  ✓${NC} idol-nifi container restarted successfully"
                else
                    echo -e "${RED}  ✗${NC} Failed to restart ${NIFI_CONTAINER}"
                fi
            fi
        fi
        echo -e "${CYAN}${BOLD}───────────────────────────────────────────────────────${NC}"
    fi 
else
    echo ""
    echo -e "${RED}${BOLD}✗${NC} Docker Compose ${RED}failed${NC}"
    exit 1
fi

# ── Docker Compose Down Command ─────────────────────────────────────────────────────────────
if [ "$IS_DOWN_COMMAND" = true ]; then
    echo -e "${CYAN}${BOLD}───────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}${BOLD}Detected 'down' command - preparing to stop and remove containers${NC}"

    # List all available Docker Compose project names with numbering
    echo ""
    echo -e "${MAGENTA}${BOLD}Available Docker Compose Projects:${LIGHTER_YELLOW}"
    projects=($(docker compose ls --format json 2>/dev/null | jq -r '.[].Name'))

    if [ ${#projects[@]} -eq 0 ]; then
        echo -e "${RED}No Docker Compose projects found.${NC}"
        exit 1
    fi

    for i in "${!projects[@]}"; do
        echo -e "  $((i+1)). ${projects[$i]}"
    done
    echo -e "${LIGHTER_YELLOW}"

    # Default project name
    DEFAULT_PROJECT="idol-demo"
    PROJECT_NAME="$DEFAULT_PROJECT"

    # Ask for project selection
    read -p "Enter the number of the project to stop and remove (default: $DEFAULT_PROJECT, press Enter to use default): " PROJECT_NUMBER

    # Set the project name based on user input
    if [[ -n "$PROJECT_NUMBER" && "$PROJECT_NUMBER" =~ ^[0-9]+$ && "$PROJECT_NUMBER" -le "${#projects[@]}" && "$PROJECT_NUMBER" -gt 0 ]]; then
        PROJECT_NAME="${projects[$((PROJECT_NUMBER-1))]}"
        echo -e "${CYAN}Selected project: ${GREEN}$PROJECT_NAME${NC}"
    elif [ -n "$PROJECT_NUMBER" ]; then
        echo -e "${RED}Invalid selection. Using default project: $DEFAULT_PROJECT${NC}"
    else
        echo -e "${CYAN}Using default project: $DEFAULT_PROJECT${NC}"
    fi

    echo -e "${LIGHTER_YELLOW}"

    # Confirm with the user
    read -p "Are you sure you want to stop and remove ALL containers, images, and volumes for project '$PROJECT_NAME'? (y/n): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo -e "${RED}${BOLD}Aborted by user.${NC}"
        exit 0
    fi

    # Execute docker compose down with cleanup
    echo ""
    echo -e "${RED}${BOLD}Stopping and removing containers for project: ${ORANGE}$PROJECT_NAME${CYAN}"

    if docker compose --progress=auto -p "$PROJECT_NAME" down -v --remove-orphans; then
        echo -e "${GREEN}${BOLD}✓${RED} All containers, images, and volumes for project ${ORANGE}$PROJECT_NAME${RED} have been stopped and removed.${NC}"
    else
        echo -e "${RED}${BOLD}✗${NC} Failed to stop and remove containers for project ${RED}$PROJECT_NAME${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  Deployment Complete${NC}"
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}"
echo ""