import { describe, expect, it } from "vitest";
import {
  escapeForScriptLiteral,
  fillScriptTemplate,
  paramsFromUrl,
  sanitizeParam,
  wantsPowerShell,
} from "../src/script";

describe("sanitizeParam", () => {
  it("allows simple tokens and hostnames", () => {
    expect(sanitizeParam("modrinth")).toBe("modrinth");
    expect(sanitizeParam("All the Mods")).toBe("All the Mods");
    expect(sanitizeParam("crash-2024")).toBe("crash-2024");
    expect(sanitizeParam("example.net")).toBe("example.net");
    expect(sanitizeParam("play.example.net:25565")).toBe(
      "play.example.net:25565",
    );
  });

  it("strips unsafe characters", () => {
    expect(sanitizeParam("$(rm -rf /)")).toBe("");
    expect(sanitizeParam("a;b")).toBe("");
    expect(sanitizeParam("x\ny")).toBe("");
  });
});

describe("escapeForScriptLiteral", () => {
  it("escapes quotes and dollars", () => {
    expect(escapeForScriptLiteral(`a"b$c`)).toBe(`a\\"b\\$c`);
  });
});

describe("fillScriptTemplate", () => {
  it("replaces placeholders including server", () => {
    const out = fillScriptTemplate(
      'API="__GRABLOG_API__" L="__GRABLOG_LAUNCHER__" S="__GRABLOG_SERVER__"',
      {
        api: "https://grablog.test",
        launcher: "prism",
        instance: "",
        name: "",
        type: "",
        server: "example.net",
        yes: "",
      },
    );
    expect(out).toContain('API="https://grablog.test"');
    expect(out).toContain('L="prism"');
    expect(out).toContain('S="example.net"');
  });
});

describe("paramsFromUrl", () => {
  it("reads filters from the query string", () => {
    const url = new URL(
      "https://grablog.test/?launcher=modrinth&instance=ATM&name=crash&type=crash&server=example.net&yes=1",
    );
    const p = paramsFromUrl(url, "https://grablog.test/");
    expect(p).toEqual({
      api: "https://grablog.test",
      launcher: "modrinth",
      instance: "ATM",
      name: "crash",
      type: "crash",
      server: "example.net",
      yes: "1",
    });
  });
});

describe("wantsPowerShell", () => {
  it("detects /ps1 and PowerShell user agents", () => {
    expect(
      wantsPowerShell(
        new Request("https://x/", {
          headers: { "user-agent": "Mozilla/5.0" },
        }),
        new URL("https://x/ps1"),
      ),
    ).toBe(true);

    expect(
      wantsPowerShell(
        new Request("https://x/", {
          headers: { "user-agent": "Mozilla/5.0 PowerShell/7.4" },
        }),
        new URL("https://x/"),
      ),
    ).toBe(true);

    expect(
      wantsPowerShell(
        new Request("https://x/", {
          headers: { "user-agent": "curl/8.0" },
        }),
        new URL("https://x/?fmt=sh"),
      ),
    ).toBe(false);
  });
});
