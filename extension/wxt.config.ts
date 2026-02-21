import { defineConfig } from 'wxt';

export default defineConfig({
  manifest: {
    name: 'Save Button',
    description: 'Save bookmarks, quotes, and images with Save Button',
    author: 'lofi.mx',
    homepage_url: 'https://savebutton.com',
    permissions: [
      'activeTab',
      'tabs',
      'contextMenus',
      'nativeMessaging',
      'storage',
      'notifications',
    ],
    browser_specific_settings: {
      gecko: {
        id: 'org.savebutton@savebutton.org',
        strict_min_version: '91.0',
      },
    },
    icons: {
      16: '/icon/icon-16.png',
      32: '/icon/icon-32.png',
      48: '/icon/icon-48.png',
      96: '/icon/icon-96.png',
      128: '/icon/icon-128.png',
    },
  },
});
