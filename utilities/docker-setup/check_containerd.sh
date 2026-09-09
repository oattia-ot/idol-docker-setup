#!/bin/bash

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