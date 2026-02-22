# Store Listing Text

Reuse this text across all browser extension stores to keep listings consistent.

## Name

Save Button

## Short Description

Save bookmarks, quotes, and images with Save Button

## Long Description

Save Button is a cross-browser bookmarking extension that saves your bookmarks, text quotes, and images locally and syncs them to your own server.

Click the toolbar button to bookmark any page. Right-click text or images to save them. Everything is stored as plain files in ~/.kaya/ on your computer and synced to your Save Button server over a simple HTTP API.

Features:
- One-click bookmarking from the toolbar
- Save text quotes and images from context menus
- Add notes to any bookmark
- Automatic sync with your Save Button server
- Works with Firefox, Chrome, Edge, and other Chromium-based browsers
- All data stored as plain files (bookmarks as .url, quotes as .md, metadata as .toml)
- No third-party analytics or tracking

Save Button requires a native host (savebutton-nativehost) to be installed separately for file storage and sync. Visit https://savebutton.com for setup instructions.

## Category

Productivity

## Website

https://savebutton.com

## Privacy Policy URL

https://savebutton.com/privacy

## Privacy Policy Summary

Save Button does not collect, transmit, or store any user data on third-party servers. All bookmarks, quotes, and images are stored locally on the user's computer in ~/.kaya/. If the user configures a Save Button server, data is synced only to that server using the credentials the user provides. No analytics, telemetry, or tracking of any kind is included in the extension or native host.

## Permissions Justification

- **nativeMessaging**: Communicates with a local native host (savebutton-nativehost) for file storage and server sync. No data leaves the user's machine except to their own configured server.
- **activeTab / tabs**: Reads the current tab URL and title to create bookmarks.
- **contextMenus**: Adds "Save to Kaya" options for saving selected text and images.
- **storage**: Stores extension preferences (server URL, email) in browser local storage.
- **notifications**: Displays error notifications to the user.
