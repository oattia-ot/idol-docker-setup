#!/bin/bash

# Find containerd binary
CONTAINERD_PATH=$(which containerd 2>/dev/null)

if [ -z "$CONTAINERD_PATH" ]; then
    echo "Error: containerd binary not found!"
    echo "Installing containerd..."
    
    # Install containerd
    sudo apt-get update
    sudo apt-get install -y containerd.io
    
    CONTAINERD_PATH=$(which containerd)
fi

echo "Containerd found at: $CONTAINERD_PATH"

# Update containerd service file with correct path
sudo tee /etc/systemd/system/containerd.service > /dev/null <<EOF
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=$CONTAINERD_PATH
Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF

# Create containerd config directory
sudo mkdir -p /etc/containerd

# Generate default containerd config
if [ -f "$CONTAINERD_PATH" ]; then
    sudo $CONTAINERD_PATH config default | sudo tee /etc/containerd/config.toml > /dev/null
fi

# Update Docker service file with correct containerd socket path
sudo tee /etc/systemd/system/docker.service > /dev/null <<'EOF'
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target docker.socket firewalld.service containerd.service
Wants=network-online.target
Requires=docker.socket containerd.service

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

# Reload systemd
sudo systemctl daemon-reload

# Start containerd first
echo "Starting containerd..."
sudo systemctl enable containerd
sudo systemctl start containerd
sudo systemctl status containerd --no-pager

echo ""
echo "Starting Docker..."
sudo systemctl enable docker.socket
sudo systemctl enable docker.service
sudo systemctl start docker.socket
sudo systemctl start docker.service

echo ""
echo "Verifying Docker installation..."
sudo systemctl status docker.service --no-pager

echo ""
echo "Testing Docker..."
sudo docker run hello-world