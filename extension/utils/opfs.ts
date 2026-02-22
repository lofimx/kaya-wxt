const ROOT_DIRS = ["anga", "meta"] as const;
export type Collection = (typeof ROOT_DIRS)[number];

async function getRoot(): Promise<FileSystemDirectoryHandle> {
  const opfsRoot = await navigator.storage.getDirectory();
  return opfsRoot.getDirectoryHandle("kaya", { create: true });
}

export async function ensureDir(
  name: Collection,
): Promise<FileSystemDirectoryHandle> {
  const root = await getRoot();
  return root.getDirectoryHandle(name, { create: true });
}

export async function writeFile(
  collection: Collection,
  filename: string,
  content: string | ArrayBuffer,
): Promise<void> {
  const dir = await ensureDir(collection);
  const fileHandle = await dir.getFileHandle(filename, { create: true });
  const writable = await fileHandle.createWritable();
  await writable.write(content);
  await writable.close();
}

export async function readFile(
  collection: Collection,
  filename: string,
): Promise<ArrayBuffer> {
  const dir = await ensureDir(collection);
  const fileHandle = await dir.getFileHandle(filename);
  const file = await fileHandle.getFile();
  return file.arrayBuffer();
}

export async function readFileText(
  collection: Collection,
  filename: string,
): Promise<string> {
  const dir = await ensureDir(collection);
  const fileHandle = await dir.getFileHandle(filename);
  const file = await fileHandle.getFile();
  return file.text();
}

export async function listFiles(collection: Collection): Promise<string[]> {
  const dir = await ensureDir(collection);
  const names: string[] = [];
  for await (const key of dir.keys()) {
    names.push(key);
  }
  return names;
}

// ---------------------------------------------------------------------------
// Words (nested directory structure: /kaya/words/{anga}/{filename})
// ---------------------------------------------------------------------------

async function getWordsDir(): Promise<FileSystemDirectoryHandle> {
  const root = await getRoot();
  return root.getDirectoryHandle("words", { create: true });
}

export async function ensureWordsDir(
  anga: string,
): Promise<FileSystemDirectoryHandle> {
  const words = await getWordsDir();
  return words.getDirectoryHandle(anga, { create: true });
}

export async function writeWordsFile(
  anga: string,
  filename: string,
  content: string,
): Promise<void> {
  const dir = await ensureWordsDir(anga);
  const fileHandle = await dir.getFileHandle(filename, { create: true });
  const writable = await fileHandle.createWritable();
  await writable.write(content);
  await writable.close();
}

export async function listWordsAngaDirs(): Promise<string[]> {
  const words = await getWordsDir();
  const names: string[] = [];
  for await (const [name, handle] of (words as any).entries()) {
    if (handle.kind === "directory") {
      names.push(name);
    }
  }
  return names;
}

export async function listWordsFiles(anga: string): Promise<string[]> {
  const words = await getWordsDir();
  try {
    const dir = await words.getDirectoryHandle(anga);
    const names: string[] = [];
    for await (const key of dir.keys()) {
      names.push(key);
    }
    return names;
  } catch {
    return [];
  }
}

// ---------------------------------------------------------------------------
// Bookmark URL scanning
// ---------------------------------------------------------------------------

export async function readAllBookmarkUrls(): Promise<Set<string>> {
  const urls = new Set<string>();
  const files = await listFiles("anga");

  for (const filename of files) {
    if (!filename.endsWith(".url")) continue;
    try {
      const text = await readFileText("anga", filename);
      for (const line of text.split("\n")) {
        if (line.startsWith("URL=")) {
          urls.add(line.slice(4).trim());
        }
      }
    } catch {
      // skip unreadable files
    }
  }

  return urls;
}
