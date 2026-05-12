import { describe, it, expect } from "vitest";
import { PhraseMemory } from "../src/decoder/phraseMemory.js";

describe("PhraseMemory", () => {
  it("scores curated bigrams positively", () => {
    const p = new PhraseMemory();
    expect(p.bigramScore("want", "to", "general")).toBeGreaterThan(0);
    expect(p.bigramScore("xyz", "abc", "general")).toBe(0);
  });

  it("scores trigrams above bigrams when both apply", () => {
    const p = new PhraseMemory();
    const bg = p.bigramScore("want", "to", "general");
    const tg = p.trigramScore("i", "want", "to", "general");
    expect(tg).toBeGreaterThan(0);
    expect(bg).toBeGreaterThan(0);
  });

  it("weights domain-specific bigrams more than general", () => {
    const p = new PhraseMemory();
    const general = p.bigramScore("prediction", "market", "general");
    const research = p.bigramScore("prediction", "market", "research");
    expect(research).toBeGreaterThan(general);
  });

  it("learns from observed phrases", () => {
    const p = new PhraseMemory();
    const before = p.bigramScore("foo", "bar", "general");
    p.learn(["foo", "bar"], "general");
    p.learn(["foo", "bar"], "general");
    p.learn(["foo", "bar"], "general");
    expect(p.bigramScore("foo", "bar", "general")).toBeGreaterThan(before);
  });

  it("snapshot/restore round-trips learned phrases", () => {
    const a = new PhraseMemory();
    a.learn(["alpha", "beta", "gamma"], "coding");
    const snap = a.snapshot();
    const b = new PhraseMemory();
    expect(b.bigramScore("alpha", "beta", "coding")).toBe(0);
    b.restore(snap);
    expect(b.bigramScore("alpha", "beta", "coding")).toBeGreaterThan(0);
    expect(b.trigramScore("alpha", "beta", "gamma", "coding")).toBeGreaterThan(0);
  });
});
