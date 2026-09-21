#!/usr/bin/env bash

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_IDOL_ROOT="$(cd "$_SCRIPT_DIR/../.." && pwd)"
if [ -f "$_IDOL_ROOT/module/os-compat.sh" ]; then
    # shellcheck source=/dev/null
    . "$_IDOL_ROOT/module/os-compat.sh"
fi

if [ "${IDOL_OS_FAMILY:-}" = "macos" ] || [ "$(uname -s)" = "Darwin" ]; then
    echo "[OS] macOS detected — containerd is bundled with Docker Desktop."
    echo "=== Docker engine ==="
    docker info 2>/dev/null | head -n 20 || echo "Docker engine is not running. Open Docker Desktop."
    exit 0
fi

echo "=== Checking containerd binary ==="
which containerd
ls -la /usr/bin/containerd 2>/dev/null || echo "containerd not found in /usr/bin/"

echo ""
echo "=== Checking containerd service ==="
sudo systemctl status containerd --no-pager

echo ""
echo "=== Checking containerd logs ==="
sudo journalctl -xeu containerd.service | tail -30

echo ""
echo "=== Trying to start containerd ==="
sudo systemctl start containerd
sleep 2

echo ""
echo "=== Containerd status after start attempt ==="
sudo systemctl status containerd --no-pager