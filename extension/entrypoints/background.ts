import { browser } from "wxt/browser";
import { generateTimestamp } from "@/utils/timestamp";
import { writeFile, readAllBookmarkUrls } from "@/utils/opfs";
import { loadConfig } from "@/utils/config";
import { syncWithServer, testConnection } from "@/utils/sync";
import { pushFileToDaemon } from "@/utils/daemon";

let knownBookmarkedUrls = new Set<string>();

async function refreshBookmarkUrls() {
  try {
    knownBookmarkedUrls = await readAllBookmarkUrls();
  } catch (error) {
    console.error("Failed to refresh bookmark URLs:", error);
  }
}

async function updateIconForActiveTab() {
  try {
    const tabs = await browser.tabs.query({
      active: true,
      currentWindow: true,
    });
    if (tabs.length === 0) return;

    const tab = tabs[0];
    const isBookmarked = tab.url ? knownBookmarkedUrls.has(tab.url) : false;

    const iconPath = isBookmarked
      ? {
          16: "/icon/icon-16.png",
          32: "/icon/icon-32.png",
          48: "/icon/icon-48.png",
          96: "/icon/icon-96.png",
        }
      : {
          16: "/icon/icon-grey-16.png",
          32: "/icon/icon-grey-32.png",
          48: "/icon/icon-grey-48.png",
          96: "/icon/icon-grey-96.png",
        };

    const action = browser.action ?? (browser as any).browserAction;
    if (action) {
      await action.setIcon({ path: iconPath, tabId: tab.id });
    }
  } catch (error) {
    console.error("Failed to update icon:", error);
  }
}

async function triggerSync() {
  try {
    const config = await loadConfig();
    if (!config.configured || !config.email || !config.password) return;
    const result = await syncWithServer(config);
    const total =
      result.anga.downloaded +
      result.anga.uploaded +
      result.meta.downloaded +
      result.meta.uploaded;
    if (total > 0) {
      console.log(
        `Sync: ${result.anga.downloaded + result.meta.downloaded} downloaded, ${result.anga.uploaded + result.meta.uploaded} uploaded`,
      );
      await refreshBookmarkUrls();
      await updateIconForActiveTab();
    }
  } catch (error) {
    console.error("Sync error:", error);
  }
}

async function saveAnga(
  filename: string,
  content: string | ArrayBuffer,
): Promise<void> {
  await writeFile("anga", filename, content);
  pushFileToDaemon("anga", filename, content);
  await refreshBookmarkUrls();
  await updateIconForActiveTab();
  triggerSync();
}

async function saveMeta(filename: string, content: string): Promise<void> {
  await writeFile("meta", filename, content);
  pushFileToDaemon("meta", filename, content);
  triggerSync();
}

async function saveImage(imageUrl: string, timestamp: string) {
  const response = await fetch(imageUrl);
  if (!response.ok) {
    throw new Error("Failed to fetch image");
  }

  const arrayBuffer = await response.arrayBuffer();

  let filename: string;
  try {
    const urlObj = new URL(imageUrl);
    const originalFilename = urlObj.pathname.split("/").pop() || "image";
    filename = `${timestamp}-${originalFilename}`;
  } catch {
    const contentType = response.headers.get("content-type") || "image/png";
    const ext = contentType.split("/")[1] || "png";
    filename = `${timestamp}-image.${ext}`;
  }

  await saveAnga(filename, arrayBuffer);
  showNotification("Image added to Save Button");
}

function showNotification(message: string) {
  browser.notifications
    .create({
      type: "basic",
      iconUrl: "/icon/icon-96.png",
      title: "Save Button",
      message: message,
    })
    .catch(console.error);
}

export default defineBackground(() => {
  refreshBookmarkUrls();

  browser.tabs.onActivated.addListener(() => {
    updateIconForActiveTab();
  });

  browser.tabs.onUpdated.addListener((_tabId, changeInfo) => {
    if (changeInfo.url || changeInfo.status === "complete") {
      updateIconForActiveTab();
    }
  });

  // Set up periodic sync via alarms (MV3-safe, minimum 1 minute)
  browser.alarms.create("sync", { periodInMinutes: 1 });
  browser.alarms.onAlarm.addListener((alarm) => {
    if (alarm.name === "sync") {
      triggerSync();
    }
  });

  browser.contextMenus.create({
    id: "save-to-kaya-text",
    title: "Add to Save Button",
    contexts: ["selection"],
  });

  browser.contextMenus.create({
    id: "save-to-kaya-image",
    title: "Add to Save Button",
    contexts: ["image"],
  });

  browser.contextMenus.onClicked.addListener(async (info) => {
    const timestamp = generateTimestamp();

    try {
      if (info.menuItemId === "save-to-kaya-text" && info.selectionText) {
        const filename = `${timestamp}-quote.md`;
        await saveAnga(filename, info.selectionText);
        showNotification("Text added to Save Button");
      } else if (info.menuItemId === "save-to-kaya-image" && info.srcUrl) {
        await saveImage(info.srcUrl, timestamp);
      }
    } catch (error: any) {
      console.error("Failed to save:", error);
      showNotification("Error: " + error.message);
    }
  });

  browser.runtime.onMessage.addListener(
    (request: any, _sender, sendResponse) => {
      if (request.action === "saveBookmark") {
        saveAnga(request.filename, request.content)
          .then(() => sendResponse({ success: true }))
          .catch((error: any) => sendResponse({ error: error.message }));
        return true;
      }

      if (request.action === "saveMeta") {
        saveMeta(request.filename, request.content)
          .then(() => sendResponse({ success: true }))
          .catch((error: any) => sendResponse({ error: error.message }));
        return true;
      }

      if (request.action === "testConnection") {
        const config = request.data;
        testConnection(config)
          .then(() => sendResponse({ success: true }))
          .catch((error: any) => sendResponse({ error: error.message }));
        return true;
      }

      if (request.action === "triggerSync") {
        triggerSync()
          .then(() => sendResponse({ success: true }))
          .catch((error: any) => sendResponse({ error: error.message }));
        return true;
      }
    },
  );
});
