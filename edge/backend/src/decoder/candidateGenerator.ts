import { loadDictionary, type WordEntry } from "./dictionary.js";
import { parseToken, type ParsedToken } from "./tokenParser.js";

const MAX_PER_TOKEN = 50;

interface Index {
  /** Map keyed by both 1-letter and 2-letter lowercase prefixes → words sorted desc by frequency. */
  byPrefix: Map<string, WordEntry[]>;
}

let cachedIndex: Index | null = null;
const tokenCache = new Map<string, string[]>();

function buildIndex(): Index {
  const byPrefix = new Map<string, WordEntry[]>();
  for (const entry of loadDictionary()) {
    const w = entry.word;
    if (!w) continue;
    const p1 = w.slice(0, 1);
    const p2 = w.length >= 2 ? w.slice(0, 2) : null;
    let b1 = byPrefix.get(p1);
    if (!b1) { b1 = []; byPrefix.set(p1, b1); }
    b1.push(entry);
    if (p2) {
      let b2 = byPrefix.get(p2);
      if (!b2) { b2 = []; byPrefix.set(p2, b2); }
      b2.push(entry);
    }
  }
  for (const arr of byPrefix.values()) arr.sort((a, b) => b.freq - a.freq);
  return { byPrefix };
}

function getIndex(): Index {
  if (!cachedIndex) cachedIndex = buildIndex();
  return cachedIndex;
}

export function resetCandidateCache(): void {
  cachedIndex = null;
  tokenCache.clear();
}

export function candidatesFor(parsed: ParsedToken, max = MAX_PER_TOKEN): string[] {
  const cacheKey = `${parsed.kind}:${parsed.raw.toLowerCase()}:${max}`;
  const cached = tokenCache.get(cacheKey);
  if (cached) return cached;

  let result: string[];
  switch (parsed.kind) {
    case "prefix": {
      const bucket = getIndex().byPrefix.get(parsed.prefix) ?? [];
      result = bucket.slice(0, max).map((e) => e.word);
      if (result.length === 0) result = [parsed.prefix];
      break;
    }
    case "literal":
      result = [parsed.word];
      break;
    case "punct":
      result = [parsed.word];
      break;
  }

  tokenCache.set(cacheKey, result);
  return result;
}

export function candidatesForToken(rawToken: string, max = MAX_PER_TOKEN): string[] {
  const parsed = parseToken(rawToken);
  if (!parsed) return [];
  return candidatesFor(parsed, max);
}
