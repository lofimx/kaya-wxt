#!/usr/bin/env bash
# Build the Save Button Safari extension.
#
# This script:
#   1. Builds the WXT extension for Safari (MV2)
#   2. Regenerates the Xcode project if safari/ doesn't exist
#
# The Xcode project references extension/.output/safari-mv2/ via relative
# paths, so step 1 is always required before opening or building in Xcode.
#
# Usage:
#   bin/build-safari.sh           # build WXT output only
#   bin/build-safari.sh --regen   # also regenerate the Xcode project

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXTENSION_DIR="$REPO_ROOT/extension"
SAFARI_DIR="$REPO_ROOT/safari"
WXT_OUTPUT="$EXTENSION_DIR/.output/safari-mv2"

REGEN=false
if [[ "${1:-}" == "--regen" ]]; then
  REGEN=true
fi

# Step 1: Build WXT for Safari
echo "Building WXT extension for Safari..."
cd "$EXTENSION_DIR"
pnpm wxt build -b safari

echo "WXT build output: $WXT_OUTPUT"

# Step 2: Regenerate Xcode project if requested or missing
if [[ "$REGEN" == true ]] || [[ ! -d "$SAFARI_DIR" ]]; then
  echo "Generating Xcode project..."

  if [[ -d "$SAFARI_DIR" ]]; then
    echo "Removing existing safari/ directory..."
    rm -rf "$SAFARI_DIR"
  fi

  xcrun safari-web-extension-converter "$WXT_OUTPUT" \
    --project-location "$SAFARI_DIR" \
    --app-name "Save Button" \
    --bundle-identifier org.savebutton.app \
    --no-open

  echo ""
  echo "Xcode project generated at: $SAFARI_DIR/Save Button/"
  echo ""
  echo "NOTE: After regenerating, you must manually reconfigure in Xcode:"
  echo "  - Set MACOSX_DEPLOYMENT_TARGET to 12.0"
  echo "  - Set IPHONEOS_DEPLOYMENT_TARGET to 16.0"
  echo "  - Set MARKETING_VERSION to match extension/package.json"
  echo "  - Configure signing team and App Groups"
  echo ""
  echo "Or apply these via sed:"
  echo "  sed -i '' 's/MACOSX_DEPLOYMENT_TARGET = 10.14/MACOSX_DEPLOYMENT_TARGET = 12.0/g' \"$SAFARI_DIR/Save Button/Save Button.xcodeproj/project.pbxproj\""
  echo "  sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = 15.0/IPHONEOS_DEPLOYMENT_TARGET = 16.0/g' \"$SAFARI_DIR/Save Button/Save Button.xcodeproj/project.pbxproj\""
  echo "  sed -i '' 's/MARKETING_VERSION = 1.0/MARKETING_VERSION = 0.2.0/g' \"$SAFARI_DIR/Save Button/Save Button.xcodeproj/project.pbxproj\""
fi

echo ""
echo "Done. To build and run in Xcode:"
echo "  open \"$SAFARI_DIR/Save Button/Save Button.xcodeproj\""
