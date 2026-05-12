import { candidatesForToken } from "./candidates.js";
import { defaultBigramSource, wordScore } from "./score.js";

interface Beam {
  words: string[];
  score: number;
}

export interface BeamSearchOptions {
  beamWidth?: number;
  contextBefore?: string;
  learnedBigrams?: Readonly<Record<string, number>>;
  wordBoosts?: Readonly<Record<string, Readonly<Record<string, number>>>>;
  maxAlternatives?: number;
}

export interface BeamSearchResult {
  best: string;
  alternatives: string[];
  wordCandidates: { token: string; candidates: string[] }[];
}

function lastWord(text: string): string {
  const m = text.match(/([a-zA-Z']+)\s*$/);
  return m ? m[1]!.toLowerCase() : "";
}

const DEFAULT_BEAM = Number(process.env.BEAM_WIDTH ?? "20") || 20;

export function beamSearch(tokens: string[], opts: BeamSearchOptions = {}): BeamSearchResult {
  const beamWidth = Math.max(1, opts.beamWidth ?? DEFAULT_BEAM);
  const maxAlts = Math.max(1, opts.maxAlternatives ?? 8);
  const source = defaultBigramSource(opts.learnedBigrams ?? {});
  const wordBoosts = opts.wordBoosts ?? {};

  const wordCandidates = tokens.map((token) => ({
    token,
    candidates: candidatesForToken(token),
  }));

  if (tokens.length === 0) {
    return { best: "", alternatives: [], wordCandidates };
  }

  const seed: Beam = { words: [], score: 0 };
  let beams: Beam[] = [seed];
  let prevSeed = lastWord(opts.contextBefore ?? "");

  for (let i = 0; i < tokens.length; i++) {
    const { token, candidates } = wordCandidates[i]!;
    const next: Beam[] = [];

    for (const beam of beams) {
      const prevWord = beam.words.length ? beam.words[beam.words.length - 1]! : prevSeed;
      for (const word of candidates) {
        const inc = wordScore({ prevWord, word, token, source, wordBoosts });
        next.push({
          words: [...beam.words, word],
          score: beam.score + inc,
        });
      }
    }

    next.sort((a, b) => b.score - a.score);
    beams = next.slice(0, beamWidth);
  }

  const top = beams.slice(0, maxAlts);
  const best = top[0]?.words.join(" ") ?? "";
  // Skip the top result when listing alternatives so the UI sees distinct options.
  const seen = new Set<string>([best]);
  const alternatives: string[] = [];
  for (const b of top) {
    const s = b.words.join(" ");
    if (seen.has(s)) continue;
    seen.add(s);
    alternatives.push(s);
  }
  return { best, alternatives, wordCandidates };
}
