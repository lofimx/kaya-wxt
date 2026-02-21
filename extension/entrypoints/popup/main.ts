import { browser } from "wxt/browser";
import { generateTimestamp, urlToDomainSlug } from "@/utils/timestamp";

// Setup view elements
const setupView = document.getElementById("setup-view")!;
const setupServerInput = document.getElementById(
  "setup-server",
) as HTMLInputElement;
const setupEmailInput = document.getElementById(
  "setup-email",
) as HTMLInputElement;
const setupPasswordInput = document.getElementById(
  "setup-password",
) as HTMLInputElement;
const setupSaveBtn = document.getElementById(
  "setup-save-btn",
) as HTMLButtonElement;
const setupError = document.getElementById("setup-error")!;

// Bookmark view elements
const bookmarkView = document.getElementById("bookmark-view")!;
const statusIcon = document.getElementById("status-icon")!;
const statusText = document.getElementById("status-text")!;
const noteContainer = document.getElementById("note-container")!;
const noteInput = document.getElementById("note-input") as HTMLInputElement;
const errorContainer = document.getElementById("error-container")!;
const errorText = document.getElementById("error-text")!;

let autoCloseTimeout: ReturnType<typeof setTimeout> | null = null;
let noteFocused = false;
let bookmarkSaved = false;
let currentTimestamp: string | null = null;
let currentFilename: string | null = null;

function showSetupError(message: string) {
  setupError.textContent = message;
  setupError.classList.remove("hidden");
}

function hideSetupError() {
  setupError.classList.add("hidden");
}

function showSuccess(message: string) {
  statusIcon.className = "success";
  statusText.textContent = message;
}

function showError(message: string) {
  statusIcon.className = "error";
  statusText.textContent = "Error";
  errorContainer.classList.remove("hidden");
  errorText.textContent = message;
}

function showSaving() {
  statusIcon.className = "saving";
  statusText.textContent = "Saving bookmark...";
}

function startAutoCloseTimer() {
  if (autoCloseTimeout) {
    clearTimeout(autoCloseTimeout);
  }
  autoCloseTimeout = setTimeout(() => {
    if (!noteFocused) {
      window.close();
    }
  }, 4000);
}

async function checkConfigured(): Promise<boolean> {
  try {
    const result = await browser.storage.local.get([
      "server",
      "email",
      "configured",
    ]);
    return result.configured === true && !!result.email;
  } catch (error) {
    console.error("Failed to check config:", error);
    return false;
  }
}

async function saveSetup() {
  hideSetupError();

  const server = setupServerInput.value.trim() || "https://savebutton.com";
  const email = setupEmailInput.value.trim();
  const password = setupPasswordInput.value;

  if (!email) {
    showSetupError("Email is required");
    return;
  }

  if (!password) {
    showSetupError("Password is required");
    return;
  }

  setupSaveBtn.textContent = "Saving...";
  setupSaveBtn.disabled = true;

  try {
    await browser.storage.local.set({ server, email, configured: true });

    const configMessage = {
      message: "config",
      server: server,
      email: email,
      password: password,
    };

    const response: any = await browser.runtime.sendMessage({
      action: "sendConfig",
      data: configMessage,
    });

    if (response && response.error) {
      showSetupError("Error: " + response.error);
      setupSaveBtn.textContent = "Save & Continue";
      setupSaveBtn.disabled = false;
      return;
    }

    // Setup complete, now save the bookmark
    setupView.classList.add("hidden");
    bookmarkView.classList.remove("hidden");
    saveBookmark();
  } catch (error: any) {
    showSetupError("Error: " + error.message);
    setupSaveBtn.textContent = "Save & Continue";
    setupSaveBtn.disabled = false;
  }
}

async function saveBookmark() {
  showSaving();

  try {
    const tabs = await browser.tabs.query({
      active: true,
      currentWindow: true,
    });
    const tab = tabs[0];

    if (!tab || !tab.url) {
      showError("No active tab found");
      return;
    }

    currentTimestamp = generateTimestamp();
    const domainSlug = urlToDomainSlug(tab.url);
    currentFilename = `${currentTimestamp}-${domainSlug}.url`;

    const urlFileContent = `[InternetShortcut]\nURL=${tab.url}\n`;

    const message = {
      message: "anga",
      filename: currentFilename,
      type: "text",
      text: urlFileContent,
    };

    const response: any = await browser.runtime.sendMessage({
      action: "sendToNative",
      data: message,
    });

    if (response && response.error) {
      showError(response.error);
    } else {
      bookmarkSaved = true;
      showSuccess("Bookmark saved!");
      startAutoCloseTimer();
    }
  } catch (error: any) {
    showError(error.message || "Failed to save bookmark");
  }
}

async function saveNote(noteText: string) {
  if (!currentTimestamp || !currentFilename) {
    showError("No bookmark to attach note to");
    return;
  }

  const metaFilename = `${currentTimestamp}-note.toml`;
  const metaContent = `[anga]\nfilename = "${currentFilename}"\n\n[meta]\nnote = '''${noteText}'''`;

  const message = {
    message: "meta",
    filename: metaFilename,
    type: "text",
    text: metaContent,
  };

  try {
    const response: any = await browser.runtime.sendMessage({
      action: "sendToNative",
      data: message,
    });

    if (response && response.error) {
      showError(response.error);
    } else {
      showSuccess("Bookmark and note saved!");
      setTimeout(() => window.close(), 1000);
    }
  } catch (error: any) {
    showError(error.message || "Failed to save note");
  }
}

// Setup view event listeners
setupSaveBtn.addEventListener("click", saveSetup);

setupPasswordInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") {
    e.preventDefault();
    saveSetup();
  }
});

// Bookmark view event listeners
noteInput.addEventListener("focus", () => {
  noteFocused = true;
  if (autoCloseTimeout) {
    clearTimeout(autoCloseTimeout);
    autoCloseTimeout = null;
  }
});

noteInput.addEventListener("blur", () => {
  noteFocused = false;
  if (bookmarkSaved && !noteInput.value.trim()) {
    startAutoCloseTimer();
  }
});

noteInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") {
    e.preventDefault();
    const noteText = noteInput.value.trim().replace(/[\n\r]/g, " ");
    if (noteText && bookmarkSaved) {
      saveNote(noteText);
    } else if (bookmarkSaved) {
      window.close();
    }
  }
});

// Initialize: check if configured
async function init() {
  const isConfigured = await checkConfigured();

  if (isConfigured) {
    bookmarkView.classList.remove("hidden");
    saveBookmark();
  } else {
    setupView.classList.remove("hidden");
    setupServerInput.value = "https://savebutton.com";
  }
}

init();
