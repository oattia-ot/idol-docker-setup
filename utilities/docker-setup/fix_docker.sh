#!/bin/bash

echo "=== Fixing containerd service file ==="

# Find containerd binary
CONTAINERD_BIN=$(which containerd 2>/dev/null)

if [ -z "$CONTAINERD_BIN" ]; then
    echo "containerd binary not found. Installing..."
    sudo apt-get update
    sudo apt-get install -y containerd.io
    CONTAINERD_BIN=$(which containerd)
fi

echo "containerd binary: $CONTAINERD_BIN"

# Remove corrupted service file
sudo rm -f /etc/systemd/system/containerd.service

# Check if system has a valid service file
if [ -f /lib/systemd/system/containerd.service ]; then
    echo "Using system containerd.service from /lib/systemd/system/"
else
    echo "Creating new containerd.service file..."
    sudo tee /lib/systemd/system/containerd.service > /dev/null <<EOF
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=$CONTAINERD_BIN
Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF
fi

# Create containerd config
sudo mkdir -p /etc/containerd
if [ ! -f /etc/containerd/config.toml ]; then
    echo "Creating containerd config..."
    $CONTAINERD_BIN config default | sudo tee /etc/containerd/config.toml > /dev/null
fi

# Reload systemd
echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

# Enable and start containerd
echo "Starting containerd..."
sudo systemctl enable containerd
sudo systemctl start containerd

# Check status
echo ""
echo "=== Containerd Status ==="
sudo systemctl status containerd --no-pager

# Now fix Docker service file
echo ""
echo "=== Fixing Docker service file ==="
sudo rm -f /etc/systemd/system/docker.service

sudo tee /lib/systemd/system/docker.service > /dev/null <<'EOF'
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target containerd.service firewalld.service time-sync.target
Wants=network-online.target
Requires=containerd.service

[Service]
Type=notify
ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutStartSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF

# Create docker.socket if needed
sudo tee /lib/systemd/system/docker.socket > /dev/null <<'EOF'
[Unit]
Description=Docker Socket for the API

[Socket]
ListenStream=/var/run/docker.sock
SocketMode=0660
SocketUser=root
SocketGroup=docker

[Install]
WantedBy=sockets.target
EOF

# Reload systemd again
echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

# Start Docker
echo "Starting Docker..."
sudo systemctl enable docker.socket
sudo systemctl enable docker
sudo systemctl start docker.socket
sudo systemctl start docker

# Check status
echo ""
echo "=== Docker Status ==="
sudo systemctl status docker --no-pager

echo ""
echo "=== Testing Docker ==="
sudo docker run hello-world