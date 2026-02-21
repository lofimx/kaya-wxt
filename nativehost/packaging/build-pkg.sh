#!/bin/bash
set -e

# Build a .pkg installer for the Save Button native host (macOS).
#
# Usage: ./build-pkg.sh <binary-path>
#   binary-path: path to the compiled savebutton-nativehost binary (universal)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="1.0.0"
PACKAGE_NAME="savebutton-nativehost"
IDENTIFIER="com.savebutton.nativehost"

BINARY_PATH="${1:?Usage: $0 <binary-path>}"

BUILD_DIR="$SCRIPT_DIR/build-pkg"
PKG_ROOT="$BUILD_DIR/root"
SCRIPTS_DIR="$BUILD_DIR/scripts"

echo "Building PKG installer..."

# Clean previous build
rm -rf "$BUILD_DIR"

# Create directory structure
mkdir -p "$PKG_ROOT/usr/local/bin"

# Copy binary
cp "$BINARY_PATH" "$PKG_ROOT/usr/local/bin/savebutton-nativehost"
chmod 755 "$PKG_ROOT/usr/local/bin/savebutton-nativehost"

# Create postinstall script — uses --install to place manifests for all browsers
mkdir -p "$SCRIPTS_DIR"
cat > "$SCRIPTS_DIR/postinstall" << 'POSTINSTALL'
#!/bin/bash

# Install native messaging manifests for all supported browsers
/usr/local/bin/savebutton-nativehost --install || true

# Determine the real user (not root)
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(dscl . -read /Users/"$REAL_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
if [ -z "$REAL_HOME" ]; then
    REAL_HOME="/Users/$REAL_USER"
fi

# Create data directories
su "$REAL_USER" -c "mkdir -p '$REAL_HOME/.kaya/anga' '$REAL_HOME/.kaya/meta'"

exit 0
POSTINSTALL
chmod 755 "$SCRIPTS_DIR/postinstall"

# Build the component package
pkgbuild \
    --root "$PKG_ROOT" \
    --identifier "$IDENTIFIER" \
    --version "$VERSION" \
    --scripts "$SCRIPTS_DIR" \
    --install-location / \
    "$BUILD_DIR/${PACKAGE_NAME}-${VERSION}.pkg"

OUTPUT="$BUILD_DIR/${PACKAGE_NAME}-${VERSION}.pkg"
echo ""
echo "PKG installer built: $OUTPUT"
