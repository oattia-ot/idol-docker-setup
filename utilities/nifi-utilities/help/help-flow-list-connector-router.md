# NiFi — ConnectorGroupRouter / ConnectorRouter Fetcher

> Recursively discovers all `ConnectorGroupRouter` and `ConnectorRouter` processors across a NiFi flow, displays their `ConnectorGroup` properties, and optionally triggers a **Purge & Sync** (`RUN_ONCE`) cycle on selected processors.

---

## Table of Contents

- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Options Reference](#options-reference)
- [Authentication Methods](#authentication-methods)
- [Output Formats](#output-formats)
- [Writing Output to a File](#writing-output-to-a-file)
- [Purge & Sync](#purge--sync)
- [Examples](#examples)
- [How It Works](#how-it-works)
- [Error Reference](#error-reference)

---

## Requirements

| Tool   | Purpose                        | Install                                      |
|--------|--------------------------------|----------------------------------------------|
| `curl` | NiFi API HTTP calls            | Pre-installed on most systems                |
| `jq`   | JSON parsing                   | `sudo apt-get install jq` / `brew install jq` |
| `bash` | Shell (version 4.0+ required)  | Pre-installed on Linux/macOS                 |

> ⚠️ **Bash 4+** is required for associative arrays (`declare -A`). macOS ships with Bash 3 by default — install a newer version via `brew install bash`.

---

## Quick Start

```bash
# Make executable
chmod +x nifi_connector_fetcher.sh

# Run interactively (prompts for URL and credentials)
./nifi_connector_fetcher.sh

# Run fully non-interactive
./nifi_connector_fetcher.sh -u https://nifi-host:8443 -U admin -P secret
```

---

## Options Reference

| Flag                    | Short | Argument     | Default                          | Description                                               |
|-------------------------|-------|--------------|----------------------------------|-----------------------------------------------------------|
| `--help`                | `-h`  | —            | —                                | Show help and exit                                        |
| `--url`                 | `-u`  | `URL`        | `https://idol-docker-host:8443`  | NiFi base URL                                             |
| `--auth`                | `-a`  | `METHOD`     | `password`                       | Auth method: `password` \| `token` \| `none`             |
| `--username`            | `-U`  | `USER`       | `admin`                          | Username for password auth                                |
| `--password`            | `-P`  | `PASS`       | `OpenText2026!`                  | Password for password auth                                |
| `--token`               | `-t`  | `TOKEN`      | —                                | Pre-existing Bearer token                                 |
| `--filter`              | `-F`  | `KEYWORD`    | `ConnectorGroup`                 | Property key substring filter (case-insensitive)          |
| `--all-props`           | —     | —            | `false`                          | Show **all** processor properties (ignores `--filter`)    |
| `--output`              | `-o`  | `FORMAT`     | `table`                          | Output format: `table` \| `json` \| `csv`                |
| `--output-file`         | `-f`  | `FILE`       | —                                | Write output to a file (see [below](#writing-output-to-a-file)) |

---

## Authentication Methods

### `password` (default)
The script exchanges your username and password for a short-lived Bearer token via `POST /nifi-api/access/token`. The token is used for all subsequent requests.

```bash
./nifi_connector_fetcher.sh -a password -U admin -P mypassword
```

### `token`
Provide a pre-existing Bearer token. Useful in CI/CD pipelines where a token is already available.

```bash
./nifi_connector_fetcher.sh -a token -t eyJhbGciOi...
```

### `none`
Disables authentication entirely. Only works if your NiFi instance has security disabled.

```bash
./nifi_connector_fetcher.sh -a none
```

---

## Output Formats

### `table` (default)
Coloured, human-readable output printed to the terminal. When combined with `--output-file`, a plain-text (no ANSI codes) version is also written to the file.

```
╔══════════════════════════════════════════════════════════════╗
║  [1/2] ConnectorGroupRouter                                  ║
╚══════════════════════════════════════════════════════════════╝
  Type:  ConnectorGroupRouter   State: RUNNING
  ID:    d02727c2-f797-38fe-c5f1-ed24cbc846a1
  Path:  NiFi Flow > MyGroup

  1. FileSystemConnectorGroup
     └─ Value: FileSystem
```

### `json`
Machine-readable JSON array. Each element represents one processor with its matched properties.

```json
[
  {
    "processorId": "d02727c2-f797-38fe-c5f1-ed24cbc846a1",
    "processorName": "ConnectorGroupRouter",
    "processorType": "ConnectorGroupRouter",
    "state": "RUNNING",
    "properties": [
      { "key": "FileSystemConnectorGroup", "value": "FileSystem" }
    ]
  }
]
```

### `csv`
Comma-separated values with a header row. Suitable for importing into Excel or similar tools.

```
ProcessorName,ProcessorId,ProcessorType,Key,Value
"ConnectorGroupRouter","d02727c2-...","ConnectorGroupRouter","FileSystemConnectorGroup","FileSystem"
```

---

## Writing Output to a File

Use `-f` / `--output-file` to save output to a file. Combine with `-o` to control format.

| Format  | Stdout             | File content              |
|---------|--------------------|---------------------------|
| `table` | Coloured terminal  | Plain text (no ANSI)      |
| `json`  | *(silent)*         | Clean JSON                |
| `csv`   | *(silent)*         | Clean CSV                 |

```bash
# Save as JSON
./nifi_connector_fetcher.sh -o json -f /tmp/connectors.json

# Save as CSV
./nifi_connector_fetcher.sh -o csv -f /tmp/connectors.csv

# Save plain-text table while also viewing in terminal
./nifi_connector_fetcher.sh -o table -f /tmp/connectors.txt

# Show all properties and save as JSON
./nifi_connector_fetcher.sh --all-props -o json -f /tmp/all_props.json
```

---

## Purge & Sync

After the property listing, the script enters an interactive **Purge & Sync** section. This allows you to trigger a `RUN_ONCE` execution on any discovered processor, which causes it to flush and re-synchronise its connector data.

### What it does

For each selected processor, the script performs these steps in order:

```
1. STOP    — if the processor is currently RUNNING, stop it gracefully
2. RUN_ONCE — trigger a single execution cycle (Purge & Sync)
3. RESTORE  — restart the processor if it was originally RUNNING
```

> The original state is always restored, even if `RUN_ONCE` fails.

### Selection prompt

```
Selection [number(s)/all/none]:
```

| Input       | Effect                                  |
|-------------|-----------------------------------------|
| `1`         | Run Purge & Sync on processor 1 only    |
| `1 3`       | Run on processors 1 and 3               |
| `all`       | Run on all discovered processors        |
| `none`      | Skip — exit without any changes         |
| *(invalid)* | Re-prompts — does not exit or crash     |

### Example output

```
▶ ConnectorGroupRouter  (d02727c2-f797-38fe-c5f1-ed24cbc846a1)
  ⟳ Stopping processor...
  ✓ Stopped
  ⟳ Triggering RUN_ONCE (Purge & Sync)...
  ✓ RUN_ONCE triggered
  ⟳ Restoring state to RUNNING...
  ✓ Restored to RUNNING
  ✓ Purge & Sync complete
```

---

## Examples

```bash
# Interactive — prompts for URL and credentials
./nifi_connector_fetcher.sh

# Non-interactive with password auth
./nifi_connector_fetcher.sh -u https://nifi-host:8443 -U admin -P secret

# Use a pre-existing token
./nifi_connector_fetcher.sh -u https://nifi-host:8443 -a token -t eyJhbGci...

# Filter by a custom property keyword
./nifi_connector_fetcher.sh -F DatabasePool

# Show ALL properties (ignore filter)
./nifi_connector_fetcher.sh --all-props

# JSON output to file
./nifi_connector_fetcher.sh -o json -f /tmp/connectors.json

# CSV output to file
./nifi_connector_fetcher.sh -o csv -f /tmp/connectors.csv

# Full example: non-interactive, JSON, saved to file
./nifi_connector_fetcher.sh \
  -u https://nifi-host:8443 \
  -U admin \
  -P secret \
  -o json \
  -f /var/log/nifi_connectors_$(date +%Y%m%d).json
```

---

## How It Works

```
1. Authenticate   →  POST /nifi-api/access/token
2. Fetch root     →  GET  /nifi-api/flow/process-groups/root
3. Recurse        →  GET  /nifi-api/flow/process-groups/{id}  (for every child group)
4. Filter         →  Keep only processors whose type ends in ConnectorGroupRouter or ConnectorRouter
5. Deduplicate    →  Remove any processor IDs seen more than once (guards against NiFi API overlap)
6. Display        →  Render properties in chosen format (table / json / csv)
7. Purge & Sync   →  PUT  /nifi-api/processors/{id}/run-status  (STOPPED → RUN_ONCE → RUNNING)
```

---

## Error Reference

| Message | Cause | Resolution |
|---|---|---|
| `✗ Failed to generate token` | Wrong credentials or unreachable NiFi URL | Verify `-u`, `-U`, `-P` values |
| `✗ Failed to reach NiFi (HTTP 000)` | Network or TLS issue | Check URL and network connectivity |
| `✗ Failed to fetch processor (HTTP 403)` | Token expired or insufficient permissions | Re-run to get a fresh token |
| `✗ RUN_ONCE failed (HTTP 409)` | Processor is in a conflicting state | Check NiFi UI and retry manually |
| `✗ Cannot write to output file` | Path is not writable | Check directory permissions for `-f` path |
| `✗ 'jq' is required but not installed` | `jq` missing | `sudo apt-get install jq` or `brew install jq` |