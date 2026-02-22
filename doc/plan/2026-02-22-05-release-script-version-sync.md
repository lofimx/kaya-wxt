# Update `release.rb` to sync all version files

## Context

The release script (`bin/release.rb`) only updated `extension/package.json`. With the addition of the Safari Xcode project, `MARKETING_VERSION` in the pbxproj also needs to stay in sync. The `bin/build-safari.sh` script also had a hardcoded version in its `--regen` hints.

## Changes

### `bin/release.rb`

- Add `safari/Save Button/Save Button.xcodeproj/project.pbxproj` as a version file
- On release, replace all `MARKETING_VERSION = <old>;` entries with the new version (8 occurrences across iOS/macOS Debug/Release for both app and extension targets)
- Read the current version from `package.json` to know what string to replace in the pbxproj
- Gracefully skip pbxproj if the file doesn't exist (Safari project may not be generated yet)
- Allow the pbxproj in the dirty-files check so it doesn't block the release

### `bin/build-safari.sh`

- Line 61: Replace hardcoded `0.2.0` with a dynamic read from `extension/package.json` so the `--regen` sed hint always prints the correct version.

## Tagging

No semver tags exist yet. After committing, tag the current SHA:

```
git tag v0.2.0
git push origin v0.2.0
```
