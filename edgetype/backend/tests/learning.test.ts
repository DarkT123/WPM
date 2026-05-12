import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { CorrectionsStore } from "../src/learning/store.js";
import { beamSearch } from "../src/prediction/beamSearch.js";
import { resetCandidatesCache } from "../src/prediction/candidates.js";
import { resetDictionaryCache } from "../src/prediction/dictionary.js";
import { resetScoreCache } from "../src/prediction/score.js";

let tmp: string;
let filePath: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), "edgetype-"));
  filePath = join(tmp, "corrections.json");
  resetCandidatesCache();
  resetDictionaryCache();
  resetScoreCache();
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

describe("CorrectionsStore", () => {
  it("records and serves an exact pattern", () => {
    const store = new CorrectionsStore(filePath);
    store.record("te qk bn fx", "the quick brown fox");
    expect(store.exactMatch("te qk bn fx")).toBe("the quick brown fox");
  });

  it("persists across instances", () => {
    const a = new CorrectionsStore(filePath);
    a.record("hi", "hi");
    const b = new CorrectionsStore(filePath);
    expect(b.exactMatch("hi")).toBe("hi");
  });

  it("rejects mismatched shape", () => {
    const store = new CorrectionsStore(filePath);
    expect(() => store.record("te qk", "the quick brown fox")).toThrow();
  });

  it("accumulates word boosts that affect beam search ranking", () => {
    const store = new CorrectionsStore(filePath);
    // Without correction, the default for "fx" is "fox" (higher freq).
    const base = beamSearch(["fx"]);
    expect(base.best).toBe("fox");

    for (let i = 0; i < 10; i++) store.record("fx", "fix");
    const corrected = beamSearch(["fx"], { wordBoosts: store.wordBoosts() });
    expect(corrected.best).toBe("fix");
  });

  it("accumulates learned bigrams", () => {
    const store = new CorrectionsStore(filePath);
    store.record("te qk", "the quick");
    const learned = store.learnedBigrams();
    expect(learned["the quick"]).toBeGreaterThan(0);
  });

  it("rebuilds cleanly from a corrupted file", () => {
    const { writeFileSync } = require("node:fs");
    writeFileSync(filePath, "not json", "utf8");
    const store = new CorrectionsStore(filePath);
    expect(store.exactMatch("anything")).toBeNull();
    expect(store.wordBoosts()).toEqual({});
  });
});
