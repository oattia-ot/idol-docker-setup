# IDOL Community — Create Users & Roles

Script: `create-users-roles.py`

Creates the required roles, users, and role assignments in IDOL Community to allow login to OpenText Find.

This is a single **generic** script shared by every IDOL deployment subtype (`basic-idol`, `data-admin`, ...). Anything that used to differ between per-subtype copies of this file — the env var used to guess a default Community port, and the folder segment used to guess a default CA cert path — is now passed in explicitly via flags/env vars, so no subtype-specific forks of this file are needed.

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
| `--host` | `COMMUNITY_HOST` | Hostname or IP of the Community instance | `IDOL_HOST_FQDN` if set, else `idol-docker-host` |
| `--port` | `COMMUNITY_PORT` | ACI port — all actions go here over HTTPS | auto-detected (see below), else `9033` |
| `--cert` | `COMMUNITY_CERT` | Path to the CA chain cert (`.pem`) that signed Community's SSL cert | `./idol-docker-setup/idol-containers-toolkit/<cert-subdir>/ssl/intermediate/certs/ca-chain.cert.pem` |
| `--port-env-name` | `COMMUNITY_PORT_ENV_NAME` | Name of an extra subtype-specific env var to check for the default port | none — see auto-detection below |
| `--cert-subdir` | `COMMUNITY_CERT_SUBDIR` | Deployment subtype folder segment used when guessing the default cert path (e.g. `basic-idol`, `data-admin`) | `data-admin` |
| `--insecure` | `COMMUNITY_INSECURE=1` | Disable TLS certificate verification | off |
| `-y` / `--yes` | `COMMUNITY_YES=1` | Non-interactive: skip prompts and the Proceed? confirmation | off |
| `--scheme https\|http` | — | URL scheme | `https` |

> **Note:** All actions (reads and writes) use the single ACI port. No separate service port is needed.

If `COMMUNITY_HOST` is not set, the script also auto-selects it from `EXTRA_IP_SANS_ENV` (preferred when it differs from `IDOL_NET_HOST_IP`) or from `IDOL_NET_HOST_IP`, before falling back to `IDOL_HOST_FQDN` / `idol-docker-host`.

### Default port auto-detection (subtype wiring)

The **default** shown for `COMMUNITY_PORT` (used only if nothing else — CLI flag, `COMMUNITY_PORT` env var, or prompt answer — sets one) is resolved like this:

1. If `--port-env-name` / `COMMUNITY_PORT_ENV_NAME` is given, only that env var is checked.
2. Otherwise, the script tries every well-known subtype port env var in order and uses the first valid one it finds:
   - `PORT_BASIC_IDOL_COMMUNITY`
   - `PORT_DATA_ADMIN_COMMUNITY`
3. If none of those are set (or the value isn't a valid port number 1–65535), it falls back to `9033`.

This means the script works as a drop-in for either the `basic-idol` or `data-admin` deploy scripts with **no extra flags**, but you can be explicit if you prefer — see [Option 5](#option-5--called-from-a-deploy-script) below.

### COMMUNITY_HOST values by context

| Where you run the script | Value to use |
|--------------------------|--------------|
| On the host machine | `idol-docker-host`, FQDN, or IP |
| Inside a container on `idol-demo-network` | `idol-dataadmin-community` |

### Finding the cert path

The script first uses `--cert` / `COMMUNITY_CERT`, then searches these locations and also resolves paths relative to the current working directory **and** the script's own directory. `<cert-subdir>` is `basic-idol`, `data-admin`, etc., set via `--cert-subdir` / `COMMUNITY_CERT_SUBDIR` (default `data-admin`):

```
<ssl-mount>/certs/ca-chain.cert.pem
./idol-docker-setup/idol-containers-toolkit/<cert-subdir>/ssl/intermediate/certs/ca-chain.cert.pem
/ssl/certs/ca-chain.cert.pem
/ssl/intermediate/certs/ca-chain.cert.pem
./ssl/certs/ca-chain.cert.pem
./certs/ca-chain.cert.pem
./ca-chain.cert.pem
$HOME/idol-docker-setup/idol-containers-toolkit/<cert-subdir>/ssl/intermediate/certs/ca-chain.cert.pem
```

If the installed user is `kduser3` and the subtype is `data-admin`, the cert is typically at:

```
/home/kduser3/idol-docker-setup/idol-containers-toolkit/data-admin/ssl/intermediate/certs/ca-chain.cert.pem
```

For a `basic-idol` deployment, pass `--cert-subdir basic-idol` (or `COMMUNITY_CERT_SUBDIR=basic-idol`) so the guessed path points at:

```
/home/kduser3/idol-docker-setup/idol-containers-toolkit/basic-idol/ssl/intermediate/certs/ca-chain.cert.pem
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

The script will prompt for each value, showing a default in brackets, and print which subtype wiring it resolved before prompting. Press Enter to accept the default:

```
============================================================
  IDOL Community - User & Role Setup
============================================================

Resolution order: CLI flag → env var → prompt → default.
Subtype wiring: port-env=PORT_BASIC_IDOL_COMMUNITY/PORT_DATA_ADMIN_COMMUNITY  cert-subdir=data-admin

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

# basic-idol subtype, letting it guess host/port/cert from subtype env vars/flags
python3 create-users-roles.py \
  --port-env-name PORT_BASIC_IDOL_COMMUNITY \
  --cert-subdir basic-idol \
  -y --insecure
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

Standalone for a specific subtype, without hardcoding `COMMUNITY_PORT`/`COMMUNITY_CERT` — let auto-detection pick them from the subtype env vars:

```bash
PORT_BASIC_IDOL_COMMUNITY=9030 \
COMMUNITY_CERT_SUBDIR=basic-idol \
COMMUNITY_YES=1 \
COMMUNITY_INSECURE=1 \
python3 create-users-roles.py --host 172.25.125.123
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

### Option 5 — Called from a deploy script

`deploy-bi.sh` (basic-idol) and `deploy-da.sh` (data-admin) both export `COMMUNITY_HOST`, `COMMUNITY_PORT`, and `COMMUNITY_CERT` after `up`, then run `python3 create-users-roles.py -y`. Those env vars still take priority and work exactly as before — the same script file is shared by both deploy scripts.

For a fully non-interactive deploy, export `COMMUNITY_YES=1`, or pass `-y` directly as the deploy scripts already do.

To make the subtype wiring explicit instead of relying on auto-detection, have each deploy script pass its own flags:

```bash
# in deploy-bi.sh
python3 create-users-roles.py -y --port-env-name PORT_BASIC_IDOL_COMMUNITY --cert-subdir basic-idol

# in deploy-da.sh
python3 create-users-roles.py -y --port-env-name PORT_DATA_ADMIN_COMMUNITY --cert-subdir data-admin
```

If the relative cert path used by the deploy script (`./ssl/intermediate/certs/ca-chain.cert.pem`) is missing, the script will search the candidate list and, with `-y`, fall back to insecure TLS rather than failing every ACI call.

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
| `CONNECTION ERROR: ... Connection refused` | Nothing listening on that host:port — container not up yet, or `COMMUNITY_PORT` / `PORT_*_COMMUNITY` points at the wrong (e.g. internal vs host-mapped) port | Check `docker ps \| grep community` for the real mapped port, and confirm the Community container has finished starting |
| `SSL ERROR: UNEXPECTED_EOF_WHILE_READING` | Wrong protocol — likely using HTTPS on a plain HTTP port | Ensure `COMMUNITY_PORT` points to the ACI port (HTTPS), not the service port |
| `SSL ERROR: certificate verify failed` | Wrong cert path or wrong CA cert | Check `COMMUNITY_CERT` / `--cert` points to `ca-chain.cert.pem`, not an intermediate or leaf cert |
| `TLS BUNDLE ERROR: Could not find a suitable TLS CA certificate bundle` | `--cert` / `COMMUNITY_CERT` path does not exist | Pass a real PEM with `--cert`, or rerun with `--insecure -y` |
| `COMMUNITY ERROR: The action you attempted is not recognized` | Wrong action name or wrong port | Confirm you are hitting the ACI port, not a different service |
| `404 Not Found` | Action not supported on this port | Switch to the ACI port (default `9033`) |
| Default port/cert look wrong for your subtype | Auto-detection picked up the wrong `PORT_*_COMMUNITY` env var, or `COMMUNITY_CERT_SUBDIR` wasn't set | Pass `--port-env-name` and `--cert-subdir` explicitly for your subtype |
