#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_NAME="savebutton-nativehost"

echo "Building Save Button native host..."
cd "$SCRIPT_DIR"
cargo build --release

echo "Installing binary..."
INSTALL_DIR="/usr/local/bin"
sudo cp "target/release/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
sudo chmod +x "$INSTALL_DIR/$BINARY_NAME"

echo "Creating ~/.kaya directories..."
mkdir -p "$HOME/.kaya/anga"
mkdir -p "$HOME/.kaya/meta"

echo "Installing native messaging manifests for all browsers..."
"$INSTALL_DIR/$BINARY_NAME" --install

echo ""
echo "Installation complete!"
echo ""
echo "Binary installed to: $INSTALL_DIR/$BINARY_NAME"
echo ""
echo "Next steps:"
echo "1. Install the browser extension from your browser's extension store"
echo "2. Configure the extension with your Save Button server credentials"
