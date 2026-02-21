import { browser } from "wxt/browser";
import { generateTimestamp } from "@/utils/timestamp";

const NATIVE_HOST_NAME = "org.savebutton.nativehost";

let nativePort: ReturnType<typeof browser.runtime.connectNative> | null = null;
let knownBookmarkedUrls = new Set<string>();
let pendingResponses = new Map<
  number,
  { resolve: (value: any) => void; reject: (reason: any) => void }
>();
let messageId = 0;

function connectToNativeHost() {
  if (nativePort) {
    return nativePort;
  }

  try {
    nativePort = browser.runtime.connectNative(NATIVE_HOST_NAME);

    nativePort.onMessage.addListener((message: any) => {
      console.log("Received from native host:", message);

      if (message.id && pendingResponses.has(message.id)) {
        const { resolve, reject } = pendingResponses.get(message.id)!;
        pendingResponses.delete(message.id);

        if (message.error) {
          reject(new Error(message.error));
        } else {
          resolve(message);
        }
      }

      if (message.type === "bookmarks") {
        knownBookmarkedUrls = new Set(message.urls || []);
        updateIconForActiveTab();
      }
    });

    nativePort.onDisconnect.addListener(() => {
      console.error("Native host disconnected");
      nativePort = null;

      for (const [_id, { reject }] of pendingResponses) {
        reject(new Error("Native host disconnected"));
      }
      pendingResponses.clear();
    });

    return nativePort;
  } catch (error) {
    console.error("Failed to connect to native host:", error);
    nativePort = null;
    throw error;
  }
}

async function sendToNativeHost(message: Record<string, any>) {
  const port = connectToNativeHost();

  return new Promise((resolve, reject) => {
    const id = ++messageId;
    message.id = id;

    pendingResponses.set(id, { resolve, reject });

    setTimeout(() => {
      if (pendingResponses.has(id)) {
        pendingResponses.delete(id);
        reject(new Error("Request timed out"));
      }
    }, 30000);

    try {
      port.postMessage(message);
    } catch (error) {
      pendingResponses.delete(id);
      reject(error);
    }
  });
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

async function saveImage(imageUrl: string, timestamp: string) {
  const response = await fetch(imageUrl);
  if (!response.ok) {
    throw new Error("Failed to fetch image");
  }

  const blob = await response.blob();
  const arrayBuffer = await blob.arrayBuffer();
  const bytes = new Uint8Array(arrayBuffer);
  let binary = "";
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  const base64 = btoa(binary);

  let filename: string;
  try {
    const urlObj = new URL(imageUrl);
    const originalFilename = urlObj.pathname.split("/").pop() || "image";
    filename = `${timestamp}-${originalFilename}`;
  } catch {
    const ext = blob.type.split("/")[1] || "png";
    filename = `${timestamp}-image.${ext}`;
  }

  const message = {
    message: "anga",
    filename: filename,
    type: "base64",
    base64: base64,
  };

  await sendToNativeHost(message);
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
  browser.tabs.onActivated.addListener(() => {
    updateIconForActiveTab();
  });

  browser.tabs.onUpdated.addListener((_tabId, changeInfo) => {
    if (changeInfo.url || changeInfo.status === "complete") {
      updateIconForActiveTab();
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
        const message = {
          message: "anga",
          filename: filename,
          type: "text",
          text: info.selectionText,
        };

        await sendToNativeHost(message);
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
      if (request.action === "sendToNative") {
        sendToNativeHost(request.data)
          .then((response) => {
            updateIconForActiveTab();
            sendResponse(response);
          })
          .catch((error: any) => {
            sendResponse({ error: error.message });
          });
        return true;
      }

      if (request.action === "sendConfig") {
        sendToNativeHost(request.data)
          .then((response) => sendResponse(response))
          .catch((error: any) => sendResponse({ error: error.message }));
        return true;
      }

      if (request.action === "testConnection") {
        sendToNativeHost(request.data)
          .then((response) => sendResponse(response))
          .catch((error: any) => sendResponse({ error: error.message }));
        return true;
      }

      if (request.action === "checkConfigStatus") {
        sendToNativeHost({ message: "config_status" })
          .then((response) => sendResponse(response))
          .catch((error: any) => sendResponse({ error: error.message }));
        return true;
      }
    },
  );

  connectToNativeHost();
});
