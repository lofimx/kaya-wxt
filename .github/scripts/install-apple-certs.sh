#!/usr/bin/env bash
# Installs Apple certificates, provisioning profiles, and App Store Connect
# API key into a temporary keychain for CI code signing.
#
# Required environment variables:
#   RUNNER_TEMP                      - GitHub Actions temp directory
#   APPLE_CERTIFICATE_BASE64         - Distribution certificate (.p12), base64-encoded
#   APPLE_CERTIFICATE_PASSWORD       - Password for the distribution .p12
#   APPLE_DEV_CERTIFICATE_BASE64     - Development certificate (.p12), base64-encoded
#   APPLE_DEV_CERTIFICATE_PASSWORD   - Password for the development .p12
#   APPLE_PROVISION_PROFILE_APP_BASE64 - Provisioning profile for container app, base64-encoded
#   APPLE_PROVISION_PROFILE_EXT_BASE64 - Provisioning profile for extension, base64-encoded
#   APP_STORE_API_KEY_BASE64         - App Store Connect API key (.p8), base64-encoded
#   APP_STORE_API_KEY                - App Store Connect API Key ID

set -euo pipefail

# Create temporary keychain
KEYCHAIN_PATH=$RUNNER_TEMP/app-signing.keychain-db
KEYCHAIN_PASSWORD=$(openssl rand -base64 32)

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

# Import distribution certificate (for App Store export)
DIST_CERT_PATH=$RUNNER_TEMP/distribution.p12
echo -n "$APPLE_CERTIFICATE_BASE64" | base64 --decode -o "$DIST_CERT_PATH"
security import "$DIST_CERT_PATH" \
  -P "$APPLE_CERTIFICATE_PASSWORD" \
  -A \
  -t cert \
  -f pkcs12 \
  -k "$KEYCHAIN_PATH"

# Import development certificate (for archive/build signing)
DEV_CERT_PATH=$RUNNER_TEMP/development.p12
echo -n "$APPLE_DEV_CERTIFICATE_BASE64" | base64 --decode -o "$DEV_CERT_PATH"
security import "$DEV_CERT_PATH" \
  -P "$APPLE_DEV_CERTIFICATE_PASSWORD" \
  -A \
  -t cert \
  -f pkcs12 \
  -k "$KEYCHAIN_PATH"

security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security list-keychain -d user -s "$KEYCHAIN_PATH"

# Install provisioning profiles
mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles

echo -n "$APPLE_PROVISION_PROFILE_APP_BASE64" | base64 --decode \
  -o ~/Library/MobileDevice/Provisioning\ Profiles/SaveButton_App.provisionprofile
echo -n "$APPLE_PROVISION_PROFILE_EXT_BASE64" | base64 --decode \
  -o ~/Library/MobileDevice/Provisioning\ Profiles/SaveButton_Ext.provisionprofile

# Write App Store Connect API key for -allowProvisioningUpdates
mkdir -p ~/.appstoreconnect/private_keys
echo -n "$APP_STORE_API_KEY_BASE64" | base64 --decode \
  -o ~/.appstoreconnect/private_keys/AuthKey_${APP_STORE_API_KEY}.p8
