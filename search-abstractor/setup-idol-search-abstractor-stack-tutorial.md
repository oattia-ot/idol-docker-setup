# 🚀 IDOL Search Abstractor Stack — Complete Setup Tutorial
> A real-world, battle-tested step-by-step guide for deploying the `search-abstractor-stack` Helm chart on Kubernetes (Minikube).  
> Every fix, error, and lesson learned from an actual deployment is documented here.  
> Picks up exactly where the `idol-licenseserver` deployment left off — your License Server bridge **must** already be running before you start.

---

## 📖 What Is This Chart?

The `search-abstractor-stack` is an **umbrella (stack) Helm chart** from [`opentext-idol/search-abstractor`](https://github.com/opentext-idol/search-abstractor). It deploys a complete **Retrieval-Augmented Generation (RAG)** pipeline on Kubernetes using OpenText IDOL components.

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           Kubernetes Cluster                             │
│                                                                          │
│  ┌─────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐     │
│  │  nifi   │  │ content  │  │ answer   │  │   qms    │  │community │     │
│  │(ingest/ │  │ (index)  │  │ server   │  │          │  │          │     │
│  │ query)  │  │          │  │  (RAG)   │  │          │  │          │     │
│  └────┬────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘     │
│       │            │             │             │             │           │
│  ┌────▼────┐  ┌────▼─────┐  ┌───▼──────┐  ┌───▼──────┐  ┌───▼──────┐     │
│  │  saapi  │  │   ogs    │  │   view   │  │   auth   │  │  session │     │
│  │  (API)  │  │          │  │          │  │  (OTDS)  │  │   api    │     │
│  └─────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────┘     │
│                                                                          │
│              Service: idol-licenseserver (already deployed)              │
└──────────────────────────────────────────────────────────────────────────┘
                                    │ forwards to
                         ┌──────────▼──────────┐
                         │  External VM/Host   │
                         │  IDOL LicenseServer │
                         └─────────────────────┘
```

The stack deploys these sub-charts together (all enabled by default unless noted):

| Key in `values.yaml` | Component | Role |
|----------------------|-----------|------|
| `content` | `idol-content` | IDOL Content engine — the search index |
| `distributedidol` | DAH + DIH + Content | Distributed index — **disabled by default** |
| `answerserver` | Answer Server | RAG answer engine |
| `qms` | QMS | Query Manipulation Server |
| `ogs` | OmniGroupServer | Group/security sync |
| `community` | Community | User authentication |
| `nifi` | NiFi | Document ingestion AND query pipeline (both flows) |
| `view` | View | Document viewing service |
| `auth` | OTDS | OpenText Directory Services (auth provider) |
| `otdsdb` | PostgreSQL | Backing database for OTDS |
| `saapiPostgresql` | PostgreSQL | Backing database for session API |
| `sessionapi` | Session API | Manages user sessions |
| `saapi` | Search Abstractor API | Main RAG API service |
| `vllmdeployment` | vLLM | LLM inference server — **disabled by default** |
| `llavadeployment` | LLaVA | Multimodal LLM — **disabled by default** |

---

## ✅ Prerequisites

| Requirement | Notes |
|-------------|-------|
| `idol-licenseserver` already deployed | Hard dependency — see the License Server tutorial |
| `kubectl` v1.24+ | Interact with your cluster |
| `helm` v3.8+ | Install and manage charts |
| Minikube (or any K8s cluster) | `idol` namespace already created |
| Docker Hub credentials | IDOL images pulled from `microfocusidolreadonly` |
| OpenText **registry token** | For `registry.opentext.com` — **not** your SSO password (see Step 4) |
| An LLM endpoint | Either a running **vLLM** server, or **Google Vertex AI** credentials |
| HuggingFace token (if using vLLM) | Required to pull model weights |

---

## 📁 Step 1 — Clone the Repository

```bash
git clone https://github.com/opentext-idol/search-abstractor.git
cd search-abstractor/helm/search-abstractor-stack
```

You will see this structure:

```
search-abstractor-stack/
├── Chart.yaml          ← chart metadata and sub-chart dependency list
├── values.yaml         ← ✅ THE FILE YOU EDIT
├── charts/             ← sub-chart tarballs (empty on fresh clone — populated in Step 4)
└── templates/          ← Kubernetes resource templates (do not edit)
```

---

## 🏷️ Step 2 — Confirm the Namespace Exists

```bash
kubectl get namespace idol
```

Expected:
```
NAME   STATUS   AGE
idol   Active   Xd
```

If missing:
```bash
kubectl create namespace idol
```

---

## 🔐 Step 3 — Create the Pull Secrets

This stack requires **two separate pull secrets** — one for Docker Hub (all IDOL components) and one for the OpenText container registry (OTDS only).

### 3a — Docker Hub Secret

The name **must be** `dockerhub-secret` — it is hardcoded in `values.yaml` under `global.imagePullSecrets` and propagates automatically to every sub-chart.

```bash
kubectl create secret docker-registry dockerhub-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=<YOUR_DOCKERHUB_USERNAME> \
  --docker-password=<YOUR_DOCKERHUB_TOKEN> \
  --docker-email=<YOUR_EMAIL> \
  -n idol
```

### 3b — OpenText Registry Secret

The OTDS image is pulled from `registry.opentext.com`. Its pull secret must be named **`opentext`** (set via `auth.otdsws.image.pullSecret` in `values.yaml`).

> ⚠️ **Your OpenText SSO password will not work here.** You need a dedicated registry token — see Step 4a for how to get it.

```bash
kubectl create secret docker-registry opentext \
  --docker-server=registry.opentext.com \
  --docker-username=<YOUR_OPENTEXT_EMAIL> \
  --docker-password=<YOUR_REGISTRY_TOKEN> \
  -n idol
```

Verify both secrets exist:

```bash
kubectl get secrets -n idol | grep -E "dockerhub-secret|opentext"
```

Expected:
```
dockerhub-secret   kubernetes.io/dockerconfigjson   1   10s
opentext           kubernetes.io/dockerconfigjson   1   5s
```

---

## 📦 Step 4 — Fetch Sub-chart Dependencies

The `charts/` directory is empty on a fresh clone. This step downloads all sub-chart `.tgz` files.

> ⚠️ **Read this entire step before running any commands.** The `otds` dependency pulls from `registry.opentext.com`, which is an OCI registry — it requires special handling that differs from the other dependencies.

### Understanding the Dependency Sources

Inspect `Chart.yaml` to see where each sub-chart comes from:

```bash
cat Chart.yaml | grep -E "name:|repository:" | paste - -
```

You will see:

| Dependency | Source |
|------------|--------|
| `single-content`, `distributed-idol`, `idol-library`, `idol-qms`, `idol-answerserver`, `idol-view`, `idol-omnigroupserver`, `idol-community`, `idol-nifi` | `raw.githubusercontent.com/opentext-idol/idol-containers-toolkit` — standard HTTP |
| `postgresql` (×2) | `bitnami` — standard HTTP |
| `vllm` (×2) | `substratusai` — standard HTTP |
| **`otds`** | **`registry.opentext.com/helm` — OCI registry ← this one is different** |

All dependencies except `otds` can be fetched with a standard `helm dependency update`. The `otds` chart must be pulled manually using OCI commands first.

---

### 4a — Obtain Your OpenText Registry Token

`registry.opentext.com` is an **OCI registry**, not a traditional Helm HTTP repository. It rejects SSO passwords. You need a dedicated token.

**Step 1 — Log in to the OpenText portal:**

Go to `https://portal.microfocus.com` or `https://myaccount.opentext.com`

**Step 2 — Navigate to your entitlements:**

Look for **Downloads → Container Images** or **My Entitlements → Container Registry**.

Find the section for `registry.opentext.com`. The token will be labelled something like "Container Registry Access Token", "Entitlement Token", or "Registry Credentials". It is a long alphanumeric string — not your SSO password.

> 💡 If you cannot find it, contact whoever manages your company's OpenText license. The token is tied to the company entitlement, not your personal account.

---

### 4b — Log In to the OCI Registry

```bash
helm registry login registry.opentext.com \
  --username your.email@company.com \
  --password <REGISTRY-TOKEN-FROM-PORTAL>
```

Expected output:
```
Login Succeeded
```

> ❌ If you see `401 Unauthorized` here, your token is wrong or has expired. Go back to the portal and regenerate it. Your SSO password will not work.

---

### 4c — Pull the OTDS Chart Manually

Pull the `otds` chart directly into the `charts/` directory:

```bash
helm pull oci://registry.opentext.com/helm/otds \
  --version 24.4.0 \
  --destination ./charts/
```

If that returns a "not found" error, try the root path:

```bash
helm pull oci://registry.opentext.com/otds \
  --version 24.4.0 \
  --destination ./charts/
```

Confirm the file is there:

```bash
ls charts/ | grep otds
```

Expected: `otds-24.4.0.tgz`

---

### 4d — Fetch All Other Sub-chart Dependencies

Now fetch the remaining sub-charts from GitHub, Bitnami, and substratusai. The `--skip-refresh` flag prevents Helm from re-attempting the OCI registry and triggering another 401:

```bash
helm dependency update . --skip-refresh
```

Expected output:
```
Saving X charts
Downloading single-content from repo ...
Downloading idol-nifi from repo ...
...
Deleting outdated charts
```

Confirm `charts/` is fully populated:

```bash
ls charts/
```

You should see `.tgz` files for all dependencies including `otds-24.4.0.tgz`.

---

## ✏️ Step 5 — Edit `values.yaml`

```bash
nano values.yaml
```

### ⚠️ Golden Rule — No Top-Level `licenseServerHostname`

Unlike the `idol-licenseserver` chart, this stack has **no top-level `licenseServerHostname` key**. The License Server hostname must be added **under each IDOL sub-chart section individually**. Do not put it at the root of `values.yaml`.

---

### 5a — License Server (add to each IDOL sub-chart)

Add `licenseServerHostname` and `licenseServerPort` under each of the seven IDOL component keys:

```yaml
content:
  enabled: true
  licenseServerHostname: "idol-licenseserver.idol.svc.cluster.local"
  licenseServerPort: "20000"
  name: idol-content
  # ... rest of existing content config unchanged ...

answerserver:
  enabled: true
  licenseServerHostname: "idol-licenseserver.idol.svc.cluster.local"
  licenseServerPort: "20000"
  # ... rest unchanged ...

qms:
  enabled: true
  licenseServerHostname: "idol-licenseserver.idol.svc.cluster.local"
  licenseServerPort: "20000"
  # ... rest unchanged ...

ogs:
  enabled: true
  licenseServerHostname: "idol-licenseserver.idol.svc.cluster.local"
  licenseServerPort: "20000"
  # ... rest unchanged ...

community:
  enabled: true
  licenseServerHostname: "idol-licenseserver.idol.svc.cluster.local"
  licenseServerPort: "20000"
  # ... rest unchanged ...

nifi:
  enabled: true
  licenseServerHostname: "idol-licenseserver.idol.svc.cluster.local"
  licenseServerPort: "20000"
  # ... rest unchanged ...

view:
  enabled: true
  licenseServerHostname: "idol-licenseserver.idol.svc.cluster.local"
  licenseServerPort: "20000"
  # ... rest unchanged ...
```

> 💡 `distributedidol` is disabled by default. If you enable it, add the license server values to `distributedidol.content`, `distributedidol.dah`, and `distributedidol.dih` as well — and set `content.enabled: false` since the two are mutually exclusive.

---

### 5b — LLM Backend (required — pick one)

#### Option A — vLLM (requires a running vLLM server)

```yaml
saapi:
  vllm:
    endpoint: "http://<YOUR-VLLM-HOST>:8000/v1/completions"
    chatEndpoint: "http://<YOUR-VLLM-HOST>:8000/v1/chat/completions"
    model: "mistralai/Mistral-7B-Instruct-v0.2"
    modelRevision: "99259002b41e116d28ccb2d04a9fbe22baed0c7f"
    HFToken: "<YOUR-HUGGINGFACE-TOKEN>"
```

To have Kubernetes deploy vLLM itself (requires NVIDIA GPU on nodes):

```yaml
vllmdeployment:
  enabled: true                            # ← flip from false
  model: "mistralai/Mistral-7B-Instruct-v0.2"
  runtimeClassName: nvidia
  env:
    - name: HF_TOKEN
      value: "<YOUR-HUGGINGFACE-TOKEN>"
```

#### Option B — Google Vertex AI

```yaml
saapi:
  vertexai:
    enabled: true                          # ← flip from false
    project: "<YOUR-GCP-PROJECT-ID>"
    location: "<GCP-REGION>"
    model: "gemini-1.5-flash-001"
    authentication: "credentials"
    credentials:
      type: "service_account"
      project_id: "<YOUR-GCP-PROJECT-ID>"
      private_key_id: "<KEY-ID>"
      private_key: "<PRIVATE-KEY>"
      client_email: "<SERVICE-ACCOUNT-EMAIL>"
      client_id: "<CLIENT-ID>"
      # ... remaining fields from your service account JSON ...
```

---

### 5c — OTDS Authentication

Defaults are fine for local testing. **Change for any non-local deployment:**

```yaml
auth:
  otdsws:
    adminEmail: discover.admin             # ← change for production
    adminPassword: discover.admin.123!    # ← change for production
  createAdminUsername: admin.user
  createAdminPassword: admin.user.123!    # ← change for production
  uiUrls: "http://localhost:4200/.*"       # ← update to your actual UI URL
  external:
    host: ""                               # ← set if OTDS must be externally reachable
    port: ""
    protocol: http
```

---

### 5d — AES Security Key (optional)

```yaml
aes:
  key: "your-custom-secret-key-here"      # default: "search-abstractor"
```

---

### 5e — IDOL Versions (informational — no changes needed)

Pre-set via YAML anchors in `values.yaml`:

```
content, nifi, community, ogs, view  →  25.2.0
answerserver, qms, saapi, sessionapi →  25.2.4
```

---

## 🔍 Step 6 — Validate the Chart

```bash
helm lint .
```

Expected:
```
1 chart(s) linted, 0 chart(s) failed
```

---

## 👁️ Step 7 — Dry Run Preview

```bash
helm template search-abstractor-stack . -n idol -f values.yaml
```

Scan the output and confirm your License Server hostname appears in rendered ConfigMaps and environment variables:

```yaml
LICENSESERVERHOSTNAME: idol-licenseserver.idol.svc.cluster.local
LICENSESERVERPORT: "20000"
```

And your LLM endpoint appears in the `saapi` deployment. Fix `values.yaml` if anything looks wrong before continuing.

---

## 🚀 Step 8 — Deploy the Chart

> ✅ **Always use `helm upgrade --install`** — idempotent, works whether the release exists or not.

```bash
helm upgrade --install search-abstractor-stack . -n idol -f values.yaml
```

Expected output:
```
NAME: search-abstractor-stack
NAMESPACE: idol
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
```

---

## ✔️ Step 9 — Verify the Deployment

```bash
# Watch all pods come up
kubectl get pods -n idol -w

# Check all Services
kubectl get svc -n idol
```

A healthy full stack looks like this:

```
NAME                                              READY   STATUS    AGE
search-abstractor-stack-idol-content-0            1/1     Running   3m
search-abstractor-stack-answerserver-0            1/1     Running   3m
search-abstractor-stack-qms-0                     1/1     Running   3m
search-abstractor-stack-community-0               1/1     Running   3m
search-abstractor-stack-ogs-0                     1/1     Running   3m
search-abstractor-stack-view-0                    1/1     Running   3m
search-abstractor-stack-idol-nifi-0               1/1     Running   3m
saapi-api-service-xxx                             1/1     Running   2m
saapi-session-api-service-xxx                     1/1     Running   2m
otdsws-xxx                                        1/1     Running   4m
otds-psqldb-0                                     1/1     Running   4m
saapi-postgresql-0                                1/1     Running   4m
```

> ⚠️ IDOL components take **3–8 minutes** to fully initialize. NiFi takes the longest. A pod showing `Running` does not mean its internal service is ready — wait for all pods to stabilize before testing.

---

## 🌐 Step 10 — Test Connectivity

### 10a — Confirm License Server Bridge Is Reachable

```bash
kubectl exec -it search-abstractor-stack-idol-content-0 -n idol -- \
  curl "http://idol-licenseserver.idol.svc.cluster.local:20000/a=GetVersion"
```

✅ Any `<autnresponse>` XML confirms the license bridge is working from inside the new pods.

---

### 10b — Test the Search Abstractor API Health

The `saapi` service runs on port **8080** with the management endpoint at `/actuator/`:

```bash
kubectl run curl-test \
  --image=curlimages/curl \
  --restart=Never \
  -it --rm \
  -n idol \
  -- curl "http://saapi-api-service.idol.svc.cluster.local:8080/actuator/health"
```

✅ `{"status":"UP"}` means the API is running.

If the pod exits before you see output:
```bash
kubectl logs curl-test -n idol
kubectl delete pod curl-test -n idol
```

---

### 10c — Test the NiFi SA API Listener Port

NiFi exposes port **8085** as the Search Abstractor API listener:

```bash
kubectl run curl-test \
  --image=curlimages/curl \
  --restart=Never \
  -it --rm \
  -n idol \
  -- curl "http://idol-nifi.idol.svc.cluster.local:8085/"
```

---

### 10d — Access the NiFi UI

```bash
kubectl get svc -n idol | grep nifi
kubectl port-forward svc/idol-nifi 8443:8443 -n idol
```

Open `https://localhost:8443/nifi` in your browser.

---

## 📑 Step 11 — Check Logs

```bash
kubectl logs <pod-name> -n idol -f           # follow live
kubectl logs <pod-name> -n idol --previous   # after a crash
kubectl describe pod <pod-name> -n idol      # for Pending / scheduling issues
```

---

## 🚨 Troubleshooting

---

### ❌ `helm dependency update` fails: 401 + hash-named cache error

**Symptom:**
```
Unable to get an update from "https://registry.opentext.com/helm": 401 Unauthorized
Error: no cached repository for helm-manager-c7444357... found.
```

**Cause:** The `otds` dependency in `Chart.yaml` points to `registry.opentext.com/helm`, which was never added to your repo list. Helm tried to fetch it as an unmanaged repo, got a 401, and left a broken hash-named cache entry.

**Fix:** Follow Steps 4a–4d above — log in via `helm registry login`, pull `otds` manually, then run `helm dependency update . --skip-refresh`.

---

### ❌ `helm repo add` fails: not a valid chart repository

**Symptom:**
```
Error: looks like "https://registry.opentext.com/helm" is not a valid chart repository
```

**Cause:** `registry.opentext.com` is an **OCI registry**, not a traditional HTTP Helm repo. `helm repo add` only works with HTTP repos that serve an `index.yaml`.

**Fix:** Use OCI commands instead — `helm registry login` then `helm pull oci://...` as shown in Steps 4b–4c.

---

### ❌ `helm registry login` fails: 401 Unauthorized

**Symptom:**
```
Error: login attempt to https://registry.opentext.com/v2/ failed with status: 401 Unauthorized
```

**Cause:** You are using your OpenText SSO password. This does not work with the container/Helm registry.

**Fix:** Get a dedicated registry token from the OpenText portal (Steps 4a), then retry `helm registry login` with that token.

---

### ❌ IDOL pods: cannot connect to license server

**Cause:** `licenseServerHostname` was not added to one or more sub-chart sections.

**Fix:** Add it under each IDOL component key (Step 5a), then redeploy:
```bash
helm upgrade --install search-abstractor-stack . -n idol -f values.yaml
```

Also verify the bridge is still healthy:
```bash
kubectl get svc idol-licenseserver -n idol
kubectl get endpointslices -n idol
```

---

### ❌ ImagePullBackOff — Docker Hub (IDOL pods)

```bash
kubectl describe pod <pod-name> -n idol | grep -A5 "Events"
# Look for: unauthorized
```

**Fix:**
```bash
kubectl delete secret dockerhub-secret -n idol
kubectl create secret docker-registry dockerhub-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=<USER> --docker-password=<TOKEN> --docker-email=<EMAIL> \
  -n idol
kubectl delete pod <pod-name> -n idol
```

---

### ❌ ImagePullBackOff — OpenText Registry (OTDS pod)

**Cause:** The `opentext` Kubernetes secret is missing or uses SSO credentials instead of a registry token.

**Fix:**
```bash
kubectl create secret docker-registry opentext \
  --docker-server=registry.opentext.com \
  --docker-username=<EMAIL> \
  --docker-password=<REGISTRY-TOKEN> \
  -n idol
```

---

### ❌ Pods stuck in Pending

**Diagnose:**
```bash
kubectl describe pod <pod-name> -n idol | grep -A10 "Events"
# Look for: Insufficient memory / Insufficient cpu
```

**Fix:**
```bash
minikube stop -p <profile>
minikube start -p <profile> --memory=12288 --cpus=6
```

> The full stack needs at least **10–12 GB RAM** on the Minikube node.

---

### ❌ cannot reuse a name that is still in use

**Fix:** Always use `upgrade --install`:
```bash
helm upgrade --install search-abstractor-stack . -n idol -f values.yaml
```

Or start completely fresh:
```bash
helm uninstall search-abstractor-stack -n idol
helm upgrade --install search-abstractor-stack . -n idol -f values.yaml
```

---

### ❌ curl-test pod — timed out / already exists

```bash
# Already exists
kubectl delete pod curl-test -n idol

# Timed out — always use --restart=Never
kubectl run curl-test \
  --image=curlimages/curl \
  --restart=Never \
  -it --rm \
  -n idol \
  -- curl "http://<service>.idol.svc.cluster.local:<port>/"
```

---

## 📋 Quick Reference

### Commands Cheat Sheet

```bash
# Clone
git clone https://github.com/opentext-idol/search-abstractor.git
cd search-abstractor/helm/search-abstractor-stack

# Confirm namespace
kubectl get namespace idol

# Create Docker Hub pull secret
kubectl create secret docker-registry dockerhub-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=<USER> --docker-password=<PASS> --docker-email=<EMAIL> \
  -n idol

# Create OpenText registry secret
kubectl create secret docker-registry opentext \
  --docker-server=registry.opentext.com \
  --docker-username=<EMAIL> --docker-password=<REGISTRY-TOKEN> \
  -n idol

# Log in to OpenText OCI registry
helm registry login registry.opentext.com \
  --username <EMAIL> --password <REGISTRY-TOKEN>

# Pull OTDS chart manually (OCI — must be done before dependency update)
helm pull oci://registry.opentext.com/helm/otds \
  --version 24.4.0 \
  --destination ./charts/

# Fetch remaining sub-chart dependencies
helm dependency update . --skip-refresh

# Validate
helm lint .

# Dry-run preview
helm template search-abstractor-stack . -n idol -f values.yaml

# Deploy or update (always use this)
helm upgrade --install search-abstractor-stack . -n idol -f values.yaml

# Watch pods come up
kubectl get pods -n idol -w

# Follow logs
kubectl logs <pod-name> -n idol -f

# Port-forward NiFi UI
kubectl port-forward svc/idol-nifi 8443:8443 -n idol

# Test SA API health
kubectl run curl-test --image=curlimages/curl --restart=Never -it --rm -n idol \
  -- curl "http://saapi-api-service.idol.svc.cluster.local:8080/actuator/health"

# Uninstall
helm uninstall search-abstractor-stack -n idol

# All Helm releases
helm list -A
```

### Credential Reference

| Credential | Used For | Where to Get It |
|------------|----------|-----------------|
| OpenText SSO | `portal.microfocus.com` website login only | Your normal login |
| OpenText **registry token** | `helm registry login` + `opentext` K8s secret | Portal → Downloads → Container Images |
| Docker Hub credentials | `dockerhub-secret` K8s secret | Docker Hub `microfocusidolreadonly` account |
| HuggingFace token | `saapi.vllm.HFToken` in `values.yaml` | `huggingface.co` account settings |

### Key Facts

```
Repository:             github.com/opentext-idol/search-abstractor
Chart path:             helm/search-abstractor-stack
Namespace:              idol
IDOL version:           25.2.0 (content, nifi, community, ogs, view)
SA version:             25.2.4 (answerserver, qms, saapi, sessionapi)
License server:         set per-sub-chart — NO top-level key
Docker Hub secret:      dockerhub-secret  (global.imagePullSecrets — auto-propagated)
OpenText secret:        opentext  (registry.opentext.com — OTDS image only)
OTDS chart source:      OCI — must use helm registry login + helm pull oci://
NiFi SA API port:       8085
saapi port:             8080  (/actuator/health for healthcheck)
Deploy command:         helm upgrade --install
Dep update command:     helm dependency update . --skip-refresh
Minimum Minikube RAM:   10–12 GB
```

---

## ✅ Deployment Checklist

- [ ] `idol-licenseserver` deployed and verified
- [ ] Repository cloned, inside `helm/search-abstractor-stack`
- [ ] `idol` namespace exists
- [ ] `dockerhub-secret` created in `idol` namespace
- [ ] OpenText **registry token** obtained from portal (not SSO password)
- [ ] `opentext` secret created in `idol` namespace with registry token
- [ ] `helm registry login registry.opentext.com` returns `Login Succeeded`
- [ ] `helm pull oci://registry.opentext.com/helm/otds --version 24.4.0 --destination ./charts/` succeeds
- [ ] `otds-24.4.0.tgz` present in `charts/`
- [ ] `helm dependency update . --skip-refresh` completes with no errors
- [ ] `charts/` directory fully populated
- [ ] `values.yaml`: `licenseServerHostname` + `licenseServerPort` added under **each** of: `content`, `answerserver`, `qms`, `ogs`, `community`, `nifi`, `view`
- [ ] `values.yaml`: LLM backend configured (`saapi.vllm.*` or `saapi.vertexai.*`)
- [ ] `values.yaml`: OTDS credentials changed from defaults (non-local deployments)
- [ ] `values.yaml`: `auth.uiUrls` updated to actual UI URL
- [ ] `helm lint .` passes with 0 failures
- [ ] `helm template` output shows correct License Server hostname and LLM endpoint
- [ ] `helm upgrade --install` returns `STATUS: deployed`
- [ ] All pods reach `Running`
- [ ] License Server reachable from inside a stack pod
- [ ] `saapi-api-service` returns `{"status":"UP"}` on port 8080
- [ ] NiFi UI accessible via port-forward on 8443
