import {
  createExecutionContext,
  env,
  waitOnExecutionContext,
} from "cloudflare:test";
import { describe, expect, it } from "vitest";
import worker from "../src/index";
import { BODY_PREFIX, META_PREFIX, type Env, type LogMeta } from "../src/env";
import { cleanupExpired } from "../src/cleanup";

async function uploadLog(
  body: string,
  filename = "latest.log",
): Promise<{ id: string; url: string }> {
  const ctx = createExecutionContext();
  const request = new Request("https://grablog.test/api/upload", {
    method: "POST",
    headers: {
      "content-type": "text/plain",
      "x-grablog-filename": filename,
    },
    body,
  });
  const response = await worker.fetch(request, env as Env, ctx);
  await waitOnExecutionContext(ctx);
  expect(response.status).toBe(200);
  return (await response.json()) as { id: string; url: string };
}

describe("worker HTTP", () => {
  it("serves health", async () => {
    const ctx = createExecutionContext();
    const res = await worker.fetch(
      new Request("https://grablog.test/health"),
      env as Env,
      ctx,
    );
    await waitOnExecutionContext(ctx);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
  });

  it("serves HTML landing to browsers", async () => {
    const ctx = createExecutionContext();
    const res = await worker.fetch(
      new Request("https://grablog.test/", {
        headers: { accept: "text/html" },
      }),
      env as Env,
      ctx,
    );
    await waitOnExecutionContext(ctx);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/html");
    const html = await res.text();
    expect(html).toContain("GrabLog");
    expect(html).toContain("curl -fsSL");
  });

  it("serves shell script to curl on /", async () => {
    const ctx = createExecutionContext();
    const res = await worker.fetch(
      new Request("https://grablog.test/?launcher=prism&yes=1", {
        headers: { "user-agent": "curl/8.5.0", accept: "*/*" },
      }),
      env as Env,
      ctx,
    );
    await waitOnExecutionContext(ctx);
    expect(res.status).toBe(200);
    const script = await res.text();
    expect(script).toContain("GrabLog");
    expect(script).toContain('GRABLOG_LAUNCHER="prism"');
    expect(script).toContain('GRABLOG_YES="1"');
    expect(script).toContain('GRABLOG_SERVER=""');
    expect(script).toContain("https://grablog.test");
    expect(script).toContain("set -eu");
  });

  it("embeds server filter in the client script", async () => {
    const ctx = createExecutionContext();
    const res = await worker.fetch(
      new Request("https://grablog.test/?server=example.net", {
        headers: { "user-agent": "curl/8.5.0", accept: "*/*" },
      }),
      env as Env,
      ctx,
    );
    await waitOnExecutionContext(ctx);
    const script = await res.text();
    expect(script).toContain('GRABLOG_SERVER="example.net"');
  });

  it("embeds the request origin as the API base (preview-safe)", async () => {
    const ctx = createExecutionContext();
    const res = await worker.fetch(
      new Request("https://preview.example.workers.dev/?yes=1", {
        headers: { "user-agent": "curl/8.5.0", accept: "*/*" },
      }),
      env as Env,
      ctx,
    );
    await waitOnExecutionContext(ctx);
    const script = await res.text();
    expect(script).toContain('GRABLOG_API="https://preview.example.workers.dev"');
    expect(script).not.toContain('GRABLOG_API="https://grablog.test"');
  });

  it("serves PowerShell from /ps1", async () => {
    const ctx = createExecutionContext();
    const res = await worker.fetch(
      new Request("https://grablog.test/ps1?instance=ATM"),
      env as Env,
      ctx,
    );
    await waitOnExecutionContext(ctx);
    const script = await res.text();
    expect(script).toContain("$GrabLogApi");
    expect(script).toContain("ATM");
    expect(script).toContain("HttpClient");
  });

  it("uploads and serves a log", async () => {
    const payload = " [INFO] Hello from Minecraft\n";
    const uploaded = await uploadLog(payload, "latest.log");
    expect(uploaded.url).toMatch(/^https:\/\/grablog\.test\/l\/[A-Za-z0-9]+$/);

    const ctx = createExecutionContext();
    const res = await worker.fetch(new Request(uploaded.url), env as Env, ctx);
    await waitOnExecutionContext(ctx);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(payload);
    expect(res.headers.get("content-disposition")).toContain("latest.log");
  });

  it("rejects empty uploads", async () => {
    const ctx = createExecutionContext();
    const res = await worker.fetch(
      new Request("https://grablog.test/api/upload", {
        method: "POST",
        body: "",
      }),
      env as Env,
      ctx,
    );
    await waitOnExecutionContext(ctx);
    expect(res.status).toBe(400);
  });

  it("returns 404 for unknown ids", async () => {
    const ctx = createExecutionContext();
    const res = await worker.fetch(
      new Request("https://grablog.test/l/ThisIdDoesNotExist99"),
      env as Env,
      ctx,
    );
    await waitOnExecutionContext(ctx);
    expect(res.status).toBe(404);
  });

  it("accepts gzip uploads via X-GrabLog-Encoding", async () => {
    const plain = "gzipped minecraft log line\n";
    // Minimal gzip via CompressionStream
    const stream = new Blob([plain])
      .stream()
      .pipeThrough(new CompressionStream("gzip"));
    const gz = await new Response(stream).arrayBuffer();

    const ctx = createExecutionContext();
    const res = await worker.fetch(
      new Request("https://grablog.test/api/upload", {
        method: "POST",
        headers: {
          "content-type": "application/gzip",
          "x-grablog-encoding": "gzip",
          "x-grablog-filename": "latest.log.gz",
        },
        body: gz,
      }),
      env as Env,
      ctx,
    );
    await waitOnExecutionContext(ctx);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { url: string; bytes: number };
    expect(body.bytes).toBe(plain.length);

    const getCtx = createExecutionContext();
    const getRes = await worker.fetch(
      new Request(body.url),
      env as Env,
      getCtx,
    );
    await waitOnExecutionContext(getCtx);
    expect(await getRes.text()).toBe(plain);
  });

  it("accepts multipart uploads", async () => {
    const form = new FormData();
    form.set(
      "file",
      new File(["crash boom"], "crash-2026-01-01.txt", {
        type: "text/plain",
      }),
    );
    const ctx = createExecutionContext();
    const res = await worker.fetch(
      new Request("https://grablog.test/api/upload", {
        method: "POST",
        body: form,
      }),
      env as Env,
      ctx,
    );
    await waitOnExecutionContext(ctx);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { id: string; url: string };
    const getCtx = createExecutionContext();
    const getRes = await worker.fetch(
      new Request(body.url),
      env as Env,
      getCtx,
    );
    await waitOnExecutionContext(getCtx);
    expect(await getRes.text()).toBe("crash boom");
  });
});

describe("cleanupExpired", () => {
  it("removes expired objects and keeps live ones", async () => {
    const live = await uploadLog("live log");
    const expiredId = "ExpiredTestId123456";
    const now = Date.now();
    const meta: LogMeta = {
      id: expiredId,
      createdAt: now - 100_000,
      expiresAt: now - 1_000,
      filename: "old.log",
      bytes: 3,
      contentType: "text/plain; charset=utf-8",
    };
    await (env as Env).LOGS.put(`${BODY_PREFIX}${expiredId}`, "old");
    await (env as Env).LOGS.put(
      `${META_PREFIX}${expiredId}`,
      JSON.stringify(meta),
    );

    const result = await cleanupExpired(env as Env);
    expect(result.removed).toBeGreaterThanOrEqual(1);
    expect(await (env as Env).LOGS.get(`${META_PREFIX}${expiredId}`)).toBeNull();
    expect(await (env as Env).LOGS.get(`${BODY_PREFIX}${expiredId}`)).toBeNull();
    expect(
      await (env as Env).LOGS.get(`${META_PREFIX}${live.id}`),
    ).not.toBeNull();
  });
});
