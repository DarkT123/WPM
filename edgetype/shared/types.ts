export interface WordCandidates {
  token: string;
  candidates: string[];
}

export interface PredictRequest {
  tokens: string[];
  contextBefore: string;
  useAI: boolean;
}

export type PredictionSource = "local" | "ai";

export interface PredictResponse {
  prediction: string;
  alternatives: string[];
  wordCandidates: WordCandidates[];
  latencyMs: number;
  source: PredictionSource;
  mismatchedWords?: number[];
}

export interface LearnRequest {
  compressed: string;
  corrected: string;
}

export interface LearnResponse {
  ok: true;
}
