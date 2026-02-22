import { defineConfig } from "wxt";

// Static key ensures a stable extension ID (kpdhgjmpibjlajlhagbgmnpjifbdbjhd) across
// dev sessions and unpacked installs. Chrome Web Store rejects manifests containing
// the key field, so it is only included in development mode.
const DEV_KEY =
  "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuGJ/yHRh2QxnX1fHwuULS3Br2dQf0WagwLjQeZsNQJR82/iHdO81HLGXfkxe8w8P8iOGxIJZbJPTVyjzHzVqMIQ3QSWapIQZ537SYNv5V+CunYHQgoiSgGMzRqlkAOt/ZLBZaZZzEYpYwpiuAXG9kyIh+4pBThmgSNXjPGBfe4BiLLUyoF7pukacuj8R78/P9d4IRqgQTnPPF0QWXu7kWuJpRUOPj5tAycE4kscFYTrQEbFigdqGQnqwuMwAMvEehiyjRPRiUdauUItYxkk2arwVIRH4U3hDGKtR+FrqF/0mPGDarcTYwz4zr8u5UdfH6TpeuSY2LhDppSvmXPXdpQIDAQAB";

export default defineConfig({
  manifest: ({ mode }) => ({
    ...(mode === "development" ? { key: DEV_KEY } : {}),
    name: "Save Button",
    description: "Save bookmarks, quotes, and images with Save Button",
    author: "lofi.mx",
    homepage_url: "https://savebutton.com",
    permissions: [
      "activeTab",
      "tabs",
      "contextMenus",
      "storage",
      "notifications",
      "alarms",
    ],
    host_permissions: ["<all_urls>"],
    browser_specific_settings: {
      gecko: {
        id: "org.savebutton@savebutton.org",
        strict_min_version: "91.0",
      },
    },
    icons: {
      16: "/icon/icon-16.png",
      32: "/icon/icon-32.png",
      48: "/icon/icon-48.png",
      96: "/icon/icon-96.png",
      128: "/icon/icon-128.png",
    },
  }),
});
