#!/bin/bash
set -e

BINARY_NAME="savebutton-nativehost"
INSTALL_DIR="/usr/local/bin"
BINARY_PATH="$INSTALL_DIR/$BINARY_NAME"

echo "Uninstalling Save Button native host..."

# Remove native messaging manifests for all browsers
if [ -f "$BINARY_PATH" ]; then
    "$BINARY_PATH" --uninstall || true
    echo "  Removed native messaging manifests"
fi

# Remove binary
if [ -f "$BINARY_PATH" ]; then
    sudo rm "$BINARY_PATH"
    echo "  Removed binary: $BINARY_PATH"
else
    echo "  Binary not found (already removed): $BINARY_PATH"
fi

echo ""
echo "Uninstallation complete!"
echo ""
echo "Note: User data in ~/.kaya was NOT removed."
echo "Delete it manually if you want to remove all Save Button data."
