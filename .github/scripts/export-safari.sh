#!/usr/bin/env bash
# Exports the Safari archive and uploads it to App Store Connect.
#
# Required environment variables:
#   APP_STORE_API_KEY     - App Store Connect API Key ID
#   APP_STORE_API_ISSUER  - App Store Connect API Issuer ID

set -euo pipefail

cd "safari/Save Button"

cat > ExportOptions.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>destination</key>
  <string>upload</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath build/SaveButton-macOS.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_${APP_STORE_API_KEY}.p8 \
  -authenticationKeyID "$APP_STORE_API_KEY" \
  -authenticationKeyIssuerID "$APP_STORE_API_ISSUER"
