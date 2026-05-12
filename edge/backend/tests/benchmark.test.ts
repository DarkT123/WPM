import { describe, it, expect, beforeAll } from "vitest";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { decode } from "../src/decoder/beamSearch.js";
import { PhraseMemory } from "../src/decoder/phraseMemory.js";
import { CorrectionMemory } from "../src/decoder/correctionMemory.js";

let phrases: PhraseMemory;
let corrections: CorrectionMemory;

beforeAll(() => {
  phrases = new PhraseMemory();
  corrections = new CorrectionMemory(
    join(mkdtempSync(join(tmpdir(), "edge-bench-")), "corrections.json"),
    phrases,
  );
  // Warm up the dictionary index by running once.
  decode(["i", "wa"], { phrases, corrections });
});

function bench(tokens: string[], iterations: number): { median: number; p95: number; mean: number } {
  const samples: number[] = [];
  for (let i = 0; i < iterations; i++) {
    const t = performance.now();
    decode(tokens, { phrases, corrections, domain: "general", beamWidth: 20, maxAlternatives: 10 });
    samples.push(performance.now() - t);
  }
  samples.sort((a, b) => a - b);
  const median = samples[Math.floor(samples.length / 2)]!;
  const p95 = samples[Math.floor(samples.length * 0.95)]!;
  const mean = samples.reduce((a, b) => a + b, 0) / samples.length;
  return { median, p95, mean };
}

describe("decoder latency", () => {
  it("decodes a 9-token sentence in under 30ms median, 60ms p95", () => {
    const tokens = ["i", "wa", "to", "ma", "a", "pr", "ma", "re", "ap"];
    const { median, p95, mean } = bench(tokens, 200);
    // eslint-disable-next-line no-console
    console.log(`[bench] 9 tokens — median=${median.toFixed(2)}ms p95=${p95.toFixed(2)}ms mean=${mean.toFixed(2)}ms`);
    expect(median).toBeLessThan(30);
    expect(p95).toBeLessThan(60);
  });

  it("decodes a 5-token sentence in under 15ms median", () => {
    const tokens = ["th", "qu", "br", "fo", "."];
    const { median, p95, mean } = bench(tokens, 200);
    // eslint-disable-next-line no-console
    console.log(`[bench] 5 tokens — median=${median.toFixed(2)}ms p95=${p95.toFixed(2)}ms mean=${mean.toFixed(2)}ms`);
    expect(median).toBeLessThan(15);
  });
});
