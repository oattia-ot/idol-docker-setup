# Harbor Registry — Complete Setup Summary

> **Updated:** May 2026 | Scripts: `install-harbor.sh`, `setup-harbor-docker.sh`, `setup-harbor-minikube.sh`

---

## Overview

Harbor can be deployed in two modes, both launched from a single entry-point script:

```bash
./install-harbor.sh          # Interactive menu
./install-harbor.sh --docker   # Docker (standalone)
./install-harbor.sh --minikube # Kubernetes / Minikube
```

---

## Mode 1 — Docker (Standalone)

> Runs Harbor via Docker Compose. Requires **root / sudo**.

### Quick Commands

```bash
# Interactive
./setup-harbor-docker.sh

# HTTP only (custom ports)
./setup-harbor-docker.sh --hostname 192.168.1.50 --http-port 9080 --yes

# HTTPS with SSL directory
./setup-harbor-docker.sh --hostname registry.mycompany.com \
  --https --ssl-dir /etc/ssl/harbor --https-port 443

# Via environment variables
HARBOR_HOSTNAME=registry.example.com HARBOR_ENABLE_HTTPS=true \
HARBOR_SSL_DIR=./ssl HARBOR_HTTP_PORT=80 HARBOR_HTTPS_PORT=443 \
./setup-harbor-docker.sh --yes

# Delete existing deployment
./setup-harbor-docker.sh --delete
./setup-harbor-docker.sh --delete --installed-folder /custom/harbor
```

### Key Options

| Flag | Default | Description |
|------|---------|-------------|
| `-H, --hostname` | *(prompted)* | Hostname or IP |
| `--http-port` | `5050` | HTTP port |
| `--https-port` | `5443` | HTTPS port |
| `--https` | off | Enable HTTPS |
| `--ssl-dir` | `../generate-ssl-certs/ssl/…` | Cert + key directory |
| `--cert / --key` | *(from ssl-dir)* | Override individual file paths |
| `-v, --version` | `v2.15.1` | Harbor version |
| `-f, --installed-folder` | `/opt/harbor` | Install path |
| `-y, --yes` | false | Non-interactive |
| `-d, --delete` | — | Tear down deployment |

### What It Does

1. Installs Docker + Docker Compose if missing
2. Downloads the Harbor online installer tarball from GitHub
3. Patches `harbor.yml` (hostname, ports, TLS paths)
4. Optionally generates a self-signed cert if SSL files are missing
5. Runs `./prepare` then `./install.sh`

### After Install — Useful Commands

```bash
cd /opt/harbor/harbor
docker-compose ps          # status
docker-compose logs -f     # tail logs
docker-compose down        # stop
docker-compose up -d       # restart
```

---

## Mode 2 — Minikube (Kubernetes)

> Deploys Harbor via Helm on a local Minikube cluster. **Do NOT run as root.**

### Quick Commands

```bash
# Standard ports (80/443) — recommended
./setup-harbor-minikube.sh --standard-ports -y

# Standard ports + HTTPS + clean restart
./setup-harbor-minikube.sh --standard-ports --https --clean-restart -y

# Custom ports (5050/5443)
./setup-harbor-minikube.sh --custom-ports -y

# Custom port numbers
./setup-harbor-minikube.sh --custom-ports \
  --http-port 8080 --https-port 8443 --https -y

# Full example
./setup-harbor-minikube.sh --hostname idol-docker-host \
  --https --standard-ports --clean-restart -y

# Utility
./setup-harbor-minikube.sh --clear          # Delete ALL profiles
./setup-harbor-minikube.sh -p               # List profiles
./setup-harbor-minikube.sh --help
```

### Key Options

| Flag | Default | Description |
|------|---------|-------------|
| `--standard-ports` | ✅ recommended | Use ports 80 / 443 |
| `--custom-ports` | — | Use ports 5050 / 5443 |
| `--http-port / --https-port` | 5050 / 5443 | Override port numbers |
| `--https` | off | Enable HTTPS |
| `--clean-restart` | off | Delete old profile before start |
| `--minikube-profile` | `harbor` | Profile name |
| `--minikube-cpus` | `4` | CPUs |
| `--minikube-memory` | `8192` | Memory (MB) |
| `--minikube-disk-size` | `20g` | Disk |
| `--minikube-k8s-version` | `v1.30.0` | Kubernetes version |
| `--namespace` | `harbor` | K8s namespace |
| `--skip-profile-select` | off | Skip profile menu |
| `--env-output-dir` | `./env` | Where to write `.env` file |

### What It Does

1. Adds the Harbor Helm repo and lets you pick a chart version
2. Starts Minikube with `--ports=127.0.0.1:30002:30002,127.0.0.1:30003:30003`
3. Deploys Harbor via Helm with `expose.type: nodePort`
4. Waits for all pods to be Ready
5. Starts `kubectl port-forward` in the background
6. Writes an env file to `./env/minikube_<profile>.env`

### NodePort Access (No Tunnel Needed)

| Protocol | NodePort | URL |
|----------|----------|-----|
| HTTP | 30002 | `http://idol-docker-host:30002` |
| HTTPS | 30003 | `https://idol-docker-host:30003` ✅ |

> **Add to Windows hosts file** (`C:\Windows\System32\drivers\etc\hosts`):
> ```
> 127.0.0.1   idol-docker-host
> ```

---

## Docker Daemon Config

For Docker to trust the Harbor registry (especially over HTTP or custom ports), configure `/etc/docker/daemon.json`:

```json
{
  "registry-mirrors": [
    "https://mirror.gcr.io",
    "https://registry.hub.docker.com"
  ],
  "insecure-registries": [
    "idol-docker-host",
    "idol-docker-host:85"
  ]
}
```

Then restart Docker:

```bash
sudo systemctl restart docker
```

---

## Default Credentials

| Field | Value |
|-------|-------|
| Username | `admin` |
| Password | `Harbor12345` |

---

## Quick Reference

| Goal | Command |
|------|---------|
| Interactive launcher | `./install-harbor.sh` |
| Docker HTTP install | `./setup-harbor-docker.sh --hostname <host> -y` |
| Docker HTTPS install | `./setup-harbor-docker.sh --hostname <host> --https --ssl-dir <dir> -y` |
| Delete Docker deploy | `./setup-harbor-docker.sh --delete` |
| Minikube standard ports | `./setup-harbor-minikube.sh --standard-ports -y` |
| Minikube custom ports | `./setup-harbor-minikube.sh --custom-ports -y` |
| Minikube clean restart | `./setup-harbor-minikube.sh --standard-ports --clean-restart -y` |
| List Minikube profiles | `./setup-harbor-minikube.sh -p` |
| Delete all profiles | `./setup-harbor-minikube.sh --clear` |
| Docker login (standard) | `docker login idol-docker-host` |
| Docker login (NodePort) | `docker login idol-docker-host:30003` |