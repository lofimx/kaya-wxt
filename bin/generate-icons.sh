#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SVG_PATH="${1:-$PROJECT_ROOT/doc/design/yellow-floppy4.svg}"
OUTPUT_DIR="$PROJECT_ROOT/extension/public/icon"

if [ ! -f "$SVG_PATH" ]; then
  echo "Error: SVG file not found: $SVG_PATH"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

SIZES=(16 32 48 96 128)

echo "Generating icons from: $SVG_PATH"
echo "Output directory: $OUTPUT_DIR"

# Generate colored PNGs
for size in "${SIZES[@]}"; do
  echo "  icon-${size}.png"
  rsvg-convert -w "$size" -h "$size" "$SVG_PATH" -o "$OUTPUT_DIR/icon-${size}.png"
done

# Generate greyscale PNGs from the colored ones
for size in "${SIZES[@]}"; do
  echo "  icon-grey-${size}.png"
  magick "$OUTPUT_DIR/icon-${size}.png" -colorspace Gray "$OUTPUT_DIR/icon-grey-${size}.png"
done

# Generate green (success flash) PNGs from the colored ones
for size in "${SIZES[@]}"; do
  echo "  icon-green-${size}.png"
  magick "$OUTPUT_DIR/icon-${size}.png" -modulate 100,100,85 -fill '#4caf50' -colorize 60 "$OUTPUT_DIR/icon-green-${size}.png"
done

# Copy colored SVG variants for Firefox
for size in 48 96; do
  echo "  icon-${size}.svg"
  cp "$SVG_PATH" "$OUTPUT_DIR/icon-${size}.svg"
done

# Generate greyscale SVG variants for Firefox
# We create a wrapper SVG that applies a greyscale filter
for size in 48 96; do
  echo "  icon-grey-${size}.svg"
  cat > "$OUTPUT_DIR/icon-grey-${size}.svg" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 512 512">
  <defs>
    <filter id="greyscale">
      <feColorMatrix type="saturate" values="0"/>
    </filter>
  </defs>
  <image href="icon-${size}.svg" width="512" height="512" filter="url(#greyscale)"/>
</svg>
EOF
done

echo "Done. Generated $(ls "$OUTPUT_DIR" | wc -l) icon files."
