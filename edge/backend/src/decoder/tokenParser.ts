/**
 * Edge supports two compressed-token forms plus literal punctuation:
 *
 *   "t"    – 1-letter prefix; any word starting with T (case-insensitive).
 *   "th"   – 2-letter prefix; any word starting with TH.
 *   "the"  – literal full word (3+ alphabetic chars). Preserved verbatim.
 *   "a"    – literal one-letter word.
 *   "i"    – literal one-letter word.
 *
 * The token parser also keeps trailing punctuation as its own token so the
 * decoder doesn't try to invent a word for a comma or period.
 */

export type ParsedToken =
  | { kind: "prefix"; raw: string; prefix: string }
  | { kind: "literal"; raw: string; word: string }
  | { kind: "punct"; raw: string; word: string };

const PUNCT = new Set([".", ",", "!", "?", ";", ":", "—", "–", "-"]);
const LITERAL_ONE_LETTER = new Set(["a", "i"]);

export function parseToken(rawIn: string): ParsedToken | null {
  const raw = rawIn.trim();
  if (!raw) return null;

  // Pure punctuation token (e.g. "." or "!")
  if ([...raw].every((c) => PUNCT.has(c))) {
    return { kind: "punct", raw, word: raw };
  }

  const lower = raw.toLowerCase();

  // 1-letter literal words ("a", "i")
  if (lower.length === 1 && LITERAL_ONE_LETTER.has(lower)) {
    return { kind: "literal", raw, word: lower };
  }

  // 1-letter prefix (any other alphabetic single character)
  if (lower.length === 1 && /^[a-z]$/.test(lower)) {
    return { kind: "prefix", raw, prefix: lower };
  }

  // 2-letter prefix
  if (lower.length === 2 && /^[a-z]{2}$/.test(lower)) {
    return { kind: "prefix", raw, prefix: lower };
  }

  // 3+ letters all alphabetic → user typed the full word
  if (/^[a-z]+$/.test(lower)) {
    return { kind: "literal", raw, word: lower };
  }

  // Mixed content we don't recognise: treat as literal punctuation-ish noise
  // so the caller can pass it through unchanged.
  return { kind: "punct", raw, word: raw };
}

export function parseTokens(tokens: string[]): ParsedToken[] {
  const out: ParsedToken[] = [];
  for (const t of tokens) {
    const parsed = parseToken(t);
    if (parsed) out.push(parsed);
  }
  return out;
}

/**
 * Does a given candidate word match the constraint encoded in the token?
 * Used both by the AI validator and by tests.
 */
export function matchesToken(parsed: ParsedToken, word: string): boolean {
  const w = word.toLowerCase();
  switch (parsed.kind) {
    case "prefix":
      return w.startsWith(parsed.prefix);
    case "literal":
      return w === parsed.word;
    case "punct":
      return w === parsed.word;
  }
}
