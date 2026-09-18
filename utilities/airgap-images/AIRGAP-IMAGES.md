# Air-gap image packer — usage guide

`airgap-images.sh` pulls images from the registry, exports them to `./airgap-bundle`, and later loads them on a host with no internet.

Default local folder:

```text
./airgap-bundle/
  images/idol/      OpenText / microfocusidolserver images
  images/public/    public images (httpd, postgres, ollama, ...)
  images/local/     images built on this machine
  models/           optional .gguf files
  manifest.txt
  offline.env
```

---

## Mandatory prerequisite

**Source `pre-setup.sh` in the same shell before every run.**

```bash
source ./pre-setup.sh
```

Do not use `./pre-setup.sh` or `bash pre-setup.sh`. Only `source` loads version tags into the current shell.

Check that placeholders are gone:

```bash
echo "SERVER=${IDOL_SERVER_VERSION}"
echo "DATA_ADMIN=${IDOL_DATA_ADMIN_VERSION}"
echo "RICH_MEDIA=${IDOL_RICH_MEDIA_VERSION}"
```

A new terminal means you must `source ./pre-setup.sh` again.

---

## Interactive menu (recommended)

Running the script with no command opens the menu. Default selections are **all stacks** and **all images**.

```bash
source ./pre-setup.sh
export IDOL_LICENSE_KEY_TOKEN='dckr_pat_YOUR_TOKEN'
chmod +x ./airgap-images.sh
./airgap-images.sh
```

### Step 0 — saved-images folder (asked first)

Before stacks and actions, the menu asks:

```text
Where should images be saved / loaded from?
Path [<script-dir>/airgap-bundle]:
```

- Press Enter to keep the default (`./airgap-bundle` next to the script).
- Type any other path (`~/idol-offline`, `/media/usb/idol-images`, …).

Skip the question by passing the folder as an argument:

```bash
./airgap-images.sh --bundle ./airgap-bundle
./airgap-images.sh menu -o /media/usb/idol-images
./airgap-images.sh bundle --bundle /opt/idol/airgap-bundle --stacks all --gzip
```

`AIRGAP_BUNDLE_DIR` can set the default shown in the prompt. `--bundle` / `-o` wins and does not prompt.

### Step 1 — select stacks

```text
[0]  ALL stacks (default)          <-- press Enter
[1]  basic-idol
[2]  data-admin
[3]  rich-media
[4]  license-server
[5]  llm
[6]  wiki
[7]  nifi-registry
[8]  mmap-basic
[9]  docsec
[c]  deploy-core
[d]  data-admin-full
```

Examples:

- Enter or `0` → every stack
- `2` → data-admin only
- `1,3,5` → basic-idol + rich-media + llm
- `c` → deploy-core

### Step 2 — select images

The menu lists every image in the stacks you picked.

- Enter or `0` → **all images** in those stacks (default)
- `1,4,7` → only those numbered images

### Step 3 — select action

| # | Action | Meaning |
|---|---|---|
| **1** | Download from registry | `docker pull` (needs internet + PAT) |
| **2** | Upload / export to local folder | `docker save` into `./airgap-bundle` |
| **3** | Download then export (bundle) | **Best default on the init host** |
| **4** | Load into Docker from local folder | `docker load` on the air-gapped host |
| **5** | List resolved images | no download |
| **6** | Verify images exist locally | no download |
| **7** | Copy GGUF models into the bundle | optional |

For save/bundle the menu then asks whether to gzip tars (default Yes).

### Typical init-host path

1. `source ./pre-setup.sh`
2. `./airgap-images.sh`
3. Stacks: Enter (all)
4. Images: Enter (all)
5. Action: Enter or `3` (download then export)
6. Gzip: Enter (yes)

Copy `./airgap-bundle` to the isolated machine.

### Typical air-gapped path

1. `source ./pre-setup.sh`
2. `./airgap-images.sh`
3. Stacks: Enter (all)
4. Images: Enter (all)
5. Action: `4` (load from local folder)
6. `source ./airgap-bundle/offline.env`
7. Run the subtype `deploy.sh`

---

## Non-interactive commands

Same prerequisite: `source ./pre-setup.sh`.

```bash
./airgap-images.sh list --stacks all --bundle ./airgap-bundle
./airgap-images.sh pull --stacks data-admin
./airgap-images.sh save --stacks data-admin --gzip --bundle ./airgap-bundle
./airgap-images.sh bundle --stacks all --gzip --bundle ./airgap-bundle
./airgap-images.sh load --bundle ./airgap-bundle
./airgap-images.sh verify --stacks all
```

`--stacks` accepts the same names as the menu (`all`, `deploy-core`, `data-admin-full`, or a comma list).

---

## Flags

```text
--stacks S1,S2,...
--bundle DIR | -o DIR     saved-images folder (skips the path question)
--env-file PATH
--server-version TAG
--data-admin-version TAG
--rich-media-version TAG
--gzip
--skip-login
--skip-pull
--force
--allow-placeholders
```

After `source pre-setup.sh`, version flags are usually unnecessary.

---

## Common mistakes

1. Forgot `source ./pre-setup.sh` — tags stay placeholders; pull/save/bundle abort.
2. Ran `./pre-setup.sh` instead of `source`.
3. New terminal without sourcing again.
4. Missing `IDOL_LICENSE_KEY_TOKEN` for IDOL registry images.
5. Local-only images (`licenseserver:latest`, `obsidian-custom:latest`) are never pulled; build them first if needed.

---

## Checklist

**Init (online)**

```bash
source ./pre-setup.sh
export IDOL_LICENSE_KEY_TOKEN='dckr_pat_...'
./airgap-images.sh          # menu: all / all / 3 bundle / gzip yes
# copy ./airgap-bundle to the isolated host
```

**Target (offline)**

```bash
source ./pre-setup.sh
./airgap-images.sh          # menu: all / all / 4 load
source ./airgap-bundle/offline.env
./airgap-images.sh verify --stacks all
```
