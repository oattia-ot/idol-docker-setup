# Deployment Guide — NiFi Config Manager UI

**Version:** June 2026  
**Status:** Production Ready

---

## 1. Overview

The **NiFi Config Manager UI** is a web-based management interface for Apache NiFi and IDOL deployments. It provides:

- Docker container lifecycle management for NiFi
- GitHub integration for flow version control
- Parameter Context management
- Controller Service configuration
- Real-time monitoring dashboard
- IDOL deployment configuration wizard

---

## 2. Prerequisites

### Required Software

| Component              | Minimum Version     | Purpose                              |
|------------------------|---------------------|--------------------------------------|
| Docker                 | 24.0+               | Container runtime                    |
| Docker Compose         | v2.20+              | Multi-container orchestration        |
| Python                 | 3.10+               | Backend runtime (if running locally) |
| Git                    | Any                 | (Optional) For development           |
| 8GB RAM / 4 CPU cores  | Recommended         | For comfortable operation            |

### Required Ports

| Port   | Service                    | Purpose                     |
|--------|---------------------------|-----------------------------|
| 5000   | Config Manager UI         | Main web interface          |
| 8443   | NiFi (default)            | NiFi web UI & API           |
| 20000  | License Server            | IDOL licensing              |

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Host Machine                         │
│  ┌──────────────────────┐      ┌────────────────────────┐  │
│  │   deploy script      │─────▶│  Docker Compose        │  │
│  └──────────────────────┘      └───────────┬────────────┘  │
│                                            │                 │
│  ┌─────────────────────────────────────────▼────────────┐  │
│  │              idol-demo-network (Docker Bridge)       │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐ │  │
│  │  │ nifi-manager │  │     NiFi     │  │ IDOL Stack  │ │  │
│  │  │  (Flask UI)  │  │  (Container) │  │ (Optional)  │ │  │
│  │  └──────┬───────┘  └──────┬───────┘  └─────────────┘ │  │
│  │         │                 │                           │  │
│  │         └─────────────────┘                           │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

**Key Components:**

- **nifi-manager** — Flask backend + frontend UI (port 5000)
- **NiFi** — Apache NiFi instance managed via Docker
- **Monitoring APIs** — Real-time system & container metrics

---

## 4. Installation

### Option A: Using the Deploy Script (Recommended)

```bash
# 1. Extract the package
tar -xzf ui-config-complete-fixed-with-all-fixes.tar.gz
cd ui-config-complete-fixed

# 2. Make deploy script executable
chmod +x deploy-setup-manager-ui.sh

# 3. First-time deployment (builds image)
./deploy-setup-manager-ui.sh --build

# 4. Subsequent deployments (faster)
./deploy-setup-manager-ui.sh --deploy
```

### Option B: Manual Docker Compose

```bash
cd backend
docker compose -f ui-docker-compose.yml up -d --build
```

---

## 5. Configuration

### Environment Variables

Create a `.env` file in the project root (optional but recommended):

```env
# NiFi
NIFI_API_URL=https://localhost:8443/nifi-api
NIFI_PORT=8443
NIFI_CONTAINER_NAME=nifi

# Paths
IDOL_BASE_PATH=/opt/idol-deployment
IDOL_NIFI_FLOWS_DIR=/persistent-data/nifi-flows

# GitHub (optional)
GITHUB_OWNER=your-org
GITHUB_REPO_NAME=nifi-flows
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
GITHUB_BRANCH=main
```

### Persistent Data

The following folders should exist on the host:

```bash
mkdir -p persistent-data/nifi-flows
mkdir -p shared-folder
```

---

## 6. Startup & Access

After successful deployment:

```bash
# Check status
./deploy-setup-manager-ui.sh --status

# View logs
./deploy-setup-manager-ui.sh --logs
```

**Access the UI:**

- Local: [http://localhost:5000](http://localhost:5000)
- Network: `http://<your-server-ip>:5000`

**Important Pages:**

| Page                    | URL                                      | Purpose                          |
|-------------------------|------------------------------------------|----------------------------------|
| Main Dashboard          | `/`                                      | Overview                         |
| NiFi Configuration      | `/config-nifi`                           | NiFi + GitHub management         |
| IDOL Setup Wizard       | `/config-idol`                           | IDOL deployment configuration    |
| Monitoring Dashboard    | `/config-monitor`                        | Live system & container metrics  |

---

## 7. Validation & Health Checks

### Quick Validation Commands

```bash
# 1. Check if UI is responding
curl -s http://localhost:5000/api/config | head -c 200

# 2. Check Docker container
docker ps | grep nifi-manager

# 3. Test monitoring endpoint
curl -s http://localhost:5000/api/monitor/system
```

### Expected Healthy State

- Container `nifi-manager` is `Up`
- Port 5000 is listening
- `/api/monitor/docker` returns container list
- NiFi can be started from the UI

---

## 8. Troubleshooting

| Problem                              | Likely Cause                        | Solution                                      |
|--------------------------------------|-------------------------------------|-----------------------------------------------|
| `Docker Compose file not found`      | Wrong working directory             | Run from inside `ui-config` folder            |
| `ModuleNotFoundError: flask_cors`    | Missing dependency                  | `pip install flask-cors` or rebuild image     |
| Port 5000 already in use             | Another service using the port      | `./deploy... --clean` or kill the process     |
| NiFi container won't start           | Port conflict or image issue        | Check logs: `docker logs nifi`                |
| Monitoring shows no containers       | Docker socket not mounted           | Ensure Docker socket is mounted in compose    |

**View detailed logs:**

```bash
docker compose -f backend/ui-docker-compose.yml logs -f nifi-manager
```

---

## 9. Maintenance

### Restart Service

```bash
./deploy-setup-manager-ui.sh --deploy
```

### Full Cleanup

```bash
./deploy-setup-manager-ui.sh --clean
```

### Update Application

```bash
# 1. Pull latest code / extract new package
# 2. Rebuild
./deploy-setup-manager-ui.sh --build
```

---

## 10. Upgrade Procedure

1. Backup persistent data:
   ```bash
   tar -czf backup-$(date +%Y%m%d).tar.gz persistent-data/
   ```

2. Stop current deployment:
   ```bash
   ./deploy-setup-manager-ui.sh --clean
   ```

3. Extract new version and redeploy:
   ```bash
   tar -xzf new-version.tar.gz
   cd new-version
   ./deploy-setup-manager-ui.sh --build
   ```

---

## Summary

| Task                    | Command                                      |
|-------------------------|----------------------------------------------|
| First deployment        | `./deploy... --build`                        |
| Normal deploy           | `./deploy... --deploy`                       |
| Check status            | `./deploy... --status`                       |
| View logs               | `./deploy... --logs`                         |
| Full cleanup            | `./deploy... --clean`                        |
| Access UI               | `http://localhost:5000`                      |

---

*Document generated on 2026-06-24*