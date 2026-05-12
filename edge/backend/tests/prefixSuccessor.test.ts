import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { CorrectionMemory } from "../src/decoder/correctionMemory.js";
import { PhraseMemory } from "../src/decoder/phraseMemory.js";
import { decode } from "../src/decoder/beamSearch.js";
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
  tmp = mkdtempSync(join(tmpdir(), "edge-ps-"));
  phrases = new PhraseMemory();
  corrections = new CorrectionMemory(join(tmp, "corrections.json"), phrases);
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

describe("prefix-successor boosts generalise corrections", () => {
  it("a single (i, wa) → was correction reshapes future predicts for the same prev/prefix", () => {
    // Baseline: bare beam picks "want" after "i" (canonical disambiguation).
    const before = decode(["i", "wa"], { phrases, corrections, domain: "general" });
    expect(before.best.split(" ")[1]).toBe("want");

    // Teach "i was" repeatedly so the prefix-successor table outweighs the
    // built-in "i want" bigram.
    for (let i = 0; i < 6; i++) {
      corrections.record("i wa", "i was", "general");
    }

    const after = decode(["i", "wa"], { phrases, corrections, domain: "general" });
    expect(after.best.split(" ")[1]).toBe("was");
  });

  it("the boost is keyed on prev word — a different prev does not benefit", () => {
    for (let i = 0; i < 6; i++) {
      corrections.record("i wa", "i was", "general");
    }
    // "she wa" — "she" never appeared as the prev word for (wa → was). The
    // successor boost should not apply, so the original (i want)-style
    // ranking does not get hijacked for this unrelated context.
    const r = decode(["she", "wa"], { phrases, corrections, domain: "general" });
    // We don't pin the exact word here (depends on dict scoring for "she wa"),
    // we only verify that the (i, wa → was) boost didn't leak into (she, wa).
    expect(corrections.prefixSuccessorBoost("she", "wa", "was", "general")).toBe(0);
    expect(corrections.prefixSuccessorBoost("i", "wa", "was", "general")).toBeGreaterThan(0);
    // And the result for "she wa" should be unaffected by the (i, wa) lesson.
    expect(r.best.split(" ")[0]).toBe("she");
  });

  it("falls back from non-general domains to general at half weight", () => {
    for (let i = 0; i < 4; i++) {
      corrections.record("i wa", "i was", "general");
    }
    const gen = corrections.prefixSuccessorBoost("i", "wa", "was", "general");
    const research = corrections.prefixSuccessorBoost("i", "wa", "was", "research");
    expect(gen).toBeGreaterThan(0);
    expect(research).toBeCloseTo(gen * 0.5, 6);
  });
});
