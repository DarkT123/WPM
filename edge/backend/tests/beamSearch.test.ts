import { describe, it, expect, beforeEach } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { decode } from "../src/decoder/beamSearch.js";
import { PhraseMemory } from "../src/decoder/phraseMemory.js";
import { CorrectionMemory } from "../src/decoder/correctionMemory.js";
import { resetCandidateCache } from "../src/decoder/candidateGenerator.js";
import { resetDictionaryCache } from "../src/decoder/dictionary.js";
import { resetScorerCache } from "../src/decoder/scorer.js";

let tmp: string;
let phrases: PhraseMemory;
let corrections: CorrectionMemory;

beforeEach(() => {
  resetCandidateCache();
  resetDictionaryCache();
  resetScorerCache();
  tmp = mkdtempSync(join(tmpdir(), "edge-"));
  phrases = new PhraseMemory();
  corrections = new CorrectionMemory(join(tmp, "corrections.json"), phrases);
});

function cleanup() {
  rmSync(tmp, { recursive: true, force: true });
}

describe("decode — context-aware reconstruction", () => {
  it("reconstructs the canonical Edge example sentence", () => {
    try {
      const r = decode(
        ["i", "wa", "to", "ma", "a", "pr", "ma", "re", "ap"],
        { phrases, corrections, domain: "general" }
      );
      expect(r.best).toBe("i want to make a prediction market research app");
      expect(r.wordCandidates).toHaveLength(9);
      expect(r.confidence).toBeGreaterThan(0);
    } finally { cleanup(); }
  });

  it("prefers 'want to' over 'was to' after 'i'", () => {
    try {
      const r = decode(["i", "wa", "to"], { phrases, corrections, domain: "general" });
      // The bigram "i want" / "want to" tie-break: "want" should win.
      expect(r.best.split(" ")[1]).toBe("want");
    } finally { cleanup(); }
  });

  it("uses right-context to influence earlier words", () => {
    try {
      const r = decode(
        ["wa", "to", "ma", "a", "prediction"],
        { phrases, corrections, domain: "general" }
      );
      // Looking ahead at "make a prediction" should push toward "want to make".
      const words = r.best.split(" ");
      expect(words[0]).toBe("want");
      expect(words[2]).toBe("make");
    } finally { cleanup(); }
  });

  it("uses domain to pick stronger phrase memory", () => {
    try {
      const general = decode(["pr", "ma"], { phrases, corrections, domain: "general" });
      const research = decode(["pr", "ma"], { phrases, corrections, domain: "research" });
      // research-domain has a much stronger "prediction market" bigram.
      expect(research.best).toBe("prediction market");
      // general should still find it via the general bigram table.
      expect(general.best).toBe("prediction market");
    } finally { cleanup(); }
  });

  it("uses contextBefore to seed bigrams across the boundary", () => {
    try {
      const r = decode(["wa"], {
        contextBefore: "i", phrases, corrections, domain: "general",
      });
      expect(r.best).toBe("want");
    } finally { cleanup(); }
  });

  it("uses 1-letter prefix tokens with context to disambiguate", () => {
    try {
      // After "i want", "t" should decode to "to" because of the bigrams.
      const r = decode(["i", "want", "t"], { phrases, corrections, domain: "general" });
      expect(r.best.split(" ")[2]).toBe("to");
    } finally { cleanup(); }
  });

  it("produces up to 10 distinct alternatives", () => {
    try {
      const r = decode(
        ["i", "wa", "to", "ma", "a", "pr", "ma", "re", "ap"],
        { phrases, corrections, domain: "general", maxAlternatives: 10 }
      );
      expect(r.alternatives.length).toBeGreaterThan(0);
      expect(r.alternatives.length).toBeLessThanOrEqual(10);
      expect(r.alternatives).not.toContain(r.best);
      expect(new Set(r.alternatives).size).toBe(r.alternatives.length);
    } finally { cleanup(); }
  });

  it("returns empty result for empty input", () => {
    try {
      const r = decode([], { phrases, corrections });
      expect(r.best).toBe("");
      expect(r.wordCandidates).toHaveLength(0);
    } finally { cleanup(); }
  });

  it("preserves punctuation tokens without spacing them", () => {
    try {
      const r = decode(["i", "wa", "to", "go", "."], { phrases, corrections, domain: "general" });
      expect(r.best).toBe("i want to go.");
    } finally { cleanup(); }
  });

  it("per-word confidence is in [0,1] and lower for ambiguous tokens", () => {
    try {
      const r = decode(["i", "wa", "to"], { phrases, corrections, domain: "general" });
      for (const wc of r.wordCandidates) {
        expect(wc.confidence).toBeGreaterThanOrEqual(0);
        expect(wc.confidence).toBeLessThanOrEqual(1);
      }
      // "wa" has many candidates → less than 1.
      const wa = r.wordCandidates.find((w) => w.token === "wa");
      expect(wa!.confidence).toBeLessThan(1);
    } finally { cleanup(); }
  });
});
