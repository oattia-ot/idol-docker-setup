#!/bin/bash

# ============================================================
# build-docker-image-from-zip.sh
# Scans all .zip files in input-files/, extracts each one,
# generates a Dockerfile, builds a Docker image, then either:
#   (default)  saves the image as a .tar to output-image/
#   (--load)   loads the image into the local Docker daemon
#
# Config priority (highest → lowest):
#   1. CLI flags
#   2. Environment variables
#   3. Interactive prompt
#   4. Built-in default
# ============================================================

set -euo pipefail

# --- Resolve script's own directory so relative defaults work ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colors ---
RED=$'\033[0;31m';    GREEN=$'\033[0;32m';   YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m';   BLUE=$'\033[0;34m';    MAGENTA=$'\033[0;35m'
WHITE=$'\033[1;37m';  GRAY=$'\033[0;90m';    BOLD=$'\033[1m'
UNDERLINE=$'\033[4m'; DIM=$'\033[2m';        RESET=$'\033[0m'

# --- Help ---
usage() {
    cat <<EOF

${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════╗
║         build-docker-image-from-zip.sh  —  Help               ║
╚══════════════════════════════════════════════════════════════════╝${RESET}

${BOLD}${UNDERLINE}DESCRIPTION${RESET}
  Scans a directory for ${CYAN}.zip${RESET} files, extracts each one, auto-generates
  a ${CYAN}Dockerfile${RESET}, builds a ${CYAN}Docker image${RESET}, then either saves it as a
  ${CYAN}.tar${RESET} file ${DIM}(default)${RESET} or loads it into the local Docker daemon ${DIM}(--load)${RESET}.

  Configuration is resolved in this priority order:
    ${GREEN}1. CLI flag${RESET}  →  ${YELLOW}2. Env variable${RESET}  →  ${BLUE}3. Interactive prompt${RESET}  →  ${GRAY}4. Default${RESET}

${BOLD}${UNDERLINE}USAGE${RESET}
  ${WHITE}./$(basename "$0")${RESET} ${GRAY}[OPTIONS]${RESET}
  ${WHITE}./$(basename "$0")${RESET} ${CYAN}-d${RESET} <path> ${CYAN}-o${RESET} <path> ${CYAN}-n${RESET} <prefix> ${CYAN}-t${RESET} <tag> ${CYAN}-p${RESET} <port>
  ${WHITE}./$(basename "$0")${RESET} ${CYAN}--dir${RESET} <path> ${CYAN}--output${RESET} <path> ${CYAN}--prefix${RESET} <prefix> ${CYAN}--tag${RESET} <tag> ${CYAN}--port${RESET} <port>
  ${WHITE}./$(basename "$0")${RESET} ${CYAN}-i${RESET} | ${CYAN}--load${RESET}
  ${WHITE}./$(basename "$0")${RESET} ${CYAN}-h${RESET} | ${CYAN}--help${RESET}

${BOLD}${UNDERLINE}OPTIONS${RESET}

  ${CYAN}${BOLD}-d${RESET}, ${CYAN}${BOLD}--dir${RESET} ${YELLOW}<path>${RESET}
        Directory containing the ${CYAN}.zip${RESET} files to process.
        ${DIM}Default${RESET} : ${GRAY}input-files/  (relative to script location)${RESET}
        ${DIM}Env var${RESET} : ${YELLOW}DOCKER_SCAN_DIR${RESET}

  ${CYAN}${BOLD}-o${RESET}, ${CYAN}${BOLD}--output${RESET} ${YELLOW}<path>${RESET}
        Directory where built ${CYAN}.tar${RESET} image files are saved.
        ${DIM}Ignored when ${RESET}${CYAN}--load${RESET}${DIM} is set.${RESET}
        ${DIM}Default${RESET} : ${GRAY}output-image/  (relative to script location)${RESET}
        ${DIM}Env var${RESET} : ${YELLOW}DOCKER_OUTPUT_DIR${RESET}

  ${CYAN}${BOLD}-i${RESET}, ${CYAN}${BOLD}--load${RESET}
        Load the built image into the local Docker daemon instead
        of saving it as a ${CYAN}.tar${RESET} file.
        ${DIM}Default${RESET} : ${GRAY}off  (saves .tar to --output directory)${RESET}
        ${DIM}Env var${RESET} : ${YELLOW}DOCKER_LOAD_MODE=true${RESET}

  ${CYAN}${BOLD}-n${RESET}, ${CYAN}${BOLD}--prefix${RESET} ${YELLOW}<prefix>${RESET}
        Registry or namespace prefix prepended to the image name.
        ${DIM}Produces${RESET} : ${GREEN}<prefix>/<imagename>:<tag>${RESET}
        ${DIM}Example${RESET}  : ${CYAN}-n myrepo${RESET}  →  ${GREEN}myrepo/content-26.1.0:latest${RESET}
        ${DIM}Default${RESET}  : ${GRAY}(none — image name only, no prefix)${RESET}
        ${DIM}Env var${RESET}  : ${YELLOW}DOCKER_IMAGE_PREFIX${RESET}

  ${CYAN}${BOLD}-t${RESET}, ${CYAN}${BOLD}--tag${RESET} ${YELLOW}<tag>${RESET}
        Docker image tag applied to every built image.
        ${DIM}Example${RESET}  : ${CYAN}-t 26.1.0${RESET}  →  ${GREEN}myrepo/content-26.1.0:26.1.0${RESET}
        ${DIM}Default${RESET}  : ${GRAY}latest${RESET}
        ${DIM}Env var${RESET}  : ${YELLOW}DOCKER_IMAGE_TAG${RESET}

  ${CYAN}${BOLD}-p${RESET}, ${CYAN}${BOLD}--port${RESET} ${YELLOW}<port>${RESET}
        Port number written into the ${CYAN}EXPOSE${RESET} instruction of the
        generated Dockerfile.
        ${DIM}Default${RESET}  : ${GRAY}9100${RESET}
        ${DIM}Env var${RESET}  : ${YELLOW}DOCKER_EXPOSE_PORT${RESET}

  ${CYAN}${BOLD}-h${RESET}, ${CYAN}${BOLD}--help${RESET}
        Show this help message and exit.

${BOLD}${UNDERLINE}OUTPUT MODES${RESET}

  ${BOLD}Save to file${RESET} ${GRAY}(default)${RESET}
    Builds the image, saves it as a ${CYAN}.tar${RESET} in ${CYAN}--output${RESET}, then removes
    it from the daemon to keep things clean.
    ${GREEN}output-image/content-26.1.0-linux-x86-64.tar${RESET}

  ${BOLD}Load into daemon${RESET} ${GRAY}(-i / --load)${RESET}
    Builds the image and keeps it in the local Docker daemon.
    Verify with: ${CYAN}docker images${RESET}

${BOLD}${UNDERLINE}ENVIRONMENT VARIABLES${RESET}
  ${YELLOW}DOCKER_SCAN_DIR${RESET}       Directory to scan for ZIPs     ${GRAY}(same as --dir)${RESET}
  ${YELLOW}DOCKER_OUTPUT_DIR${RESET}     Directory to save .tar files   ${GRAY}(same as --output)${RESET}
  ${YELLOW}DOCKER_LOAD_MODE${RESET}      Set to ${CYAN}true${RESET} to load into daemon    ${GRAY}(same as --load)${RESET}
  ${YELLOW}DOCKER_IMAGE_PREFIX${RESET}   Image registry / namespace     ${GRAY}(same as --prefix)${RESET}
  ${YELLOW}DOCKER_IMAGE_TAG${RESET}      Image tag                      ${GRAY}(same as --tag)${RESET}
  ${YELLOW}DOCKER_EXPOSE_PORT${RESET}    Port in Dockerfile EXPOSE      ${GRAY}(same as --port)${RESET}

  ${DIM}Useful for CI/CD pipelines to skip interactive prompts:${RESET}
    ${GREEN}export${RESET} ${YELLOW}DOCKER_SCAN_DIR${RESET}=${CYAN}./input-files${RESET}
    ${GREEN}export${RESET} ${YELLOW}DOCKER_OUTPUT_DIR${RESET}=${CYAN}./output-image${RESET}
    ${GREEN}export${RESET} ${YELLOW}DOCKER_IMAGE_PREFIX${RESET}=${CYAN}myrepo${RESET}
    ${GREEN}export${RESET} ${YELLOW}DOCKER_IMAGE_TAG${RESET}=${CYAN}26.1.0${RESET}
    ${GREEN}export${RESET} ${YELLOW}DOCKER_EXPOSE_PORT${RESET}=${CYAN}9100${RESET}

${BOLD}${UNDERLINE}IMAGE NAMING${RESET}
  Base name is derived from the ZIP filename
  ${DIM}(lowercased, underscores → dashes):${RESET}

    ${CYAN}Content_26.1.0_LINUX_X86_64.zip${RESET}  →  ${GREEN}content-26.1.0-linux-x86-64${RESET}

  With prefix and tag:
    ${CYAN}--prefix myrepo --tag 26.1.0${RESET}  →  ${GREEN}myrepo/content-26.1.0-linux-x86-64:26.1.0${RESET}

  Saved tar filename:
    ${GREEN}output-image/content-26.1.0-linux-x86-64.tar${RESET}

${BOLD}${UNDERLINE}EXAMPLES${RESET}
  ${GRAY}# Default: save .tar files to output-image/${RESET}
  ${WHITE}./$(basename "$0")${RESET}

  ${GRAY}# Load images into Docker daemon instead of saving${RESET}
  ${WHITE}./$(basename "$0")${RESET} ${CYAN}--load${RESET}
  ${WHITE}./$(basename "$0")${RESET} ${CYAN}-i${RESET}

  ${GRAY}# Custom input/output directories${RESET}
  ${WHITE}./$(basename "$0")${RESET} ${CYAN}--dir${RESET} ${GREEN}./zips${RESET} ${CYAN}--output${RESET} ${GREEN}./images${RESET}

  ${GRAY}# Fully specified, save mode${RESET}
  ${WHITE}./$(basename "$0")${RESET} ${CYAN}-d${RESET} ${GREEN}./input-files${RESET} ${CYAN}-o${RESET} ${GREEN}./output-image${RESET} ${CYAN}-n${RESET} ${GREEN}myrepo${RESET} ${CYAN}-t${RESET} ${GREEN}26.1.0${RESET} ${CYAN}-p${RESET} ${GREEN}9100${RESET}

  ${GRAY}# Fully specified, load mode${RESET}
  ${WHITE}./$(basename "$0")${RESET} ${CYAN}-d${RESET} ${GREEN}./input-files${RESET} ${CYAN}-n${RESET} ${GREEN}myrepo${RESET} ${CYAN}-t${RESET} ${GREEN}26.1.0${RESET} ${CYAN}-p${RESET} ${GREEN}9100${RESET} ${CYAN}--load${RESET}

  ${GRAY}# Via environment variables (CI/CD), save mode${RESET}
  ${YELLOW}DOCKER_IMAGE_PREFIX${RESET}=myrepo ${YELLOW}DOCKER_IMAGE_TAG${RESET}=26.1.0 ${WHITE}./$(basename "$0")${RESET}

EOF
    exit 0
}

# --- Parse arguments ---
SCAN_DIR_ARG=""
OUTPUT_DIR_ARG=""
EXPOSE_PORT_ARG=""
IMAGE_PREFIX_ARG=""
IMAGE_TAG_ARG=""
LOAD_MODE_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    usage ;;
        -d|--dir)     SCAN_DIR_ARG="$2";    shift 2 ;;
        -o|--output)  OUTPUT_DIR_ARG="$2";  shift 2 ;;
        -p|--port)    EXPOSE_PORT_ARG="$2"; shift 2 ;;
        -n|--prefix)  IMAGE_PREFIX_ARG="$2";shift 2 ;;
        -t|--tag)     IMAGE_TAG_ARG="$2";   shift 2 ;;
        -i|--load)    LOAD_MODE_ARG="true"; shift 1 ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${RESET}"
            echo "   Run '$(basename "$0") --help' for usage."
            exit 1
            ;;
    esac
done

# --- Resolve values: CLI > ENV > interactive prompt > default ---
prompt_if_empty() {
    local var_name="$1"
    local prompt_msg="$2"
    local default_val="$3"
    local current_val="${!var_name}"

    if [ -z "$current_val" ]; then
        if [ -t 0 ]; then
            read -rp "$(echo -e "${CYAN}${prompt_msg}${RESET} [${BOLD}${default_val:-none}${RESET}]: ")" input
            printf -v "$var_name" '%s' "${input:-$default_val}"
        else
            printf -v "$var_name" '%s' "$default_val"
        fi
    fi
}

SCAN_DIR="${SCAN_DIR_ARG:-${DOCKER_SCAN_DIR:-}}"
prompt_if_empty SCAN_DIR "📁 Input directory (ZIP files)" "$SCRIPT_DIR/input-files"

OUTPUT_DIR="${OUTPUT_DIR_ARG:-${DOCKER_OUTPUT_DIR:-}}"
prompt_if_empty OUTPUT_DIR "💾 Output directory (saved .tar images)" "$SCRIPT_DIR/output-image"

EXPOSE_PORT="${EXPOSE_PORT_ARG:-${DOCKER_EXPOSE_PORT:-}}"
prompt_if_empty EXPOSE_PORT "🔌 Port to EXPOSE in Dockerfile" "9100"

IMAGE_PREFIX="${IMAGE_PREFIX_ARG:-${DOCKER_IMAGE_PREFIX:-}}"
prompt_if_empty IMAGE_PREFIX "🏷️  Image prefix (e.g. myrepo, or leave blank)" ""

IMAGE_TAG="${IMAGE_TAG_ARG:-${DOCKER_IMAGE_TAG:-}}"
prompt_if_empty IMAGE_TAG "🔖 Image tag (e.g. latest, 26.1.0)" "latest"

# Load mode: CLI flag > env var > false
LOAD_MODE="${LOAD_MODE_ARG:-${DOCKER_LOAD_MODE:-false}}"

# --- Validate ---
if [ ! -d "$SCAN_DIR" ]; then
    echo -e "${RED}❌ Input directory not found: '$SCAN_DIR'${RESET}"
    exit 1
fi

if [ "$LOAD_MODE" != "true" ]; then
    mkdir -p "$OUTPUT_DIR"
fi

# --- Print resolved config ---
echo ""
echo -e "${BOLD}${CYAN}============================================${RESET}"
echo -e "${BOLD} Configuration${RESET}"
echo -e "${BOLD}${CYAN}============================================${RESET}"
echo -e "  📁 Input directory  : ${CYAN}$SCAN_DIR${RESET}"
if [ "$LOAD_MODE" = "true" ]; then
    echo -e "  🐳 Output mode      : ${GREEN}Load into Docker daemon${RESET}"
else
    echo -e "  💾 Output mode      : ${YELLOW}Save .tar → ${OUTPUT_DIR}${RESET}"
fi
echo -e "  🔌 Expose port      : ${CYAN}$EXPOSE_PORT${RESET}"
echo -e "  🏷️  Image prefix     : ${CYAN}${IMAGE_PREFIX:-<none>}${RESET}"
echo -e "  🔖 Image tag        : ${CYAN}$IMAGE_TAG${RESET}"
echo ""

ZIP_FILES=("$SCAN_DIR"/*.zip)

if [ ! -e "${ZIP_FILES[0]}" ]; then
    echo -e "${RED}❌ No ZIP files found in '$SCAN_DIR'. Exiting.${RESET}"
    exit 1
fi

echo -e "${BOLD}Found ${CYAN}${#ZIP_FILES[@]}${RESET}${BOLD} ZIP file(s) to process${RESET}"

SUCCESS=()
FAILED=()

for ZIP_PATH in "${ZIP_FILES[@]}"; do
    ZIP_FILE=$(basename "$ZIP_PATH")
    ZIP_NAME="${ZIP_FILE%.zip}"

    BASE_NAME=$(echo "$ZIP_NAME" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
    if [ -n "$IMAGE_PREFIX" ]; then
        FULL_IMAGE_NAME="${IMAGE_PREFIX}/${BASE_NAME}:${IMAGE_TAG}"
    else
        FULL_IMAGE_NAME="${BASE_NAME}:${IMAGE_TAG}"
    fi

    TAR_FILE="$OUTPUT_DIR/${BASE_NAME}.tar"
    BUILD_DIR="/tmp/docker_build_${ZIP_NAME}_$$"

    echo ""
    echo -e "${BOLD}${CYAN}--------------------------------------------${RESET}"
    echo -e "📦 Processing  : ${CYAN}$ZIP_FILE${RESET}"
    echo -e "🐳 Image name  : ${GREEN}$FULL_IMAGE_NAME${RESET}"
    if [ "$LOAD_MODE" != "true" ]; then
        echo -e "💾 Output tar  : ${YELLOW}$TAR_FILE${RESET}"
    fi
    echo -e "${BOLD}${CYAN}--------------------------------------------${RESET}"

    # Cleanup build dir on exit
    trap 'rm -rf "$BUILD_DIR"' EXIT

    # Step 1: Create isolated temp build directory
    mkdir -p "$BUILD_DIR"

    # Step 2: Extract ZIP
    echo -e "📂 Extracting → ${CYAN}$BUILD_DIR${RESET} ..."
    if ! unzip -q "$ZIP_PATH" -d "$BUILD_DIR"; then
        echo -e "${RED}❌ Failed to extract $ZIP_FILE. Skipping.${RESET}"
        FAILED+=("$ZIP_FILE")
        continue
    fi

    # Step 3: Find extracted subdirectory
    EXTRACT_SUBDIR=$(find "$BUILD_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    if [ -z "$EXTRACT_SUBDIR" ]; then
        EXTRACT_SUBDIR="$BUILD_DIR"
        COPY_PATH="."
    else
        COPY_PATH=$(basename "$EXTRACT_SUBDIR")
    fi

    # Step 4: Detect start/stop scripts and main executable
    START_SCRIPT=$(find "$EXTRACT_SUBDIR" -maxdepth 1 -name "start-*.sh" | head -n 1)
    START_CMD=$(basename "${START_SCRIPT:-}")
    MAIN_EXE=$(find "$EXTRACT_SUBDIR" -maxdepth 1 -name "*.exe" | head -n 1)
    MAIN_EXE_NAME=$(basename "${MAIN_EXE:-}")

    CHMOD_TARGETS=""
    [ -n "$MAIN_EXE_NAME" ] && CHMOD_TARGETS+=" $MAIN_EXE_NAME"
    [ -n "$START_CMD" ]     && CHMOD_TARGETS+=" $START_CMD"
    STOP_SCRIPT=$(find "$EXTRACT_SUBDIR" -maxdepth 1 -name "stop-*.sh" | head -n 1)
    [ -n "$STOP_SCRIPT" ]   && CHMOD_TARGETS+=" $(basename "$STOP_SCRIPT")"

    CMD_LINE="${START_CMD:-./$(basename "${MAIN_EXE:-app}")}"

    echo -e "  ✅ Extracted to  : ${CYAN}$EXTRACT_SUBDIR${RESET}"
    echo -e "  ✅ Start command : ${CYAN}$CMD_LINE${RESET}"

    # Step 5: Generate Dockerfile
    DOCKERFILE="$BUILD_DIR/Dockerfile"
    echo -e "📝 Generating Dockerfile → ${CYAN}$DOCKERFILE${RESET} ..."

    cat > "$DOCKERFILE" <<EOF
FROM ubuntu:22.04

# Install common runtime dependencies
RUN apt-get update && apt-get install -y \\
    libstdc++6 \\
    libgcc-s1 \\
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/app/${ZIP_NAME}

# Copy extracted application files
COPY ${COPY_PATH}/ .

# Make scripts and binaries executable
RUN chmod +x${CHMOD_TARGETS}

EXPOSE ${EXPOSE_PORT}

CMD ["./${CMD_LINE}"]
EOF

    echo -e "${GRAY}  --- Dockerfile ---${RESET}"
    sed 's/^/  /' "$DOCKERFILE"
    echo -e "${GRAY}  ------------------${RESET}"

    # Step 6: Build Docker image
    echo -e "🔨 Building image: ${GREEN}$FULL_IMAGE_NAME${RESET} ..."
    if ! docker build -t "$FULL_IMAGE_NAME" "$BUILD_DIR"; then
        echo -e "${RED}❌ Docker build failed for $ZIP_FILE${RESET}"
        FAILED+=("$ZIP_FILE")
        rm -rf "$BUILD_DIR"
        continue
    fi

    # Step 7: Save or load
    if [ "$LOAD_MODE" = "true" ]; then
        echo -e "${GREEN}✅ Image loaded into Docker daemon: $FULL_IMAGE_NAME${RESET}"
        SUCCESS+=("daemon:$FULL_IMAGE_NAME")
    else
        echo -e "💾 Saving image → ${YELLOW}$TAR_FILE${RESET} ..."
        if docker save -o "$TAR_FILE" "$FULL_IMAGE_NAME"; then
            echo -e "${GREEN}✅ Saved: $TAR_FILE${RESET}"
            # Remove from daemon after saving to keep things clean
            docker rmi "$FULL_IMAGE_NAME" > /dev/null 2>&1 && \
                echo -e "${GRAY}   (removed from daemon after save)${RESET}"
            SUCCESS+=("file:$TAR_FILE")
        else
            echo -e "${RED}❌ Failed to save image to $TAR_FILE${RESET}"
            FAILED+=("$ZIP_FILE")
        fi
    fi

    rm -rf "$BUILD_DIR"
    trap - EXIT

done

# --- Summary ---
echo ""
echo -e "${BOLD}${CYAN}============================================${RESET}"
echo -e "${BOLD} Summary${RESET}"
echo -e "${BOLD}${CYAN}============================================${RESET}"

if [ ${#SUCCESS[@]} -gt 0 ]; then
    echo -e "${GREEN}✅ Successfully processed:${RESET}"
    for entry in "${SUCCESS[@]}"; do
        mode="${entry%%:*}"
        value="${entry#*:}"
        if [ "$mode" = "file" ]; then
            echo -e "   ${GREEN}💾 $value${RESET}"
        else
            echo -e "   ${GREEN}🐳 $value${RESET}  ${GRAY}(in Docker daemon)${RESET}"
        fi
    done
fi

if [ ${#FAILED[@]} -gt 0 ]; then
    echo -e "${RED}❌ Failed:${RESET}"
    for f in "${FAILED[@]}"; do
        echo -e "   ${RED}- $f${RESET}"
    done
    exit 1
fi

echo ""
if [ "$LOAD_MODE" = "true" ]; then
    echo -e "Run ${CYAN}'docker images'${RESET} to see loaded images."
else
    echo -e "Saved images are in: ${CYAN}$OUTPUT_DIR${RESET}"
    echo -e "To load a saved image: ${CYAN}docker load -i <file>.tar${RESET}"
fi