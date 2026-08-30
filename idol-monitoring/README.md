# IDOL Monitoring Stack

Complete, production-ready monitoring solution for IDOL / OpenText environments.

## What's Included

- **Full Docker Compose stack** (11 services):
  - Container management: Yacht, Dockge
  - Logging: Dozzle, Loki + Promtail
  - Metrics: Prometheus, cAdvisor, Node Exporter, Grafana, Dokemon
  - **NEW: Config Monitor UI** (Flask + modern reactive dashboard) on port 5011

- **monitor.sh** — one-command management script (start/stop/status/logs/urls for any service or all)
- **Config Monitor UI** — beautiful real-time service health dashboard with:
  - Live polling every 8 seconds
  - Filter by healthy/degraded
  - Clickable service cards + detail panel
  - Demo restart/logs actions
  - Toast notifications + modals
- All configs are self-contained (no external files needed)

## Quick Start (Recommended)

```bash
# 1. Extract
tar -xzf idol-monitoring-v2906-fixed-deployable.tar.gz
cd idol-monitoring

# 2. Deploy everything (builds the UI + starts the full stack)
docker compose -f docker-compose.monitoring.yml up -d --build

# 3. Check status
./monitor.sh status all

# 4. Open the beautiful Config Monitor UI
open http://localhost:5011
```

## Access Everything

| Port  | Service              | URL                          | Default Login          |
|-------|----------------------|------------------------------|------------------------|
| 5011  | **Config Monitor UI**    | http://localhost:5011       | (no login)            |
| 5001  | Yacht                | http://localhost:5001       | admin@idol.local / opentext1! |
| 5002  | Dockge               | http://localhost:5002       | admin / opentext1!    |
| 5003  | Dozzle (logs)        | http://localhost:5003       | admin / opentext1!    |
| 5004  | cAdvisor             | http://localhost:5004       | —                     |
| 5005  | Prometheus           | http://localhost:5005       | —                     |
| 5006  | Grafana              | http://localhost:5006       | admin / opentext1!    |
| 5007  | Loki                 | http://localhost:5007       | —                     |
| 5008  | Promtail             | http://localhost:5008       | —                     |
| 5009  | Dokemon              | http://localhost:5009       | —                     |
| 5010  | Node Exporter        | http://localhost:5010       | —                     |

## Management Script

```bash
./monitor.sh help                 # full help
./monitor.sh start all            # start everything
./monitor.sh start monitor-ui     # start only the Config Monitor
./monitor.sh logs monitor-ui -f   # follow UI logs
./monitor.sh restart grafana      # restart one service
./monitor.sh urls                 # show all URLs with status
./monitor.sh disable all          # stop + clean volumes
```

## Project Structure

```
idol-monitoring/
├── docker-compose.monitoring.yml   # Main compose (now includes monitor-ui)
├── monitor.sh                      # Management script (updated)
├── create-monitor-ui.sh            # Regenerates the UI if you want to customize
├── README.md                       # This file
├── help/
│   └── help-idol-monitoring.md
├── monitor-ui/                     # Config Monitor UI (Flask)
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── server.py                   # Flask backend + mock /api/status
│   └── static/                     # Modern ES6 frontend (grid, state, modals, toasts)
└── monitoring/                     # Extra config templates (Prometheus, Loki, etc.)
```

## Notes

- All services use the `idol-network` bridge.
- Default password everywhere: `opentext1!`
- The Config Monitor UI currently shows mock service data (easy to replace with real API later).
- Grafana comes with Prometheus + Loki datasources pre-configured in the compose setup jobs.
- No external volumes or config files are required — everything is self-bootstrapping.

## Updating the Config Monitor UI

If you want to customize the frontend:

```bash
cd monitor-ui
./../create-monitor-ui.sh   # (or edit files directly)
docker compose -f ../docker-compose.monitoring.yml up -d --build monitor-ui
```

---

**Ready to deploy.** Just run the Quick Start commands above.

## Recent Improvements (v2906-fixed)

- **Fixed live status display** in Config Monitor UI:
  - Clear "Loading service status..." indicator on first load
  - Better empty-state and filter messages
  - Visible error state with Retry button if backend fetch fails
  - More robust polling and error handling

- **Pre-built image support**:
  ```bash
  docker build -t idol-monitor-ui:latest ./monitor-ui
  ```
  Then edit `docker-compose.monitoring.yml` and replace the `build:` section under `monitor-ui` with `image: idol-monitor-ui:latest`

- **Persistent volume** added for `monitor-ui` (`monitor-ui-data`) — ready for future config, logs, or custom service data.

- Updated management script, documentation, and compose file for the new service on port 5011.

## Monitoring Real IDOL Demo Services

The Config Monitor UI (port 5011) now **automatically discovers and displays all `idol-*` containers** running on the host, including your actual IDOL application services from docker ps.

When running alongside an IDOL demo stack, you will see both:
- The full monitoring infrastructure (Yacht, Grafana, Prometheus, Dozzle, etc.)
- All your **IDOL Demo services** with proper names, ports, live CPU/MEM metrics, status, and clickable URLs:

  - HTTPD Reverse Proxy (:8330)
  - IDOL Find (:8440)
  - IDOL Community (:9030)
  - IDOL View (:9080)
  - IDOL Content (:9100)
  - IDOL NiFi (:8443 / 11000)
  - Agentstore, Categorisation Agentstore, Category, etc.

Everything is real-time from the Docker API — no mocks.

---

Built for IDOL / OpenText environments — June 2026
