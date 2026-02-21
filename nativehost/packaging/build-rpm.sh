#!/bin/bash
set -e

# Build an .rpm package for the Save Button native host.
#
# Usage: ./build-rpm.sh <binary-path>
#   binary-path: path to the compiled savebutton-nativehost binary

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="1.0.0"
PACKAGE_NAME="savebutton-nativehost"

BINARY_PATH="$(realpath "${1:?Usage: $0 <binary-path>}")"

RPMBUILD_DIR="$SCRIPT_DIR/build-rpm/rpmbuild"

echo "Building RPM package..."

# Clean previous build
rm -rf "$RPMBUILD_DIR"

# Create rpmbuild directory structure
mkdir -p "$RPMBUILD_DIR"/{SPECS,SOURCES,BUILD,RPMS,SRPMS}

# Create source tarball
TARBALL_DIR="$RPMBUILD_DIR/SOURCES/${PACKAGE_NAME}-${VERSION}"
mkdir -p "$TARBALL_DIR"
cp "$BINARY_PATH" "$TARBALL_DIR/savebutton-nativehost"

tar -czf "$RPMBUILD_DIR/SOURCES/${PACKAGE_NAME}-${VERSION}.tar.gz" \
    -C "$RPMBUILD_DIR/SOURCES" "${PACKAGE_NAME}-${VERSION}"

# Create spec file
cat > "$RPMBUILD_DIR/SPECS/${PACKAGE_NAME}.spec" << EOF
Name:           ${PACKAGE_NAME}
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        Save Button Native Host
License:        MIT
URL:            https://savebutton.com
Source0:        %{name}-%{version}.tar.gz

%description
Native messaging host for the Save Button browser extension.
Saves bookmarks, quotes, and images locally and syncs them
with the Save Button server.

%prep
%setup -q

%install
mkdir -p %{buildroot}/usr/lib/savebutton
mkdir -p %{buildroot}/etc/skel/.kaya/anga
mkdir -p %{buildroot}/etc/skel/.kaya/meta

install -m 755 savebutton-nativehost %{buildroot}/usr/lib/savebutton/savebutton-nativehost

%post
# Install native messaging manifests for all supported browsers
/usr/lib/savebutton/savebutton-nativehost --install || true

# Create data directories for the current user if running interactively
if [ -n "\$SUDO_USER" ]; then
    REAL_HOME=\$(getent passwd "\$SUDO_USER" | cut -d: -f6)
    if [ -n "\$REAL_HOME" ]; then
        su "\$SUDO_USER" -c "mkdir -p '\$REAL_HOME/.kaya/anga' '\$REAL_HOME/.kaya/meta'"
    fi
fi

%preun
# Remove native messaging manifests on uninstall
/usr/lib/savebutton/savebutton-nativehost --uninstall || true

%files
%dir /usr/lib/savebutton
/usr/lib/savebutton/savebutton-nativehost
%dir /etc/skel/.kaya
%dir /etc/skel/.kaya/anga
%dir /etc/skel/.kaya/meta
EOF

# Build the RPM
rpmbuild --define "_topdir $RPMBUILD_DIR" -bb "$RPMBUILD_DIR/SPECS/${PACKAGE_NAME}.spec"

OUTPUT=$(find "$RPMBUILD_DIR/RPMS" -name "*.rpm" | head -1)
echo ""
echo "RPM package built: $OUTPUT"
