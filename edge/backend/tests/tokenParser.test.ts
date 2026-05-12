import { describe, it, expect } from "vitest";
import { parseToken, parseTokens, matchesToken } from "../src/decoder/tokenParser.js";

describe("parseToken", () => {
  it("parses 1-letter prefixes", () => {
    const p = parseToken("t");
    expect(p).toEqual({ kind: "prefix", raw: "t", prefix: "t" });
  });

  it("parses 2-letter prefixes", () => {
    const p = parseToken("th");
    expect(p).toEqual({ kind: "prefix", raw: "th", prefix: "th" });
  });

  it("parses single-letter literals for 'a' and 'i'", () => {
    expect(parseToken("a")).toMatchObject({ kind: "literal", word: "a" });
    expect(parseToken("i")).toMatchObject({ kind: "literal", word: "i" });
  });

  it("parses 3+ letter literals (user typed full word)", () => {
    expect(parseToken("the")).toMatchObject({ kind: "literal", word: "the" });
    expect(parseToken("hello")).toMatchObject({ kind: "literal", word: "hello" });
  });

  it("handles case-insensitively", () => {
    expect(parseToken("T")).toMatchObject({ kind: "prefix", prefix: "t" });
    expect(parseToken("Th")).toMatchObject({ kind: "prefix", prefix: "th" });
    expect(parseToken("HELLO")).toMatchObject({ kind: "literal", word: "hello" });
  });

  it("treats punctuation as punct tokens", () => {
    expect(parseToken(".")).toMatchObject({ kind: "punct", word: "." });
    expect(parseToken(",")).toMatchObject({ kind: "punct", word: "," });
  });

  it("returns null for empty input", () => {
    expect(parseToken("")).toBeNull();
    expect(parseToken("   ")).toBeNull();
  });

  it("parses a multi-token list", () => {
    const out = parseTokens(["i", "wa", "to", "ma", "."]);
    expect(out.map((p) => p.kind)).toEqual(["literal", "prefix", "prefix", "prefix", "punct"]);
  });
});

describe("matchesToken", () => {
  it("validates prefix tokens by startsWith (case-insensitive)", () => {
    expect(matchesToken(parseToken("wa")!, "want")).toBe(true);
    expect(matchesToken(parseToken("wa")!, "was")).toBe(true);
    expect(matchesToken(parseToken("wa")!, "walk")).toBe(true);
    expect(matchesToken(parseToken("wa")!, "WANT")).toBe(true);
    expect(matchesToken(parseToken("wa")!, "where")).toBe(false);
    expect(matchesToken(parseToken("wa")!, "went")).toBe(false);
  });

  it("validates 1-letter prefixes", () => {
    expect(matchesToken(parseToken("t")!, "the")).toBe(true);
    expect(matchesToken(parseToken("t")!, "to")).toBe(true);
    expect(matchesToken(parseToken("t")!, "apple")).toBe(false);
  });

  it("validates literals exactly", () => {
    expect(matchesToken(parseToken("the")!, "the")).toBe(true);
    expect(matchesToken(parseToken("the")!, "they")).toBe(false);
  });
});
