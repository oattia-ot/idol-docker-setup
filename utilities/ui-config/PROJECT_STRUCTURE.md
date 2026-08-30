# Project Structure Guide — NiFi Config Manager UI

**Version:** June 2026

This document explains the complete folder and file structure, responsibilities of each component, and guidelines for adding new functionality.

---

## 1. High-Level Overview

```
ui-config/
├── backend/                    # Python Flask backend (API + business logic)
├── frontend/                   # Static frontend assets (HTML, CSS, JS)
├── deploy-setup-manager-ui.sh  # Main deployment script
├── config-nifi.md              # NiFi-specific documentation
├── MIGRATION_PLAN.md           # Technical migration roadmap
├── README-FIXES.md             # Summary of recent improvements
├── DEPLOYMENT.md               # ← This deployment guide
└── PROJECT_STRUCTURE.md        # ← This file
```

**Core Philosophy:**
- **Backend** = API + Business Logic (stateless where possible)
- **Frontend** = Presentation Layer (mostly static files served by Flask)
- **Scripts** = One-command deployment and operations

---

## 2. Detailed Folder Structure

### `backend/` — Backend Application

| Path                              | Purpose                                                                 | Responsibility |
|-----------------------------------|--------------------------------------------------------------------------|--------------|
| `app.py`                          | Flask application factory + route registration                           | Entry point, blueprint registration |
| `config.py`                       | `ConfigManager` singleton + logging, cache, rate limiting setup          | Centralized configuration |
| `requirements.txt`                | Python dependencies                                                      | Dependency management |
| `ui-docker-compose.yml`           | Docker Compose definition for the UI container                           | Container orchestration |
| `dockerfile`                      | Dockerfile for building the nifi-manager image                           | Container image definition |
| `utils/path_utils.py`             | Path resolution helpers (IDOL_BASE_PATH, etc.)                           | Reusable utilities |
| `routes/monitor.py`               | Monitoring API blueprint (`/api/monitor/*`)                              | System & Docker metrics |
| `data/`                           | Runtime generated data (logs, temp files)                                | Ephemeral storage |

**Where to add new backend functionality:**

| Type of Feature                    | Recommended Location                              | Example |
|------------------------------------|---------------------------------------------------|--------|
| New API endpoints                  | `backend/routes/<feature>.py`                     | `routes/nifi_flows.py` |
| Business logic / services          | `backend/services/<feature>_service.py`           | `services/github_service.py` |
| Configuration                      | `backend/config.py` (AppConfig dataclass)         | Add new field |
| Reusable utilities                 | `backend/utils/`                                  | `utils/docker_utils.py` |
| Error handling                     | `backend/error_handlers.py`                       | Custom exceptions |

---

### `frontend/` — Frontend Assets

```
frontend/
├── templates/                    # Jinja2 HTML templates (served by Flask)
│   ├── index.html
│   ├── config-nifi.html
│   ├── config-idol.html
│   └── config-monitor.html
│
├── static/
│   ├── css/
│   │   ├── core/                 # Design system (tokens, buttons, modals)
│   │   └── features/             # Feature-specific styles
│   │       ├── monitor/
│   │       └── dashboard/
│   │
│   ├── js/
│   │   ├── core/                 # Shared UI primitives
│   │   │   ├── ui/
│   │   │   │   ├── toast/
│   │   │   │   ├── modal/
│   │   │   │   └── dom-utils.js
│   │   │   └── clipboard.js
│   │   │
│   │   └── features/             # Feature-specific JavaScript
│   │       ├── monitor/
│   │       └── dashboard/
│   │
│   └── config-idol/              # Legacy / feature-specific assets
│       ├── css/
│       └── js/
│           ├── idol-setup-manager.js
│           └── idol-versions.js
│
└── static/favicon.ico
```

**Frontend Organization Rules:**

- `core/` → Shared components used across multiple pages (toast, modal, etc.)
- `features/<feature>/` → All code related to one major feature
- Keep large monolithic JS files (`nifi-config.js`, `idol-setup-manager.js`) as-is until migrated to ES modules

---

### `deploy-setup-manager-ui.sh`

**Purpose:** One-command deployment, lifecycle management, and operations.

**Key Features:**
- Automatic project root detection
- Colored output
- Health checks
- Port conflict resolution
- Docker network management

**When to modify:**
- Add new deployment options (`--backup`, `--restore`, etc.)
- Improve path detection logic
- Add environment variable validation

---

## 3. Dependency Relationships

```
deploy script
     │
     ▼
Docker Compose (ui-docker-compose.yml)
     │
     ▼
Flask App (app.py)
     ├── config.py (ConfigManager)
     ├── routes/*.py (Blueprints)
     │    └── services/*.py (Business Logic)
     └── frontend/templates + static
```

**Rule:** 
- Routes should **not** contain heavy business logic.
- Business logic belongs in `services/`.
- Configuration lives only in `config.py`.

---

## 4. Where to Add New Functionality

### Common Use Cases

| Use Case                              | Location to Add                                                                 | Notes |
|---------------------------------------|----------------------------------------------------------------------------------|-------|
| New monitoring metric                 | `backend/routes/monitor.py` + `frontend/static/js/features/monitor/`            | Add both backend + frontend |
| New NiFi operation (e.g. templates)   | `backend/routes/nifi_*.py` + `backend/services/nifi_*.py`                       | Create new blueprint if complex |
| New configuration field               | `backend/config.py` → `AppConfig` dataclass                                     | Also update `.env` example |
| New UI page                           | `frontend/templates/new-page.html` + route in `app.py`                          | Register blueprint or route |
| Reusable helper function              | `backend/utils/` or `frontend/static/js/core/`                                  | Keep it pure |
| New validation logic                  | `features/idol-setup/validation/` or `features/nifi-config/validation/`         | Pure functions preferred |
| Docker-related operation              | `backend/services/docker_service.py`                                            | Wrap docker SDK calls here |

---

## 5. Naming Conventions

### Backend (Python)

| Type               | Convention                     | Example                          |
|--------------------|--------------------------------|----------------------------------|
| Blueprint file     | `snake_case.py`                | `nifi_parameter_contexts.py`     |
| Service file       | `snake_case_service.py`        | `github_service.py`              |
| Class              | `PascalCase`                   | `ConfigManager`, `NiFiClient`    |
| Function           | `snake_case`                   | `get_registry_clients()`         |
| Constant           | `UPPER_SNAKE_CASE`             | `ALLOWED_COMMANDS`               |

### Frontend (JavaScript)

| Type                  | Convention                     | Example                              |
|-----------------------|--------------------------------|--------------------------------------|
| Feature folder        | `kebab-case` or `snake_case`   | `parameter-contexts/`                |
| Component file        | `kebab-case.js` or `camelCase` | `parameter-context-table.js`         |
| API file              | `feature.api.js`               | `parameter-contexts.api.js`          |
| State file            | `feature.state.js`             | `connection-config.state.js`         |
| Function (exported)   | `camelCase`                    | `showUpdateModal()`                  |

---

## 6. Best Practices & Guidelines

### Backend

1. **Use Blueprints** for grouping related routes.
2. **Keep routes thin** — move logic to `services/`.
3. **Use `ConfigManager`** for all configuration.
4. **Never hardcode paths** — use `path_utils.py` or `ConfigManager`.
5. **Add logging** using the configured logger from `config.py`.

### Frontend

1. **Prefer composition** over large monolithic files.
2. **Extract shared UI** into `core/ui/`.
3. **Keep API calls** in `*.api.js` files.
4. **Use `showToast()`** and `openModal()` from core instead of custom implementations.

### Deployment Script

- Always use absolute paths.
- Provide clear colored feedback.
- Support `--help` with good documentation.
- Make cleanup safe (`--clean` should be idempotent).

---

## 7. Migration Notes (From MIGRATION_PLAN.md)

Large files that still need modularization:

- `backend/app.py` (→ should become thin factory)
- `frontend/static/config-nifi/js/nifi-config.js`
- `frontend/static/config-idol/js/idol-setup-manager.js`

Follow the plan in `MIGRATION_PLAN.md` when refactoring these files.

---

## Summary

| Goal                              | How This Structure Helps                              |
|-----------------------------------|-------------------------------------------------------|
| Easy onboarding                   | Clear folder responsibilities + this document         |
| Safe feature addition             | Well-defined locations for new code                   |
| Maintainability                   | Separation of concerns (routes vs services)           |
| Consistency                       | Naming conventions + best practices                   |
| Scalability                       | Blueprint + service pattern scales well               |

---

*This document should be updated whenever major structural changes are made to the project.*

**Last updated:** 2026-06-24