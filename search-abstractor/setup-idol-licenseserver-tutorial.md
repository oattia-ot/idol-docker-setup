# 🚀 IDOL License Server — Complete Setup Tutorial
> A real-world, battle-tested step-by-step guide for setting up IDOL License Server on Kubernetes (Minikube) using the OpenText `idol-containers-toolkit` Helm chart.  
> Every fix, error, and lesson learned from an actual deployment is documented here.

---

## 📖 What Is This Chart?

This Helm chart does **NOT** deploy a new License Server container. It creates a Kubernetes **Service + EndpointSlice** that acts as a **bridge** pointing to an already-running IDOL License Server installed on an external VM or bare-metal host outside the cluster.

  ```
┌──────────────────────────────────────────────────────────┐
│                  Kubernetes Cluster                      │
│                                                          │
│  [idol-content pod] ──┐                                  │
│  [idol-find pod]   ───┼──► Service: idol-licenseserver   │
│  [idol-dah pod]    ───┘         port 20000               │
│                                      │                   │
└──────────────────────────────────────┼───────────────────┘
                                       │ forwards to
                              ┌────────▼─────────────┐
                              │  External VM/Host    │
                              │  IDOL LicenseServer  │
                              │  e.g. 172.25.125.123 │
                              │  port: 20000         │
                              └──────────────────────┘
```

---

## ✅ Prerequisites

| Tool | Why You Need It |
|------|-----------------|
| `kubectl` v1.24+ | Interact with your Kubernetes cluster |
| `helm` v3.8+ | Install and manage Helm charts |
| Minikube (or any K8s cluster) | Where IDOL services will run |
| External IDOL License Server | Already running on a VM/host outside the cluster |
| License Server IP or DNS name | To configure the bridge in `values.yaml` |

---

## 📁 Step 1 — Clone the Repository

```bash
git clone https://github.com/opentext-idol/idol-containers-toolkit.git
cd idol-containers-toolkit/helm/idol-licenseserver
```

You will see this structure:

```
idol-licenseserver/
├── Chart.yaml          ← chart metadata (do not edit)
├── values.yaml         ← ✅ THE ONLY FILE YOU NEED TO EDIT
└── templates/          ← Kubernetes resource templates (do not edit)
```

---

## 🏷️ Step 2 — Create the Namespace

```bash
kubectl create namespace idol
```

> 💡 All commands going forward use `-n idol`. If you skip this step, deployments will fail with a namespace not found error.

---

## ✏️ Step 3 — Edit `values.yaml`

This is the **only file** you need to touch. Open it:

```bash
nano values.yaml
```

The full file looks like this — here is what each field means:

```yaml
# PICK ONE — never fill both at the same time
licenseServerExternalName: ""       # DNS hostname of your License Server
licenseServerIp:                    # IPv4 address of your License Server

licenseServerPort: "20000"          # Default ACI port — only change if yours differs
licenseServerService: idol-licenseserver  # K8s Service name — safe to leave as-is
```

### ⚠️ Golden Rule
Use **either** `licenseServerExternalName` **or** `licenseServerIp` — **never both at the same time**. Filling both will cause a hard error during deployment.

---

### Scenario A — Using an IP Address (most common)

```yaml
licenseServerExternalName: ""            # ← clear this to empty string
licenseServerIp: "172.25.125.123"        # ← your real License Server IP
licenseServerPort: "20000"
licenseServerService: idol-licenseserver
```

### Scenario B — Using a DNS Hostname

```yaml
licenseServerExternalName: "ls.mycompany.com"  # ← your hostname
licenseServerIp:                               # ← leave completely blank
licenseServerPort: "20000"
licenseServerService: idol-licenseserver
```

---

## 🔍 Step 4 — Validate the Chart

```bash
helm lint .
```

Expected output:
```
1 chart(s) linted, 0 chart(s) failed
```

---

## 👁️ Step 5 — Dry Run Preview (Before Deploying)

```bash
helm template idol-licenseserver . -n idol -f values.yaml
```

Check the generated output. Your IP or hostname **must appear** in the `EndpointSlice` section:

```yaml
endpoints:
  - addresses:
      - "172.25.125.123"    ← confirm this is correct
ports:
  - name: aci-port
    port: 20000
```

If you see an error here, check the Troubleshooting section before proceeding.

---

## 🚀 Step 6 — Deploy the Chart

> ✅ **Always use `helm upgrade --install`** instead of plain `helm install`. This works whether the chart is already deployed or not, and prevents the "cannot reuse a name" error.

```bash
helm upgrade --install idol-licenseserver . -n idol -f values.yaml
```

Expected output:
```
NAME: idol-licenseserver
NAMESPACE: idol
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
```

---

## ✔️ Step 7 — Verify the Deployment

```bash
# Check the Service was created
kubectl get svc -n idol

# Check the EndpointSlice points to your License Server IP
kubectl get endpointslices -n idol
```

Expected output:
```
NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)     AGE
idol-licenseserver   ClusterIP   None         <none>        20000/TCP   11s

NAME                 ADDRESSTYPE   PORTS   ENDPOINTS        AGE
idol-licenseserver   IPv4          20000   172.25.125.123   21s
```

---

## 🌐 Step 8 — Test Connectivity

### From the Minikube Node (Quickest Check)

```bash
# First — find your Minikube profile name
minikube profile list

# Then SSH using YOUR profile name (it may not be "minikube")
minikube ssh -p <your-profile-name> -- curl "http://172.25.125.123:20000/a=GetVersion"
```

✅ Any XML response means the License Server is alive and reachable.

---

### From Inside the Cluster (Full End-to-End Test)

> ⚠️ Always use `--restart=Never` to prevent the pod from restarting in a loop after it finishes.

```bash
kubectl run curl-test \
  --image=curlimages/curl \
  --restart=Never \
  -it --rm \
  -n idol \
  -- curl "http://idol-licenseserver.idol.svc.cluster.local:20000/a=LicenseInfo"
```

If the pod exits before you see output, grab the logs:

```bash
kubectl logs curl-test -n idol
```

Then clean up:

```bash
kubectl delete pod curl-test -n idol
```

✅ **Success:** Any `<autnresponse>` XML response — even an error message inside XML means the server is alive and the bridge is working.

---

## 🔗 Step 9 — Connect Other IDOL Services

When deploying other IDOL Helm charts, point them to the License Server using the stable in-cluster DNS name:

```
idol-licenseserver.idol.svc.cluster.local:20000
```

Example:

```bash
helm upgrade --install idol-content ./idol-content \
  -n idol \
  --set licenseServerHostname=idol-licenseserver.idol.svc.cluster.local \
  --set licenseServerPort=20000
```

---

## 🚨 Troubleshooting

---

### ❌ Error: Only one of licenseServerExternalName or licenseServerIp should be set

**Cause:** Both fields have values at the same time.

**Fix:** Open `values.yaml` and clear one:

```yaml
licenseServerExternalName: ""          # ← clear to empty string if using IP
licenseServerIp: "172.25.125.123"      # ← keep your IP
```

Then re-run:
```bash
helm template idol-licenseserver . -n idol -f values.yaml
helm upgrade --install idol-licenseserver . -n idol -f values.yaml
```

---

### ❌ Error: cannot reuse a name that is still in use

**Cause:** You ran `helm install` when the chart is already deployed.

**Fix:** Always use `upgrade --install` instead:

```bash
helm upgrade --install idol-licenseserver . -n idol -f values.yaml
```

Or to start completely fresh:
```bash
helm uninstall idol-licenseserver -n idol
helm install idol-licenseserver . -n idol -f values.yaml
```

---

### ❌ Error: services "idol-licenseserver" not found

**Cause:** Chart was never deployed, deployed to the wrong namespace, or you're looking at the wrong Minikube profile.

**Diagnose:**

```bash
# Search all namespaces
kubectl get svc -A | grep licenseserver

# Check all Helm releases
helm list -A

# Check what's in the idol namespace
kubectl get all -n idol
```

**Fix based on result:**

```bash
# Nothing found anywhere — deploy it
kubectl create namespace idol
helm upgrade --install idol-licenseserver . -n idol -f values.yaml

# Found in wrong namespace — move it
helm uninstall idol-licenseserver -n <wrong-namespace>
helm upgrade --install idol-licenseserver . -n idol -f values.yaml
```

---

### ❌ minikube ssh — Profile "minikube" not found

**Cause:** Your Minikube cluster uses a custom profile name, not the default `minikube`.

**Fix:** Check your real profile name first:

```bash
minikube profile list
```

Example output:
```
┌─────────┬────────┬─────────┬──────────────┬─────────┬────────┐
│ PROFILE │ DRIVER │ RUNTIME │      IP      │ VERSION │ STATUS │
├─────────┼────────┼─────────┼──────────────┼─────────┼────────┤
│ test-1  │ docker │ docker  │ 192.168.49.2 │ v1.32.0 │ OK     │
└─────────┴────────┴─────────┴──────────────┴─────────┴────────┘
```

Then use `-p <profile-name>` on all minikube commands:

```bash
minikube ssh -p test-1 -- curl "http://172.25.125.123:20000/a=GetVersion"
```

---

### ❌ curl-test pod — error: timed out waiting for the condition

**Cause:** Missing `--restart=Never` flag — Kubernetes restarts the pod in a loop before you can attach to it.

**Fix:** Always add `--restart=Never`:

```bash
kubectl run curl-test \
  --image=curlimages/curl \
  --restart=Never \
  -it --rm \
  -n idol \
  -- curl "http://idol-licenseserver.idol.svc.cluster.local:20000/a=LicenseInfo"
```

---

### ❌ Error: pods "curl-test" already exists

**Cause:** A previous test pod was not cleaned up.

**Fix:** Delete it first, then re-run:

```bash
kubectl delete pod curl-test -n idol

kubectl run curl-test \
  --image=curlimages/curl \
  --restart=Never \
  -it --rm \
  -n idol \
  -- curl "http://idol-licenseserver.idol.svc.cluster.local:20000/a=LicenseInfo"
```

---

### ❌ curl-test pod — BackOff restarting (Warning)

**Cause:** Pod was created without `--restart=Never` so Kubernetes keeps restarting it after completion. This is **not a real failure** — check the exit code.

**Check if curl actually succeeded:**
```bash
kubectl logs curl-test -n idol
```

If logs show XML output → curl worked fine. Clean up:
```bash
kubectl delete pod curl-test -n idol
```

---

### ❌ Connection refused or No route to host

**Cause:** The Minikube VM cannot reach the external License Server IP.

**Diagnose:**
```bash
# Test from Minikube node directly
minikube ssh -p <profile> -- ping 172.25.125.123
minikube ssh -p <profile> -- curl "http://172.25.125.123:20000/a=GetVersion"

# Test from your host machine
curl "http://172.25.125.123:20000/a=GetVersion"

# Check if the port is open
nc -zv 172.25.125.123 20000
```

**Fix:**
```bash
# Add a static route (Linux host)
sudo ip route add 172.25.125.0/24 via $(minikube ip -p test-1)

# Or use minikube tunnel
minikube tunnel -p test-1
```

---

### ❌ License Server returns error XML (action not recognized)

**This is NOT a failure.** Any XML response means the server is running and reachable. The error just means you used an unsupported action name.

Use these valid actions instead:
```bash
curl "http://172.25.125.123:20000/a=GetVersion"
curl "http://172.25.125.123:20000/a=LicenseInfo"
```

---

## 📋 Quick Reference

### Commands Cheat Sheet

```bash
# Check Minikube profile name
minikube profile list

# Create namespace
kubectl create namespace idol

# Validate chart
helm lint .

# Dry-run preview
helm template idol-licenseserver . -n idol -f values.yaml

# Deploy or update (use this always)
helm upgrade --install idol-licenseserver . -n idol -f values.yaml

# Verify deployment
kubectl get svc,endpointslices -n idol

# Check all Helm releases across namespaces
helm list -A

# Check all services across namespaces
kubectl get svc -A | grep licenseserver

# Test from Minikube node
minikube ssh -p <profile> -- curl "http://<LICENSE-IP>:20000/a=GetVersion"

# Test from inside cluster (correct way)
kubectl run curl-test --image=curlimages/curl --restart=Never -it --rm -n idol \
  -- curl "http://idol-licenseserver.idol.svc.cluster.local:20000/a=LicenseInfo"

# Get logs from test pod
kubectl logs curl-test -n idol

# Delete test pod
kubectl delete pod curl-test -n idol

# Uninstall chart
helm uninstall idol-licenseserver -n idol
```

### Key Facts

```
Repository:       github.com/opentext-idol/idol-containers-toolkit
Chart path:       helm/idol-licenseserver
Default port:     20000
Recommended NS:   idol
In-cluster DNS:   idol-licenseserver.idol.svc.cluster.local
Only edit:        values.yaml — IP or DNS name, never both
Deploy command:   helm upgrade --install (not helm install)
```

---

## ✅ Deployment Checklist

- [ ] Repository cloned and inside `helm/idol-licenseserver` directory
- [ ] Namespace `idol` created
- [ ] `values.yaml` has **only one** of `licenseServerIp` or `licenseServerExternalName` set
- [ ] `helm lint .` passes with 0 failures
- [ ] `helm template` shows correct IP/hostname in EndpointSlice output
- [ ] `helm upgrade --install` returns `STATUS: deployed`
- [ ] `kubectl get svc -n idol` shows `idol-licenseserver`
- [ ] `kubectl get endpointslices -n idol` shows correct License Server IP
- [ ] `minikube ssh -p <profile>` connectivity test returns XML response
- [ ] In-cluster `curl-test` pod returns XML response
- [ ] Other IDOL services configured to use `idol-licenseserver.idol.svc.cluster.local:20000`