#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_NAME="savebutton-daemon"

echo "Building Save Button daemon..."
cd "$SCRIPT_DIR"
cargo build --release

echo "Installing binary..."
INSTALL_DIR="/usr/local/bin"
sudo cp "target/release/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
sudo chmod +x "$INSTALL_DIR/$BINARY_NAME"

echo "Creating ~/.kaya directories..."
mkdir -p "$HOME/.kaya/anga"
mkdir -p "$HOME/.kaya/meta"

echo ""
echo "Installation complete!"
echo ""
echo "Binary installed to: $INSTALL_DIR/$BINARY_NAME"
echo ""
echo "To start the daemon:"
echo "  $BINARY_NAME"
echo ""
echo "The daemon listens on localhost:21420 and writes files to ~/.kaya/"
