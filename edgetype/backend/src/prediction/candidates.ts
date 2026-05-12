import { loadDictionary, type WordEntry } from "./dictionary.js";

const MAX_PER_TOKEN = 50;

interface Index {
  byEdge: Map<string, WordEntry[]>;
  byFirst: Map<string, WordEntry[]>;
}

let cachedIndex: Index | null = null;

function buildIndex(): Index {
  const byEdge = new Map<string, WordEntry[]>();
  const byFirst = new Map<string, WordEntry[]>();
  for (const entry of loadDictionary()) {
    const w = entry.word;
    if (!w) continue;
    const first = w[0]!;
    const last = w[w.length - 1]!;
    const key = `${first}|${last}`;
    let bucket = byEdge.get(key);
    if (!bucket) {
      bucket = [];
      byEdge.set(key, bucket);
    }
    bucket.push(entry);

    let fb = byFirst.get(first);
    if (!fb) {
      fb = [];
      byFirst.set(first, fb);
    }
    fb.push(entry);
  }
  for (const arr of byEdge.values()) arr.sort((a, b) => b.freq - a.freq);
  for (const arr of byFirst.values()) arr.sort((a, b) => b.freq - a.freq);
  return { byEdge, byFirst };
}

function getIndex(): Index {
  if (!cachedIndex) cachedIndex = buildIndex();
  return cachedIndex;
}

export function resetCandidatesCache(): void {
  cachedIndex = null;
}

/**
 * Compressed token grammar:
 *   length 1 → single-letter words ("a", "i"); fall back to the token itself.
 *   length 2 → words whose first letter is token[0] and last is token[1].
 *   length >2 → treat as already-typed literal word (lets users mix in full words).
 * All input is lower-cased; case is restored at render time, not here.
 */
export function candidatesForToken(rawToken: string): string[] {
  const token = rawToken.toLowerCase().trim();
  if (!token) return [];

  if (token.length === 1) {
    // Only "a" and "i" are real one-letter English words.
    if (token === "a" || token === "i") return [token];
    return [token];
  }

  if (token.length > 2) {
    // The user typed the full word — keep it. Useful for proper nouns and
    // codewords the dictionary won't cover.
    return [token];
  }

  const first = token[0]!;
  const last = token[1]!;
  const index = getIndex();
  const bucket = index.byEdge.get(`${first}|${last}`) ?? [];

  const out: string[] = [];
  for (const entry of bucket) {
    out.push(entry.word);
    if (out.length >= MAX_PER_TOKEN) break;
  }

  if (out.length === 0) {
    // Unknown token: passthrough so the sentence still reconstructs end-to-end.
    out.push(token);
  }
  return out;
}

export function candidatesForTokens(tokens: string[]): { token: string; candidates: string[] }[] {
  return tokens.map((token) => ({ token, candidates: candidatesForToken(token) }));
}

export function matchesEdgeConstraint(token: string, word: string): boolean {
  const t = token.toLowerCase();
  const w = word.toLowerCase();
  if (!t || !w) return false;
  if (t.length === 1) return w === t;
  if (t.length === 2) return w[0] === t[0] && w[w.length - 1] === t[1];
  return w === t;
}
