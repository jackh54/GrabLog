# GrabLog

Find a Minecraft log on any launcher (vanilla, Prism, Modrinth, CurseForge, MultiMC, Lunar, …) and share it for **24 hours** with one command.

## Usage

**macOS / Linux**

```bash
curl -fsSL https://grablog.pandascript.dev | sh
```

**Windows (PowerShell)**

```powershell
irm https://grablog.pandascript.dev/ps1 | iex
```

The script searches common launcher paths, picks the newest preferred log (`latest.log` over older/crash files unless filtered), shows a short preview, asks for confirmation, then uploads to GrabLog.

### URL filters

| Param | Example | Effect |
| --- | --- | --- |
| `launcher` | `?launcher=modrinth` | Optional — limit to a launcher family. Omit to auto-pick across all. |
| `server` | `?server=example.net` | Prefer the newest log that mentions that host/IP |
| `instance` | `?instance=ATM` | Substring match on instance/profile path |
| `name` | `?name=crash` | Filename substring |
| `type` | `?type=crash` or `?type=log` | Prefer crash reports or normal logs |
| `yes` | `?yes=1` | Skip confirmation (careful — uploads immediately) |

Example:

```bash
curl -fsSL 'https://grablog.pandascript.dev?server=example.net' | sh
```

Share links look like `https://grablog.pandascript.dev/l/<unguessable-id>` and expire after 24 hours.

## API

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/` | Landing page (browsers) or runnable script (`curl`) |
| `GET` | `/ps1` | PowerShell client |
| `POST` | `/api/upload` | Raw body or multipart `file` — returns `{ id, url, expiresAt, bytes }` |
| `GET` | `/l/:id` | Fetch stored log |
| `GET` | `/health` | Liveness |

Header `X-GrabLog-Filename` sets the download filename for raw uploads. Max size defaults to 10 MiB.

## Architecture

- **Cloudflare Worker** serves the clients, upload API, and log pages
- **R2** stores log bodies + JSON metadata
- **Cron** (hourly) deletes expired objects
- IDs are 22-character cryptographically random tokens

## Develop

```bash
npm install
npm test
npm run typecheck
npm run dev      # local worker + R2 (wrangler)
npm run deploy   # requires Cloudflare auth + R2 bucket
```

### Cloudflare setup

1. Create R2 buckets `grablog-logs` and `grablog-logs-preview` (or rename in `wrangler.toml`)
2. Set `PUBLIC_BASE_URL` in `wrangler.toml` (or `[vars]`) to your hostname
3. Attach a custom domain (e.g. `grablog.pandascript.dev`)
4. Put `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` in GitHub Actions secrets for deploy on `main`

## License

MIT
