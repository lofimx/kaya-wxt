import { browser } from "wxt/browser";
import { pushConfigToDaemon } from "@/utils/daemon";
import { loadConfig, saveConfig } from "@/utils/config";

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
    const config = await loadConfig();
    serverInput.value = config.server;
    if (config.email) {
      emailInput.value = config.email;
    }
    if (config.password) {
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
    const configUpdate: Parameters<typeof saveConfig>[0] = {
      server,
      email,
      configured: true,
    };

    if (passwordChanged) {
      configUpdate.password = passwordInput.value;
    }

    await saveConfig(configUpdate);

    // Push config to daemon if running (daemon is optional)
    const config = await loadConfig();
    pushConfigToDaemon(config);

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
    const config = await loadConfig();
    password = config.password;
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
