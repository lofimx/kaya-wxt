const ROOT_DIRS = ["anga", "meta"] as const;
export type Collection = (typeof ROOT_DIRS)[number];

async function getRoot(): Promise<FileSystemDirectoryHandle> {
  return navigator.storage.getDirectory();
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
