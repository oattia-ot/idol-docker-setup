#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

usage() {
  echo -e "${CYAN}Usage:${NC}"
  echo -e "  $0 <OLD_ZIP> <NEW_ZIP> [TARGET_FOLDER] [--force]"
  echo
  echo -e "${CYAN}Arguments:${NC}"
  echo -e "  ${YELLOW}OLD_ZIP${NC}         Path to the older ZIP file"
  echo -e "  ${YELLOW}NEW_ZIP${NC}         Path to the newer ZIP file (master)"
  echo -e "  ${YELLOW}TARGET_FOLDER${NC}   Folder where changed files will be copied (default: changed-files)"
  echo -e "  ${YELLOW}--force${NC}         Create a new ZIP based on OLD_ZIP and overwrite the changed files"
  echo
  echo -e "${CYAN}Examples:${NC}"
  echo -e "  $0 old.zip new.zip"
  echo -e "  $0 old.zip new.zip my-changed-files"
  echo -e "  $0 old.zip new.zip my-changed-files --force"
  echo
  exit 1
}

# Parse arguments
FORCE=false
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --force|-f)
      FORCE=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

set -- "${POSITIONAL[@]}"

if [[ $# -lt 2 ]]; then
  echo -e "${RED}Error: Missing required arguments${NC}"
  echo
  usage
fi

OLD_ZIP="$1"
NEW_ZIP="$2"
TARGET="${3:-changed-files}"

# Validate ZIP files exist
if [[ ! -f "$OLD_ZIP" ]]; then
  echo -e "${RED}Error: OLD_ZIP not found → $OLD_ZIP${NC}"
  exit 1
fi

if [[ ! -f "$NEW_ZIP" ]]; then
  echo -e "${RED}Error: NEW_ZIP not found → $NEW_ZIP${NC}"
  exit 1
fi

mkdir -p "$TARGET"

echo -e "${GREEN}=== Comparing text files (.sh .yml .md .json) ===${NC}"
echo -e "OLD ZIP : ${YELLOW}$OLD_ZIP${NC}"
echo -e "NEW ZIP : ${YELLOW}$NEW_ZIP${NC}"
echo -e "TARGET  : ${YELLOW}$TARGET${NC}"
echo -e "FORCE   : ${YELLOW}$FORCE${NC}"
echo
echo -e "${CYAN}OLD_SIZE  OLD_LINES   |  NEW_SIZE  NEW_LINES   |  RELATIVE_PATH${NC}"
echo "----------------------------------------------------------------------"

# Create temporary normalized lists
tmpdir=$(mktemp -d)

# Old ZIP → size + normalized path
unzip -l "$OLD_ZIP" | awk 'NR>3 && NF && $NF ~ /\.(sh|yml|md|json)$/ {
  path=$4
  sub(/^[^\/]+\//, "", path)
  print $1, path
}' | sort -k2 > "$tmpdir/old.list"

# New ZIP → size + normalized path
unzip -l "$NEW_ZIP" | awk 'NR>3 && NF && $NF ~ /\.(sh|yml|md|json)$/ {
  path=$4
  sub(/^[^\/]+\//, "", path)
  print $1, path
}' | sort -k2 > "$tmpdir/new.list"

# Find common relative paths that have different size
join -j 2 "$tmpdir/old.list" "$tmpdir/new.list" | while read -r relpath old_size new_size; do
  [[ "$old_size" == "$new_size" ]] && continue

  # Get the real full path inside each ZIP
  old_full=$(unzip -l "$OLD_ZIP" | awk -v p="$relpath" 'NR>3 && $NF ~ p"$" {print $NF; exit}')
  new_full=$(unzip -l "$NEW_ZIP" | awk -v p="$relpath" 'NR>3 && $NF ~ p"$" {print $NF; exit}')

  old_lines=$(unzip -p "$OLD_ZIP" "$old_full" 2>/dev/null | wc -l)
  new_lines=$(unzip -p "$NEW_ZIP" "$new_full" 2>/dev/null | wc -l)

  printf "%-9s %-10s | %-9s %-10s | %s\n" \
    "$old_size" "$old_lines" "$new_size" "$new_lines" "$relpath"

  # Copy the NEW version of the file into TARGET (keeping structure)
  unzip -o -q "$NEW_ZIP" "$new_full" -d "$TARGET"
done

rm -rf "$tmpdir"

echo
echo -e "${GREEN}Done!${NC} Changed files copied to: ${YELLOW}$(pwd)/$TARGET${NC}"

# === FORCE mode: create updated ZIP based on OLD_ZIP ===
if [[ "$FORCE" == true ]]; then
  NEW_ZIP_NAME="updated-$(basename "$OLD_ZIP")"
  WORKDIR=$(mktemp -d)

  echo -e "${CYAN}Creating updated ZIP based on OLD_ZIP...${NC}"

  # 1. Extract the entire OLD_ZIP
  unzip -q "$OLD_ZIP" -d "$WORKDIR"

  # 2. Overwrite the changed files (from TARGET) into the correct locations
  #    We need to map the files from TARGET back into the OLD structure
  find "$TARGET" -type f \( -name "*.sh" -o -name "*.yml" -o -name "*.md" -o -name "*.json" \) | while read -r changed_file; do
    # Get relative path inside TARGET
    rel_path="${changed_file#$TARGET/}"

    # Find the matching file inside the extracted OLD_ZIP
    # (we search by the end of the path because root folder names may differ)
    target_in_old=$(find "$WORKDIR" -type f -path "*/$rel_path" | head -n 1)

    if [[ -n "$target_in_old" ]]; then
      cp -f "$changed_file" "$target_in_old"
      echo -e "  ${GREEN}Updated:${NC} $rel_path"
    else
      echo -e "  ${YELLOW}Skipped (not found in OLD structure):${NC} $rel_path"
    fi
  done

  # 3. Create the new ZIP
  (
    cd "$WORKDIR" || exit 1
    zip -r -q "../$NEW_ZIP_NAME" .
  )

  # Move the new ZIP to current directory
  mv "$WORKDIR/../$NEW_ZIP_NAME" .

  # Cleanup
  rm -rf "$WORKDIR"

  echo
  echo -e "${GREEN}New ZIP created:${NC} ${YELLOW}$(pwd)/$NEW_ZIP_NAME${NC}"
  echo -e "${CYAN}This ZIP is based on the OLD_ZIP with the changed text files overwritten.${NC}"
fi