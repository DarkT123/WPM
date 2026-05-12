import type { Domain } from "../../../shared/types.js";
import { loadDictionary } from "./dictionary.js";
import type { PhraseMemory } from "./phraseMemory.js";
import type { CorrectionMemory } from "./correctionMemory.js";

let freqMap: Map<string, number> | null = null;

function getFreqMap(): Map<string, number> {
  if (freqMap) return freqMap;
  freqMap = new Map();
  for (const e of loadDictionary()) freqMap.set(e.word, e.freq);
  return freqMap;
}

export function resetScorerCache(): void {
  freqMap = null;
}

const OBSCURITY_THRESHOLD = 500;
const OBSCURITY_PENALTY = 1.0;
const PUNCT_BONUS = 0.2;

export interface StepInputs {
  prev2: string;
  prev1: string;
  word: string;
  token: string;
  next: string;          // right-context preview (e.g. literal word the user already typed past)
  domain: Domain;
  phrases: PhraseMemory;
  corrections: CorrectionMemory;
  isPunct: boolean;
}

/**
 * Score one word in a beam during left-to-right search. Includes:
 *   - unigram weight (log frequency)
 *   - bigram (prev1, word)
 *   - trigram (prev2, prev1, word)
 *   - right-context bigram (word, next) if a next word is fixed
 *   - learned token-to-word boost from corrections
 *   - learned (prev, prefix → word) successor boost — strongest local signal
 *   - obscurity penalty
 *   - punctuation pass-through bonus (so commas and periods don't get dropped)
 */
export function stepScore(inp: StepInputs): number {
  if (inp.isPunct) return PUNCT_BONUS;

  const freq = getFreqMap().get(inp.word.toLowerCase()) ?? 1;
  let s = Math.log(freq + 1);

  s += inp.phrases.bigramScore(inp.prev1, inp.word, inp.domain);
  s += inp.phrases.trigramScore(inp.prev2, inp.prev1, inp.word, inp.domain) * 1.4;

  if (inp.next) {
    s += inp.phrases.bigramScore(inp.word, inp.next, inp.domain) * 0.8;
  }

  const boost = inp.corrections.wordBoost(inp.token, inp.word, inp.domain);
  if (boost > 0) s += Math.log(1 + boost) * 2.5;

  // (prev, prefix → word) is the highest-signal correction in a prefix
  // decoder. Weight it more aggressively than the token-only boost so a
  // single taught (i, wa) → was overrides general-purpose ranking.
  const succ = inp.corrections.prefixSuccessorBoost(inp.prev1, inp.token, inp.word, inp.domain);
  if (succ > 0) s += Math.log(1 + succ) * 4.0;

  if (freq < OBSCURITY_THRESHOLD) s -= OBSCURITY_PENALTY;

  return s;
}
