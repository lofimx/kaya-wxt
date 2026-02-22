import { browser } from "wxt/browser";
import { pushConfigToDaemon } from "@/utils/daemon";

const serverInput = document.getElementById("server") as HTMLInputElement;
const emailInput = document.getElementById("email") as HTMLInputElement;
const passwordInput = document.getElementById("password") as HTMLInputElement;
const saveBtn = document.getElementById("save-btn") as HTMLButtonElement;
const testBtn = document.getElementById("test-btn") as HTMLButtonElement;
const statusDiv = document.getElementById("status")!;

const PASSWORD_SENTINEL = "\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022";
let passwordChanged = false;

passwordInput.addEventListener("input", () => {
  passwordChanged = true;
});

function showStatus(message: string, type: string) {
  statusDiv.textContent = message;
  statusDiv.className = type;
}

async function loadSettings() {
  try {
    const result = await browser.storage.local.get([
      "server",
      "email",
      "password",
    ]);
    if (result.server) {
      serverInput.value = result.server as string;
    } else {
      serverInput.value = "https://savebutton.com";
    }
    if (result.email) {
      emailInput.value = result.email as string;
    }
    if (result.password) {
      passwordInput.value = PASSWORD_SENTINEL;
      passwordChanged = false;
    }
  } catch (error) {
    console.error("Failed to load settings:", error);
  }
}

async function saveSettings() {
  const server = serverInput.value.trim() || "https://savebutton.com";
  const email = emailInput.value.trim();

  if (!email) {
    showStatus("Email is required", "error");
    return;
  }

  if (passwordChanged && !passwordInput.value) {
    showStatus("Password is required", "error");
    return;
  }

  try {
    const settings: Record<string, string | boolean> = {
      server,
      email,
      configured: true,
    };

    if (passwordChanged) {
      settings.password = passwordInput.value;
    }

    await browser.storage.local.set(settings);

    // Push config to daemon if running (daemon is optional)
    const stored = await browser.storage.local.get([
      "server",
      "email",
      "password",
    ]);
    pushConfigToDaemon({
      server: stored.server as string,
      email: stored.email as string,
      password: stored.password as string,
      configured: true,
    });

    showStatus("Settings saved successfully", "success");
    passwordInput.value = PASSWORD_SENTINEL;
    passwordChanged = false;
  } catch (error: any) {
    showStatus("Error: " + error.message, "error");
  }
}

async function doTestConnection() {
  const server = serverInput.value.trim() || "https://savebutton.com";
  const email = emailInput.value.trim();

  if (!email) {
    showStatus("Email is required to test connection", "error");
    return;
  }

  let password: string;
  if (passwordChanged) {
    password = passwordInput.value;
  } else {
    const result = await browser.storage.local.get(["password"]);
    password = (result.password as string) || "";
  }

  if (!password) {
    showStatus("Password is required to test connection", "error");
    return;
  }

  showStatus("Testing connection...", "info");

  try {
    const response: any = await browser.runtime.sendMessage({
      action: "testConnection",
      data: { server, email, password, configured: true },
    });

    if (response && response.error) {
      showStatus("Connection failed: " + response.error, "error");
    } else if (response && response.success) {
      showStatus("Connection successful!", "success");
    } else {
      showStatus("Connection failed: no response", "error");
    }
  } catch (error: any) {
    showStatus("Connection failed: " + error.message, "error");
  }
}

saveBtn.addEventListener("click", saveSettings);
testBtn.addEventListener("click", doTestConnection);

loadSettings();
