import { cleanupExpired } from "./cleanup";
import type { Env } from "./env";
import { landingHtml } from "./landing";
import {
  fillScriptTemplate,
  paramsFromUrl,
  resolvePublicBase,
  wantsPowerShell,
} from "./script";
import { handleServe } from "./serve";
import { handleUpload } from "./upload";

import shTemplate from "./scripts/grablog.sh";
import ps1Template from "./scripts/grablog.ps1";

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "access-control-allow-origin": "*",
    },
  });
}

function text(body: string, status = 200, headers: HeadersInit = {}): Response {
  return new Response(body, {
    status,
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-store",
      ...headers,
    },
  });
}

function corsPreflight(): Response {
  return new Response(null, {
    status: 204,
    headers: {
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "GET, POST, OPTIONS",
      "access-control-allow-headers":
        "content-type, content-encoding, x-grablog-filename, accept",
      "access-control-max-age": "86400",
    },
  });
}

function prefersHtml(request: Request): boolean {
  const accept = request.headers.get("accept") ?? "";
  return accept.includes("text/html");
}

async function serveClientScript(
  request: Request,
  env: Env,
  url: URL,
): Promise<Response> {
  const apiBase = resolvePublicBase(request, env.PUBLIC_BASE_URL);
  const params = paramsFromUrl(url, apiBase);
  const ps = wantsPowerShell(request, url);
  const filled = fillScriptTemplate(ps ? ps1Template : shTemplate, params);
  return text(filled, 200, {
    "content-type": ps
      ? "text/plain; charset=utf-8"
      : "text/x-shellscript; charset=utf-8",
    "content-disposition": ps
      ? 'inline; filename="grablog.ps1"'
      : 'inline; filename="grablog.sh"',
    "x-grablog-shell": ps ? "powershell" : "sh",
  });
}

export default {
  async fetch(
    request: Request,
    env: Env,
    _ctx: ExecutionContext,
  ): Promise<Response> {
    const url = new URL(request.url);
    const publicBase = resolvePublicBase(request, env.PUBLIC_BASE_URL);

    if (request.method === "OPTIONS") {
      return corsPreflight();
    }

    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true });
    }

    if (request.method === "POST" && url.pathname === "/api/upload") {
      try {
        const result = await handleUpload(request, env, publicBase);
        if (!result.ok) {
          return json({ error: result.error }, result.status);
        }
        return json({
          id: result.id,
          url: result.url,
          expiresAt: result.expiresAt,
          bytes: result.bytes,
        });
      } catch (err) {
        const message = err instanceof Error ? err.message : "upload failed";
        console.error("upload error", message);
        return json({ error: message }, 500);
      }
    }

    if (request.method === "GET" && url.pathname.startsWith("/l/")) {
      const id = url.pathname.slice(3).replace(/\/$/, "");
      const result = await handleServe(env, id);
      if (!result.ok) {
        return text(result.error + "\n", result.status);
      }
      const headers = new Headers();
      headers.set(
        "content-type",
        result.meta.contentType || "text/plain; charset=utf-8",
      );
      headers.set(
        "content-disposition",
        `inline; filename="${result.meta.filename.replace(/"/g, "")}"`,
      );
      headers.set("cache-control", "public, max-age=300");
      headers.set("x-grablog-expires-at", String(result.meta.expiresAt));
      headers.set("access-control-allow-origin", "*");
      return new Response(result.body.body, { status: 200, headers });
    }

    if (
      request.method === "GET" &&
      (url.pathname === "/ps1" ||
        url.pathname === "/grablog.ps1" ||
        url.pathname === "/grablog.sh" ||
        url.pathname === "/sh")
    ) {
      return serveClientScript(request, env, url);
    }

    if (request.method === "GET" && url.pathname === "/") {
      if (prefersHtml(request)) {
        return new Response(landingHtml(publicBase), {
          status: 200,
          headers: {
            "content-type": "text/html; charset=utf-8",
            "cache-control": "public, max-age=300",
          },
        });
      }
      return serveClientScript(request, env, url);
    }

    return text("not found\n", 404);
  },

  async scheduled(
    _controller: ScheduledController,
    env: Env,
    ctx: ExecutionContext,
  ): Promise<void> {
    ctx.waitUntil(
      cleanupExpired(env).then((r) => {
        console.log(`grablog cleanup removed=${r.removed}`);
      }),
    );
  },
};
