# deploy-minikube.sh – Help and Usage Guide

## Overview
`deploy-minikube.sh` is a comprehensive deployment script for managing Minikube clusters on Ubuntu 24.04. It automates the installation of prerequisites (Docker, kubectl, helm, jq), allows selection of predefined cluster profiles, and handles cluster startup, add‑on configuration, and registry secrets.

## Prerequisites
- Ubuntu 24.04 (or similar Debian‑based system)
- `sudo` privileges for the executing user
- Internet connection to download packages and container images
- The script will install missing dependencies automatically (Docker, kubectl, helm, minikube, jq).

## Command‑Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--base-path PATH` | Base directory containing `config/`, `lib/`, and where `env/` will be created. | Directory of the script |
| `--log-path PATH` | Directory where log files will be written. | `BASE_PATH/logs` |
| `--install-version VER` | Version identifier used in log file names (e.g., `1.0.0`). | `1.0.0` |
| `--profile-name NAME` | Directly use a specific profile defined in `profiles.json` (bypass interactive selection). | None |
| `--non-interactive` | Run without interactive prompts. Requires `--profile-name`. | Disabled |
| `--standalone` | Execute the full deployment (instead of just loading functions for sourcing). | Disabled |
| `--list-profiles` | List all existing Minikube clusters on the system and exit. | Disabled |
| `-h, --help` | Show this help message. | |

## Configuration File
The script reads cluster definitions from `config/profiles.json`. The file must contain a top‑level object `Minikube_Settings` with profile keys and their settings.

### Example `profiles.json`
```json
{
    "Minikube_Settings": {
        "Knowledge_Discovery": {
            "Profile_Name": "opentext-idol",
            "Memory": "8192",
            "CPUs": "4",
            "Storage": "50GB",
            "Container_Runtime": "docker",
            "Network_Policy": "calico",
            "Insecure_Registry": "myregistry.local:5000",
            "Kubernetes_Version": "stable"
        },
        "Extended_ECM": {
            "Profile_Name": "opentext-xecm",
            "Memory": "8192",
            "CPUs": "4",
            "Storage": "50GB",
            "Container_Runtime": "docker",
            "Network_Policy": "calico",
            "Insecure_Registry": "myregistry.local:5000",
            "Kubernetes_Version": "v1.35.0"
        },
        "Default": {
            "Profile_Name": "minikube",
            "Memory": "4096",
            "CPUs": "2",
            "Storage": "20GB",
            "Container_Runtime": "docker",
            "Network_Policy": "bridge",
            "Insecure_Registry": "",
            "Kubernetes_Version": "stable"
        }
    }
}
```

### Profile Fields
- **Profile_Name** – The actual Minikube cluster name (must follow Minikube naming rules: alphanumeric + dashes only, start with alphanumeric, min 2 characters).
- **Memory** – RAM in MB (e.g., `4096`).
- **CPUs** – Number of CPU cores.
- **Storage** – Disk size (e.g., `20GB`, `50GB`).
- **Container_Runtime** – `docker` or `containerd`.
- **Network_Policy** – CNI plugin (`bridge`, `calico`, `flannel`, etc.).
- **Insecure_Registry** – Optional insecure registry endpoint (e.g., `myregistry.local:5000`).
- **Kubernetes_Version** – Desired Kubernetes version (e.g., `v1.28.0`, `stable`).

## Environment Variables
After selecting a profile, the script exports settings as environment variables prefixed with `MINIKUBE_` (e.g., `MINIKUBE_MEMORY`, `MINIKUBE_CPUS`). These are written to `env/minikube_<profile_name>.env` and can be sourced for manual use.

Registry‑related variables can be set in a global `env/profile.env` file if needed:
- `REGISTRY_URL`
- `REGISTRY_PROJECT`
- `REGISTRY_USERNAME`
- `REGISTRY_PASSWORD`

## Usage Examples

### 1. Interactive deployment (choose profile from list)
```bash
./deploy-minikube.sh --standalone
```

### 2. Deploy a specific profile non‑interactively
```bash
./deploy-minikube.sh --profile-name Knowledge_Discovery --non-interactive --standalone
```

### 3. List existing Minikube clusters
```bash
./deploy-minikube.sh --list-profiles
```

### 4. Use a custom base path and log directory
```bash
./deploy-minikube.sh --base-path /opt/my-deployment --log-path /var/log/minikube --standalone
```

### 5. Source profile settings without deploying (e.g., in another script)
```bash
source ./deploy-minikube.sh --profile-name Knowledge_Discovery
# Now MINIKUBE_MEMORY, MINIKUBE_CPUS, etc. are available
```

## Exit Codes
| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error (invalid arguments, missing file, prerequisite failure) |
| 2 | Profile selection invalid or cancelled |

## Logging
Logs are written to the directory specified by `--log-path` (default `logs/`) with filenames like `deploy_minikube_<version>.log`. Each log entry is timestamped and color‑coded when viewed in a terminal.

## Directory Structure
```
.
├── deploy-minikube.sh          # Main script
├── config/
│   └── profiles.json           # Profile definitions
├── lib/
│   ├── common.sh               # Logging, helpers, validation
│   ├── prerequisites.sh        # Docker, kubectl, helm, minikube checks/install
│   ├── profile.sh              # Profile listing, selection, loading
│   └── minikube.sh             # Minikube start, addons, registry
├── env/                        # Generated environment files (created on demand)
└── logs/                       # Log files (created on demand)
```

## Notes
- The script must be executed by a user with `sudo` privileges (but not as `root`).
- If Docker is installed during the run, you may need to log out and back in for group changes to take effect.
- Minikube profile names must follow the naming rules: only lowercase alphanumeric and dashes, starting with alphanumeric.
- The script checks for existing clusters and will not start a new one if a cluster with the same name is already running.

## Troubleshooting
- **"Profile name is not valid"** – Ensure the `Profile_Name` field in your JSON contains only alphanumeric characters and dashes, and is at least 2 characters long.
- **"jq: command not found"** – The script will attempt to install jq automatically; if it fails, install it manually with `sudo apt install jq`.
- **"Docker daemon not responding"** – Verify Docker is running with `sudo systemctl status docker`. If not, start it with `sudo systemctl start docker`.

## See Also
- [Minikube documentation](https://minikube.sigs.k8s.io/docs/)
- [Kubernetes documentation](https://kubernetes.io/docs/home/)