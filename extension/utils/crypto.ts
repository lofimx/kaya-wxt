import { browser } from "wxt/browser";

const ALGO = "AES-GCM";
const KEY_LENGTH = 256;
const IV_LENGTH = 12; // 96 bits, recommended for AES-GCM

// Storage keys in browser.storage.local
const ENCRYPTED_PASSWORD_KEY = "encryptedPassword";
const IV_KEY = "passwordIv";
const CRYPTO_KEY_KEY = "cryptoKey";

function arrayBufferToBase64(buffer: ArrayBuffer | Uint8Array): string {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function base64ToArrayBuffer(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

async function generateKey(): Promise<CryptoKey> {
  return crypto.subtle.generateKey(
    { name: ALGO, length: KEY_LENGTH },
    true, // extractable for JWK export
    ["encrypt", "decrypt"],
  );
}

async function exportKey(key: CryptoKey): Promise<JsonWebKey> {
  return crypto.subtle.exportKey("jwk", key);
}

async function importKey(jwk: JsonWebKey): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: ALGO, length: KEY_LENGTH },
    true,
    ["encrypt", "decrypt"],
  );
}

async function storeKey(key: CryptoKey): Promise<void> {
  const jwk = await exportKey(key);
  await browser.storage.local.set({ [CRYPTO_KEY_KEY]: jwk });
}

async function retrieveKey(): Promise<CryptoKey | null> {
  const result = await browser.storage.local.get(CRYPTO_KEY_KEY);
  if (result[CRYPTO_KEY_KEY]) {
    return importKey(result[CRYPTO_KEY_KEY] as JsonWebKey);
  }
  return null;
}

export async function encryptPassword(password: string): Promise<void> {
  let key = await retrieveKey();
  if (!key) {
    key = await generateKey();
    await storeKey(key);
  }

  const iv = crypto.getRandomValues(new Uint8Array(IV_LENGTH));
  const encoded = new TextEncoder().encode(password);
  const ciphertext = await crypto.subtle.encrypt(
    { name: ALGO, iv },
    key,
    encoded,
  );

  await browser.storage.local.set({
    [ENCRYPTED_PASSWORD_KEY]: arrayBufferToBase64(ciphertext),
    [IV_KEY]: arrayBufferToBase64(iv),
  });

  // 2026-02-26 TODO: remove legacy password-handling migration block
  await browser.storage.local.remove("password");
}

export async function decryptPassword(): Promise<string | null> {
  const result = await browser.storage.local.get([
    ENCRYPTED_PASSWORD_KEY,
    IV_KEY,
  ]);

  if (!result[ENCRYPTED_PASSWORD_KEY] || !result[IV_KEY]) {
    return null;
  }

  const key = await retrieveKey();
  if (!key) {
    return null;
  }

  try {
    const iv = base64ToArrayBuffer(result[IV_KEY] as string);
    const ciphertext = base64ToArrayBuffer(
      result[ENCRYPTED_PASSWORD_KEY] as string,
    );

    const decrypted = await crypto.subtle.decrypt(
      { name: ALGO, iv },
      key,
      ciphertext,
    );

    return new TextDecoder().decode(decrypted);
  } catch {
    // Decryption failed (corrupted data) -- clear and require re-auth
    await browser.storage.local.remove([
      ENCRYPTED_PASSWORD_KEY,
      IV_KEY,
      CRYPTO_KEY_KEY,
    ]);
    return null;
  }
}
