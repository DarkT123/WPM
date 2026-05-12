/**
 * Confidence is derived from beam-search gap: the bigger the gap between the
 * best beam and the second-best beam (per word and overall), the more
 * confident we are. We map raw gaps through a logistic so confidence is in
 * [0, 1], which the UI uses for highlighting and the route uses to decide
 * whether to call MiniMax.
 */

function logistic(x: number, k: number): number {
  return 1 / (1 + Math.exp(-k * x));
}

// Cap below 1 so "had alternatives" never reports as absolutely certain — the
// only way to get a true 1.0 is "only one candidate ever existed".
const SOFT_MAX = 0.99;

export function sentenceConfidence(topScore: number, secondScore: number | undefined): number {
  if (secondScore == null || !Number.isFinite(secondScore)) return 0.95;
  const gap = topScore - secondScore;
  // Tune so a gap of ~2 (one strong bigram) → ~0.85 confidence,
  //                  a gap of ~0.2                  → ~0.55.
  return Math.max(0, Math.min(SOFT_MAX, logistic(gap, 1.5)));
}

export function wordConfidence(bestScore: number, secondScore: number | undefined, options: number): number {
  if (options <= 1) return 1; // forced choice
  if (secondScore == null || !Number.isFinite(secondScore)) return 0.95;
  const gap = bestScore - secondScore;
  return Math.max(0, Math.min(SOFT_MAX, logistic(gap, 2)));
}
