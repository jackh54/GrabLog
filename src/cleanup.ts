import type { Env } from "./env";
import { BODY_PREFIX, META_PREFIX } from "./env";
import type { LogMeta } from "./env";

const LIST_LIMIT = 500;

/**
 * Delete expired log objects. Safe to run hourly via cron.
 * Returns how many meta/body pairs were removed.
 */
export async function cleanupExpired(env: Env): Promise<{ removed: number }> {
  const now = Date.now();
  let removed = 0;
  let cursor: string | undefined;

  do {
    const listed = await env.LOGS.list({
      prefix: META_PREFIX,
      limit: LIST_LIMIT,
      cursor,
    });

    for (const obj of listed.objects) {
      const id = obj.key.slice(META_PREFIX.length);
      if (!id) continue;

      const metaObj = await env.LOGS.get(obj.key);
      if (!metaObj) continue;

      let expiresAt: number | null = null;
      try {
        const meta = (await metaObj.json()) as LogMeta;
        expiresAt = meta.expiresAt;
      } catch {
        expiresAt = 0;
      }

      if (expiresAt !== null && expiresAt <= now) {
        await Promise.all([
          env.LOGS.delete(`${META_PREFIX}${id}`),
          env.LOGS.delete(`${BODY_PREFIX}${id}`),
        ]);
        removed += 1;
      }
    }

    cursor = listed.truncated ? listed.cursor : undefined;
  } while (cursor);

  return { removed };
}
