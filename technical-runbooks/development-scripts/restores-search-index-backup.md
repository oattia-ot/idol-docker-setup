# IDOL DIH Index Restore Script — Help Guide

## Overview

This script restores a search index backup on an **IDOL DIH (Distributed Index Handler)** engine — part of the OpenText / Micro Focus IDOL platform used for enterprise search and data indexing.

It performs a two-step restore operation:
1. **DREADD** — Loads the `.idx` backup file into the engine
2. **DRESYNC** — Synchronises the restored data across all child engines and mirrors

---

## Prerequisites

### Python Dependencies

Install required packages before running:

```bash
pip install requests
```

### Certificate

The script uses TLS certificate verification. Ensure the certificate bundle exists at the path defined in `get_data`:

```python
'cert_bundle': '/home/vinay/projects/ssl_nifi/code/content'
```

Update this path if your certificate is stored elsewhere.

### Backup File

Ensure the `.idx` backup file exists and is accessible on the server at the path defined in `get_data`:

```python
'backupLocation': '/data/ICICI_Bank.idx'
```

---

## Configuration

All settings are managed through the `get_data` dictionary at the top of the script. Update these values before running.

| Key | Default Value | Description |
|-----|---------------|-------------|
| `name` | `dih.idoldemos.net` | Human-readable server name (used in log output only) |
| `FQDN` | `dih.idoldemos.net` | Fully qualified domain name used in HTTP requests |
| `PORT_INDEX` | `9071` | IDOL DIH index port |
| `scheme` | `https` | Connection protocol (`http` or `https`) |
| `backupLocation` | `/data/ICICI_Bank.idx` | Absolute path to the `.idx` backup file to restore |
| `cert_bundle` | `/home/vinay/projects/ssl_nifi/code/content` | Path to the TLS certificate bundle for HTTPS verification |

### Example — Pointing to a Different Server or Backup

```python
get_data = {
    'name': 'my-idol-server.example.com',
    'FQDN': 'my-idol-server.example.com',
    'PORT_INDEX': '9071',
    'scheme': 'https',
    'backupLocation': '/data/my_backup.idx',
    'cert_bundle': '/etc/ssl/certs/ca-bundle.crt'
}
```

---

## Functions

### `restoreBackup(file, fqdn, scheme, port, certbundle)`

Executes the two-step restore process against the DIH engine.

| Parameter | Type | Description |
|-----------|------|-------------|
| `file` | `str` | Absolute path to the `.idx` backup file |
| `fqdn` | `str` | Fully qualified domain name of the DIH server |
| `scheme` | `str` | Protocol to use (`http` or `https`) |
| `port` | `str` | Port number of the DIH index service |
| `certbundle` | `str` | Path to the TLS certificate bundle |

**Step 1 — DREADD (Load Backup)**

```
GET https://<fqdn>:<port>/DREADD?<file>
```

Instructs the IDOL engine to read and load the specified `.idx` backup file into its index.

**Step 2 — DRESYNC (Synchronise)**

```
GET https://<fqdn>:<port>/DRESYNC
```

Tells the DIH to synchronise the newly restored data across all connected child engines and mirrors, ensuring consistency across the distributed system.

---

### `restoreIndex()`

A wrapper function that reads configuration from `get_data` and calls `restoreBackup()`. This is the main entry point of the script.

No parameters — all configuration is read from the global `get_data` dictionary.

**Example call:**
```python
restoreIndex()
```

---

## Execution Flow

```
restoreIndex()
    │
    ├─► Log: "Restoring index from DIH engine dih.idoldemos.net"
    │
    └─► restoreBackup('/data/ICICI_Bank.idx', ...)
            │
            ├─► GET /DREADD?/data/ICICI_Bank.idx
            │       Log: "Restoring backup /data/ICICI_Bank.idx"
            │       ← Loads the .idx backup into the engine index
            │
            └─► GET /DRESYNC
                    Log: "Syncing..."
                    ← Synchronises data across child engines
```

---

## Running the Script

```bash
python3 restore_dih_index.py
```

### Expected Console Output

```
Restoring index from DIH engine dih.idoldemos.net
Restoring backup /data/ICICI_Bank.idx
Syncing...
```

---

## Known Issues & Recommended Fixes

### 1. No Response or Error Handling

Neither the `DREADD` nor `DRESYNC` responses are checked. A failed request is silently ignored, giving a false impression of success.

**Fix:** Add status checks after each request:

```python
def restoreBackup(file, fqdn, scheme, port, certbundle):
    url_add = "{0}://{1}:{2}/DREADD?{3}".format(scheme, fqdn, port, file)
    print("Restoring backup {0}".format(file))
    response = requests.get(url_add, verify=certbundle)
    if response.status_code != 200:
        print("ERROR: DREADD failed with status {0}".format(response.status_code))
        return

    print("Syncing...")
    url_sync = "{0}://{1}:{2}/DRESYNC".format(scheme, fqdn, port)
    response = requests.get(url_sync, verify=certbundle)
    if response.status_code != 200:
        print("ERROR: DRESYNC failed with status {0}".format(response.status_code))
        return

    print("Restore complete.")
```

---

### 2. Unused `import os`

`os` is imported but never used. Remove to keep the script clean:

```python
# Remove this line
import os
```

---

### 3. Hardcoded Configuration

All settings are hardcoded in `get_data`. For a more flexible and secure setup, use environment variables or command-line arguments:

```python
import os
import argparse

parser = argparse.ArgumentParser(description='Restore IDOL DIH index backup')
parser.add_argument('--fqdn', default=os.getenv('DIH_FQDN', 'dih.idoldemos.net'))
parser.add_argument('--port', default=os.getenv('DIH_PORT', '9071'))
parser.add_argument('--backup', required=True, help='Path to .idx backup file')
parser.add_argument('--cert', required=True, help='Path to TLS certificate bundle')
args = parser.parse_args()
```

---

### 4. No Timeout on HTTP Requests

If the server is unreachable, the script will hang indefinitely.

**Fix:** Add a timeout to all requests:

```python
response = requests.get(URL, verify=certbundle, timeout=30)
```

---

## References

- [OpenText IDOL DIH Documentation](https://www.microfocus.com/documentation/idol/)
- [IDOL DREADD Action Reference](https://www.microfocus.com/documentation/idol/)
- [Python `requests` library](https://docs.python-requests.org/)