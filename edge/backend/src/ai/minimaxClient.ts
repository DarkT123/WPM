import { DEFAULT_INSTRUCTION, type LLMClient, type LLMRerankRequest, type LLMRerankResponse } from "./llmClient.js";

export interface MiniMaxConfig {
  baseUrl: string | undefined;
  apiKey: string | undefined;
  model: string;
  timeoutMs: number;
  fetchImpl?: typeof fetch;
}

export function miniMaxConfigFromEnv(): MiniMaxConfig {
  return {
    baseUrl: process.env.MINIMAX_API_BASE_URL,
    apiKey: process.env.MINIMAX_API_KEY,
    model: process.env.MINIMAX_MODEL ?? "abab6.5-chat",
    timeoutMs: Number(process.env.MINIMAX_TIMEOUT_MS ?? "200") || 200,
  };
}

/**
 * MiniMax adapter. Talks to MiniMax's OpenAI-compatible /v1/chat/completions
 * endpoint by default. The contract is shared via the LLMClient interface so
 * the route layer can swap in a different adapter without changes.
 */
export class MiniMaxClient implements LLMClient {
  constructor(private readonly cfg: MiniMaxConfig) {}

  available(): boolean {
    return Boolean(this.cfg.baseUrl);
  }

  async rerank(req: LLMRerankRequest, signal: AbortSignal): Promise<LLMRerankResponse | null> {
    if (!this.cfg.baseUrl) return null;
    const url = `${this.cfg.baseUrl.replace(/\/$/, "")}/v1/chat/completions`;
    const headers: Record<string, string> = { "content-type": "application/json" };
    if (this.cfg.apiKey) headers.authorization = `Bearer ${this.cfg.apiKey}`;

    const userContent = JSON.stringify({
      compressedTokens: req.compressedTokens,
      wordCandidates: req.wordCandidates,
      contextBefore: req.contextBefore,
      contextAfter: req.contextAfter,
      domain: req.domain,
    });

    const body = {
      model: this.cfg.model,
      messages: [
        { role: "system", content: req.instruction || DEFAULT_INSTRUCTION },
        { role: "user", content: userContent },
      ],
      response_format: { type: "json_object" },
      temperature: 0.2,
    };

    const fetchImpl = this.cfg.fetchImpl ?? fetch;
    try {
      const resp = await fetchImpl(url, {
        method: "POST", headers, body: JSON.stringify(body), signal,
      });
      if (!resp.ok) return null;
      const data = (await resp.json()) as {
        choices?: { message?: { content?: string } }[];
        // Some MiniMax responses use `reply` instead of OpenAI choices.
        reply?: string;
      };
      const text =
        data.choices?.[0]?.message?.content ??
        data.reply ??
        "";
      if (!text) return null;
      let parsed: unknown;
      try { parsed = JSON.parse(text); }
      catch { return null; }
      if (typeof parsed !== "object" || parsed === null) return null;
      const obj = parsed as Partial<LLMRerankResponse>;
      if (typeof obj.prediction !== "string" || !obj.prediction) return null;
      return {
        prediction: obj.prediction,
        alternatives: Array.isArray(obj.alternatives)
          ? obj.alternatives.filter((a): a is string => typeof a === "string")
          : [],
      };
    } catch {
      return null;
    }
  }
}

/**
 * Helper for the route layer: runs the client with a timeout. Returns null on
 * timeout or any failure so the caller can keep the local prediction.
 */
export async function rerankWithTimeout(
  client: LLMClient,
  req: LLMRerankRequest,
  timeoutMs: number,
): Promise<LLMRerankResponse | null> {
  if (!client.available()) return null;
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    return await client.rerank(req, ctrl.signal);
  } finally {
    clearTimeout(timer);
  }
}
