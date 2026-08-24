import type { Env, LogMeta } from "./env";
import { BODY_PREFIX, META_PREFIX, parsePositiveInt } from "./env";
import { generateId } from "./id";

const TEXT_PLAIN = "text/plain; charset=utf-8";

export type UploadResult =
  | { ok: true; id: string; url: string; expiresAt: number; bytes: number }
  | { ok: false; status: number; error: string };

function sanitizeFilename(name: string | null): string {
  if (!name) return "latest.log";
  const base = name.replace(/\\/g, "/").split("/").pop() ?? "latest.log";
  const cleaned = base.replace(/[^\w.\-()+ ]+/g, "_").slice(0, 128);
  return cleaned.length > 0 ? cleaned : "latest.log";
}

function toArrayBuffer(data: ArrayBuffer | ArrayBufferView | string): ArrayBuffer {
  if (typeof data === "string") {
    return new TextEncoder().encode(data).buffer as ArrayBuffer;
  }
  if (ArrayBuffer.isView(data)) {
    return data.buffer.slice(
      data.byteOffset,
      data.byteOffset + data.byteLength,
    ) as ArrayBuffer;
  }
  return data;
}

function looksGzip(bytes: ArrayBuffer): boolean {
  if (bytes.byteLength < 2) return false;
  const view = new Uint8Array(bytes);
  return view[0] === 0x1f && view[1] === 0x8b;
}

async function maybeGunzip(
  bytes: ArrayBuffer,
  contentType: string,
  encoding: string | null,
): Promise<ArrayBuffer> {
  const wants =
    encoding?.toLowerCase().includes("gzip") ||
    contentType.toLowerCase().includes("gzip") ||
    looksGzip(bytes);
  if (!wants) return bytes;

  try {
    const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"));
    return toArrayBuffer(await new Response(stream).arrayBuffer());
  } catch {
    // If the client said gzip but body isn't valid, keep raw bytes.
    return bytes;
  }
}

export async function handleUpload(
  request: Request,
  env: Env,
  publicBaseUrl: string,
): Promise<UploadResult> {
  if (!env.LOGS) {
    return { ok: false, status: 500, error: "R2 bucket not configured" };
  }

  const maxBytes = parsePositiveInt(env.MAX_UPLOAD_BYTES, 10 * 1024 * 1024);
  const ttlSeconds = parsePositiveInt(env.TTL_SECONDS, 86_400);
  const contentType = request.headers.get("content-type") ?? "";
  const encoding =
    request.headers.get("x-grablog-encoding") ??
    request.headers.get("content-encoding");

  let body: ArrayBuffer;
  let filename = "latest.log";

  if (contentType.includes("multipart/form-data")) {
    const form = await request.formData();
    const entry = form.get("file") ?? form.get("log") ?? form.get("content");
    if (typeof entry === "string") {
      body = toArrayBuffer(entry);
      filename = sanitizeFilename(form.get("filename")?.toString() ?? null);
    } else if (entry) {
      const blob = entry as Blob & { name?: string };
      body = toArrayBuffer(await blob.arrayBuffer());
      filename = sanitizeFilename(
        blob.name || form.get("filename")?.toString() || null,
      );
    } else {
      return { ok: false, status: 400, error: "missing file field" };
    }
  } else {
    body = toArrayBuffer(await request.arrayBuffer());
    filename = sanitizeFilename(request.headers.get("x-grablog-filename"));
  }

  body = await maybeGunzip(body, contentType, encoding);
  // Strip .gz after decompress so share links open as plain text.
  if (filename.toLowerCase().endsWith(".gz")) {
    filename = filename.slice(0, -3) || "latest.log";
  }

  if (body.byteLength === 0) {
    return { ok: false, status: 400, error: "empty body" };
  }
  if (body.byteLength > maxBytes) {
    return {
      ok: false,
      status: 413,
      error: `log exceeds ${maxBytes} byte limit`,
    };
  }

  const id = generateId();
  const now = Date.now();
  const meta: LogMeta = {
    id,
    createdAt: now,
    expiresAt: now + ttlSeconds * 1000,
    filename,
    bytes: body.byteLength,
    contentType: TEXT_PLAIN,
  };

  await Promise.all([
    env.LOGS.put(`${BODY_PREFIX}${id}`, body, {
      httpMetadata: {
        contentType: TEXT_PLAIN,
        contentDisposition: `inline; filename="${filename.replace(/"/g, "")}"`,
      },
      customMetadata: {
        expiresAt: String(meta.expiresAt),
        filename,
      },
    }),
    env.LOGS.put(`${META_PREFIX}${id}`, JSON.stringify(meta), {
      httpMetadata: { contentType: "application/json" },
    }),
  ]);

  const base = publicBaseUrl.replace(/\/$/, "");
  return {
    ok: true,
    id,
    url: `${base}/l/${id}`,
    expiresAt: meta.expiresAt,
    bytes: meta.bytes,
  };
}
