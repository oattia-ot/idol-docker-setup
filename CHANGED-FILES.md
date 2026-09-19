# Updated files only

Overlay of every file changed for Ubuntu + macOS host support and the Phase 2 installers.

## New
- `module/os-compat.sh`
- `utilities/docker-setup/install-prereqs.sh` (auto-detect)
- `utilities/docker-setup/install-ubuntu-prereqs.sh`
- `utilities/docker-setup/install-macos-prereqs.sh`
- `utilities/docker-setup/README.md`
- `OS-COMPAT.md`
- `PREREQ-INSTALLERS.md`

## Updated markdown
- `README.md`
- `utilities/ui-config/DEPLOYMENT.md`
- `utilities/minikube-setup/setup-minikube.md`
- `utilities/harbor-setup/install-harbor.md`

Unpack over an existing `idol-docker-setup` clone:

```bash
unzip -o idol-docker-setup-updated-files-only.zip -d /path/to/parent
```
