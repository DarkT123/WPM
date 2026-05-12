import type { WordCandidate } from "../../../shared/types.js";

export interface LLMRerankRequest {
  compressedTokens: string[];
  wordCandidates: WordCandidate[];
  contextBefore: string;
  contextAfter: string;
  domain: string;
  instruction: string;
}

export interface LLMRerankResponse {
  prediction: string;
  alternatives: string[];
}

/** Pluggable AI adapter. Implement this to use a different provider. */
export interface LLMClient {
  /** Returns null on timeout, network error, or any non-success response. */
  rerank(req: LLMRerankRequest, signal: AbortSignal): Promise<LLMRerankResponse | null>;
  /** Whether the adapter is configured enough to actually call. */
  available(): boolean;
}

export const DEFAULT_INSTRUCTION =
  "Reconstruct the most likely sentence from these compressed tokens. " +
  "Each compressed token is a 1- or 2-letter prefix of the intended word; " +
  "each output word must start with the same prefix (case-insensitive) " +
  "unless correcting an obvious typo. Use the candidate lists as hints. " +
  'Return JSON: {"prediction": "...", "alternatives": ["...", "..."]}';
