/** Shared Cloudflare Worker bindings. */
export interface Env {
  LOGS: R2Bucket;
  PUBLIC_BASE_URL: string;
  MAX_UPLOAD_BYTES: string;
  TTL_SECONDS: string;
}

export interface LogMeta {
  id: string;
  createdAt: number;
  expiresAt: number;
  filename: string;
  bytes: number;
  contentType: string;
}

export const META_PREFIX = "meta/";
export const BODY_PREFIX = "body/";

export function parsePositiveInt(value: string, fallback: number): number {
  const n = Number.parseInt(value, 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}
