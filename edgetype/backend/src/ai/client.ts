import type { WordCandidates } from "../../../shared/types.js";
import { matchesEdgeConstraint } from "../prediction/candidates.js";

export interface AICompleteRequest {
  compressedTokens: string[];
  wordCandidates: WordCandidates[];
  contextBefore: string;
  instruction: string;
}

export interface AICompleteResponse {
  prediction: string;
  alternatives?: string[];
}

export interface AIResult {
  prediction: string;
  alternatives: string[];
  mismatchedWords: number[];
}

export interface AIClientConfig {
  baseUrl: string | undefined;
  apiKey: string | undefined;
  timeoutMs: number;
  fetchImpl?: typeof fetch;
}

const DEFAULT_INSTRUCTION =
  "Reconstruct the most likely sentence. Every output word must match the corresponding first and last letter constraint unless correcting an obvious user typo.";

export function aiConfigFromEnv(): AIClientConfig {
  return {
    baseUrl: process.env.AI_API_BASE_URL,
    apiKey: process.env.AI_API_KEY,
    timeoutMs: Number(process.env.AI_TIMEOUT_MS ?? "150") || 150,
  };
}

export async function callAI(
  tokens: string[],
  wordCandidates: WordCandidates[],
  contextBefore: string,
  config: AIClientConfig
): Promise<AIResult | null> {
  if (!config.baseUrl) return null;

  const url = `${config.baseUrl.replace(/\/$/, "")}/complete`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), config.timeoutMs);

  const headers: Record<string, string> = { "content-type": "application/json" };
  if (config.apiKey) headers.authorization = `Bearer ${config.apiKey}`;

  const body: AICompleteRequest = {
    compressedTokens: tokens,
    wordCandidates,
    contextBefore,
    instruction: DEFAULT_INSTRUCTION,
  };

  const fetchImpl = config.fetchImpl ?? fetch;
  try {
    const resp = await fetchImpl(url, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (!resp.ok) return null;
    const data = (await resp.json()) as AICompleteResponse;
    if (!data?.prediction || typeof data.prediction !== "string") return null;

    const predictionWords = data.prediction.trim().split(/\s+/);
    const mismatchedWords: number[] = [];
    for (let i = 0; i < tokens.length; i++) {
      const w = predictionWords[i];
      if (!w || !matchesEdgeConstraint(tokens[i]!, w)) mismatchedWords.push(i);
    }

    return {
      prediction: data.prediction,
      alternatives: Array.isArray(data.alternatives) ? data.alternatives.filter((x): x is string => typeof x === "string") : [],
      mismatchedWords,
    };
  } catch {
    // Timeout, network error, or bad JSON — caller falls back to local.
    return null;
  } finally {
    clearTimeout(timer);
  }
}
