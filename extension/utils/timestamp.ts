export function generateTimestamp(): string {
  const now = new Date();
  const year = now.getUTCFullYear();
  const month = String(now.getUTCMonth() + 1).padStart(2, '0');
  const day = String(now.getUTCDate()).padStart(2, '0');
  const hours = String(now.getUTCHours()).padStart(2, '0');
  const minutes = String(now.getUTCMinutes()).padStart(2, '0');
  const seconds = String(now.getUTCSeconds()).padStart(2, '0');
  return `${year}-${month}-${day}T${hours}${minutes}${seconds}`;
}

export function urlToDomainSlug(url: string): string {
  try {
    const urlObj = new URL(url);
    return urlObj.hostname.replace(/[^a-zA-Z0-9]/g, '-');
  } catch {
    return 'unknown';
  }
}
