import { describe, it, expect } from "vitest";
import {
  applyBackslash,
  cycleWord,
  cycleSentence,
  mostUncertainWordIndex,
  defaultSelectedIndex,
} from "../../shared/cycle.js";
import type { WordCandidate } from "../../shared/types.js";

function wc(token: string, selected: string, candidates: string[], confidence = 0.5): WordCandidate {
  return { token, selected, candidates, confidence };
}

describe("cycleWord", () => {
  it("rotates forward through candidates", () => {
    const c = wc("wa", "want", ["want", "went", "wait", "what"]);
    expect(cycleWord(c, "want", 1)).toBe("went");
    expect(cycleWord(c, "went", 1)).toBe("wait");
    expect(cycleWord(c, "wait", 1)).toBe("what");
    expect(cycleWord(c, "what", 1)).toBe("want"); // wraps
  });

  it("rotates backward with shift", () => {
    const c = wc("wa", "want", ["want", "went", "wait", "what"]);
    expect(cycleWord(c, "want", -1)).toBe("what"); // wraps
    expect(cycleWord(c, "wait", -1)).toBe("went");
  });

  it("noops on a single candidate", () => {
    const c = wc("a", "a", ["a"]);
    expect(cycleWord(c, "a", 1)).toBe("a");
  });
});

describe("cycleSentence", () => {
  it("walks through a fixed cycle list forward and back", () => {
    const list = ["i want to", "i went to", "i wait to"];
    expect(cycleSentence(list[0]!, list, 1)).toBe("i went to");
    expect(cycleSentence("i went to", list, 1)).toBe("i wait to");
    expect(cycleSentence("i wait to", list, 1)).toBe(list[0]); // wraps to the anchor
    expect(cycleSentence(list[0]!, list, -1)).toBe("i wait to");
  });

  it("noops without a cycle list", () => {
    expect(cycleSentence("hi", [], 1)).toBe("hi");
  });
});

describe("mostUncertainWordIndex / defaultSelectedIndex", () => {
  it("returns the index with lowest confidence among those with options", () => {
    const list = [
      wc("a", "a", ["a"], 1.0),         // locked
      wc("wa", "want", ["want", "went"], 0.6),
      wc("pr", "prediction", ["prediction", "person"], 0.4),
    ];
    expect(mostUncertainWordIndex(list)).toBe(2);
    expect(defaultSelectedIndex({ wordCandidates: list })).toBe(2);
  });

  it("returns -1 when every word is locked", () => {
    const list = [wc("a", "a", ["a"], 1.0)];
    expect(mostUncertainWordIndex(list)).toBe(-1);
    expect(defaultSelectedIndex({ wordCandidates: list })).toBeNull();
  });
});

describe("applyBackslash", () => {
  const state = {
    words: ["i", "want", "to"],
    selected: 1,
    wordCandidates: [
      wc("i", "i", ["i"], 1),
      wc("wa", "want", ["want", "went", "wait", "what"], 0.55),
      wc("to", "to", ["to"], 1),
    ],
    alternatives: ["i went to", "i wait to"],
    originalPrediction: "i want to",
  };

  it("plain \\ cycles the selected word forward", () => {
    const r = applyBackslash(state, {});
    expect(r.kind).toBe("word");
    if (r.kind === "word") {
      expect(r.index).toBe(1);
      expect(r.newWord).toBe("went");
      expect(r.words[1]).toBe("went");
    }
  });

  it("Shift+\\ cycles the selected word backward", () => {
    const r = applyBackslash(state, { shift: true });
    if (r.kind !== "word") throw new Error("expected word cycle");
    expect(r.newWord).toBe("what");
  });

  it("Alt+\\ cycles the whole sentence", () => {
    const r = applyBackslash(state, { alt: true });
    if (r.kind !== "sentence") throw new Error("expected sentence cycle");
    expect(r.words.join(" ")).toBe("i went to");
  });

  it("Cmd/Ctrl+\\ accepts the current sentence", () => {
    const r = applyBackslash(state, { meta: true });
    if (r.kind !== "accept") throw new Error("expected accept");
    expect(r.sentence).toBe("i want to");
  });

  it("falls back to most uncertain word when nothing is selected", () => {
    const s = { ...state, selected: null };
    const r = applyBackslash(s, {});
    if (r.kind !== "word") throw new Error("expected word cycle");
    expect(r.index).toBe(1); // wa is the only ambiguous one
  });
});

describe("applyBackslash — aiSuggestions in the Alt+\\ cycle", () => {
  const baseState = {
    words: ["i", "want", "to"],
    selected: null,
    wordCandidates: [
      wc("i", "i", ["i"], 1),
      wc("wa", "want", ["want", "was"], 0.55),
      wc("to", "to", ["to"], 1),
    ],
    alternatives: ["i was to"],
    originalPrediction: "i want to",
  };

  it("Alt+\\ rotates through local alternatives, then AI suggestions, then wraps to the original", () => {
    const state = { ...baseState, aiSuggestions: ["i want too", "i wait to"] };

    // First Alt+\: original → local alternative
    let words = state.words;
    let r = applyBackslash({ ...state, words }, { alt: true });
    if (r.kind !== "sentence") throw new Error("expected sentence cycle");
    expect(r.words.join(" ")).toBe("i was to");

    // Second Alt+\: into AI territory
    words = r.words;
    r = applyBackslash({ ...state, words }, { alt: true });
    if (r.kind !== "sentence") throw new Error("expected sentence cycle");
    expect(r.words.join(" ")).toBe("i want too");

    // Third Alt+\: next AI suggestion
    words = r.words;
    r = applyBackslash({ ...state, words }, { alt: true });
    if (r.kind !== "sentence") throw new Error("expected sentence cycle");
    expect(r.words.join(" ")).toBe("i wait to");

    // Fourth Alt+\: wraps back to the original prediction
    words = r.words;
    r = applyBackslash({ ...state, words }, { alt: true });
    if (r.kind !== "sentence") throw new Error("expected sentence cycle");
    expect(r.words.join(" ")).toBe("i want to");
  });

  it("dedupes AI suggestions against the original and local alternatives", () => {
    const state = {
      ...baseState,
      // First entry duplicates the anchor; second duplicates a local alt.
      aiSuggestions: ["i want to", "i was to", "i wait to"],
    };
    // From the anchor, the first new sentence is the local alt, then we
    // should jump straight to the deduped AI sentence ("i wait to").
    let r = applyBackslash({ ...state, words: state.words }, { alt: true });
    if (r.kind !== "sentence") throw new Error("expected sentence cycle");
    expect(r.words.join(" ")).toBe("i was to");

    r = applyBackslash({ ...state, words: r.words }, { alt: true });
    if (r.kind !== "sentence") throw new Error("expected sentence cycle");
    expect(r.words.join(" ")).toBe("i wait to");

    // And wraps.
    r = applyBackslash({ ...state, words: r.words }, { alt: true });
    if (r.kind !== "sentence") throw new Error("expected sentence cycle");
    expect(r.words.join(" ")).toBe("i want to");
  });

  it("Cmd+\\ on a cycled AI suggestion accepts that sentence verbatim", () => {
    const state = {
      ...baseState,
      aiSuggestions: ["i want too"],
      words: ["i", "want", "too"], // simulate post-Alt+\ state on the AI suggestion
    };
    const r = applyBackslash(state, { meta: true });
    if (r.kind !== "accept") throw new Error("expected accept");
    expect(r.sentence).toBe("i want too");
  });

  it("Shift+Alt+\\ rotates backward through the same combined list", () => {
    const state = { ...baseState, aiSuggestions: ["i want too"] };
    // From the anchor going backward → last entry in the cycle (the AI one).
    const r = applyBackslash({ ...state, words: state.words }, { alt: true, shift: true });
    if (r.kind !== "sentence") throw new Error("expected sentence cycle");
    expect(r.words.join(" ")).toBe("i want too");
  });

  it("Alt+\\ is a noop when there are no alternatives and no AI suggestions", () => {
    const state = {
      words: ["hello"],
      selected: null,
      wordCandidates: [wc("hello", "hello", ["hello"], 1)],
      alternatives: [],
      aiSuggestions: [],
      originalPrediction: "hello",
    };
    const r = applyBackslash(state, { alt: true });
    expect(r.kind).toBe("noop");
  });
});
