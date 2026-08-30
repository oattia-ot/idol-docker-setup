#!/bin/bash

# PDF Merge and Compress Script
# Sorts PDF files by name and merges them into a single compressed PDF

# Configuration
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