# IDOL Community — Create Users & Roles

Script: `create-users-roles.py`

Creates the required roles, users, and role assignments in IDOL Community to allow login to OpenText Find.

---

## Prerequisites

- Python 3.x
- `requests` library installed (`pip install requests`)
- Network access to the IDOL Community ACI port (HTTPS by default)
- Either:
  - the CA chain certificate file used to sign Community's SSL certificate, **or**
  - `--insecure` / `COMMUNITY_INSECURE=1` for standalone / lab use when the CA file is not available

---

## What the Script Does

1. Creates roles: `FindBI`, `FindUser`, `FindAdmin`, `AnswerBankUser`, `IDAUser`, `ISOAdmin`, `ISOUser`, `everyone`
2. Creates users: `admin` (password: `admin`), `bank` (password: `admin`)
3. Assigns roles:

| User | Roles |
|------|-------|
| `admin` | `FindBI`, `FindAdmin`, `FindUser`, `IDAUser`, `AnswerBankUser` |
| `bank` | `FindUser`, `IDAUser`, `AnswerBankUser` |

4. Verifies the final role state for both users

Roles and users that already exist are silently skipped — the script is safe to run multiple times.

---

## Configuration

Settings are resolved in this order (first match wins):

1. Command-line flags
2. Environment variables
3. Interactive prompt (skipped with `-y` / `--yes` / `COMMUNITY_YES=1`)
4. Built-in default

| Flag | Environment variable | Description | Default |
|------|----------------------|-------------|---------|
| `--host` | `COMMUNITY_HOST` | Hostname or IP of the Community instance | `idol-docker-host` |
| `--port` | `COMMUNITY_PORT` | ACI port — all actions go here over HTTPS | `9033` |
| `--cert` | `COMMUNITY_CERT` | Path to the CA chain cert (`.pem`) that signed Community's SSL cert | `./idol-docker-setup/idol-containers-toolkit/data-admin/ssl/intermediate/certs/ca-chain.cert.pem` |
| `--insecure` | `COMMUNITY_INSECURE=1` | Disable TLS certificate verification | off |
| `-y` / `--yes` | `COMMUNITY_YES=1` | Non-interactive: skip prompts and the Proceed? confirmation | off |
| `--scheme https\|http` | — | URL scheme | `https` |

> **Note:** All actions (reads and writes) use the single ACI port. No separate service port is needed.

If `COMMUNITY_HOST` is not set, the script also auto-selects it from `EXTRA_IP_SANS_ENV` (preferred when it differs from `IDOL_NET_HOST_IP`) or from `IDOL_NET_HOST_IP`.

### COMMUNITY_HOST values by context

| Where you run the script | Value to use |
|--------------------------|--------------|
| On the host machine | `idol-docker-host`, FQDN, or IP |
| Inside a container on `idol-demo-network` | `idol-dataadmin-community` |

### Finding the cert path

The script first uses `--cert` / `COMMUNITY_CERT`, then searches these locations and also resolves paths relative to the current working directory **and** the script's own directory:

```
<ssl-mount>/certs/ca-chain.cert.pem
./idol-docker-setup/idol-containers-toolkit/data-admin/ssl/intermediate/certs/ca-chain.cert.pem
/ssl/certs/ca-chain.cert.pem
/ssl/intermediate/certs/ca-chain.cert.pem
./ssl/certs/ca-chain.cert.pem
./certs/ca-chain.cert.pem
./ca-chain.cert.pem
$HOME/idol-docker-setup/idol-containers-toolkit/data-admin/ssl/intermediate/certs/ca-chain.cert.pem
```

If the installed user is `kduser3`, the cert is typically at:

```
/home/kduser3/idol-docker-setup/idol-containers-toolkit/data-admin/ssl/intermediate/certs/ca-chain.cert.pem
```

Replace `kduser3` with your actual username if different.

Inside a container (where the ssl volume is mounted at `/ssl`):

```
/ssl/certs/ca-chain.cert.pem
```

If no CA file is found:

- **Interactive:** the script warns and asks whether to continue without TLS verification.
- **Non-interactive (`-y`):** it falls back to `verify=False` and prints a warning.

Use `--insecure` explicitly when you know the CA bundle is not available.

---

## Usage

### Option 1 — Interactive (no flags / env vars)

```bash
python3 create-users-roles.py
```

The script will prompt for each value, showing a default in brackets. Press Enter to accept the default:

```
============================================================
  IDOL Community - User & Role Setup
============================================================

Resolution order: CLI flag → env var → prompt → default.

COMMUNITY_HOST
  Inside a container on idol-demo-network : idol-dataadmin-community
  On the host machine                     : FQDN, IP, or idol-docker-host
  > [idol-docker-host]:

COMMUNITY_PORT  (ACI port — all actions go here over HTTPS)
  Inside a container : 9033
  On the host        : check with 'docker ps | grep community'
                       and use the mapped host port (e.g. 19033)
  > [9033]:

COMMUNITY_CERT  (CA chain cert for Community's SSL; leave default if unknown)
  > [./idol-docker-setup/.../ca-chain.cert.pem]:

------------------------------------------------------------
  Community URL : https://idol-docker-host:9033
  Cert path     : ...
  TLS verify    : CA bundle
------------------------------------------------------------

Proceed? [Y/n]:
```

### Option 2 — Command-line flags (recommended for standalone)

```bash
# Host IP, skip prompts, skip TLS verify (typical standalone run)
python3 create-users-roles.py --host 172.25.125.123 --port 9033 --insecure -y

# Same, but verify TLS with an explicit CA bundle
python3 create-users-roles.py \
  --host 172.25.125.123 \
  --port 9033 \
  --cert /home/kduser3/idol-docker-setup/idol-containers-toolkit/data-admin/ssl/intermediate/certs/ca-chain.cert.pem \
  -y
```

### Option 3 — Pre-set env vars (no prompts if all are set + COMMUNITY_YES)

Set any combination of the variables before running. Unset variables are prompted unless `-y` / `COMMUNITY_YES=1` is set.

```bash
export COMMUNITY_HOST=idol-docker-host
export COMMUNITY_PORT=9033
export COMMUNITY_CERT=/home/kduser3/idol-docker-setup/idol-containers-toolkit/data-admin/ssl/intermediate/certs/ca-chain.cert.pem
export COMMUNITY_YES=1

python3 create-users-roles.py
```

Standalone without a cert file:

```bash
COMMUNITY_HOST=172.25.125.123 \
COMMUNITY_PORT=9033 \
COMMUNITY_INSECURE=1 \
COMMUNITY_YES=1 \
python3 create-users-roles.py
```

When a variable is taken from the CLI or environment, the script confirms it:

```
COMMUNITY_HOST
  [FROM CLI] 172.25.125.123

COMMUNITY_PORT
  [FROM ENV] 9033
```

### Option 4 — Run from inside a container

Copy the script into the Find container (which is already on `idol-demo-network`) and run it with the container hostname:

```bash
docker cp create-users-roles.py idol-demo-idol-dataadmin-find-1:/tmp/

docker exec idol-demo-idol-dataadmin-find-1 sh -c "
  python3 /tmp/create-users-roles.py \
    --host idol-dataadmin-community \
    --port 9033 \
    --cert /ssl/certs/ca-chain.cert.pem \
    -y
"
```

### Option 5 — Called from deploy-data-admin.sh

`deploy-data-admin.sh` exports `COMMUNITY_HOST`, `COMMUNITY_PORT`, and `COMMUNITY_CERT` after `up`, then runs `python3 create-users-roles.py`. Those env vars still work. For a fully non-interactive deploy, also export:

```bash
export COMMUNITY_YES=1
```

or change the deploy script call to:

```bash
python3 create-users-roles.py -y
```

If the relative cert path used by the deploy script (`./ssl/intermediate/certs/ca-chain.cert.pem`) is missing, the updated Python script will search the candidate list and, with `-y`, fall back to insecure TLS rather than failing every ACI call.

---

## Finding the mapped host port

If running on the host and unsure of the mapped Community port:

```bash
docker ps | grep community
```

Look for a line like `0.0.0.0:19033->9033/tcp` — use `19033` as `COMMUNITY_PORT`.

---

## Output

Each operation prints a single status line:

```
[Create role 'FindAdmin']
  OK (already exists — skipping)

[Assign 'admin' -> 'FindAdmin']
  OK

[Verify roles for 'admin']
  ...XML role list...
```

Error lines are prefixed with `!!` and include a short explanation and remediation hint.

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `CONNECTION ERROR: Failed to resolve '...'` | Hostname not resolvable from this network context | Use the host IP / `localhost` on the host, or the container name from inside the Docker network |
| `SSL ERROR: UNEXPECTED_EOF_WHILE_READING` | Wrong protocol — likely using HTTPS on a plain HTTP port | Ensure `COMMUNITY_PORT` points to the ACI port (HTTPS), not the service port |
| `SSL ERROR: certificate verify failed` | Wrong cert path or wrong CA cert | Check `COMMUNITY_CERT` / `--cert` points to `ca-chain.cert.pem`, not an intermediate or leaf cert |
| `TLS BUNDLE ERROR: Could not find a suitable TLS CA certificate bundle` | `--cert` / `COMMUNITY_CERT` path does not exist | Pass a real PEM with `--cert`, or rerun with `--insecure -y` |
| `COMMUNITY ERROR: The action you attempted is not recognized` | Wrong action name or wrong port | Confirm you are hitting the ACI port, not a different service |
| `404 Not Found` | Action not supported on this port | Switch to the ACI port (default `9033`) |
