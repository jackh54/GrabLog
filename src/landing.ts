export function landingHtml(baseUrl: string): string {
  const base = baseUrl.replace(/\/$/, "");
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>GrabLog</title>
  <style>
    :root {
      --bg0: #0f1410;
      --bg1: #172018;
      --ink: #e7efe6;
      --muted: #9bb09a;
      --accent: #7dbe63;
      --line: rgba(125, 190, 99, 0.25);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: "IBM Plex Sans", "Segoe UI", sans-serif;
      color: var(--ink);
      background:
        radial-gradient(1200px 600px at 10% -10%, #243528 0%, transparent 55%),
        radial-gradient(900px 500px at 100% 0%, #1a2a1c 0%, transparent 50%),
        linear-gradient(160deg, var(--bg0), var(--bg1));
    }
    main {
      max-width: 42rem;
      margin: 0 auto;
      padding: 4.5rem 1.25rem 3rem;
    }
    h1 {
      font-family: "IBM Plex Mono", ui-monospace, monospace;
      font-size: clamp(2.4rem, 6vw, 3.4rem);
      letter-spacing: -0.04em;
      margin: 0 0 0.6rem;
      color: var(--accent);
    }
    .lead {
      font-size: 1.1rem;
      color: var(--muted);
      margin: 0 0 2rem;
      line-height: 1.5;
    }
    pre {
      background: rgba(0, 0, 0, 0.35);
      border: 1px solid var(--line);
      border-radius: 10px;
      padding: 1rem 1.1rem;
      overflow-x: auto;
      font-family: "IBM Plex Mono", ui-monospace, monospace;
      font-size: 0.92rem;
      line-height: 1.45;
    }
    code { font-family: inherit; }
    h2 {
      margin: 2.2rem 0 0.7rem;
      font-size: 0.85rem;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: var(--muted);
      font-weight: 600;
    }
    ul {
      margin: 0;
      padding-left: 1.1rem;
      color: var(--muted);
      line-height: 1.6;
    }
    a { color: var(--accent); }
    footer {
      margin-top: 2.5rem;
      color: var(--muted);
      font-size: 0.85rem;
    }
  </style>
</head>
<body>
  <main>
    <h1>GrabLog</h1>
    <p class="lead">Find the newest Minecraft log on this machine — any launcher — and share it for 24 hours.</p>

    <h2>macOS / Linux</h2>
    <pre><code>curl -fsSL ${base} | sh</code></pre>

    <h2>Windows (PowerShell)</h2>
    <pre><code>irm ${base}/ps1 | iex</code></pre>

    <h2>Optional filters</h2>
    <ul>
      <li><code>?launcher=modrinth</code> — optional; omit to auto-pick any launcher</li>
      <li><code>?server=example.net</code> — log whose contents mention that host/IP</li>
      <li><code>?instance=MyPack</code> — substring match on instance/profile path</li>
      <li><code>?name=crash</code> — filename substring</li>
      <li><code>?type=crash</code> or <code>?type=log</code></li>
      <li><code>?yes=1</code> — skip confirmation (use carefully)</li>
    </ul>

    <h2>Example</h2>
    <pre><code>curl -fsSL '${base}?server=example.net' | sh</code></pre>

    <footer>
      Logs expire after 24 hours. Upload requires your confirmation.
    </footer>
  </main>
</body>
</html>`;
}
