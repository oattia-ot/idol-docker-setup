#!/usr/bin/env bash
# =============================================================================
# airgap-images.sh
# Prepare, save, and load Docker images (and optional GGUF models) so IDOL
# deploy.sh stacks can run without internet.
#
# Version tags are GENERIC. They are never hard-coded to 24.3 / 26.1 / etc.
# Resolve them from (highest priority last):
#   1) discovered .env / .env-template / pre-setup.sh files
#   2) process environment
#   3) --env-file PATH
#   4) CLI flags  --server-version / --data-admin-version / --rich-media-version
#
# Placeholder values such as SETUP-SERVER-VERSION-PLACEHOLDER are rejected
# before pull/save/bundle.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Colors (tput only; empty when stdout is not a TTY)
# -----------------------------------------------------------------------------
RED="" GREEN="" YELLOW="" BLUE="" CYAN="" BOLD="" DIM="" NC=""
if [[ -t 1 && -z "${NO_COLOR:-}" ]] && command -v tput >/dev/null 2>&1; then
  RED="$(tput setaf 1 2>/dev/null || true)"
  GREEN="$(tput setaf 2 2>/dev/null || true)"
  YELLOW="$(tput setaf 3 2>/dev/null || true)"
  BLUE="$(tput setaf 4 2>/dev/null || true)"
  CYAN="$(tput setaf 6 2>/dev/null || true)"
  BOLD="$(tput bold 2>/dev/null || true)"
  DIM="$(tput dim 2>/dev/null || true)"
  NC="$(tput sgr0 2>/dev/null || true)"
fi

log()     { printf "%s[INFO]%s %s\n" "$CYAN" "$NC" "$*"; }
ok()      { printf "%s[OK]%s %s\n" "$GREEN" "$NC" "$*"; }
warn()    { printf "%s[WARN]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()     { printf "%s[ERROR]%s %s\n" "$RED" "$NC" "$*" >&2; }
step()    { printf "\n%s-- %s --%s\n" "${BOLD}${BLUE}" "$*" "$NC"; }
die()     { err "$*"; exit 1; }

hdr()  { printf "%s%s%s\n" "${BOLD}${CYAN}" "$1" "$NC"; }
note() { printf "%s%s%s\n" "${DIM}" "$1" "$NC"; }
cmdl() { printf "  %s%-22s%s %s\n" "${GREEN}" "$1" "$NC" "$2"; }
optl() { printf "  %s%-22s%s %s\n" "${YELLOW}" "$1" "$NC" "$2"; }
envl() { printf "  %s%-28s%s %s\n" "${BLUE}" "$1" "$NC" "$2"; }

# -----------------------------------------------------------------------------
# Paths / flags  (version vars stay empty until resolve_versions)
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="${AIRGAP_BUNDLE_DIR:-${SCRIPT_DIR}/airgap-bundle}"
MODEL_SRC_DIR="${IDOL_LLM_MODEL_PATH:-${HOME}/llm-models}"
DEFAULT_MODELS_JSON="${DEFAULT_MODELS_JSON:-}"
ENV_FILE_CLI=""

GZIP_TARS=false
SKIP_LOGIN=false
SKIP_PULL=false
FORCE=false
ALLOW_PLACEHOLDERS=false
BUNDLE_DIR_FROM_CLI=false
SELECTED_STACKS=""
COMMAND=""
IMAGE_FILTER=()
STACKS_RESOLVED=()

# CLI overrides (empty = not passed)
CLI_REGISTRY=""
CLI_SERVER_VERSION=""
CLI_DATA_ADMIN_VERSION=""
CLI_RICH_MEDIA_VERSION=""
CLI_MMAP_APP_BASIC=""
CLI_MMAP_APP_RICH=""
CLI_OPENWEBUI=""
CLI_HTTPD=""
CLI_POSTGRES=""
CLI_UBUNTU=""
CLI_OLLAMA=""
CLI_OBSIDIAN=""
CLI_NIFI_REG=""

# Resolved values
IDOL_REGISTRY="${IDOL_REGISTRY:-}"
IDOL_SERVER_VERSION="${IDOL_SERVER_VERSION:-}"
IDOL_DATA_ADMIN_VERSION="${IDOL_DATA_ADMIN_VERSION:-}"
IDOL_RICH_MEDIA_VERSION="${IDOL_RICH_MEDIA_VERSION:-}"
MMAP_APP_BASIC_TAG="${MMAP_APP_BASIC_TAG:-}"
MMAP_APP_RICH_TAG="${MMAP_APP_RICH_TAG:-}"
OPENWEBUI_IMAGE="${OPENWEBUI_IMAGE:-}"
HTTPD_IMAGE="${HTTPD_IMAGE:-}"
POSTGRES_IMAGE="${POSTGRES_IMAGE:-}"
UBUNTU_IMAGE="${UBUNTU_IMAGE:-}"
OLLAMA_IMAGE="${OLLAMA_IMAGE:-}"
OBSIDIAN_IMAGE="${OBSIDIAN_IMAGE:-}"
NIFI_REGISTRY_IMAGE="${NIFI_REGISTRY_IMAGE:-}"

# Public-image fallbacks (not IDOL placeholders; overridable)
PUBLIC_HTTPD_DEFAULT="httpd:2.4"
PUBLIC_POSTGRES_DEFAULT="postgres:11-alpine"
PUBLIC_UBUNTU_DEFAULT="ubuntu:22.04"
PUBLIC_OLLAMA_DEFAULT="ollama/ollama:latest"
PUBLIC_OPENWEBUI_DEFAULT="ghcr.io/open-webui/open-webui:v0.11.3"
PUBLIC_OBSIDIAN_DEFAULT="lscr.io/linuxserver/obsidian:latest"
PUBLIC_NIFI_REG_DEFAULT="apache/nifi-registry:latest"

usage() {
  printf "%s%sairgap-images.sh%s %s-- offline image packer / loader for IDOL deploy.sh stacks%s\n\n" \
    "$BOLD" "$CYAN" "$NC" "$DIM" "$NC"

  hdr "COMMANDS"
  cmdl "list"         "Print resolved image lists per stack"
  cmdl "pull"         "docker login (IDOL) + docker pull selected images"
  cmdl "save"         "docker save already-local images into the bundle"
  cmdl "bundle"       "pull + save (init host, needs internet)"
  cmdl "load"         "docker load every tar in the bundle (air-gapped host)"
  cmdl "verify"       "Check that every required image exists locally"
  cmdl "models-copy"  "Copy existing GGUF files into bundle/models"
  cmdl "menu"         "Interactive stack / image / action picker (default)"
  cmdl "help"         "This message"
  printf "\n"

  hdr "OPTIONS"
  optl "--stacks S1,S2"            "Stacks (default: all)"
  optl "--bundle DIR, -o DIR"      "Saved-images folder (skips the path question)"
  optl "--env-file PATH"           "Load KEY=VAL file (after auto-discovery)"
  optl "--server-version TAG"      "Sets IDOL_SERVER_VERSION"
  optl "--data-admin-version TAG"  "Sets IDOL_DATA_ADMIN_VERSION"
  optl "--rich-media-version TAG"  "Sets IDOL_RICH_MEDIA_VERSION"
  optl "--mmap-app-basic TAG"      "mmap_app tag for mmap-basic overlay"
  optl "--mmap-app-rich TAG"       "mmap_app tag for rich-media"
  optl "--registry NAME"           "IDOL registry (default: microfocusidolserver)"
  optl "--gzip"                    "gzip tars after save"
  optl "--skip-login"              "Do not docker login"
  optl "--skip-pull"               "On bundle: save only"
  optl "--force"                   "Overwrite existing tars"
  optl "--allow-placeholders"      "Do not abort if a tag still looks like a placeholder"
  optl "-h, --help"                "Show this help"
  printf "\n"

  hdr "STACKS"
  printf "  %sbasic-idol data-admin rich-media license-server%s\n" "$GREEN" "$NC"
  printf "  %sllm wiki nifi-registry mmap-basic docsec%s\n" "$GREEN" "$NC"
  optl "all"             "every stack above"
  optl "deploy-core"     "basic-idol,data-admin,rich-media,license-server"
  optl "data-admin-full" "data-admin,llm,wiki"
  printf "\n"

  hdr "VERSION RESOLUTION (generic, no baked-in IDOL tags)"
  note "  Auto-loads the first readable file among:"
  note "    ./pre-setup.sh  ./.env  ./.env-template"
  note "    ../pre-setup.sh  sibling template .env-template files"
  note "  Then applies process env, --env-file, and CLI flags."
  note "  Values containing PLACEHOLDER / SETUP- / FIXME are rejected"
  note "  on pull/save/bundle unless --allow-placeholders is set."
  printf "\n"

  hdr "ENV"
  envl "IDOL_REGISTRY"              "default: microfocusidolserver"
  envl "IDOL_SERVER_VERSION"        "required for basic-idol / data-admin"
  envl "IDOL_DATA_ADMIN_VERSION"    "falls back to IDOL_SERVER_VERSION"
  envl "IDOL_RICH_MEDIA_VERSION"    "required for rich-media / mmap-basic"
  envl "MMAP_APP_BASIC_TAG"         "falls back to IDOL_RICH_MEDIA_VERSION or SERVER"
  envl "MMAP_APP_RICH_TAG"          "falls back to IDOL_RICH_MEDIA_VERSION"
  envl "IDOL_LICENSE_KEY_TOKEN"     "Docker Hub PAT (dckr_pat_...)"
  envl "IDOL_LLM_MODEL_PATH"        "GGUF directory to copy"
  envl "AIRGAP_BUNDLE_DIR"          "bundle output/input directory"
  envl "HTTPD_IMAGE"                "override public httpd image"
  envl "POSTGRES_IMAGE"             "override public postgres image"
  envl "OPENWEBUI_IMAGE"            "override Open WebUI image"
  printf "\n"

  hdr "LOCAL FOLDER"
  printf "  Images:  %s%s/images/{idol,public,local}%s\n" "$YELLOW" "${BUNDLE_DIR}" "$NC"
  printf "  Models:  %s%s/models%s\n\n" "$YELLOW" "${BUNDLE_DIR}" "$NC"

  hdr "EXAMPLES"
  note "  # Tags come from your env / pre-setup.sh"
  printf "  %sIDOL_LICENSE_KEY_TOKEN=dckr_pat_xxx \\%s\n" "$GREEN" "$NC"
  printf "    %s%s bundle --stacks all --gzip --bundle ./airgap-bundle%s\n\n" "$GREEN" "$(basename "$0")" "$NC"
  note "  # Or pass tags explicitly (any release)"
  printf "  %s%s bundle --stacks deploy-core --gzip \\%s\n" "$GREEN" "$(basename "$0")" "$NC"
  printf "    %s--server-version 25.4 --data-admin-version 25.4 --rich-media-version 26.2%s\n\n" "$GREEN" "$NC"
  note "  # Load an existing generated .env"
  printf "  %s%s bundle --env-file ./basic-idol/template-script/.env --stacks basic-idol%s\n\n" "$GREEN" "$(basename "$0")" "$NC"
  note "  # Air-gapped host"
  printf "  %s%s load --bundle ./airgap-bundle%s\n" "$GREEN" "$(basename "$0")" "$NC"
  printf "  %s%s verify --stacks all%s\n" "$GREEN" "$(basename "$0")" "$NC"
}

# -----------------------------------------------------------------------------
# Version / env loading
# -----------------------------------------------------------------------------
is_placeholder() {
  local v="${1:-}"
  [[ -z "$v" ]] && return 1
  [[ "$v" == *PLACEHOLDER* || "$v" == *SETUP-* || "$v" == *FIXME* || "$v" == *TODO* || "$v" == "changeme" ]]
}

# Source KEY=VAL lines without executing the rest of a script.
# Accepts export KEY=VAL and KEY=VAL. Ignores comments and functions.
ingest_kv_file() {
  local file="$1"
  [[ -f "$file" && -r "$file" ]] || return 1
  log "Loading key/values from $file"
  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[2]}"
      val="${BASH_REMATCH[3]}"
      val="${val%\"}"
      val="${val#\"}"
      val="${val%\'}"
      val="${val#\'}"
      case "$key" in
        IDOL_REGISTRY|IDOL_SERVER_VERSION|IDOL_DATA_ADMIN_VERSION|IDOL_RICH_MEDIA_VERSION| \
        MMAP_APP_BASIC_TAG|MMAP_APP_RICH_TAG|IDOL_LICENSE_KEY_TOKEN|IDOL_LLM_MODEL_PATH| \
        AIRGAP_BUNDLE_DIR|HTTPD_IMAGE|POSTGRES_IMAGE|UBUNTU_IMAGE|OLLAMA_IMAGE| \
        OPENWEBUI_IMAGE|OPENWEBUI_TAG|OBSIDIAN_IMAGE|NIFI_REGISTRY_IMAGE)
          if [[ -z "${!key:-}" ]] || is_placeholder "${!key:-}"; then
            printf -v "$key" '%s' "$val"
            export "$key"
          fi
          ;;
      esac
    fi
  done < "$file"
}

discover_env_files() {
  local candidates=(
    "${PWD}/pre-setup.sh"
    "${PWD}/.env"
    "${PWD}/.env-template"
    "${SCRIPT_DIR}/pre-setup.sh"
    "${SCRIPT_DIR}/.env"
    "${SCRIPT_DIR}/.env-template"
    "${SCRIPT_DIR}/../pre-setup.sh"
    "${PWD}/templates/basic-idol/template-script/.env-template"
    "${PWD}/templates/data-admin/template-script/.env-template"
    "${PWD}/templates/rich-media/template-script/.env-template"
    "${SCRIPT_DIR}/templates/basic-idol/template-script/.env-template"
    "${SCRIPT_DIR}/templates/data-admin/template-script/.env-template"
    "${SCRIPT_DIR}/templates/rich-media/template-script/.env-template"
  )
  local f
  for f in "${candidates[@]}"; do
    [[ -f "$f" ]] && ingest_kv_file "$f" || true
  done
}

pick_first_real() {
  local v
  for v in "$@"; do
    if [[ -n "$v" ]] && ! is_placeholder "$v"; then
      printf '%s' "$v"
      return 0
    fi
  done
  # last non-empty even if placeholder (caller decides)
  for v in "$@"; do
    [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }
  done
  return 0
}

resolve_versions() {
  discover_env_files
  if [[ -n "$ENV_FILE_CLI" ]]; then
    ingest_kv_file "$ENV_FILE_CLI" || die "Cannot read --env-file $ENV_FILE_CLI"
  fi

  IDOL_REGISTRY="$(pick_first_real \
    "$CLI_REGISTRY" "${IDOL_REGISTRY:-}" "microfocusidolserver")"

  IDOL_SERVER_VERSION="$(pick_first_real \
    "$CLI_SERVER_VERSION" "${IDOL_SERVER_VERSION:-}")"

  IDOL_DATA_ADMIN_VERSION="$(pick_first_real \
    "$CLI_DATA_ADMIN_VERSION" "${IDOL_DATA_ADMIN_VERSION:-}" "${IDOL_SERVER_VERSION:-}")"

  IDOL_RICH_MEDIA_VERSION="$(pick_first_real \
    "$CLI_RICH_MEDIA_VERSION" "${IDOL_RICH_MEDIA_VERSION:-}")"

  MMAP_APP_BASIC_TAG="$(pick_first_real \
    "$CLI_MMAP_APP_BASIC" "${MMAP_APP_BASIC_TAG:-}" \
    "${IDOL_RICH_MEDIA_VERSION:-}" "${IDOL_SERVER_VERSION:-}")"

  MMAP_APP_RICH_TAG="$(pick_first_real \
    "$CLI_MMAP_APP_RICH" "${MMAP_APP_RICH_TAG:-}" \
    "${IDOL_RICH_MEDIA_VERSION:-}" "${IDOL_SERVER_VERSION:-}")"

  HTTPD_IMAGE="$(pick_first_real "$CLI_HTTPD" "${HTTPD_IMAGE:-}" "$PUBLIC_HTTPD_DEFAULT")"
  POSTGRES_IMAGE="$(pick_first_real "$CLI_POSTGRES" "${POSTGRES_IMAGE:-}" "$PUBLIC_POSTGRES_DEFAULT")"
  UBUNTU_IMAGE="$(pick_first_real "$CLI_UBUNTU" "${UBUNTU_IMAGE:-}" "$PUBLIC_UBUNTU_DEFAULT")"
  OLLAMA_IMAGE="$(pick_first_real "$CLI_OLLAMA" "${OLLAMA_IMAGE:-}" "$PUBLIC_OLLAMA_DEFAULT")"
  OBSIDIAN_IMAGE="$(pick_first_real "$CLI_OBSIDIAN" "${OBSIDIAN_IMAGE:-}" "$PUBLIC_OBSIDIAN_DEFAULT")"
  NIFI_REGISTRY_IMAGE="$(pick_first_real "$CLI_NIFI_REG" "${NIFI_REGISTRY_IMAGE:-}" "$PUBLIC_NIFI_REG_DEFAULT")"

  if [[ -n "$CLI_OPENWEBUI" ]]; then
    OPENWEBUI_IMAGE="$CLI_OPENWEBUI"
  elif [[ -n "${OPENWEBUI_IMAGE:-}" ]] && ! is_placeholder "$OPENWEBUI_IMAGE"; then
    :
  elif [[ -n "${OPENWEBUI_TAG:-}" ]] && ! is_placeholder "$OPENWEBUI_TAG"; then
    OPENWEBUI_IMAGE="ghcr.io/open-webui/open-webui:${OPENWEBUI_TAG}"
  else
    OPENWEBUI_IMAGE="$PUBLIC_OPENWEBUI_DEFAULT"
  fi

  export IDOL_REGISTRY IDOL_SERVER_VERSION IDOL_DATA_ADMIN_VERSION IDOL_RICH_MEDIA_VERSION
  export MMAP_APP_BASIC_TAG MMAP_APP_RICH_TAG
  export HTTPD_IMAGE POSTGRES_IMAGE UBUNTU_IMAGE OLLAMA_IMAGE OPENWEBUI_IMAGE OBSIDIAN_IMAGE NIFI_REGISTRY_IMAGE
}

require_tags_for_stacks() {
  $ALLOW_PLACEHOLDERS && return 0
  local s missing=()
  for s in "$@"; do
    case "$s" in
      basic-idol|data-admin)
        [[ -n "${IDOL_SERVER_VERSION:-}" ]] && ! is_placeholder "$IDOL_SERVER_VERSION" \
          || missing+=("IDOL_SERVER_VERSION (needed by $s)")
        ;;
    esac
    case "$s" in
      data-admin)
        [[ -n "${IDOL_DATA_ADMIN_VERSION:-}" ]] && ! is_placeholder "$IDOL_DATA_ADMIN_VERSION" \
          || missing+=("IDOL_DATA_ADMIN_VERSION (needed by $s)")
        ;;
      rich-media|mmap-basic)
        [[ -n "${IDOL_RICH_MEDIA_VERSION:-}" ]] && ! is_placeholder "$IDOL_RICH_MEDIA_VERSION" \
          || missing+=("IDOL_RICH_MEDIA_VERSION (needed by $s)")
        ;;
    esac
  done
  if ((${#missing[@]} > 0)); then
    err "Unresolved version tags (placeholders or empty):"
    local m
    for m in "${missing[@]}"; do
      err "  - $m"
    done
    err "Pass --server-version / --data-admin-version / --rich-media-version"
    err "or export them, or use --env-file pointing at a resolved .env"
    die "Refusing to pull/save with unresolved tags"
  fi
}

display_tag() {
  local v="$1"
  if [[ -z "$v" ]]; then
    printf '%sunset%s' "$RED" "$NC"
  elif is_placeholder "$v"; then
    printf '%s%s (placeholder)%s' "$YELLOW" "$v" "$NC"
  else
    printf '%s%s%s' "$GREEN" "$v" "$NC"
  fi
}

# -----------------------------------------------------------------------------
# Image catalogs
# -----------------------------------------------------------------------------
IMAGES=()

add_img() {
  local kind="$1" image="$2"
  IMAGES+=("${kind} ${image}")
}

idol() { add_img auth "${IDOL_REGISTRY}/$1"; }

stack_basic_idol() {
  idol "content:${IDOL_SERVER_VERSION}"
  idol "agentstore:${IDOL_SERVER_VERSION}"
  idol "category:${IDOL_SERVER_VERSION}"
  idol "categorisation-agentstore:${IDOL_SERVER_VERSION}"
  idol "community:${IDOL_SERVER_VERSION}"
  idol "view:${IDOL_SERVER_VERSION}"
  idol "nifi-ver2-full:${IDOL_SERVER_VERSION}"
  idol "find:${IDOL_SERVER_VERSION}"
  add_img public "$HTTPD_IMAGE"
}

stack_data_admin() {
  idol "answerbank-agentstore:${IDOL_SERVER_VERSION}"
  idol "content:${IDOL_SERVER_VERSION}"
  idol "agentstore:${IDOL_SERVER_VERSION}"
  idol "category:${IDOL_SERVER_VERSION}"
  idol "categorisation-agentstore:${IDOL_SERVER_VERSION}"
  idol "answerserver:${IDOL_SERVER_VERSION}"
  idol "qms-agentstore:${IDOL_SERVER_VERSION}"
  idol "qms:${IDOL_SERVER_VERSION}"
  idol "statsserver:${IDOL_SERVER_VERSION}"
  idol "view:${IDOL_SERVER_VERSION}"
  idol "community:${IDOL_SERVER_VERSION}"
  idol "dataadmin:${IDOL_DATA_ADMIN_VERSION}"
  idol "nifi-ver2-full:${IDOL_SERVER_VERSION}"
  idol "find:${IDOL_SERVER_VERSION}"
  add_img public "$POSTGRES_IMAGE"
}

stack_rich_media() {
  idol "content:${IDOL_RICH_MEDIA_VERSION}"
  idol "agentstore:${IDOL_RICH_MEDIA_VERSION}"
  idol "category:${IDOL_RICH_MEDIA_VERSION}"
  idol "categorisation-agentstore:${IDOL_RICH_MEDIA_VERSION}"
  idol "community:${IDOL_RICH_MEDIA_VERSION}"
  idol "view:${IDOL_RICH_MEDIA_VERSION}"
  idol "mediaserver-english:${IDOL_RICH_MEDIA_VERSION}"
  idol "mediaserver-playlistserver:${IDOL_RICH_MEDIA_VERSION}"
  idol "mmap_app:${MMAP_APP_RICH_TAG}"
  add_img public "$POSTGRES_IMAGE"
}

stack_license_server() {
  add_img public "$UBUNTU_IMAGE"
  add_img local  "licenseserver:latest"
}

stack_llm() {
  add_img public "$OLLAMA_IMAGE"
  add_img public "$OPENWEBUI_IMAGE"
}

stack_wiki() {
  add_img public "$OBSIDIAN_IMAGE"
  add_img local  "obsidian-custom:latest"
}

stack_nifi_registry() {
  add_img public "$NIFI_REGISTRY_IMAGE"
}

stack_mmap_basic() {
  idol "mediaserver-english:${IDOL_RICH_MEDIA_VERSION}"
  idol "mediaserver-playlistserver:${IDOL_RICH_MEDIA_VERSION}"
  idol "mmap_app:${MMAP_APP_BASIC_TAG}"
  add_img public "$POSTGRES_IMAGE"
}

stack_docsec() {
  add_img local "idol-compose/docsec-content"
  add_img local "idol-compose/docsec-community"
  add_img local "idol-compose/docsec-omnigroupserver"
}

ALL_STACK_NAMES=(
  basic-idol
  data-admin
  rich-media
  license-server
  llm
  wiki
  nifi-registry
  mmap-basic
  docsec
)

resolve_stack_list() {
  local raw="${1:-all}"
  local out=()
  IFS=',' read -ra parts <<< "$raw"
  for p in "${parts[@]}"; do
    p="$(echo "$p" | xargs)"
    case "$p" in
      "" ) ;;
      all) out+=("${ALL_STACK_NAMES[@]}") ;;
      deploy-core) out+=(basic-idol data-admin rich-media license-server) ;;
      data-admin-full) out+=(data-admin llm wiki) ;;
      basic-idol|data-admin|rich-media|license-server|llm|wiki|nifi-registry|mmap-basic|docsec)
        out+=("$p") ;;
      *) die "Unknown stack: $p  (see --help)" ;;
    esac
  done
  local seen="" uniq=()
  for s in "${out[@]}"; do
    case " $seen " in
      *" $s "*) ;;
      *) seen+=" $s"; uniq+=("$s") ;;
    esac
  done
  printf '%s\n' "${uniq[@]}"
}

collect_images_for_stacks() {
  IMAGES=()
  local s
  for s in "$@"; do
    case "$s" in
      basic-idol)      stack_basic_idol ;;
      data-admin)      stack_data_admin ;;
      rich-media)      stack_rich_media ;;
      license-server)  stack_license_server ;;
      llm)             stack_llm ;;
      wiki)            stack_wiki ;;
      nifi-registry)   stack_nifi_registry ;;
      mmap-basic)      stack_mmap_basic ;;
      docsec)          stack_docsec ;;
    esac
  done
}

UNIQUE_KIND=()
UNIQUE_IMG=()

rebuild_unique_images() {
  UNIQUE_KIND=()
  UNIQUE_IMG=()
  local seen="" line kind img
  for line in "${IMAGES[@]}"; do
    kind="${line%% *}"
    img="${line#* }"
    case " $seen " in
      *" $img "*) continue ;;
    esac
    seen+=" $img"
    UNIQUE_KIND+=("$kind")
    UNIQUE_IMG+=("$img")
  done
  apply_image_filter
}

apply_image_filter() {
  ((${#IMAGE_FILTER[@]} == 0)) && return 0
  local nk=() ni=() i img keep f
  for i in "${!UNIQUE_IMG[@]}"; do
    img="${UNIQUE_IMG[$i]}"
    keep=false
    for f in "${IMAGE_FILTER[@]}"; do
      if [[ "$img" == "$f" || "$img" == *"$f"* ]]; then
        keep=true
        break
      fi
    done
    if $keep; then
      nk+=("${UNIQUE_KIND[$i]}")
      ni+=("$img")
    fi
  done
  UNIQUE_KIND=("${nk[@]}")
  UNIQUE_IMG=("${ni[@]}")
  ((${#UNIQUE_IMG[@]} > 0)) || die "Image filter matched nothing. Check your selection."
}

image_to_filename() {
  local img="$1"
  echo "${img}" | sed -e 's|/|_|g' -e 's|:|_|g' -e 's|[^A-Za-z0-9._-]|_|g'
}

subdir_for_kind() {
  case "$1" in
    auth)    echo "idol" ;;
    public)  echo "public" ;;
    local)   echo "local" ;;
    *)       echo "other" ;;
  esac
}

needs_auth() {
  rebuild_unique_images
  local i
  for i in "${!UNIQUE_KIND[@]}"; do
    [[ "${UNIQUE_KIND[$i]}" == "auth" ]] && return 0
  done
  return 1
}

# -----------------------------------------------------------------------------
# Docker helpers
# -----------------------------------------------------------------------------
require_docker() {
  command -v docker >/dev/null 2>&1 || die "docker is not installed or not in PATH"
  docker info >/dev/null 2>&1 || die "Docker daemon is not running or not accessible"
}

idol_login() {
  if $SKIP_LOGIN; then
    warn "Skipping Docker login (--skip-login)"
    return 0
  fi
  if ! needs_auth; then
    log "No authenticated IDOL images in selection — login not required"
    return 0
  fi

  step "Docker Hub login (microfocusidolreadonly)"
  local token="${IDOL_LICENSE_KEY_TOKEN:-}"
  if [[ -z "$token" ]]; then
    printf "%sEnter IDOL Docker PAT [dckr_pat_XXXXX]: %s" "$CYAN" "$NC"
    read -rs token
    echo
    export IDOL_LICENSE_KEY_TOKEN="$token"
  else
    log "Using IDOL_LICENSE_KEY_TOKEN from environment"
  fi
  [[ "$token" =~ ^dckr[_A-Za-z0-9-]+$ ]] || die "Token format invalid (expected dckr_pat_...)"
  if echo "$token" | docker login --username microfocusidolreadonly --password-stdin; then
    ok "Docker login succeeded"
  else
    die "Docker login failed — cannot pull ${IDOL_REGISTRY}/* images"
  fi
}

image_exists() {
  docker image inspect "$1" >/dev/null 2>&1
}

pull_one() {
  local kind="$1" img="$2"
  if image_exists "$img"; then
    ok "Already present: $img"
    return 0
  fi
  if [[ "$kind" == "local" ]]; then
    warn "Local-only image not present (will not pull): $img"
    warn "  Build it on the init host if you want it in the bundle."
    return 0
  fi
  log "Pulling $img"
  if docker pull "$img"; then
    ok "Pulled $img"
  else
    err "Failed to pull $img"
    return 1
  fi
}

save_one() {
  local kind="$1" img="$2"
  local sub dir base dest
  sub="$(subdir_for_kind "$kind")"
  dir="${BUNDLE_DIR}/images/${sub}"
  mkdir -p "$dir"
  base="$(image_to_filename "$img")"
  dest="${dir}/${base}.tar"

  if ! image_exists "$img"; then
    if [[ "$kind" == "local" ]]; then
      warn "Skip save (not built locally): $img"
      return 0
    fi
    err "Cannot save missing image: $img  (run pull first)"
    return 1
  fi

  if [[ -f "$dest" || -f "${dest}.gz" ]] && ! $FORCE; then
    ok "Tar already exists (use --force to overwrite): ${dest}${GZIP_TARS:+[.gz]}"
    return 0
  fi

  log "Saving $img -> $dest"
  docker save -o "$dest" "$img"
  if $GZIP_TARS; then
    log "Compressing $dest"
    gzip -f "$dest"
    ok "Saved ${dest}.gz"
  else
    ok "Saved $dest"
  fi
}

load_tar() {
  local file="$1"
  log "Loading $file"
  case "$file" in
    *.tar.gz|*.tgz) gunzip -c "$file" | docker load ;;
    *.tar)          docker load -i "$file" ;;
    *)              warn "Skip unknown file: $file"; return 0 ;;
  esac
  ok "Loaded $file"
}

write_manifest() {
  mkdir -p "$BUNDLE_DIR"
  local mf="${BUNDLE_DIR}/manifest.txt"
  {
    echo "# airgap-images.sh manifest"
    echo "# generated: $(date -Is 2>/dev/null || date)"
    echo "# host: $(hostname 2>/dev/null || echo unknown)"
    echo "# IDOL_REGISTRY=$IDOL_REGISTRY"
    echo "# IDOL_SERVER_VERSION=$IDOL_SERVER_VERSION"
    echo "# IDOL_DATA_ADMIN_VERSION=$IDOL_DATA_ADMIN_VERSION"
    echo "# IDOL_RICH_MEDIA_VERSION=$IDOL_RICH_MEDIA_VERSION"
    echo "# MMAP_APP_BASIC_TAG=$MMAP_APP_BASIC_TAG"
    echo "# MMAP_APP_RICH_TAG=$MMAP_APP_RICH_TAG"
    echo "# stacks: ${STACKS_RESOLVED[*]}"
    echo
    echo "# images"
    rebuild_unique_images
    local i kind img id
    for i in "${!UNIQUE_IMG[@]}"; do
      kind="${UNIQUE_KIND[$i]}"
      img="${UNIQUE_IMG[$i]}"
      id="MISSING"
      if image_exists "$img"; then
        id="$(docker image inspect --format '{{.Id}}' "$img" 2>/dev/null || echo unknown)"
      fi
      printf '%-8s %-70s %s\n' "$kind" "$img" "$id"
    done
    echo
    echo "# files in bundle/images"
    find "${BUNDLE_DIR}/images" -type f \( -name '*.tar' -o -name '*.tar.gz' -o -name '*.tgz' \) 2>/dev/null | sort || true
  } > "$mf"
  ok "Wrote $mf"
}

write_offline_env() {
  mkdir -p "$BUNDLE_DIR"
  cat > "${BUNDLE_DIR}/offline.env" <<EOF
# Source this on the air-gapped host BEFORE running any deploy.sh
#   source ${BUNDLE_DIR}/offline.env
export IDOL_AIRGAP=true
export COMPOSE_PULL=never
export IDOL_REGISTRY="${IDOL_REGISTRY}"
export IDOL_SERVER_VERSION="${IDOL_SERVER_VERSION}"
export IDOL_DATA_ADMIN_VERSION="${IDOL_DATA_ADMIN_VERSION}"
export IDOL_RICH_MEDIA_VERSION="${IDOL_RICH_MEDIA_VERSION}"
export MMAP_APP_BASIC_TAG="${MMAP_APP_BASIC_TAG}"
export MMAP_APP_RICH_TAG="${MMAP_APP_RICH_TAG}"
EOF
  ok "Wrote ${BUNDLE_DIR}/offline.env"
}

write_readme() {
  cat > "${BUNDLE_DIR}/README-AIRGAP.md" <<EOF
# IDOL air-gap image bundle

Generated by airgap-images.sh with tags:
- IDOL_SERVER_VERSION=${IDOL_SERVER_VERSION}
- IDOL_DATA_ADMIN_VERSION=${IDOL_DATA_ADMIN_VERSION}
- IDOL_RICH_MEDIA_VERSION=${IDOL_RICH_MEDIA_VERSION}

## Load on the isolated host

    ./airgap-images.sh load --bundle $(basename "$BUNDLE_DIR")
    source $(basename "$BUNDLE_DIR")/offline.env
    ./airgap-images.sh verify --stacks ${SELECTED_STACKS:-all} \\
      --server-version ${IDOL_SERVER_VERSION} \\
      --data-admin-version ${IDOL_DATA_ADMIN_VERSION} \\
      --rich-media-version ${IDOL_RICH_MEDIA_VERSION}

## Then deploy

Existing deploy.sh scripts still call docker login and may try to pull.
On an isolated host load images first, then run compose with --pull never.
EOF
}

copy_models() {
  step "Copy GGUF models into bundle"
  mkdir -p "${BUNDLE_DIR}/models"
  if [[ ! -d "$MODEL_SRC_DIR" ]]; then
    warn "IDOL_LLM_MODEL_PATH does not exist: $MODEL_SRC_DIR"
    warn "Place .gguf files there and re-run: $0 models-copy"
    return 0
  fi
  local count=0 f
  shopt -s nullglob
  for f in "$MODEL_SRC_DIR"/*.gguf; do
    cp -f "$f" "${BUNDLE_DIR}/models/"
    ok "Copied $(basename "$f")"
    count=$((count + 1))
  done
  shopt -u nullglob
  if (( count == 0 )); then
    warn "No .gguf files in $MODEL_SRC_DIR"
  else
    ok "Copied $count GGUF file(s) -> ${BUNDLE_DIR}/models"
  fi
}

# -----------------------------------------------------------------------------
# Commands
# -----------------------------------------------------------------------------
cmd_list() {
  step "Resolved versions"
  printf "  IDOL_REGISTRY              = "; display_tag "$IDOL_REGISTRY"; printf "\n"
  printf "  IDOL_SERVER_VERSION        = "; display_tag "$IDOL_SERVER_VERSION"; printf "\n"
  printf "  IDOL_DATA_ADMIN_VERSION    = "; display_tag "$IDOL_DATA_ADMIN_VERSION"; printf "\n"
  printf "  IDOL_RICH_MEDIA_VERSION    = "; display_tag "$IDOL_RICH_MEDIA_VERSION"; printf "\n"
  printf "  MMAP_APP_BASIC_TAG         = "; display_tag "$MMAP_APP_BASIC_TAG"; printf "\n"
  printf "  MMAP_APP_RICH_TAG          = "; display_tag "$MMAP_APP_RICH_TAG"; printf "\n"
  printf "  HTTPD_IMAGE                = "; display_tag "$HTTPD_IMAGE"; printf "\n"
  printf "  POSTGRES_IMAGE             = "; display_tag "$POSTGRES_IMAGE"; printf "\n"
  printf "  OPENWEBUI_IMAGE            = "; display_tag "$OPENWEBUI_IMAGE"; printf "\n"
  echo "  stacks                     = ${STACKS_RESOLVED[*]}"
  echo "  bundle                     = ${BUNDLE_DIR}"

  local s
  for s in "${STACKS_RESOLVED[@]}"; do
    IMAGES=()
    collect_images_for_stacks "$s"
    rebuild_unique_images
    step "Stack: $s"
    local i kind img mark
    for i in "${!UNIQUE_IMG[@]}"; do
      kind="${UNIQUE_KIND[$i]}"
      img="${UNIQUE_IMG[$i]}"
      mark="-"
      if command -v docker >/dev/null 2>&1 && image_exists "$img" 2>/dev/null; then
        mark="local"
      fi
      printf "  %-8s %-70s %s\n" "$kind" "$img" "$mark"
    done
  done

  collect_images_for_stacks "${STACKS_RESOLVED[@]}"
  rebuild_unique_images
  step "Deduplicated union"
  local i
  for i in "${!UNIQUE_IMG[@]}"; do
    printf "  %-8s %s\n" "${UNIQUE_KIND[$i]}" "${UNIQUE_IMG[$i]}"
  done
}

cmd_pull() {
  require_docker
  require_tags_for_stacks "${STACKS_RESOLVED[@]}"
  collect_images_for_stacks "${STACKS_RESOLVED[@]}"
  idol_login
  step "Pulling images"
  rebuild_unique_images
  local failed=0 i
  for i in "${!UNIQUE_IMG[@]}"; do
    pull_one "${UNIQUE_KIND[$i]}" "${UNIQUE_IMG[$i]}" || failed=$((failed + 1))
  done
  (( failed == 0 )) || die "Pull finished with $failed failure(s)"
  ok "Pull complete"
}

cmd_save() {
  require_docker
  require_tags_for_stacks "${STACKS_RESOLVED[@]}"
  collect_images_for_stacks "${STACKS_RESOLVED[@]}"
  mkdir -p "${BUNDLE_DIR}/images"/{idol,public,local}
  step "Saving images -> ${BUNDLE_DIR}"
  rebuild_unique_images
  local failed=0 i
  for i in "${!UNIQUE_IMG[@]}"; do
    save_one "${UNIQUE_KIND[$i]}" "${UNIQUE_IMG[$i]}" || failed=$((failed + 1))
  done
  write_manifest
  write_offline_env
  write_readme
  (( failed == 0 )) || die "Save finished with $failed failure(s)"
  ok "Save complete: $BUNDLE_DIR"
}

cmd_bundle() {
  $SKIP_PULL || cmd_pull
  cmd_save
  if [[ " ${STACKS_RESOLVED[*]} " == *" llm "* ]]; then
    copy_models
  fi
  step "Bundle ready"
  echo "  Directory : $BUNDLE_DIR"
  echo "  Transfer  : copy the whole directory to the air-gapped host"
  echo "  Load      : $0 load --bundle $BUNDLE_DIR"
}

cmd_load() {
  require_docker
  [[ -d "$BUNDLE_DIR" ]] || die "Bundle not found: $BUNDLE_DIR"
  step "Loading images from $BUNDLE_DIR"
  local found=0 f list
  list="$(find "${BUNDLE_DIR}/images" -type f \( -name '*.tar' -o -name '*.tar.gz' -o -name '*.tgz' \) 2>/dev/null | sort)"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    load_tar "$f"
    found=$((found + 1))
  done <<< "$list"

  (( found > 0 )) || die "No .tar / .tar.gz files under ${BUNDLE_DIR}/images"
  ok "Loaded $found archive(s)"

  if [[ -d "${BUNDLE_DIR}/models" ]]; then
    local n
    n="$(find "${BUNDLE_DIR}/models" -name '*.gguf' -type f | wc -l | tr -d ' ')"
    if [[ "$n" != "0" ]]; then
      mkdir -p "$MODEL_SRC_DIR"
      cp -f "${BUNDLE_DIR}/models/"*.gguf "$MODEL_SRC_DIR/" 2>/dev/null || true
      ok "Installed $n GGUF model(s) -> $MODEL_SRC_DIR"
    fi
  fi

  if [[ -f "${BUNDLE_DIR}/offline.env" ]]; then
    log "Source offline env:  source ${BUNDLE_DIR}/offline.env"
  fi
}

cmd_verify() {
  require_docker
  require_tags_for_stacks "${STACKS_RESOLVED[@]}"
  collect_images_for_stacks "${STACKS_RESOLVED[@]}"
  step "Verify local images"
  rebuild_unique_images
  local missing=0 local_missing=0 i kind img
  for i in "${!UNIQUE_IMG[@]}"; do
    kind="${UNIQUE_KIND[$i]}"
    img="${UNIQUE_IMG[$i]}"
    if image_exists "$img"; then
      ok "$img"
    else
      if [[ "$kind" == "local" ]]; then
        warn "LOCAL not built: $img"
        local_missing=$((local_missing + 1))
      else
        err "MISSING: $img"
        missing=$((missing + 1))
      fi
    fi
  done
  echo
  if (( missing > 0 )); then
    die "$missing required image(s) missing. Run load or bundle first."
  fi
  if (( local_missing > 0 )); then
    warn "$local_missing local-build image(s) absent — build them if that stack is used."
  fi
  ok "All registry images for selected stacks are present locally"
}

# -----------------------------------------------------------------------------
# Interactive menu
# -----------------------------------------------------------------------------
require_presource_hint() {
  if [[ -z "${IDOL_SERVER_VERSION:-}" && -z "${IDOL_RICH_MEDIA_VERSION:-}" && -z "${IDOL_DATA_ADMIN_VERSION:-}" ]]; then
    warn "No IDOL version tags in this shell."
    warn "Mandatory first step:  source ./pre-setup.sh"
    printf "  Continue anyway? [y/N]: "
    local ans=""
    read -r ans || true
    [[ "$ans" =~ ^[Yy]$ ]] || die "Aborted. Run: source ./pre-setup.sh"
  fi
}

menu_pick_stacks() {
  hdr "SELECT STACKS"
  note "  Default = ALL stacks. Enter numbers separated by comma, or press Enter."
  printf "\n"
  local i
  printf "  %s[0]%s  %sALL stacks (default)%s\n" "$YELLOW" "$NC" "$BOLD" "$NC"
  for i in "${!ALL_STACK_NAMES[@]}"; do
    printf "  %s[%d]%s  %s\n" "$GREEN" "$((i + 1))" "$NC" "${ALL_STACK_NAMES[$i]}"
  done
  printf "  %s[c]%s  deploy-core     (basic-idol,data-admin,rich-media,license-server)\n" "$CYAN" "$NC"
  printf "  %s[d]%s  data-admin-full (data-admin,llm,wiki)\n" "$CYAN" "$NC"
  printf "\n"
  printf "%sStack selection [0 / Enter = ALL]: %s" "$YELLOW" "$NC"
  local raw=""
  read -r raw || true
  raw="$(echo "$raw" | xargs)"
  if [[ -z "$raw" || "$raw" == "0" || "$raw" == "all" ]]; then
    SELECTED_STACKS="all"
    return 0
  fi
  if [[ "$raw" == "c" || "$raw" == "C" ]]; then
    SELECTED_STACKS="deploy-core"
    return 0
  fi
  if [[ "$raw" == "d" || "$raw" == "D" ]]; then
    SELECTED_STACKS="data-admin-full"
    return 0
  fi
  local picked=() part
  IFS=',' read -ra parts <<< "$raw"
  for part in "${parts[@]}"; do
    part="$(echo "$part" | xargs)"
    [[ -z "$part" ]] && continue
    if [[ "$part" =~ ^[0-9]+$ ]]; then
      if (( part >= 1 && part <= ${#ALL_STACK_NAMES[@]} )); then
        picked+=("${ALL_STACK_NAMES[$((part - 1))]}")
      else
        die "Invalid stack number: $part"
      fi
    else
      picked+=("$part")
    fi
  done
  ((${#picked[@]} > 0)) || die "No stacks selected"
  local IFS=','
  SELECTED_STACKS="${picked[*]}"
}

menu_pick_images() {
  collect_images_for_stacks "${STACKS_RESOLVED[@]}"
  IMAGE_FILTER=()
  rebuild_unique_images
  hdr "SELECT IMAGES"
  printf "  Stacks: %s%s%s\n" "$GREEN" "${STACKS_RESOLVED[*]}" "$NC"
  note "  Default = ALL images in the selected stacks. Enter numbers, or Enter for all."
  printf "\n"
  local i
  printf "  %s[0]%s  %sALL images (default)%s\n" "$YELLOW" "$NC" "$BOLD" "$NC"
  for i in "${!UNIQUE_IMG[@]}"; do
    printf "  %s[%2d]%s  %-8s %s\n" "$GREEN" "$((i + 1))" "$NC" "${UNIQUE_KIND[$i]}" "${UNIQUE_IMG[$i]}"
  done
  printf "\n"
  printf "%sImage selection [0 / Enter = ALL]: %s" "$YELLOW" "$NC"
  local raw=""
  read -r raw || true
  raw="$(echo "$raw" | xargs)"
  if [[ -z "$raw" || "$raw" == "0" || "$raw" == "all" ]]; then
    IMAGE_FILTER=()
    ok "Using ALL images in selected stacks (${#UNIQUE_IMG[@]})"
    return 0
  fi
  local part idx
  IFS=',' read -ra parts <<< "$raw"
  for part in "${parts[@]}"; do
    part="$(echo "$part" | xargs)"
    [[ -z "$part" ]] && continue
    if [[ "$part" =~ ^[0-9]+$ ]]; then
      idx=$((part - 1))
      if (( idx >= 0 && idx < ${#UNIQUE_IMG[@]} )); then
        IMAGE_FILTER+=("${UNIQUE_IMG[$idx]}")
      else
        die "Invalid image number: $part"
      fi
    else
      IMAGE_FILTER+=("$part")
    fi
  done
  ((${#IMAGE_FILTER[@]} > 0)) || die "No images selected"
  ok "Selected ${#IMAGE_FILTER[@]} image(s)"
}

menu_pick_action() {
  hdr "SELECT ACTION"
  printf "  %s[1]%s  %sDownload from registry%s          docker pull (needs internet + PAT)\n" "$GREEN" "$NC" "$BOLD" "$NC"
  printf "  %s[2]%s  %sUpload / export to local folder%s  docker save -> ./airgap-bundle\n" "$GREEN" "$NC" "$BOLD" "$NC"
  printf "  %s[3]%s  %sDownload then export (bundle)%s    recommended on the init host [default]\n" "$YELLOW" "$NC" "$BOLD" "$NC"
  printf "  %s[4]%s  Load into Docker from local folder  docker load (air-gapped host)\n" "$CYAN" "$NC"
  printf "  %s[5]%s  List resolved images\n" "$CYAN" "$NC"
  printf "  %s[6]%s  Verify images exist locally\n" "$CYAN" "$NC"
  printf "  %s[7]%s  Copy GGUF models into bundle\n" "$CYAN" "$NC"
  printf "  %s[h]%s  Help\n" "$DIM" "$NC"
  printf "  %s[q]%s  Quit\n" "$RED" "$NC"
  printf "\n"
  printf "%sAction [3 = bundle]: %s" "$YELLOW" "$NC"
  local raw=""
  read -r raw || true
  raw="$(echo "${raw:-3}" | xargs)"
  case "$raw" in
    1|pull|download) COMMAND="pull" ;;
    2|save|upload|export) COMMAND="save" ;;
    3|bundle|"") COMMAND="bundle" ;;
    4|load) COMMAND="load" ;;
    5|list) COMMAND="list" ;;
    6|verify) COMMAND="verify" ;;
    7|models-copy) COMMAND="models-copy" ;;
    h|help) COMMAND="help" ;;
    q|quit|0) COMMAND="quit" ;;
    *) die "Unknown action: $raw" ;;
  esac
}

menu_pick_gzip() {
  case "$COMMAND" in
    save|bundle) ;;
    *) return 0 ;;
  esac
  printf "%sGzip image tars after save? [Y/n]: %s" "$YELLOW" "$NC"
  local raw=""
  read -r raw || true
  if [[ -z "$raw" || "$raw" =~ ^[Yy]$ ]]; then
    GZIP_TARS=true
    ok "gzip enabled"
  else
    GZIP_TARS=false
  fi
}

normalize_bundle_dir() {
  local p="${1:-}"
  p="${p/#\~/$HOME}"
  if [[ "$p" != /* ]]; then
    p="${PWD}/${p}"
  fi
  # collapse /./ 
  p="$(cd "$(dirname "$p")" 2>/dev/null && printf '%s/%s' "$(pwd)" "$(basename "$p")" || echo "$p")"
  printf '%s' "$p"
}

menu_pick_bundle_dir() {
  hdr "SAVED IMAGES FOLDER"
  note "  Tars are written to  <folder>/images/{idol,public,local}"
  note "  Pass --bundle DIR to skip this question."
  printf "\n"
  if $BUNDLE_DIR_FROM_CLI; then
    BUNDLE_DIR="$(normalize_bundle_dir "$BUNDLE_DIR")"
    ok "Using --bundle path: $BUNDLE_DIR"
    return 0
  fi
  local default="$BUNDLE_DIR"
  printf "%sWhere should images be saved / loaded from?%s\n" "$CYAN" "$NC"
  printf "%sPath [%s]: %s" "$YELLOW" "$default" "$NC"
  local raw=""
  read -r raw || true
  raw="$(echo "$raw" | xargs)"
  if [[ -n "$raw" ]]; then
    BUNDLE_DIR="$raw"
  fi
  BUNDLE_DIR="$(normalize_bundle_dir "$BUNDLE_DIR")"
  mkdir -p "$BUNDLE_DIR" 2>/dev/null || true
  ok "Saved-images folder: $BUNDLE_DIR"
}

cmd_menu() {
  require_presource_hint
  menu_pick_bundle_dir
  printf "\n%s%s IDOL air-gap image menu %s\n\n" "$BOLD" "$CYAN" "$NC"
  printf "  Bundle folder: %s%s%s\n" "$YELLOW" "$BUNDLE_DIR" "$NC"
  printf "  Registry:      %s%s%s\n" "$YELLOW" "${IDOL_REGISTRY:-unset}" "$NC"
  printf "  Server tag:    "; display_tag "${IDOL_SERVER_VERSION:-}"; printf "\n"
  printf "  Data-admin:    "; display_tag "${IDOL_DATA_ADMIN_VERSION:-}"; printf "\n"
  printf "  Rich-media:    "; display_tag "${IDOL_RICH_MEDIA_VERSION:-}"; printf "\n\n"

  menu_pick_stacks
  STACKS_RESOLVED=()
  local _s
  while IFS= read -r _s; do
    [[ -n "$_s" ]] && STACKS_RESOLVED+=("$_s")
  done <<< "$(resolve_stack_list "${SELECTED_STACKS:-all}")"
  [[ ${#STACKS_RESOLVED[@]} -gt 0 ]] || die "No stacks selected"
  ok "Stacks: ${STACKS_RESOLVED[*]}"

  menu_pick_images
  menu_pick_action
  [[ "$COMMAND" == "quit" ]] && { log "Bye."; exit 0; }
  [[ "$COMMAND" == "help" ]] && { usage; exit 0; }
  menu_pick_gzip
}

# -----------------------------------------------------------------------------
# Arg parse
# -----------------------------------------------------------------------------
parse_args() {
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help|help) usage; exit 0 ;;
      --stacks)                SELECTED_STACKS="${2:-}"; shift 2 ;;
      --stacks=*)              SELECTED_STACKS="${1#*=}"; shift ;;
      --bundle)                BUNDLE_DIR="${2:-}"; BUNDLE_DIR_FROM_CLI=true; shift 2 ;;
      --bundle=*)              BUNDLE_DIR="${1#*=}"; BUNDLE_DIR_FROM_CLI=true; shift ;;
      -o)                      BUNDLE_DIR="${2:-}"; BUNDLE_DIR_FROM_CLI=true; shift 2 ;;
      --env-file)              ENV_FILE_CLI="${2:-}"; shift 2 ;;
      --env-file=*)            ENV_FILE_CLI="${1#*=}"; shift ;;
      --server-version)        CLI_SERVER_VERSION="${2:-}"; shift 2 ;;
      --server-version=*)      CLI_SERVER_VERSION="${1#*=}"; shift ;;
      --data-admin-version)    CLI_DATA_ADMIN_VERSION="${2:-}"; shift 2 ;;
      --data-admin-version=*)  CLI_DATA_ADMIN_VERSION="${1#*=}"; shift ;;
      --rich-media-version)    CLI_RICH_MEDIA_VERSION="${2:-}"; shift 2 ;;
      --rich-media-version=*)  CLI_RICH_MEDIA_VERSION="${1#*=}"; shift ;;
      --mmap-app-basic)        CLI_MMAP_APP_BASIC="${2:-}"; shift 2 ;;
      --mmap-app-rich)         CLI_MMAP_APP_RICH="${2:-}"; shift 2 ;;
      --registry)              CLI_REGISTRY="${2:-}"; shift 2 ;;
      --gzip)                  GZIP_TARS=true; shift ;;
      --skip-login)            SKIP_LOGIN=true; shift ;;
      --skip-pull)             SKIP_PULL=true; shift ;;
      --force)                 FORCE=true; shift ;;
      --allow-placeholders)    ALLOW_PLACEHOLDERS=true; shift ;;
      --models-json)           DEFAULT_MODELS_JSON="${2:-}"; shift 2 ;;
      --)                      shift; args+=("$@"); break ;;
      -*)                      die "Unknown option: $1" ;;
      *)                       args+=("$1"); shift ;;
    esac
  done
  if [[ ${#args[@]} -eq 0 ]]; then
    COMMAND="menu"
    return 0
  fi
  COMMAND="${args[0]}"
}

main() {
  parse_args "$@"

  BUNDLE_DIR="${BUNDLE_DIR/#\~/$HOME}"
  MODEL_SRC_DIR="${MODEL_SRC_DIR/#\~/$HOME}"

  resolve_versions

  if [[ "$COMMAND" == "menu" ]]; then
    cmd_menu
  else
    STACKS_RESOLVED=()
    local _s
    while IFS= read -r _s; do
      [[ -n "$_s" ]] && STACKS_RESOLVED+=("$_s")
    done <<< "$(resolve_stack_list "${SELECTED_STACKS:-all}")"
    [[ ${#STACKS_RESOLVED[@]} -gt 0 ]] || die "No stacks selected"
  fi

  case "$COMMAND" in
    list)         cmd_list ;;
    pull)         cmd_pull ;;
    save)         cmd_save ;;
    bundle)       cmd_bundle ;;
    load)         cmd_load ;;
    verify)       cmd_verify ;;
    models-copy)  copy_models ;;
    help)         usage ;;
    quit)         exit 0 ;;
    menu)         die "Menu did not select an action" ;;
    *)            die "Unknown command: $COMMAND  (see --help)" ;;
  esac
}

main "$@"
