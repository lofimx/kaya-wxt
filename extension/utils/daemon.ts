const DAEMON_BASE = "http://localhost:21420";
const TIMEOUT_MS = 2000;

async function fetchWithTimeout(
  url: string,
  options: RequestInit = {},
): Promise<Response> {
  const controller = new AbortController();
  const id = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(id);
  }
}

export async function isDaemonRunning(): Promise<boolean> {
  try {
    const response = await fetchWithTimeout(`${DAEMON_BASE}/health`);
    return response.ok;
  } catch {
    return false;
  }
}

export async function pushFileToDaemon(
  collection: "anga" | "meta",
  filename: string,
  content: string | ArrayBuffer,
): Promise<void> {
  try {
    const body =
      typeof content === "string" ? new TextEncoder().encode(content) : content;
    await fetchWithTimeout(
      `${DAEMON_BASE}/${collection}/${encodeURIComponent(filename)}`,
      {
        method: "POST",
        body,
      },
    );
  } catch {
    // Daemon is optional -- silently ignore failures
  }
}
