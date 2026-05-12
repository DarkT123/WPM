import { describe, it, expect } from "vitest";
import { sentenceConfidence, wordConfidence } from "../src/decoder/confidence.js";

describe("sentenceConfidence", () => {
  it("returns ~1 when there is no runner-up", () => {
    expect(sentenceConfidence(5, undefined)).toBeGreaterThan(0.9);
  });

  it("rises monotonically with the gap to second-best", () => {
    const a = sentenceConfidence(10, 9.9);
    const b = sentenceConfidence(10, 8);
    const c = sentenceConfidence(10, 5);
    expect(a).toBeLessThan(b);
    expect(b).toBeLessThan(c);
  });

  it("is bounded in [0, 1]", () => {
    for (let g = -5; g <= 5; g += 0.5) {
      const v = sentenceConfidence(0, -g);
      expect(v).toBeGreaterThanOrEqual(0);
      expect(v).toBeLessThanOrEqual(1);
    }
  });
});

describe("wordConfidence", () => {
  it("returns 1 when only one candidate exists", () => {
    expect(wordConfidence(3, undefined, 1)).toBe(1);
  });

  it("rises with the gap to second-best", () => {
    const a = wordConfidence(5, 4.9, 4);
    const b = wordConfidence(5, 2, 4);
    expect(b).toBeGreaterThan(a);
  });
});
