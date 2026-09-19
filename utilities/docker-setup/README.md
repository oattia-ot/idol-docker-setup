# Host prerequisite installers

These scripts install **Phase 2** tools from the root README so `prepare-env.sh` / `init-setup.sh` can run on either Ubuntu or macOS.

| Script | Host | What it installs |
|---|---|---|
| `install-prereqs.sh` | auto-detect | Calls the Ubuntu or macOS script below |
| `install-ubuntu-prereqs.sh` | Ubuntu / Debian | Docker Engine + Compose plugin, OpenJDK 21, OpenSSL, jq, git, curl, python3. Adds `$USER` to the `docker` group and enables systemd units. |
| `install-macos-prereqs.sh` | macOS (Intel / Apple silicon) | Homebrew, Docker Desktop, OpenJDK 21, OpenSSL, jq, git, curl, bash 5, python3. Does **not** use `apt` or `systemctl`. |

Optional extras (`helm`, `kubectl`, `minikube`, `ghostscript`) are off by default. Pass `--with-optional` to include them.

## Quick start

```bash
cd /path/to/idol-docker-setup

# Auto-detect host OS
./utilities/docker-setup/install-prereqs.sh

# Or pick the OS explicitly
sudo ./utilities/docker-setup/install-ubuntu-prereqs.sh
./utilities/docker-setup/install-macos-prereqs.sh

# Check only
./utilities/docker-setup/install-prereqs.sh --verify-only
```

On Ubuntu the installer must run with `sudo` (package + systemd changes). On macOS run it as your normal user; Homebrew will prompt for a password when needed.

## After install

```bash
export IDOL_BASE_PATH="$PWD"
./utilities/ui-config/deploy-setup-manager-ui.sh --deploy
./prepare-env.sh --setup-prerequisites
./init-setup.sh
```

See also `OS-COMPAT.md` at the repository root.
