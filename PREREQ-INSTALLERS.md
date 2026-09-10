# Prerequisite installer overlay

This overlay adds dedicated Phase 2 installers and updates the related docs.

## New scripts

| Path | Role |
|---|---|
| `utilities/docker-setup/install-prereqs.sh` | Detects Ubuntu vs macOS and execs the matching installer |
| `utilities/docker-setup/install-ubuntu-prereqs.sh` | `apt` + systemd: Docker Engine, Compose plugin, OpenJDK 21, OpenSSL, jq, git, curl, python3 |
| `utilities/docker-setup/install-macos-prereqs.sh` | Homebrew + Docker Desktop: same tools, no `apt`/`systemctl` |
| `utilities/docker-setup/README.md` | How to run the installers |

```bash
./utilities/docker-setup/install-prereqs.sh
sudo ./utilities/docker-setup/install-ubuntu-prereqs.sh
./utilities/docker-setup/install-macos-prereqs.sh
./utilities/docker-setup/install-prereqs.sh --verify-only
# optional helm / kubectl / minikube / ghostscript:
./utilities/docker-setup/install-prereqs.sh --with-optional
```

## Updated markdown

- `README.md` — Phase 2 now starts with the OS-specific scripts
- `OS-COMPAT.md` — installer table and commands
- `utilities/ui-config/DEPLOYMENT.md`
- `utilities/minikube-setup/setup-minikube.md`
- `utilities/harbor-setup/install-harbor.md`
- `PREREQ-INSTALLERS.md` — this file
