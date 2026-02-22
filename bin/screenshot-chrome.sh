#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXTENSION_DIR="$PROJECT_ROOT/extension"
OUTPUT_DIR="$PROJECT_ROOT/doc/stores"
SCREENSHOT_PATH="$OUTPUT_DIR/screenshot-1-popup.png"

# --- Preflight checks ---

echo "=== Save Button Screenshot Helper ==="
echo ""

# Check pnpm
if ! command -v pnpm &>/dev/null; then
  PNPM_PATH="$(mise which pnpm 2>/dev/null || true)"
  if [ -z "$PNPM_PATH" ]; then
    echo "Error: pnpm not found. Install it via mise or npm."
    exit 1
  fi
  export PATH="$(dirname "$PNPM_PATH"):$PATH"
fi

# Check that Chrome for Testing is available (WXT downloads it on first dev run)
echo "Step 1: Checking Chrome for Testing..."
cd "$EXTENSION_DIR"
if [ ! -d node_modules ]; then
  echo "  Installing extension dependencies..."
  pnpm install
fi

# WXT stores Chrome for Testing under node_modules
CHROME_FOR_TESTING=$(find "$EXTENSION_DIR/node_modules" -name "chrome" -type f -executable 2>/dev/null | grep "chrome-for-testing" | head -1)
if [ -z "$CHROME_FOR_TESTING" ]; then
  echo "  Chrome for Testing not found yet. Running a quick build to trigger download..."
  pnpm wxt build -b chrome >/dev/null 2>&1 || true
  CHROME_FOR_TESTING=$(find "$EXTENSION_DIR/node_modules" -name "chrome" -type f -executable 2>/dev/null | grep "chrome-for-testing" | head -1)
fi

if [ -z "$CHROME_FOR_TESTING" ]; then
  echo "  Warning: Could not locate Chrome for Testing binary."
  echo "  WXT will download it when you run 'pnpm dev:chrome'."
else
  echo "  Found: $CHROME_FOR_TESTING"
fi

# --- Launch Chrome for Testing with WXT ---

echo ""
echo "Step 2: Launching Chrome with the extension..."
echo ""
echo "  The browser will open. To take a screenshot:"
echo ""
echo "  1. Resize the browser window to approximately 1280x800"
echo "     (GNOME: drag the window edges, or use a tiling shortcut)"
echo "  2. Navigate to any website (e.g. https://savebutton.com)"
echo "  3. Click the Save Button toolbar icon to show the popup"
echo "  4. Take a screenshot of the browser window:"
echo "     - GNOME: press Alt+Print Screen to capture just the window"
echo "     - Or use: gnome-screenshot -w -f $SCREENSHOT_PATH"
echo "  5. If you used Alt+Print Screen, copy the file to:"
echo "     $SCREENSHOT_PATH"
echo ""
echo "  Press Ctrl+C in this terminal when you're done to stop the dev server."
echo ""
read -p "Press Enter to launch Chrome for Testing..."

cd "$EXTENSION_DIR"
pnpm dev:chrome
