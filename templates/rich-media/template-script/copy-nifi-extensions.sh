#!/bin/bash
# =============================================================
# Script: copy-nifi-extensions.sh
# Purpose: Copy IDOL NiFi extensions from the official image
#          to your host directory for persistent volume mount
# =============================================================

set -e  # Exit on any error

# Set default values for environment variables (can be overridden)
# IDOL OS detection (Ubuntu / macOS) — loads module/os-compat.sh when present
if [ -z "${IDOL_OS_COMPAT_LOADED:-}" ]; then
  _idol_os_src=""
  if [ -n "${IDOL_BASE_PATH:-}" ] && [ -f "${IDOL_BASE_PATH}/module/os-compat.sh" ]; then
    _idol_os_src="${IDOL_BASE_PATH}/module/os-compat.sh"
  else
    _idol_os_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
    _idol_os_probe="$_idol_os_dir"
    _idol_os_i=0
    while [ -n "$_idol_os_probe" ] && [ "$_idol_os_probe" != "/" ] && [ "$_idol_os_i" -lt 20 ]; do
      if [ -f "$_idol_os_probe/module/os-compat.sh" ]; then
        _idol_os_src="$_idol_os_probe/module/os-compat.sh"
        break
      fi
      _idol_os_probe="$(dirname "$_idol_os_probe")"
      _idol_os_i=$((_idol_os_i + 1))
    done
  fi
  if [ -n "$_idol_os_src" ]; then
    # shellcheck source=/dev/null
    . "$_idol_os_src"
  else
    case "$(uname -s 2>/dev/null)" in
      Darwin)
        export IDOL_HOST_OS=macos IDOL_OS_FAMILY=macos
        ;;
      Linux)
        export IDOL_OS_FAMILY=linux
        if [ -f /etc/os-release ] && grep -qi ubuntu /etc/os-release 2>/dev/null; then
          export IDOL_HOST_OS=ubuntu
        else
          export IDOL_HOST_OS=linux
        fi
        ;;
      *)
        export IDOL_HOST_OS=unknown IDOL_OS_FAMILY=unknown
        ;;
    esac
  fi
  unset _idol_os_src _idol_os_dir _idol_os_probe _idol_os_i
fi

IDOL_REGISTRY="${IDOL_REGISTRY:-microfocusidolserver}"
IDOL_RICH_MEDIA_VERSION="${IDOL_RICH_MEDIA_VERSION:-26.1}"

echo "=== OpenText IDOL NiFi Extensions Copy Script ==="

echo "ℹ️  Using IDOL_REGISTRY=${IDOL_REGISTRY}"
echo "ℹ️  Using IDOL_RICH_MEDIA_VERSION=${IDOL_RICH_MEDIA_VERSION}"

# Define variables
IMAGE="${IDOL_REGISTRY}/nifi-ver2-full:${IDOL_RICH_MEDIA_VERSION}"
TEMP_CONTAINER="temp-nifi"
TARGET_DIR="./nifi/data/extensions"

echo "📦 Using image: ${IMAGE}"
echo "📁 Target directory: ${TARGET_DIR}"

# Create target directory if it doesn't exist
mkdir -p "${TARGET_DIR}"
echo "✅ Target directory created/verified."

# Remove old temp container if it exists
if docker ps -a --format '{{.Names}}' | grep -q "^${TEMP_CONTAINER}$"; then
    echo "🗑️  Removing old temporary container..."
    docker rm -f "${TEMP_CONTAINER}" >/dev/null 2>&1
fi

# Run temporary container
echo "🚀 Starting temporary NiFi container..."
docker run --rm -d --name "${TEMP_CONTAINER}" "${IMAGE}"

# Wait a few seconds for container to be ready
sleep 5

# Copy extensions
echo "📋 Copying extensions from container to host..."
docker cp "${TEMP_CONTAINER}:/opt/nifi/nifi-current/extensions/." "${TARGET_DIR}/"

echo "✅ Extensions successfully copied to ${TARGET_DIR}"

# Stop and remove the temporary container
echo "🛑 Stopping temporary container..."
docker stop "${TEMP_CONTAINER}" >/dev/null

echo ""
echo "🎉 Done! You can now use this volume mount in docker-compose:"
echo "   - ${TARGET_DIR}:/opt/nifi/nifi-current/extensions"
echo ""
echo "Next steps:"
echo "   1. docker compose down"
echo "   2. Uncomment the extensions volume in your docker-compose.yml"
echo "   3. docker compose up -d"