# Host OS compatibility — Ubuntu and macOS

All setup scripts now detect whether they are running on **Ubuntu/Linux** or **macOS** and branch package installs, service control, and GNU vs BSD command syntax.

## How detection works

1. Every `.sh` file loads a short bootstrap that looks for `module/os-compat.sh` (from `IDOL_BASE_PATH` or by walking up from the script).
2. That module exports:

| Variable | Values |
|---|---|
| `IDOL_HOST_OS` | `ubuntu` · `debian` · `linux` · `macos` · `unknown` |
| `IDOL_OS_FAMILY` | `linux` · `macos` · `unknown` |
| `IDOL_OS_PRETTY` | e.g. `Ubuntu 24.04.4 LTS` or `macOS 15.1` |
| `IDOL_PKG_MGR` | `apt` · `brew` · `none` |
| `IDOL_ARCH` | `x86_64` · `arm64` · `aarch64` · … |

3. Shared helpers (used by `prepare-env.sh`, Docker setup, minikube, Harbor, ownership fix, etc.):

- `idol_pkg_install` / `idol_pkg_update` — `apt-get` on Ubuntu, Homebrew on macOS
- `idol_install_docker` — Docker Engine + systemd on Ubuntu; Docker Desktop cask on macOS
- `idol_install_docker_compose` / `idol_install_java21` / `idol_install_kubectl` / `idol_install_minikube`
- `idol_service_start` / `status` / `enable` — `systemctl` on Linux; Docker.app on macOS
- `idol_sed_inplace` — portable in-place `sed` (GNU `-i` vs BSD `-i ''`)
- `idol_stat_owner` · `idol_sha256` · `idol_realpath` · `idol_host_ip` · `idol_nproc` · `idol_mem_info` · `idol_to_lower`

Scripts that already `source module/general-utilities.code` get the module automatically.

## Phase 2 prerequisite installers

Use one script per OS. A thin wrapper detects the host and calls the right one.

```bash
# Auto-detect
./utilities/docker-setup/install-prereqs.sh

# Ubuntu / Debian
sudo ./utilities/docker-setup/install-ubuntu-prereqs.sh
sudo ./utilities/docker-setup/install-ubuntu-prereqs.sh --with-optional
./utilities/docker-setup/install-ubuntu-prereqs.sh --verify-only

# macOS
./utilities/docker-setup/install-macos-prereqs.sh
./utilities/docker-setup/install-macos-prereqs.sh --with-optional
./utilities/docker-setup/install-macos-prereqs.sh --verify-only
```

| Script | Installs |
|---|---|
| `install-ubuntu-prereqs.sh` | `apt` packages: Docker Engine + Compose plugin, OpenJDK 21, OpenSSL, jq, git, curl, python3. Enables `docker` via systemd and adds the user to the `docker` group. |
| `install-macos-prereqs.sh` | Homebrew, Docker Desktop cask, OpenJDK 21, OpenSSL, jq, git, curl, bash 5, python3. Starts Docker.app and waits for the engine. |

`--with-optional` adds helm, kubectl, minikube, and ghostscript.

Then run the same entry points on either OS:

```bash
export IDOL_BASE_PATH="$PWD"
./utilities/ui-config/deploy-setup-manager-ui.sh --deploy
# configure in the UI, then:
./prepare-env.sh --setup-prerequisites
./init-setup.sh
```

## What still runs as Linux

IDOL containers, Helm hooks, and NiFi entrypoints execute **inside Linux images**. Those scripts still detect the *container* OS (`linux`/`ubuntu`). The host-side installer is what needed macOS branches (apt vs brew, systemd vs Docker Desktop, `sed -i`, `stat -c`, `hostname -I`, `truncate`, `/usr/bin` symlinks).

## Notes

- Docker Desktop on Apple silicon runs `linux/arm64` containers by default. Official IDOL images are typically `linux/amd64` — enable Rosetta / emulate amd64 if a service will not start (`docker pull --platform linux/amd64 …`).
- `chmod 666 /var/run/docker.sock` and `usermod -aG docker` are skipped on macOS (Docker Desktop owns the socket).
- `utilities/docker-setup/setup_docker_systemd_service.sh`, `fix_docker.sh`, and `check_containerd.sh` no-op on macOS and print guidance to use Docker Desktop.
- macOS `/bin/bash` is 3.2. Prefer Homebrew bash (`brew install bash`) if you hit `mapfile` / globstar issues in a few utility scripts.
