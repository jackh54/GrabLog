/**
 * Escape a value for safe embedding inside double-quoted shell / PowerShell
 * string literals used as script placeholders.
 */
export function escapeForScriptLiteral(value: string): string {
  return value
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\$/g, "\\$")
    .replace(/`/g, "\\`")
    .replace(/\r/g, "")
    .replace(/\n/g, "");
}

/** Only allow simple filter tokens from the query string. */
export function sanitizeParam(raw: string | null, max = 64): string {
  if (!raw) return "";
  const trimmed = raw.trim().slice(0, max);
  // Hostnames, IPs, ports, and simple launcher/instance tokens.
  if (!/^[A-Za-z0-9._\-+=@: ]*$/.test(trimmed)) {
    return "";
  }
  return trimmed;
}

/**
 * Prefer the host the client actually hit (preview / workers.dev / custom domain)
 * so uploads and share links stay on the same deployment.
 */
export function resolvePublicBase(
  request: Request,
  fallback: string,
): string {
  try {
    const url = new URL(request.url);
    if (url.protocol === "http:" || url.protocol === "https:") {
      return url.origin;
    }
  } catch {
    // fall through
  }
  return fallback.replace(/\/$/, "");
}

export interface ScriptParams {
  api: string;
  launcher: string;
  instance: string;
  name: string;
  type: string;
  server: string;
  yes: string;
}

export function fillScriptTemplate(
  template: string,
  params: ScriptParams,
): string {
  return template
    .replaceAll("__GRABLOG_API__", escapeForScriptLiteral(params.api))
    .replaceAll("__GRABLOG_LAUNCHER__", escapeForScriptLiteral(params.launcher))
    .replaceAll("__GRABLOG_INSTANCE__", escapeForScriptLiteral(params.instance))
    .replaceAll("__GRABLOG_NAME__", escapeForScriptLiteral(params.name))
    .replaceAll("__GRABLOG_TYPE__", escapeForScriptLiteral(params.type))
    .replaceAll("__GRABLOG_SERVER__", escapeForScriptLiteral(params.server))
    .replaceAll("__GRABLOG_YES__", escapeForScriptLiteral(params.yes));
}

export function paramsFromUrl(
  url: URL,
  apiBase: string,
): ScriptParams {
  const yesRaw = (url.searchParams.get("yes") ?? url.searchParams.get("y") ?? "")
    .toLowerCase();
  return {
    api: apiBase.replace(/\/$/, ""),
    launcher: sanitizeParam(
      url.searchParams.get("launcher") ?? url.searchParams.get("client"),
    ),
    instance: sanitizeParam(
      url.searchParams.get("instance") ??
        url.searchParams.get("profile") ??
        url.searchParams.get("pack"),
    ),
    name: sanitizeParam(
      url.searchParams.get("name") ?? url.searchParams.get("file"),
    ),
    type: sanitizeParam(url.searchParams.get("type")).toLowerCase(),
    server: sanitizeParam(
      url.searchParams.get("server") ??
        url.searchParams.get("host") ??
        url.searchParams.get("ip"),
      128,
    ),
    yes: yesRaw === "1" || yesRaw === "true" || yesRaw === "yes" ? "1" : "",
  };
}

export function wantsPowerShell(request: Request, url: URL): boolean {
  const fmt = (url.searchParams.get("fmt") ?? "").toLowerCase();
  if (fmt === "ps1" || fmt === "powershell" || fmt === "pwsh") return true;
  if (fmt === "sh" || fmt === "bash") return false;

  const path = url.pathname.toLowerCase();
  if (path === "/ps1" || path.endsWith(".ps1")) return true;

  const ua = (request.headers.get("user-agent") ?? "").toLowerCase();
  if (ua.includes("powershell") || ua.includes("windows powershell")) {
    return true;
  }
  return false;
}
