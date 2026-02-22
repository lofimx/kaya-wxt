import { type Config } from "./config";
import {
  type Collection,
  listFiles,
  readFile,
  writeFile,
  listWordsAngaDirs,
  listWordsFiles,
  writeWordsFile,
} from "./opfs";

function authHeader(config: Config): string {
  return "Basic " + btoa(`${config.email}:${config.password}`);
}

function apiUrl(
  config: Config,
  collection: Collection,
  filename?: string,
): string {
  const base = `${config.server.replace(/\/+$/, "")}/api/v1/${encodeURIComponent(config.email)}/${collection}`;
  return filename ? `${base}/${encodeURIComponent(filename)}` : base;
}

function mimeTypeFor(filename: string): string {
  const ext = filename.split(".").pop()?.toLowerCase() || "";
  const types: Record<string, string> = {
    md: "text/markdown",
    url: "text/plain",
    txt: "text/plain",
    json: "application/json",
    toml: "application/toml",
    pdf: "application/pdf",
    png: "image/png",
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    gif: "image/gif",
    webp: "image/webp",
    svg: "image/svg+xml",
    html: "text/html",
    htm: "text/html",
  };
  return types[ext] || "application/octet-stream";
}

async function fetchServerFileList(
  config: Config,
  collection: Collection,
): Promise<Set<string>> {
  const response = await fetch(apiUrl(config, collection), {
    headers: { Authorization: authHeader(config) },
  });

  if (!response.ok) {
    throw new Error(
      `Server returned ${response.status} for ${collection} listing`,
    );
  }

  const text = await response.text();
  const files = new Set<string>();
  for (const line of text.split("\n")) {
    const trimmed = decodeURIComponent(line.trim());
    if (trimmed) files.add(trimmed);
  }
  return files;
}

async function downloadFile(
  config: Config,
  collection: Collection,
  filename: string,
): Promise<void> {
  const response = await fetch(apiUrl(config, collection, filename), {
    headers: { Authorization: authHeader(config) },
  });

  if (!response.ok) {
    throw new Error(
      `Download failed for ${collection}/${filename}: ${response.status}`,
    );
  }

  const content = await response.arrayBuffer();
  await writeFile(collection, filename, content);
}

async function uploadFile(
  config: Config,
  collection: Collection,
  filename: string,
): Promise<void> {
  const content = await readFile(collection, filename);
  const blob = new Blob([content], { type: mimeTypeFor(filename) });

  const formData = new FormData();
  formData.append("file", blob, filename);

  const response = await fetch(apiUrl(config, collection, filename), {
    method: "POST",
    headers: { Authorization: authHeader(config) },
    body: formData,
  });

  // 409 Conflict = file already exists, that's fine
  if (!response.ok && response.status !== 409) {
    throw new Error(
      `Upload failed for ${collection}/${filename}: ${response.status}`,
    );
  }
}

async function syncCollection(
  config: Config,
  collection: Collection,
): Promise<{ downloaded: number; uploaded: number }> {
  const serverFiles = await fetchServerFileList(config, collection);
  const localFiles = new Set(await listFiles(collection));

  const toDownload: string[] = [];
  for (const f of serverFiles) {
    if (!localFiles.has(f)) toDownload.push(f);
  }

  const toUpload: string[] = [];
  for (const f of localFiles) {
    if (!serverFiles.has(f)) toUpload.push(f);
  }

  for (const filename of toDownload) {
    await downloadFile(config, collection, filename);
  }

  for (const filename of toUpload) {
    await uploadFile(config, collection, filename);
  }

  return { downloaded: toDownload.length, uploaded: toUpload.length };
}

// ---------------------------------------------------------------------------
// Words sync (download-only, nested: words/{anga}/{filename})
// ---------------------------------------------------------------------------

function wordsApiUrl(config: Config, ...parts: string[]): string {
  const base = `${config.server.replace(/\/+$/, "")}/api/v1/${encodeURIComponent(config.email)}/words`;
  if (parts.length === 0) return base;
  return base + "/" + parts.map(encodeURIComponent).join("/");
}

async function fetchWordsListing(
  config: Config,
  ...pathParts: string[]
): Promise<Set<string>> {
  const response = await fetch(wordsApiUrl(config, ...pathParts), {
    headers: { Authorization: authHeader(config) },
  });

  if (!response.ok) {
    throw new Error(`Server returned ${response.status} for words listing`);
  }

  const text = await response.text();
  const items = new Set<string>();
  for (const line of text.split("\n")) {
    const trimmed = decodeURIComponent(line.trim());
    if (trimmed) items.add(trimmed);
  }
  return items;
}

export interface WordsDownload {
  anga: string;
  filename: string;
  content: string;
}

export interface WordsSyncResult {
  downloaded: number;
  files: WordsDownload[];
}

export async function syncWords(config: Config): Promise<WordsSyncResult> {
  const files: WordsDownload[] = [];

  // Level 1: list anga directories from server
  const serverAngaDirs = await fetchWordsListing(config);

  for (const anga of serverAngaDirs) {
    // Level 2: list files within this anga dir from server
    const serverFiles = await fetchWordsListing(config, anga);
    const localFiles = new Set(await listWordsFiles(anga));

    for (const filename of serverFiles) {
      if (localFiles.has(filename)) continue;

      // Download missing file
      const response = await fetch(wordsApiUrl(config, anga, filename), {
        headers: { Authorization: authHeader(config) },
      });

      if (response.ok) {
        const content = await response.text();
        await writeWordsFile(anga, filename, content);
        files.push({ anga, filename, content });
      }
    }
  }

  return { downloaded: files.length, files };
}

// ---------------------------------------------------------------------------
// Top-level sync
// ---------------------------------------------------------------------------

export interface SyncResult {
  anga: { downloaded: number; uploaded: number };
  meta: { downloaded: number; uploaded: number };
  words: WordsSyncResult;
}

export async function syncWithServer(config: Config): Promise<SyncResult> {
  const anga = await syncCollection(config, "anga");
  const meta = await syncCollection(config, "meta");
  const words = await syncWords(config);
  return { anga, meta, words };
}

export async function testConnection(config: Config): Promise<void> {
  const response = await fetch(apiUrl(config, "anga"), {
    headers: { Authorization: authHeader(config) },
  });

  if (response.status === 401) {
    throw new Error("Authentication failed - check your email and password");
  }

  if (!response.ok) {
    throw new Error(`Server returned status ${response.status}`);
  }
}
