import type { Env, LogMeta } from "./env";
import { BODY_PREFIX, META_PREFIX } from "./env";
import { isValidId } from "./id";

export type ServeResult =
  | { ok: true; body: R2ObjectBody; meta: LogMeta }
  | { ok: false; status: number; error: string };

export async function loadMeta(
  env: Env,
  id: string,
): Promise<LogMeta | null> {
  const obj = await env.LOGS.get(`${META_PREFIX}${id}`);
  if (!obj) return null;
  try {
    return (await obj.json()) as LogMeta;
  } catch {
    return null;
  }
}

export async function handleServe(
  env: Env,
  id: string,
): Promise<ServeResult> {
  if (!isValidId(id)) {
    return { ok: false, status: 400, error: "invalid id" };
  }

  const meta = await loadMeta(env, id);
  if (!meta) {
    return { ok: false, status: 404, error: "not found" };
  }

  if (meta.expiresAt <= Date.now()) {
    await Promise.allSettled([
      env.LOGS.delete(`${BODY_PREFIX}${id}`),
      env.LOGS.delete(`${META_PREFIX}${id}`),
    ]);
    return { ok: false, status: 404, error: "expired" };
  }

  const body = await env.LOGS.get(`${BODY_PREFIX}${id}`);
  if (!body) {
    return { ok: false, status: 404, error: "not found" };
  }

  return { ok: true, body, meta };
}
