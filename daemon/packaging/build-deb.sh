#!/bin/bash
set -e

# Build a .deb package for the Save Button daemon.
#
# Usage: ./build-deb.sh <binary-path>
#   binary-path: path to the compiled savebutton-daemon binary

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="1.0.0"
PACKAGE_NAME="savebutton-daemon"
ARCH="amd64"

BINARY_PATH="${1:?Usage: $0 <binary-path>}"

BUILD_DIR="$SCRIPT_DIR/build-deb"
PKG_ROOT="$BUILD_DIR/${PACKAGE_NAME}_${VERSION}_${ARCH}"

echo "Building DEB package..."

# Clean previous build
rm -rf "$PKG_ROOT"

# Create directory structure
mkdir -p "$PKG_ROOT/DEBIAN"
mkdir -p "$PKG_ROOT/usr/lib/savebutton"
mkdir -p "$PKG_ROOT/etc/skel/.kaya/anga"
mkdir -p "$PKG_ROOT/etc/skel/.kaya/meta"

# Copy binary
cp "$BINARY_PATH" "$PKG_ROOT/usr/lib/savebutton/savebutton-daemon"
chmod 755 "$PKG_ROOT/usr/lib/savebutton/savebutton-daemon"

# Create control file
cat > "$PKG_ROOT/DEBIAN/control" << EOF
Package: ${PACKAGE_NAME}
Version: ${VERSION}
Architecture: ${ARCH}
Maintainer: lofi.mx
Description: Save Button Daemon
 Optional local daemon for the Save Button browser extension.
 Mirrors saved bookmarks, quotes, and images to ~/.kaya/ on disk
 and syncs them with the Save Button server.
Section: web
Priority: optional
Homepage: https://savebutton.com
EOF

# Create postinst script
cat > "$PKG_ROOT/DEBIAN/postinst" << 'POSTINST'
#!/bin/bash
set -e

# Create data directories for the current user if running interactively
if [ -n "$SUDO_USER" ]; then
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    if [ -n "$REAL_HOME" ]; then
        su "$SUDO_USER" -c "mkdir -p '$REAL_HOME/.kaya/anga' '$REAL_HOME/.kaya/meta'"
    fi
fi
POSTINST
chmod 755 "$PKG_ROOT/DEBIAN/postinst"

# Build the .deb
dpkg-deb --build --root-owner-group "$PKG_ROOT"

OUTPUT="${PKG_ROOT}.deb"
echo ""
echo "DEB package built: $OUTPUT"
