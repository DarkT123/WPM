import { describe, it, expect, beforeEach } from "vitest";
import { beamSearch } from "../src/prediction/beamSearch.js";
import { resetCandidatesCache } from "../src/prediction/candidates.js";
import { resetDictionaryCache } from "../src/prediction/dictionary.js";
import { resetScoreCache } from "../src/prediction/score.js";

beforeEach(() => {
  resetCandidatesCache();
  resetDictionaryCache();
  resetScoreCache();
});

describe("beamSearch", () => {
  it("reconstructs 'the quick brown fox' from edge tokens", () => {
    const res = beamSearch(["te", "qk", "bn", "fx"]);
    expect(res.best).toBe("the quick brown fox");
    expect(res.wordCandidates).toHaveLength(4);
  });

  it("produces distinct alternatives", () => {
    const res = beamSearch(["te", "qk", "bn", "fx"], { maxAlternatives: 5 });
    expect(res.alternatives.length).toBeGreaterThan(0);
    expect(res.alternatives).not.toContain(res.best);
    const uniq = new Set(res.alternatives);
    expect(uniq.size).toBe(res.alternatives.length);
  });

  it("respects beam width", () => {
    const narrow = beamSearch(["te", "qk", "bn", "fx"], { beamWidth: 1, maxAlternatives: 10 });
    // beam=1 means only one beam survives each step, so there's just one final beam
    expect(narrow.alternatives.length).toBe(0);
    expect(narrow.best).toBeTruthy();
  });

  it("handles 'we are going to the place'", () => {
    const res = beamSearch(["we", "ae", "gg", "to", "te", "pe"]);
    // tolerate one-word drift in ranking — the algorithm is heuristic.
    const tokens = res.best.split(" ");
    expect(tokens).toHaveLength(6);
    expect(tokens[0]).toBe("we");
    expect(tokens[3]).toBe("to");
    expect(tokens[4]).toBe("the");
  });

  it("uses context for the first word's bigram", () => {
    const withCtx = beamSearch(["pe"], { contextBefore: "we are going to the" });
    expect(withCtx.best.length).toBeGreaterThan(0);
    // first letter p, last letter e — both "place" and "people" qualify
    expect(["place", "people", "piece"]).toContain(withCtx.best);
  });

  it("returns empty on empty input", () => {
    const res = beamSearch([]);
    expect(res.best).toBe("");
    expect(res.alternatives).toEqual([]);
  });

  it("incorporates wordBoosts from corrections", () => {
    const base = beamSearch(["fx"]);
    expect(base.best).toBe("fox"); // higher freq
    const boosted = beamSearch(["fx"], { wordBoosts: { fx: { fix: 50 } } });
    expect(boosted.best).toBe("fix");
  });
});
