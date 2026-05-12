import { describe, it, expect, beforeEach } from "vitest";
import { candidatesForToken, matchesEdgeConstraint, resetCandidatesCache } from "../src/prediction/candidates.js";
import { resetDictionaryCache } from "../src/prediction/dictionary.js";

beforeEach(() => {
  resetCandidatesCache();
  resetDictionaryCache();
});

describe("candidatesForToken", () => {
  it("matches by first and last letter", () => {
    const out = candidatesForToken("te");
    expect(out).toContain("the");
    expect(out).toContain("time");
    expect(out).toContain("take");
    for (const w of out) {
      expect(w.startsWith("t")).toBe(true);
      expect(w.endsWith("e")).toBe(true);
    }
  });

  it("is case insensitive", () => {
    const lower = candidatesForToken("te");
    const upper = candidatesForToken("TE");
    const mixed = candidatesForToken("Te");
    expect(upper).toEqual(lower);
    expect(mixed).toEqual(lower);
  });

  it("handles single-letter words", () => {
    expect(candidatesForToken("a")).toEqual(["a"]);
    expect(candidatesForToken("i")).toEqual(["i"]);
  });

  it("caps at 50 candidates per token", () => {
    const out = candidatesForToken("ae"); // a... e is a fertile bucket
    expect(out.length).toBeLessThanOrEqual(50);
  });

  it("passes through unknown tokens so the sentence still reconstructs", () => {
    const out = candidatesForToken("zq");
    expect(out).toContain("zq");
  });

  it("treats tokens longer than 2 chars as literal words", () => {
    expect(candidatesForToken("hello")).toEqual(["hello"]);
  });

  it("ranks higher-frequency words first", () => {
    const out = candidatesForToken("te");
    expect(out[0]).toBe("the"); // most common t__e word in our dictionary
  });
});

describe("matchesEdgeConstraint", () => {
  it("accepts words that obey first/last letter rule", () => {
    expect(matchesEdgeConstraint("te", "the")).toBe(true);
    expect(matchesEdgeConstraint("qk", "quick")).toBe(true);
  });

  it("rejects words that violate the constraint", () => {
    expect(matchesEdgeConstraint("te", "two")).toBe(false);
    expect(matchesEdgeConstraint("qk", "queen")).toBe(false);
  });

  it("is case insensitive", () => {
    expect(matchesEdgeConstraint("TE", "The")).toBe(true);
  });
});
