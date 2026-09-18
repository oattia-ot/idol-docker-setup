#!/bin/bash

# PDF Merge and Compress Script
# Sorts PDF files by name and merges them into a single compressed PDF

# Configuration
# IDOL OS detection (Ubuntu / macOS) — loads module/os-compat.sh when present
if [ -z "${IDOL_OS_COMPAT_LOADED:-}" ]; then
  _idol_os_src=""
  if [ -n "${IDOL_BASE_PATH:-}" ] && [ -f "${IDOL_BASE_PATH}/module/os-compat.sh" ]; then
    _idol_os_src="${IDOL_BASE_PATH}/module/os-compat.sh"
  else
    _idol_os_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
    _idol_os_probe="$_idol_os_dir"
    _idol_os_i=0
    while [ -n "$_idol_os_probe" ] && [ "$_idol_os_probe" != "/" ] && [ "$_idol_os_i" -lt 20 ]; do
      if [ -f "$_idol_os_probe/module/os-compat.sh" ]; then
        _idol_os_src="$_idol_os_probe/module/os-compat.sh"
        break
      fi
      _idol_os_probe="$(dirname "$_idol_os_probe")"
      _idol_os_i=$((_idol_os_i + 1))
    done
  fi
  if [ -n "$_idol_os_src" ]; then
    # shellcheck source=/dev/null
    . "$_idol_os_src"
  else
    case "$(uname -s 2>/dev/null)" in
      Darwin)
        export IDOL_HOST_OS=macos IDOL_OS_FAMILY=macos
        ;;
      Linux)
        export IDOL_OS_FAMILY=linux
        if [ -f /etc/os-release ] && grep -qi ubuntu /etc/os-release 2>/dev/null; then
          export IDOL_HOST_OS=ubuntu
        else
          export IDOL_HOST_OS=linux
        fi
        ;;
      *)
        export IDOL_HOST_OS=unknown IDOL_OS_FAMILY=unknown
        ;;
    esac
  fi
  unset _idol_os_src _idol_os_dir _idol_os_probe _idol_os_i
fi

INPUT_DIR="${1:-.}"  # Use first argument as directory, or current directory
OUTPUT_FILE="${2:-merged_output.pdf}"  # Use second argument as output name, or default
TEMP_MERGED="temp_merged.pdf"

# Check if ghostscript is installed
if ! command -v gs &> /dev/null; then
    echo "Error: Ghostscript (gs) is not installed."
    echo "Install it with: sudo apt-get install ghostscript  # Debian/Ubuntu"
    echo "              or: brew install ghostscript         # macOS"
    exit 1
fi

# Navigate to input directory
cd "$INPUT_DIR" || exit 1

# Find and sort PDF files
mapfile -t pdf_files < <(find . -maxdepth 1 -type f -name "*.pdf" | sort)

# Check if any PDF files were found
if [ ${#pdf_files[@]} -eq 0 ]; then
    echo "No PDF files found in $INPUT_DIR"
    exit 1
fi

echo "Found ${#pdf_files[@]} PDF file(s):"
printf '%s\n' "${pdf_files[@]}"
echo ""

# Merge PDFs using ghostscript
echo "Merging PDFs..."
gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite \
   -sOutputFile="$TEMP_MERGED" \
   "${pdf_files[@]}"

if [ $? -ne 0 ]; then
    echo "Error: Failed to merge PDFs"
    exit 1
fi

# Compress the merged PDF
echo "Compressing merged PDF..."
gs -dBATCH -dNOPAUSE -q \
   -sDEVICE=pdfwrite \
   -dCompatibilityLevel=1.4 \
   -dPDFSETTINGS=/ebook \
   -dEmbedAllFonts=true \
   -dSubsetFonts=true \
   -dColorImageDownsampleType=/Bicubic \
   -dColorImageResolution=150 \
   -dGrayImageDownsampleType=/Bicubic \
   -dGrayImageResolution=150 \
   -dMonoImageDownsampleType=/Bicubic \
   -dMonoImageResolution=150 \
   -sOutputFile="$OUTPUT_FILE" \
   "$TEMP_MERGED"

if [ $? -ne 0 ]; then
    echo "Error: Failed to compress PDF"
    rm -f "$TEMP_MERGED"
    exit 1
fi

# Clean up temporary file
rm -f "$TEMP_MERGED"

# Display results
ORIGINAL_SIZE=$(du -h "${pdf_files[@]}" | awk '{sum+=$1} END {print sum}')
FINAL_SIZE=$(du -h "$OUTPUT_FILE" | awk '{print $1}')

echo ""
echo "✓ Success!"
echo "Output file: $OUTPUT_FILE"
echo "Final size: $FINAL_SIZE"
echo ""