import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        wrangler: { configPath: "./wrangler.toml" },
        // Direct R2 seeding in cleanup tests needs non-isolated storage.
        isolatedStorage: false,
        miniflare: {
          bindings: {
            PUBLIC_BASE_URL: "https://grablog.test",
            MAX_UPLOAD_BYTES: "10485760",
            TTL_SECONDS: "86400",
          },
        },
      },
    },
  },
});
