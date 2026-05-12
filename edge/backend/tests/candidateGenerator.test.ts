import { describe, it, expect, beforeEach } from "vitest";
import { candidatesForToken, resetCandidateCache } from "../src/decoder/candidateGenerator.js";
import { resetDictionaryCache } from "../src/decoder/dictionary.js";

beforeEach(() => {
  resetCandidateCache();
  resetDictionaryCache();
});

describe("candidatesForToken — 2-letter prefix tokens", () => {
  it("returns words starting with the prefix, sorted by frequency", () => {
    const out = candidatesForToken("wa");
    expect(out.length).toBeGreaterThan(0);
    expect(out).toContain("want");
    expect(out).toContain("was");
    expect(out).toContain("wait");
    for (const w of out) {
      expect(w.startsWith("wa")).toBe(true);
    }
  });

  it("is case insensitive", () => {
    expect(candidatesForToken("WA")).toEqual(candidatesForToken("wa"));
    expect(candidatesForToken("Wa")).toEqual(candidatesForToken("wa"));
  });

  it("caps at 50 candidates per token", () => {
    const out = candidatesForToken("a", 50);
    expect(out.length).toBeLessThanOrEqual(50);
    for (const w of out) {
      expect(w.startsWith("a")).toBe(true);
    }
  });

  it("supports a smaller user-specified cap", () => {
    const out = candidatesForToken("wa", 3);
    expect(out.length).toBeLessThanOrEqual(3);
  });

  it("passes through unknown prefixes as a single candidate", () => {
    const out = candidatesForToken("zq");
    expect(out).toContain("zq");
  });
});

describe("candidatesForToken — 1-letter prefix tokens", () => {
  it("returns words starting with the single letter, sorted by frequency", () => {
    const out = candidatesForToken("t");
    expect(out.length).toBeGreaterThan(0);
    // common t-words should appear near the top
    expect(out).toContain("the");
    expect(out).toContain("to");
    for (const w of out) {
      expect(w.startsWith("t")).toBe(true);
    }
  });
});

describe("candidatesForToken — literals & punctuation", () => {
  it("returns a single candidate for the literal one-letter words", () => {
    expect(candidatesForToken("a")).toEqual(["a"]);
    expect(candidatesForToken("i")).toEqual(["i"]);
  });

  it("returns the full word verbatim for 3+ letter literals", () => {
    expect(candidatesForToken("hello")).toEqual(["hello"]);
    expect(candidatesForToken("the")).toEqual(["the"]);
  });

  it("preserves punctuation tokens", () => {
    expect(candidatesForToken(".")).toEqual(["."]);
  });
});
