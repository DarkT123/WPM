import { loadDictionary } from "./dictionary.js";
import { bigramScore, getStarterBigrams, type BigramSource } from "./bigrams.js";

let freqMap: Map<string, number> | null = null;

function getFreqMap(): Map<string, number> {
  if (freqMap) return freqMap;
  freqMap = new Map();
  for (const e of loadDictionary()) freqMap.set(e.word, e.freq);
  return freqMap;
}

export function resetScoreCache(): void {
  freqMap = null;
}

const OBSCURITY_THRESHOLD = 500;
const OBSCURITY_PENALTY = 0.8;

export interface ScoreInputs {
  prevWord: string;
  word: string;
  token: string;
  source: BigramSource;
  wordBoosts: Readonly<Record<string, Readonly<Record<string, number>>>>;
}

/**
 * Combined word score. All components are in log-space-friendly units so they
 * can be summed across a sentence. The weights here are tuned by hand against
 * the example sentences in the README; raise them through correction-learning
 * rather than editing the constants whenever possible.
 */
export function wordScore({ prevWord, word, token, source, wordBoosts }: ScoreInputs): number {
  const freq = getFreqMap().get(word) ?? 1;
  let s = Math.log(freq + 1); // base unigram weight

  s += bigramScore(prevWord, word, source); // n-gram continuity

  if (freq < OBSCURITY_THRESHOLD) s -= OBSCURITY_PENALTY; // discourage rare words

  const boostForToken = wordBoosts[token.toLowerCase()];
  if (boostForToken) {
    const b = boostForToken[word.toLowerCase()] ?? 0;
    if (b) s += Math.log(1 + b) * 2; // user corrections compound over time
  }

  return s;
}

export function defaultBigramSource(learned: Readonly<Record<string, number>>): BigramSource {
  return { starter: getStarterBigrams(), learned };
}
