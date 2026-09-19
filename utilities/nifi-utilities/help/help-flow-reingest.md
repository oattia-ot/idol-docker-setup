# NiFi — ConnectorRouter Purge & Sync (Reingest)

> Recursively discovers all `ConnectorGroupRouter` and `ConnectorRouter` processors across a NiFi flow, presents a selection menu, then executes a safe **Purge & Sync** (`RUN_ONCE`) cycle on the chosen processor(s). Supports both interactive terminal use and fully scripted/CI execution.

---

## Table of Contents

- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Options Reference](#options-reference)
- [Execution Modes](#execution-modes)
  - [Interactive Mode](#interactive-mode)
  - [Non-Interactive (Bash/CI) Mode](#non-interactive-bashci-mode)
- [Authentication Methods](#authentication-methods)
- [How Purge & Sync Works](#how-purge--sync-works)
- [Selection Reference](#selection-reference)
- [Examples](#examples)
- [How It Works Internally](#how-it-works-internally)
- [Error Reference](#error-reference)

---

## Requirements

| Tool   | Purpose                        | Install                                        |
|--------|--------------------------------|------------------------------------------------|
| `curl` | NiFi API HTTP calls            | Pre-installed on most systems                  |
| `jq`   | JSON parsing                   | `sudo apt-get install jq` / `brew install jq`  |
| `bash` | Shell (version 4.0+ required)  | Pre-installed on Linux / `brew install bash` on macOS |

> ⚠️ **Bash 4+** is required for associative arrays used during deduplication. macOS ships with Bash 3 — install a newer version via `brew install bash`.

---

## Quick Start

```bash
# Make executable
chmod +x nifi_purge_sync.sh

# Interactive — prompts for URL, credentials, and processor selection
./nifi_purge_sync.sh

# Non-interactive — run Purge & Sync on ALL processors immediately
./nifi_purge_sync.sh -u https://nifi-host:8443 -U admin -P secret -s all
```

---

## Options Reference

| Flag             | Short | Argument  | Default                         | Description                                                      |
|------------------|-------|-----------|---------------------------------|------------------------------------------------------------------|
| `--help`         | `-h`  | —         | —                               | Show help and exit                                               |
| `--url`          | `-u`  | `URL`     | `https://idol-docker-host:8443` | NiFi base URL                                                    |
| `--auth`         | `-a`  | `METHOD`  | `password`                      | Auth method: `password` \| `token` \| `none`                    |
| `--username`     | `-U`  | `USER`    | `admin`                         | Username for password auth                                       |
| `--password`     | `-P`  | `PASS`    | `OpenText2026!`                 | Password for password auth                                       |
| `--token`        | `-t`  | `TOKEN`   | —                               | Pre-existing Bearer token                                        |
| `--select`       | `-s`  | `SEL`     | —                               | Non-interactive selection: `all` \| `none` \| `"1 3"` (numbers) |

> When `--select` is provided, the script runs fully non-interactively — no prompts are shown for URL, credentials, or processor selection.

---

## Execution Modes

### Interactive Mode

Run the script with no `--select` flag. The script will prompt you for:

1. **NiFi URL** — or press Enter to use the default
2. **Authentication method** — choose from password, token, or none
3. **Credentials** — username/password or Bearer token
4. **Processor selection** — choose which processors to Purge & Sync

Invalid selections re-prompt rather than exiting, so typos are handled gracefully.

```bash
./nifi_purge_sync.sh
```

```
NiFi URL [default: https://idol-docker-host:8443]:
Authentication:
  1) Username / password
  2) Existing Bearer token
  3) None
Choice [1-3, default: 1]:

  1. ConnectorGroupRouter  ● RUNNING  [ConnectorGroupRouter]
     ├─ Location: NiFi Flow > Ingest
     └─ ID:       d02727c2-f797-38fe-c5f1-ed24cbc846a1
        · FileSystemConnectorGroup = FileSystem

  2. FileSystemConnector Router  ● RUNNING  [ConnectorRouter]
     ├─ Location: NiFi Flow > Ingest
     └─ ID:       c100228c-834a-36f1-7311-aabcab80949d

Selection [number(s)/all/none]:
```

---

### Non-Interactive (Bash/CI) Mode

Pass all required values as flags. Use `--select` / `-s` to specify which processors to run without any prompts. This mode is suitable for cron jobs, CI/CD pipelines, and automation scripts.

```bash
# Purge & Sync ALL processors
./nifi_purge_sync.sh \
  -u https://nifi-host:8443 \
  -U admin \
  -P secret \
  -s all

# Purge & Sync only processor 2
./nifi_purge_sync.sh \
  -u https://nifi-host:8443 \
  -U admin \
  -P secret \
  -s "2"

# Purge & Sync processors 1 and 3
./nifi_purge_sync.sh \
  -u https://nifi-host:8443 \
  -U admin \
  -P secret \
  -s "1 3"

# Use a pre-existing Bearer token
./nifi_purge_sync.sh \
  -u https://nifi-host:8443 \
  -a token \
  -t eyJhbGciOi... \
  -s all
```

> In non-interactive mode the script prints a confirmation line showing the resolved selection before proceeding:
> ```
> ℹ  Non-interactive mode — selection: all
> ```

---

## Authentication Methods

### `password` (default)

Exchanges username and password for a short-lived Bearer token via `POST /nifi-api/access/token`. The token is used for all subsequent API calls within the session.

```bash
./nifi_purge_sync.sh -a password -U admin -P mypassword
```

### `token`

Supply a pre-existing Bearer token directly. Useful when a token is already available in the environment (e.g. injected by a secrets manager).

```bash
./nifi_purge_sync.sh -a token -t eyJhbGciOi...
```

### `none`

Disables authentication. Only works if the NiFi instance has security disabled.

```bash
./nifi_purge_sync.sh -a none
```

---

## How Purge & Sync Works

For each selected processor, the script performs three steps in sequence:

```
1. STOP     — if the processor is currently RUNNING, stop it gracefully
2. RUN_ONCE — trigger a single execution cycle (Purge & Sync / Reingest)
3. RESTORE  — restart the processor if it was originally RUNNING
```

The revision token is re-fetched between each state change to ensure NiFi's optimistic locking is never violated. The original state is always restored — even if `RUN_ONCE` fails.

### Example execution output

```
▶ ConnectorGroupRouter  [ConnectorGroupRouter]
  ID: d02727c2-f797-38fe-c5f1-ed24cbc846a1
  Revision: 42  |  State: RUNNING
  ⟳ Stopping processor...
  ✓ Stopped
  ⟳ Triggering RUN_ONCE (Purge & Sync)...
  ✓ RUN_ONCE triggered
  ⟳ Restoring to RUNNING...
  ✓ Restored to RUNNING
  ✓ Purge & Sync complete
```

### Summary block

At the end of execution a summary is always printed:

```
╔══════════════════════════════════════════════════════════════╗
║                  Purge & Sync Summary                        ║
╚══════════════════════════════════════════════════════════════╝
  Processors attempted:  2
  ✓ Succeeded:           2
```

---

## Selection Reference

| Input       | Effect                                        |
|-------------|-----------------------------------------------|
| `all`       | Run Purge & Sync on every discovered processor |
| `none`      | Cancel — exit without making any changes      |
| `1`         | Run on processor number 1 only                |
| `2`         | Run on processor number 2 only                |
| `1 3`       | Run on processors 1 and 3                     |
| `1 2 3`     | Run on processors 1, 2, and 3                 |
| *(invalid)* | Interactive: re-prompts. Non-interactive: exits with error |

Processor numbers correspond to the numbered list displayed in the **Available Processors** section at runtime. Numbers are 1-based.

---

## Examples

```bash
# Interactive — full prompts
./nifi_purge_sync.sh

# Non-interactive — password auth, run all
./nifi_purge_sync.sh -u https://nifi-host:8443 -U admin -P secret -s all

# Non-interactive — password auth, run processor 1 only
./nifi_purge_sync.sh -u https://nifi-host:8443 -U admin -P secret -s "1"

# Non-interactive — password auth, run processors 1 and 2
./nifi_purge_sync.sh -u https://nifi-host:8443 -U admin -P secret -s "1 2"

# Non-interactive — token auth
./nifi_purge_sync.sh \
  -u https://nifi-host:8443 \
  -a token \
  -t eyJhbGciOi... \
  -s all

# Non-interactive — skip (no-op, useful as a safe default in scripts)
./nifi_purge_sync.sh -u https://nifi-host:8443 -U admin -P secret -s none

# Cron job — run every night at 02:00, log output
0 2 * * * /opt/scripts/nifi_purge_sync.sh \
  -u https://nifi-host:8443 \
  -U admin \
  -P secret \
  -s all \
  >> /var/log/nifi_purge_sync.log 2>&1
```

---

## How It Works Internally

```
1. Authenticate    →  POST /nifi-api/access/token
2. Fetch root      →  GET  /nifi-api/flow/process-groups/root
3. Recurse         →  GET  /nifi-api/flow/process-groups/{id}  (all child groups)
4. Filter          →  Keep processors whose type ends in ConnectorGroupRouter or ConnectorRouter
5. Deduplicate     →  Remove any processor ID seen more than once (guards against NiFi API overlap)
6. Display list    →  Show numbered menu with state, location, ID, and ConnectorGroup properties
7. Resolve select  →  Interactive prompt (re-prompts on error) or --select flag (validates and exits on error)
8. Purge & Sync    →  For each selected processor:
                       a. GET  /nifi-api/processors/{id}              (fetch revision)
                       b. PUT  /nifi-api/processors/{id}/run-status   (STOPPED)
                       c. GET  /nifi-api/processors/{id}              (refresh revision)
                       d. PUT  /nifi-api/processors/{id}/run-status   (RUN_ONCE)
                       e. GET  /nifi-api/processors/{id}              (refresh revision)
                       f. PUT  /nifi-api/processors/{id}/run-status   (RUNNING — if was running)
```

---

## Error Reference

| Message | Cause | Resolution |
|---|---|---|
| `✗ Failed to generate token` | Wrong credentials or unreachable NiFi URL | Verify `-u`, `-U`, `-P` |
| `✗ Failed to reach NiFi (HTTP 000)` | Network or TLS issue | Check URL and network connectivity |
| `✗ Failed to stop (HTTP 403)` | Token expired or insufficient permissions | Re-run to get a fresh token |
| `✗ RUN_ONCE failed (HTTP 409)` | Processor is in a conflicting state | Check NiFi UI; retry once the processor is idle |
| `✗ Could not restore to RUNNING` | State change failed post-RUN_ONCE | Manual restart required in the NiFi UI |
| `✗ Invalid --select value` | `--select` contains an unrecognised token | Use `all`, `none`, or space-separated numbers e.g. `"1 3"` |
| `✗ N is out of range` | Number exceeds the count of discovered processors | Re-run to see the current list and choose a valid number |
| `✗ 'jq' is required but not installed` | `jq` missing from PATH | `sudo apt-get install jq` or `brew install jq` |