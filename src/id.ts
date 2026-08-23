const ALPHABET =
  "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

/**
 * Cryptographically random, URL-safe ID (unguessable share token).
 * Default 22 chars ≈ 131 bits of entropy.
 */
export function generateId(length = 22): string {
  if (length < 16) {
    throw new Error("id length must be at least 16");
  }
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  let out = "";
  for (let i = 0; i < length; i++) {
    out += ALPHABET[bytes[i]! % ALPHABET.length]!;
  }
  return out;
}

/** Reject path traversal / odd characters in public IDs. */
export function isValidId(id: string): boolean {
  return /^[A-Za-z0-9]{16,64}$/.test(id);
}
