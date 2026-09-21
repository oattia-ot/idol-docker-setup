````md
# build-docker-image.sh

Quick Usage Summary

Zero-config Bash script that automatically turns `.zip` application packages into Docker images.

Scans a directory → extracts ZIPs → generates Dockerfile → builds image → either saves as `.tar` or loads into Docker daemon.

---

# Quick Start

```bash
# 1. Make script executable
chmod +x build-docker-image.sh

# 2. Put your .zip files here
mkdir -p input-files
cp your-app-26.1.0_LINUX_X86_64.zip input-files/

# 3. Run
./build-docker-image.sh
````

---

# Configuration Options

| Option            | Short | Description                               | Default         | Env Variable            |
| ----------------- | ----- | ----------------------------------------- | --------------- | ----------------------- |
| `--dir <path>`    | `-d`  | Folder with `.zip` files                  | `input-files/`  | `DOCKER_SCAN_DIR`       |
| `--output <path>` | `-o`  | Where `.tar` files are saved              | `output-image/` | `DOCKER_OUTPUT_DIR`     |
| `--load`          | `-i`  | Load into Docker instead of saving `.tar` | `false`         | `DOCKER_LOAD_MODE=true` |
| `--prefix <name>` | `-n`  | Registry prefix (`myrepo/`)               | none            | `DOCKER_IMAGE_PREFIX`   |
| `--tag <tag>`     | `-t`  | Image tag                                 | `latest`        | `DOCKER_IMAGE_TAG`      |
| `--port <number>` | `-p`  | `EXPOSE` port in Dockerfile               | `9100`          | `DOCKER_EXPOSE_PORT`    |

Priority order:

```text
CLI flags > Environment variables > Interactive prompt > Defaults
```

---

# Examples

## Default, save `.tar` files

```bash
./build-docker-image.sh
```

## Load directly into Docker

```bash
./build-docker-image.sh --load
```

## Full custom example

```bash
./build-docker-image.sh \
  --dir ./zips \
  --prefix mycompany \
  --tag 26.1.0 \
  --port 8080
```

## CI/CD style

```bash
DOCKER_IMAGE_PREFIX=mycompany \
DOCKER_IMAGE_TAG=26.1.0 \
DOCKER_LOAD_MODE=true \
./build-docker-image.sh
```

---

# Image Naming

```text
Content_26.1.0_LINUX_X86_64.zip
→ content-26.1.0-linux-x86-64
```

With prefix and tag:

```text
mycompany/content-26.1.0-linux-x86-64:26.1.0
```

Saved file:

```text
output-image/content-26.1.0-linux-x86-64.tar
```

---

# Run the Image

## After `--load`

```bash
docker run -d -p 9100:9100 content-26.1.0-linux-x86-64
```

## After loading `.tar`

```bash
docker load -i output-image/content-26.1.0-linux-x86-64.tar

docker run -d -p 9100:9100 content-26.1.0-linux-x86-64
```

---

# Recommended Folder Structure

```text
.
├── build-docker-image.sh
├── input-files/          # your .zip files go here
├── output-image/         # .tar files saved here
└── build-docker-image.md
```

