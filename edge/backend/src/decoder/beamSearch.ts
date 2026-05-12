import type { Domain, WordCandidate } from "../../../shared/types.js";
import { parseTokens, type ParsedToken } from "./tokenParser.js";
import { candidatesFor } from "./candidateGenerator.js";
import { stepScore } from "./scorer.js";
import type { PhraseMemory } from "./phraseMemory.js";
import type { CorrectionMemory } from "./correctionMemory.js";
import { sentenceConfidence, wordConfidence } from "./confidence.js";

interface Beam {
  words: string[];
  score: number;
}

export interface BeamSearchOptions {
  beamWidth?: number;
  maxAlternatives?: number;
  contextBefore?: string;
  contextAfter?: string;
  domain?: Domain;
  phrases: PhraseMemory;
  corrections: CorrectionMemory;
}

export interface BeamSearchResult {
  best: string;
  alternatives: string[];
  wordCandidates: WordCandidate[];
  confidence: number;
}

function tailWords(text: string, n: number): string[] {
  const words = text.toLowerCase().match(/[a-z']+/g) ?? [];
  return words.slice(-n);
}

function headWord(text: string): string {
  const m = text.toLowerCase().match(/[a-z']+/);
  return m ? m[0]! : "";
}

const DEFAULT_BEAM = Number(process.env.BEAM_WIDTH ?? "20") || 20;
const DEFAULT_MAX_ALTS = Number(process.env.MAX_ALTERNATIVES ?? "10") || 10;

export function decode(tokensIn: string[], opts: BeamSearchOptions): BeamSearchResult {
  const beamWidth = Math.max(1, opts.beamWidth ?? DEFAULT_BEAM);
  const maxAlts = Math.max(1, opts.maxAlternatives ?? DEFAULT_MAX_ALTS);
  const domain: Domain = opts.domain ?? "general";

  const parsed: ParsedToken[] = parseTokens(tokensIn);
  if (parsed.length === 0) {
    return { best: "", alternatives: [], wordCandidates: [], confidence: 0 };
  }

  // Pre-compute candidate lists once per position.
  const allCandidates: string[][] = parsed.map((p) => candidatesFor(p));

  // Seed prev2/prev1 from left context.
  const leftTail = tailWords(opts.contextBefore ?? "", 2);
  const seedPrev2 = leftTail[leftTail.length - 2] ?? "";
  const seedPrev1 = leftTail[leftTail.length - 1] ?? "";
  const rightHead = headWord(opts.contextAfter ?? "");

  let beams: Beam[] = [{ words: [], score: 0 }];

  for (let i = 0; i < parsed.length; i++) {
    const p = parsed[i]!;
    const isPunct = p.kind === "punct";
    // Right-context preview: literal/punct already known; for prefix tokens,
    // use the top-of-bucket candidate as a heuristic (the actual chosen word
    // at i+1 will refine in the next iteration).
    let next = "";
    if (i + 1 < parsed.length) {
      const nxt = parsed[i + 1]!;
      next = (nxt.kind === "literal" || nxt.kind === "punct")
        ? nxt.word
        : allCandidates[i + 1]?.[0] ?? "";
    } else {
      next = rightHead;
    }

    const candidates = allCandidates[i]!;
    const expanded: Beam[] = [];

    for (const beam of beams) {
      const prev1 = beam.words.length ? beam.words[beam.words.length - 1]! : seedPrev1;
      const prev2 = beam.words.length >= 2
        ? beam.words[beam.words.length - 2]!
        : (beam.words.length === 1 ? seedPrev1 : seedPrev2);
      for (const word of candidates) {
        const inc = stepScore({
          prev2, prev1, word, token: p.raw, next,
          domain, phrases: opts.phrases, corrections: opts.corrections, isPunct,
        });
        expanded.push({ words: [...beam.words, word], score: beam.score + inc });
      }
    }

    expanded.sort((a, b) => b.score - a.score);
    beams = expanded.slice(0, beamWidth);
  }

  const top = beams.slice(0, maxAlts);
  const bestBeam = top[0]!;
  const second = top[1];
  const confidence = sentenceConfidence(bestBeam.score, second?.score);
  const best = renderSentence(bestBeam.words, parsed);

  const seen = new Set<string>([best]);
  const alternatives: string[] = [];
  for (const b of top.slice(1)) {
    const s = renderSentence(b.words, parsed);
    if (!s || seen.has(s)) continue;
    seen.add(s);
    alternatives.push(s);
  }

  const wordCandidates = computePerWordCandidates(
    bestBeam.words, parsed, allCandidates, seedPrev2, seedPrev1, rightHead,
    domain, opts.phrases, opts.corrections,
  );

  return { best, alternatives, wordCandidates, confidence };
}

function renderSentence(words: string[], parsed: ParsedToken[]): string {
  // Render with appropriate spacing around punctuation tokens.
  let out = "";
  for (let i = 0; i < words.length; i++) {
    const w = words[i]!;
    const p = parsed[i]!;
    const isPunct = p.kind === "punct";
    if (i === 0) out = w;
    else if (isPunct) out += w;
    else out += " " + w;
  }
  return out;
}

function computePerWordCandidates(
  picked: string[],
  parsed: ParsedToken[],
  allCandidates: string[][],
  seedPrev2: string,
  seedPrev1: string,
  rightHead: string,
  domain: Domain,
  phrases: PhraseMemory,
  corrections: CorrectionMemory,
): WordCandidate[] {
  const out: WordCandidate[] = [];
  for (let i = 0; i < parsed.length; i++) {
    const p = parsed[i]!;
    const candidates = allCandidates[i]!;
    const isPunct = p.kind === "punct";

    const prev1 = i > 0 ? picked[i - 1]! : seedPrev1;
    const prev2 = i > 1 ? picked[i - 2]! : (i === 1 ? seedPrev1 : seedPrev2);
    const next = i + 1 < parsed.length ? picked[i + 1]! : rightHead;

    // Score every candidate with the *final* surrounding context for clean
    // local confidence numbers.
    const scored = candidates.map((c) => ({
      word: c,
      s: stepScore({ prev2, prev1, word: c, token: p.raw, next, domain, phrases, corrections, isPunct }),
    }));
    scored.sort((a, b) => b.s - a.s);

    const selected = picked[i]!;
    const best = scored[0]?.s ?? 0;
    const second = scored[1]?.s;
    const conf = wordConfidence(best, second, scored.length);

    out.push({
      token: p.raw,
      selected,
      candidates: scored.map((x) => x.word),
      confidence: conf,
    });
  }
  return out;
}
