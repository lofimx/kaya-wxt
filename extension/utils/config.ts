import { browser } from "wxt/browser";

export interface Config {
  server: string;
  email: string;
  password: string;
  configured: boolean;
}

const DEFAULT_SERVER = "https://savebutton.com";

export async function loadConfig(): Promise<Config> {
  const result = await browser.storage.local.get([
    "server",
    "email",
    "password",
    "configured",
  ]);
  return {
    server: (result.server as string) || DEFAULT_SERVER,
    email: (result.email as string) || "",
    password: (result.password as string) || "",
    configured: result.configured === true,
  };
}

export async function saveConfig(config: Partial<Config>): Promise<void> {
  await browser.storage.local.set(config);
}

export async function isConfigured(): Promise<boolean> {
  const config = await loadConfig();
  return config.configured && !!config.email && !!config.password;
}
