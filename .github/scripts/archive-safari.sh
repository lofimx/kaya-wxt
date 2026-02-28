#!/usr/bin/env bash
# Archives the Safari extension as a universal binary (arm64 + x86_64).
#
# Required environment variables:
#   APP_STORE_API_KEY     - App Store Connect API Key ID
#   APP_STORE_API_ISSUER  - App Store Connect API Issuer ID
#   APPLE_TEAM_ID         - Apple Developer Team ID

set -euo pipefail

cd "safari/Save Button"

xcodebuild archive \
  -scheme "Save Button (macOS)" \
  -configuration Release \
  -archivePath build/SaveButton-macOS.xcarchive \
  -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_${APP_STORE_API_KEY}.p8 \
  -authenticationKeyID "$APP_STORE_API_KEY" \
  -authenticationKeyIssuerID "$APP_STORE_API_ISSUER"
