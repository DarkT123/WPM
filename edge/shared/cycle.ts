/**
 * Pure cycling helpers used by the backslash-correction keymap. Kept in the
 * shared/ tree so the frontend's keydown handler and the backend tests both
 * reach the same logic.
 */

import type { PredictResponse, WordCandidate } from "./types.js";

/** Index of the word the next "\" press should target. */
export function mostUncertainWordIndex(wc: WordCandidate[]): number {
  if (wc.length === 0) return -1;
  let bestIdx = 0;
  let bestConf = Infinity;
  for (let i = 0; i < wc.length; i++) {
    const c = wc[i]!.confidence;
    if (c < bestConf && wc[i]!.candidates.length > 1) {
      bestConf = c;
      bestIdx = i;
    }
  }
  // If every word is locked (single candidate), nothing to cycle.
  if (!Number.isFinite(bestConf)) return -1;
  return bestIdx;
}

/** Rotate a single word's selection forward (\) or backward (Shift+\). */
export function cycleWord(
  wc: WordCandidate,
  current: string,
  direction: 1 | -1,
): string {
  const cands = wc.candidates;
  if (cands.length <= 1) return current;
  const idx = cands.indexOf(current);
  const start = idx === -1 ? 0 : idx;
  const next = (start + direction + cands.length) % cands.length;
  return cands[next]!;
}

/**
 * Rotate through a fixed cycle list. The caller is expected to build the list
 * with the original prediction at index 0 followed by alternatives; that way
 * "wrap" always lands back on the original even if the current displayed
 * sentence is one of the alternatives.
 */
export function cycleSentence(
  current: string,
  list: readonly string[],
  direction: 1 | -1,
): string {
  if (list.length === 0) return current;
  const idx = list.indexOf(current);
  const start = idx === -1 ? 0 : idx;
  const next = (start + direction + list.length) % list.length;
  return list[next]!;
}

/**
 * Apply a backslash event to the current view state. The frontend wires this
 * directly into its keydown handler; tests cover the same call paths.
 */
export interface ViewState {
  words: string[];               // current displayed words
  selected: number | null;       // currently-targeted word index
  wordCandidates: WordCandidate[];
  alternatives: string[];
  /**
   * AI completions (from MiniMax). Folded into the Alt+\ cycle list after
   * local alternatives so the keyboard can reach them. Cmd+\ on an AI
   * suggestion teaches it exactly like any other accepted sentence.
   */
  aiSuggestions?: string[];
  /** The originally-predicted sentence — wrap point for Alt+\ cycling. */
  originalPrediction: string;
}

export interface CycleEvent {
  shift?: boolean;
  alt?: boolean;
  meta?: boolean;                // cmd / ctrl
}

export type CycleResult =
  | { kind: "accept"; sentence: string }
  | { kind: "noop" }
  | { kind: "word"; index: number; newWord: string; words: string[] }
  | { kind: "sentence"; words: string[] };

export function applyBackslash(state: ViewState, ev: CycleEvent): CycleResult {
  if (ev.meta) {
    return { kind: "accept", sentence: state.words.join(" ") };
  }
  if (ev.alt) {
    const current = state.words.join(" ");
    // Build a stable cycle list: original first, then local alternatives,
    // then AI suggestions, deduped against each other and the anchor.
    const seen = new Set<string>();
    const list: string[] = [];
    const sources = [
      state.originalPrediction,
      ...state.alternatives,
      ...(state.aiSuggestions ?? []),
    ];
    for (const s of sources) {
      if (!s || seen.has(s)) continue;
      seen.add(s); list.push(s);
    }
    if (list.length <= 1) return { kind: "noop" };
    const next = cycleSentence(current, list, ev.shift ? -1 : 1);
    if (next === current) return { kind: "noop" };
    return { kind: "sentence", words: next.split(/\s+/).filter(Boolean) };
  }

  // Per-word cycle: target the explicitly-selected word, else the most uncertain.
  const idx = state.selected ?? mostUncertainWordIndex(state.wordCandidates);
  if (idx < 0 || idx >= state.wordCandidates.length) return { kind: "noop" };
  const wc = state.wordCandidates[idx]!;
  const current = state.words[idx] ?? wc.selected;
  const newWord = cycleWord(wc, current, ev.shift ? -1 : 1);
  if (newWord === current) return { kind: "noop" };
  const words = [...state.words];
  words[idx] = newWord;
  return { kind: "word", index: idx, newWord, words };
}

/** Convenience used by both frontend rendering and tests. */
export function defaultSelectedIndex(resp: Pick<PredictResponse, "wordCandidates">): number | null {
  const idx = mostUncertainWordIndex(resp.wordCandidates);
  return idx >= 0 ? idx : null;
}
