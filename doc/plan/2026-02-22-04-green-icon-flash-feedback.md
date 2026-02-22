# Replace browser.notifications with green icon flash

**Date**: 2026-02-22

## Context

Safari doesn't support `browser.notifications.create()`. Context menu saves (text and images) currently use this API for user feedback at `background.ts:145`. Replace with a momentary green icon flash on the toolbar button -- works in all browsers including Safari, no new permissions needed.

## Approach

1. **Generate green icon PNGs** by recoloring the yellow floppy icon (`#ffd700` -> `#4caf50`) using ImageMagick. Add `icon-green-{16,32,48,96}.png` to `extension/public/icon/`. Update `bin/generate-icons.sh` to also produce green variants.

2. **Replace `showNotification()`** in `background.ts` with `flashGreenIcon()` that:
   - Gets the active tab ID
   - Sets the toolbar icon to the green variants for that tab
   - After 2 seconds, calls `updateIconForActiveTab()` to restore the correct state (yellow if bookmarked, grey if not)

3. **Remove `notifications` permission** from `wxt.config.ts` since it's no longer used.

4. **Add "Safari: Manual Tasks" section** to README.md covering Xcode signing, testing, and App Store submission steps.

## Files to modify

- `extension/entrypoints/background.ts` -- replace `showNotification()` with `flashGreenIcon()`
- `extension/public/icon/` -- add green icon PNGs
- `extension/wxt.config.ts` -- remove `notifications` from permissions
- `bin/generate-icons.sh` -- add green icon generation
- `README.md` -- add Safari manual tasks section

## Verification

- Build for Chrome: `pnpm wxt build -b chrome` -- no errors
- Build for Safari: `pnpm wxt build -b safari` -- no errors, no `notifications` in manifest
- Run tests: `pnpm test`
