import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { CorrectionMemory } from "../src/decoder/correctionMemory.js";
import { PhraseMemory } from "../src/decoder/phraseMemory.js";
import { decode } from "../src/decoder/beamSearch.js";
import { resetCandidateCache } from "../src/decoder/candidateGenerator.js";
import { resetDictionaryCache } from "../src/decoder/dictionary.js";
import { resetScorerCache } from "../src/decoder/scorer.js";

let tmp: string;
let filePath: string;
let phrases: PhraseMemory;
let store: CorrectionMemory;

beforeEach(() => {
  resetCandidateCache();
  resetDictionaryCache();
  resetScorerCache();
  tmp = mkdtempSync(join(tmpdir(), "edge-cm-"));
  filePath = join(tmp, "corrections.json");
  phrases = new PhraseMemory();
  store = new CorrectionMemory(filePath, phrases);
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

describe("CorrectionMemory", () => {
  it("records and serves an exact pattern by domain", () => {
    store.record("pr ma", "prediction market", "business");
    expect(store.exactMatch("pr ma", "business")).toBe("prediction market");
    // Different domain → no exact hit.
    expect(store.exactMatch("pr ma", "general")).toBeNull();
  });

  it("persists across instances and across domains", () => {
    store.record("hi", "hi", "texting");
    const b = new CorrectionMemory(filePath, new PhraseMemory());
    expect(b.exactMatch("hi", "texting")).toBe("hi");
  });

  it("teaches token-to-word boosts that reshape beam search", () => {
    // Without correction, decoder picks something else for "ap" alone.
    const base = decode(["ap"], { phrases, corrections: store, domain: "general" });
    // teach repeatedly so the boost is large
    for (let i = 0; i < 8; i++) store.record("ap", "app", "general");
    const after = decode(["ap"], { phrases, corrections: store, domain: "general" });
    expect(after.best).toBe("app");
    // Confidence never drops after teaching (the cap saturates both cases when the
    // boost is large enough, so we assert >= rather than strict >).
    expect(after.wordCandidates[0]!.confidence).toBeGreaterThanOrEqual(base.wordCandidates[0]!.confidence);
  });

  it("teaches phrase memory from corrections", () => {
    store.record("pr ma", "prediction market", "research");
    // PhraseMemory now has the learned bigram.
    expect(phrases.bigramScore("prediction", "market", "research")).toBeGreaterThan(0);
  });

  it("records prefix-successor counts under (prev|prefix|word)", () => {
    store.record("i wa", "i was", "general");
    expect(store.prefixSuccessorBoost("i", "wa", "was", "general")).toBeGreaterThan(0);
    // Different prev → no boost
    expect(store.prefixSuccessorBoost("he", "wa", "was", "general")).toBe(0);
    // Different word → no boost
    expect(store.prefixSuccessorBoost("i", "wa", "want", "general")).toBe(0);
  });

  it("persists prefix successors across instances", () => {
    store.record("i wa", "i was", "general");
    const b = new CorrectionMemory(filePath, new PhraseMemory());
    expect(b.prefixSuccessorBoost("i", "wa", "was", "general")).toBeGreaterThan(0);
  });

  it("rejects mismatched shape", () => {
    expect(() => store.record("a b c", "two words", "general")).toThrow();
  });

  it("rebuilds cleanly from a corrupted file", () => {
    writeFileSync(filePath, "not json", "utf8");
    const s = new CorrectionMemory(filePath, new PhraseMemory());
    expect(s.exactMatch("anything", "general")).toBeNull();
  });

  it("wipes data on schema version mismatch", () => {
    // Simulate an old (v1) corrections file from the first/last-letter era.
    writeFileSync(filePath, JSON.stringify({
      exactPatterns: { general: { "wt": "want" } },
      wordBoosts: { general: { wt: { want: 5 } } },
    }), "utf8");
    const s = new CorrectionMemory(filePath, new PhraseMemory());
    // Old patterns and boosts must not bleed into the new decoder.
    expect(s.exactMatch("wt", "general")).toBeNull();
    expect(s.wordBoost("wt", "want", "general")).toBe(0);
  });
});
