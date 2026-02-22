#!/bin/bash
set -e

BINARY_NAME="savebutton-daemon"
INSTALL_DIR="/usr/local/bin"
BINARY_PATH="$INSTALL_DIR/$BINARY_NAME"

echo "Uninstalling Save Button daemon..."

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
