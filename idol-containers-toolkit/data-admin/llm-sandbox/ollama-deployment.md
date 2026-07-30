# Ollama + Gemma 4 + Open WebUI — Full Deployment Tutorial

> **Stack:** Ollama · Gemma 4 (2B Q4_K_M) · Open WebUI  
> **Platform:** Docker Compose  
> **Time to deploy:** ~10 minutes (+ model download time)

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Project Structure](#2-project-structure)
3. [Configuration Files](#3-configuration-files)
4. [Deploy the Stack](#4-deploy-the-stack)
5. [Download & Register Gemma 4](#5-download--register-gemma-4)
6. [Access the Web UI](#6-access-the-web-ui)
7. [Password Management](#7-password-management)
8. [Useful Commands](#8-useful-commands)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Prerequisites

Make sure the following are installed on your machine:

| Tool | Minimum Version | Check |
|------|----------------|-------|
| Docker | 24+ | `docker --version` |
| Docker Compose | v2+ | `docker compose version` |
| wget or curl | Any | `wget --version` |
| Free disk space | ~3 GB | For model + images |

> **GPU (optional):** If you have an NVIDIA GPU, add the `deploy` section shown in the [GPU note](#gpu-optional) below for faster inference.

---

## 2. Project Structure

Create your working directory:

```bash
mkdir -p ~/ollama-stack/models
cd ~/ollama-stack
```

Your final folder layout will look like this:

```
ollama-stack/
├── docker-compose.yml      ← orchestrates Ollama + Open WebUI
├── Modelfile               ← custom model config (system prompt, params)
├── models/                 ← GGUF model files + Ollama model storage
└── open-webui/             ← Open WebUI persistent data (auto-created)
```

---

## 3. Configuration Files

### 3.1 `docker-compose.yml`

Create `docker-compose.yml` in your project root:

```yaml
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    ports:
      - "11434:11434"
    volumes:
      - ./models:/root/.ollama   # persists all models
      - .:/app                   # mounts project folder as /app
    restart: unless-stopped

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    ports:
      - "8080:8080"
    volumes:
      - ./open-webui:/app/backend/data
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
    depends_on:
      - ollama
    restart: unless-stopped
```

#### GPU (Optional)

If you have an NVIDIA GPU, add this block inside the `ollama` service:

```yaml
  ollama:
    ...
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
```

---

### 3.2 `Modelfile`

Create `Modelfile` in your project root:

```dockerfile
FROM /app/models/gemma-4-E2B-it-Q4_K_M.gguf

PARAMETER temperature 0.2
PARAMETER top_p 0.9
PARAMETER num_ctx 4096

SYSTEM """
You are an enterprise-grade assistant specialized in document analysis.
"""
```

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `temperature` | 0.2 | Low = more focused, deterministic responses |
| `top_p` | 0.9 | Nucleus sampling — controls diversity |
| `num_ctx` | 4096 | Context window size in tokens |

---

## 4. Deploy the Stack

### 4.1 Start all containers

```bash
docker compose up -d
```

### 4.2 Verify containers are running

```bash
docker compose ps
```

Expected output:

```
NAME           IMAGE                                  STATUS
ollama         ollama/ollama:latest                   Up
open-webui     ghcr.io/open-webui/open-webui:main    Up
```

### 4.3 Watch startup logs (optional)

```bash
docker compose logs -f
```

Press `Ctrl+C` to stop following logs.

---

## 5. Download & Register Gemma 4

You have two options. **Option B is recommended** if you want to use your custom `Modelfile` (system prompt + parameters).

---

### Option A — Pull directly via Ollama (simple)

```bash
docker exec -it ollama ollama pull \
  hf.co/lmstudio-community/gemma-4-E2B-it-GGUF:gemma-4-E2B-it-Q4_K_M.gguf
```

This downloads and registers the model with default settings.

---

### Option B — Download GGUF + build custom model (recommended)

**Step 1:** Download the GGUF file into `./models`

```bash
wget -P ./models \
  "https://huggingface.co/lmstudio-community/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf"
```

> The file is ~1.5 GB. Download time depends on your connection.

**Step 2:** Build the custom model using your `Modelfile`

```bash
docker exec -it ollama ollama create gemma4-enterprise -f /app/Modelfile
```

**Step 3:** Confirm the model is registered

```bash
docker exec -it ollama ollama list
```

Expected output:

```
NAME                    ID            SIZE    MODIFIED
gemma4-enterprise       abc123def456  1.5 GB  Just now
```

---

## 6. Access the Web UI

Open your browser and go to:

```
http://localhost:8080
```

### First-time setup

1. Click **"Get Started"**
2. Create your **admin account** (name, email, password)
3. Log in
4. Click the **model dropdown** at the top and select `gemma4-enterprise`
5. Start chatting!

> **Note:** If you used Option A, the model will appear by its full HuggingFace name in the dropdown.

---

## 7. Password Management

### 7.1 Reset via the UI

Go to `http://localhost:8080` → click **"Forgot password"** on the login page.

---

### 7.2 Reset via SQLite (manual)

Use this method if you've lost access completely.

```bash
# Step 1: Enter the open-webui container
docker exec -it open-webui bash

# Step 2: Install sqlite3 (if not present)
apt-get install -y sqlite3

# Step 3: Generate a bcrypt hash for your new password
python3 -c "import bcrypt; print(bcrypt.hashpw(b'YourNewPassword', bcrypt.gensalt()).decode())"
# Copy the hash output (starts with $2b$...)

# Step 4: Open the database and update the password
sqlite3 /app/backend/data/webui.db

-- Inside SQLite shell:
SELECT id, email FROM user;  -- find your user
UPDATE user SET password = '$2b$12$PASTE_YOUR_HASH_HERE' WHERE email = 'your@email.com';
SELECT email, password FROM user WHERE email = 'your@email.com';  -- confirm
.quit
```

```bash
# Step 5: Restart the container to apply changes
docker compose restart open-webui
```

---

### 7.3 Full reset (wipe everything)

> ⚠️ This deletes all users, chats, and settings.

```bash
docker compose down
rm -rf ./open-webui
docker compose up -d
```

---

## 8. Useful Commands

### Container management

```bash
# Start the stack
docker compose up -d

# Stop the stack
docker compose down

# Restart a single service
docker compose restart open-webui
docker compose restart ollama

# View live logs
docker compose logs -f
docker compose logs -f ollama
docker compose logs -f open-webui
```

### Model management

```bash
# List all models
docker exec -it ollama ollama list

# Remove a model
docker exec -it ollama ollama rm gemma4-enterprise

# Run a model directly in the terminal (no UI)
docker exec -it ollama ollama run gemma4-enterprise

# Show model info
docker exec -it ollama ollama show gemma4-enterprise
```

### API usage (without the UI)

You can also call Ollama directly via REST:

```bash
curl http://localhost:11434/api/generate -d '{
  "model": "gemma4-enterprise",
  "prompt": "Summarize the key points of a contract.",
  "stream": false
}'
```

---

## 9. Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `open-webui` can't reach Ollama | Wrong URL | Confirm `OLLAMA_BASE_URL=http://ollama:11434` — use the **container name**, not `localhost` |
| Model not showing in UI | Model not loaded | Run `ollama list` inside container; restart open-webui |
| Port 8080 already in use | Port conflict | Change to `"8081:8080"` in `docker-compose.yml` |
| `wget` download stalls | Network issue | Retry or use `curl -L -o ./models/gemma-4-E2B-it-Q4_K_M.gguf <url>` |
| Container exits immediately | Config error | Check logs: `docker compose logs ollama` |
| `Modelfile` path not found | Wrong volume mount | Ensure `. :/app` is in the ollama volumes and Modelfile is in the root |
| Slow inference | No GPU | Add GPU deploy block (see Section 3.1) or use a smaller model |

---

## Summary

```
1. mkdir ~/ollama-stack && cd ~/ollama-stack
2. Create docker-compose.yml and Modelfile
3. docker compose up -d
4. wget the GGUF into ./models/
5. docker exec -it ollama ollama create gemma4-enterprise -f /app/Modelfile
6. Open http://localhost:8080
```

You now have a fully local, private AI assistant powered by Gemma 4 with a custom system prompt, accessible through a clean web UI — no cloud, no API keys.
