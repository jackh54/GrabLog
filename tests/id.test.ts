import { describe, expect, it } from "vitest";
import { generateId, isValidId } from "../src/id";

describe("generateId", () => {
  it("returns the requested length", () => {
    expect(generateId(22)).toHaveLength(22);
    expect(generateId(32)).toHaveLength(32);
  });

  it("rejects short lengths", () => {
    expect(() => generateId(8)).toThrow(/at least 16/);
  });

  it("uses URL-safe alphanumeric characters", () => {
    const id = generateId(48);
    expect(id).toMatch(/^[A-Za-z0-9]+$/);
  });

  it("produces unique values", () => {
    const set = new Set(Array.from({ length: 50 }, () => generateId()));
    expect(set.size).toBe(50);
  });
});

describe("isValidId", () => {
  it("accepts generated ids", () => {
    expect(isValidId(generateId())).toBe(true);
  });

  it("rejects path traversal and short tokens", () => {
    expect(isValidId("../etc/passwd")).toBe(false);
    expect(isValidId("short")).toBe(false);
    expect(isValidId("has spaces in id!!")).toBe(false);
    expect(isValidId("")).toBe(false);
  });
});
