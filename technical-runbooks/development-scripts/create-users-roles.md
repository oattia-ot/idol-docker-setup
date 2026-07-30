# IDOL Community — Create Users & Roles

Script: `create-users-roles.py`

Creates the required roles, users, and role assignments in IDOL Community to allow login to OpenText Find.

---

## Prerequisites

- Python 3.x
- `requests` library installed (`pip install requests`)
- Network access to the IDOL Community ACI port (HTTPS)
- The CA chain certificate file used to sign Community's SSL certificate

---

## What the Script Does

1. Creates roles: `FindBI`, `FindUser`, `FindAdmin`, `AnswerBankUser`, `IDAUser`, `ISOAdmin`, `ISOUser`, `everyone`
2. Creates users: `admin` (password: `admin`), `bank` (password: `password`)
3. Assigns roles:

| User | Roles |
|------|-------|
| `admin` | `FindBI`, `FindAdmin`, `FindUser`, `IDAUser`, `AnswerBankUser` |
| `bank` | `FindUser`, `IDAUser`, `AnswerBankUser` |

4. Verifies the final role state for both users

Roles and users that already exist are silently skipped — the script is safe to run multiple times.

---

## Configuration

The script requires three values. Each can be supplied as an environment variable or entered interactively at runtime.

| Variable | Description | Default |
|----------|-------------|---------|
| `COMMUNITY_HOST` | Hostname or IP of the Community instance | `idol-docker-host` |
| `COMMUNITY_PORT` | ACI port — all actions go here over HTTPS | `9033` |
| `COMMUNITY_CERT` | Path to the CA chain cert (`.pem`) that signed Community's SSL cert | `./idol-docker-setup/idol-containers-toolkit/data-admin/ssl/intermediate/certs/ca-chain.cert.pem` |

> **Note:** All actions (reads and writes) use the single ACI port over HTTPS. No separate service port is needed.

### COMMUNITY_HOST values by context

| Where you run the script | Value to use |
|--------------------------|--------------|
| On the host machine | `idol-docker-host`, FQDN, or IP |
| Inside a container on `idol-demo-network` | `idol-dataadmin-community` |

### Finding the cert path

The CA chain cert is typically located at:

```
<ssl-mount>/certs/ca-chain.cert.pem
```

If the installed user is `kduser3`, the cert is located at:

```
/home/kduser3/idol-docker-setup/idol-containers-toolkit/data-admin/ssl/intermediate/certs/ca-chain.cert.pem
```
Replace `kduser3` with your actual username if different.

Inside a container (where the ssl volume is mounted at `/ssl`):

```
/ssl/certs/ca-chain.cert.pem
```

---

## Usage

### Option 1 — Interactive (no env vars set)

```bash
python3 create-users-roles.py
```

The script will prompt for each value, showing a default in brackets. Press Enter to accept the default:

```
============================================================
  IDOL Community - User & Role Setup
============================================================

Variables already set as env vars will be used without prompting.

COMMUNITY_HOST
  Inside a container on idol-demo-network : idol-dataadmin-community
  On the host machine                     : FQDN, IP, or idol-docker-host
  > [idol-docker-host]:

COMMUNITY_PORT  (ACI port — all actions go here over HTTPS)
  Inside a container : 9033
  On the host        : check with 'docker ps | grep community'
                       and use the mapped host port (e.g. 19033)
  > [9033]:

COMMUNITY_CERT  (CA chain cert for Community's SSL)
  > [./idol-docker-setup/.../ca-chain.cert.pem]:

------------------------------------------------------------
  Community URL : https://idol-docker-host:9033
  Cert path     : ./idol-docker-setup/.../ca-chain.cert.pem
------------------------------------------------------------

Proceed? [Y/n]:
```

### Option 2 — Pre-set env vars (no prompts)

Set any combination of the three variables before running. Only unset variables will be prompted.

```bash
# Set all three — script runs without any prompts
export COMMUNITY_HOST=idol-docker-host
export COMMUNITY_PORT=9033
export COMMUNITY_CERT=/home/kduser3/idol-docker-setup/idol-containers-toolkit/data-admin/ssl/intermediate/certs/ca-chain.cert.pem

python3 create-users-roles.py
```

When a variable is taken from the environment, the script confirms it:

```
COMMUNITY_HOST
  [FROM ENV] idol-docker-host
```

### Option 3 — Run from inside a container

Copy the script into the Find container (which is already on `idol-demo-network`) and run it with the container hostname:

```bash
docker cp create-users-roles.py idol-demo-idol-dataadmin-find-1:/tmp/

docker exec idol-demo-idol-dataadmin-find-1 sh -c "
  COMMUNITY_HOST=idol-dataadmin-community \
  COMMUNITY_PORT=9033 \
  COMMUNITY_CERT=/ssl/certs/ca-chain.cert.pem \
  python3 /tmp/create-users-roles.py
"
```

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
| `CONNECTION ERROR: Failed to resolve '...'` | Hostname not resolvable from this network context | Use `localhost` on the host, or the container name from inside Docker network |
| `SSL ERROR: UNEXPECTED_EOF_WHILE_READING` | Wrong protocol — likely using HTTPS on a plain HTTP port | Ensure `COMMUNITY_PORT` points to the ACI port (HTTPS), not the service port |
| `SSL ERROR: certificate verify failed` | Wrong cert path or wrong CA cert | Check `COMMUNITY_CERT` points to `ca-chain.cert.pem`, not an intermediate or leaf cert |
| `COMMUNITY ERROR: The action you attempted is not recognized` | Wrong action name or wrong port | Confirm you are hitting the ACI port, not a different service |
| `404 Not Found` | Action not supported on this port | Switch to the ACI port (default `9033`) |