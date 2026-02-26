import { browser } from "wxt/browser";
import { encryptPassword, decryptPassword } from "./crypto";

export interface Config {
  server: string;
  email: string;
  password: string; // TODO: remove me -- legacy
  configured: boolean;
}

const DEFAULT_SERVER = "https://savebutton.com";

export async function loadConfig(): Promise<Config> {
  const result = await browser.storage.local.get([
    "server",
    "email",
    "configured",
    "password", // TODO: remove me -- legacy -- checked for migration
  ]);

  let password = "";

  // Try decrypting the encrypted password first
  const decrypted = await decryptPassword();
  if (decrypted !== null) {
    password = decrypted;
  } else if (result.password) {
    // TODO: remove legacy password block
    // Legacy plaintext password found -- migrate it
    password = result.password as string;
    await encryptPassword(password);
  }

  return {
    server: (result.server as string) || DEFAULT_SERVER,
    email: (result.email as string) || "",
    password,
    configured: result.configured === true,
  };
}

export async function saveConfig(config: Partial<Config>): Promise<void> {
  const toStore: Record<string, string | boolean> = {};

  if (config.server !== undefined) toStore.server = config.server;
  if (config.email !== undefined) toStore.email = config.email;
  if (config.configured !== undefined) toStore.configured = config.configured;

  if (Object.keys(toStore).length > 0) {
    await browser.storage.local.set(toStore);
  }

  // Encrypt and store password separately
  if (config.password !== undefined) {
    await encryptPassword(config.password);
  }
}

export async function isConfigured(): Promise<boolean> {
  const config = await loadConfig();
  return config.configured && !!config.email && !!config.password;
}
