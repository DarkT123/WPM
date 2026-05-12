export type Domain = "general" | "school" | "business" | "coding" | "texting" | "research";

export interface WordCandidate {
  token: string;
  selected: string;
  candidates: string[];
  confidence: number; // 0..1
}

export interface PredictRequest {
  tokens: string[];
  contextBefore: string;
  contextAfter: string;
  domain: Domain;
  useAI: boolean;
}

export type PredictionSource = "local" | "ai" | "phrase" | "exact";

export interface PredictResponse {
  prediction: string;
  alternatives: string[];
  wordCandidates: WordCandidate[];
  confidence: number; // 0..1 over the whole sentence
  latencyMs: number;
  source: PredictionSource;
  aiAvailable: boolean;
  aiPending?: boolean;
  /**
   * AI completions returned alongside the local prediction. Populated when
   * useAI is on and the MiniMax call beats its timeout. The first entry is
   * the AI's top guess; subsequent entries are its alternatives. The primary
   * `prediction` field is only switched to AI when its confidence is clearly
   * higher than local — otherwise both are shown to the user.
   */
  aiSuggestions?: string[];
}

export interface LearnRequest {
  compressed: string;
  corrected: string;
  domain?: Domain;
}

export interface LearnResponse {
  ok: true;
}
