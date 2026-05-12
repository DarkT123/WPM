import type { Request, Response } from "express";
import type { Domain, PredictRequest, PredictResponse } from "../../../shared/types.js";
import { decode } from "../decoder/beamSearch.js";
import type { PhraseMemory } from "../decoder/phraseMemory.js";
import type { CorrectionMemory } from "../decoder/correctionMemory.js";
import { rerankWithTimeout, type MiniMaxConfig } from "../ai/minimaxClient.js";
import type { LLMClient } from "../ai/llmClient.js";
import { DEFAULT_INSTRUCTION } from "../ai/llmClient.js";
import { LRU } from "../cache.js";

const sentenceCache = new LRU<string, PredictResponse>(256);

export function invalidatePredictCache(): void { sentenceCache.clear(); }

function cacheKey(tokens: string[], contextBefore: string, contextAfter: string, domain: Domain, useAI: boolean): string {
  return `${useAI ? "ai" : "local"}|${domain}|${contextBefore}||${contextAfter}|${tokens.join(" ")}`;
}

function normalizeTokens(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return raw.map((t) => (typeof t === "string" ? t.trim() : "")).filter(Boolean);
}

function isValidDomain(d: unknown): d is Domain {
  return typeof d === "string" && ["general", "school", "business", "coding", "texting", "research"].includes(d);
}

export interface PredictHandlerDeps {
  phrases: PhraseMemory;
  corrections: CorrectionMemory;
  ai: LLMClient;
  aiConfig: MiniMaxConfig;
  /** Minimum local confidence below which AI is consulted. */
  aiConfidenceThreshold: number;
  /** Minimum token count that counts as "long" — also triggers AI. */
  aiLongSentence: number;
}

/**
 * AI confidence is "clearly higher" than local when local confidence is well
 * below the threshold. We don't promote AI to primary on small differences —
 * we want the user to see both options, with local always staying as the
 * deterministic floor.
 */
function aiClearlyBetter(localConfidence: number, threshold: number): boolean {
  return localConfidence + 0.2 < threshold;
}

export function makePredictHandler(deps: PredictHandlerDeps) {
  return async function predictHandler(req: Request, res: Response): Promise<void> {
    const t0 = performance.now();
    const body = (req.body ?? {}) as Partial<PredictRequest>;
    const tokens = normalizeTokens(body.tokens);
    const contextBefore = typeof body.contextBefore === "string" ? body.contextBefore : "";
    const contextAfter = typeof body.contextAfter === "string" ? body.contextAfter : "";
    const domain: Domain = isValidDomain(body.domain) ? body.domain : "general";
    const useAI = body.useAI === true;
    const beamWidth = Number(req.query.beam ?? process.env.BEAM_WIDTH ?? 20) || 20;

    if (tokens.length === 0) {
      res.json({
        prediction: "", alternatives: [], wordCandidates: [],
        confidence: 0, latencyMs: 0, source: "local",
        aiAvailable: deps.ai.available(),
      } satisfies PredictResponse);
      return;
    }

    const key = cacheKey(tokens, contextBefore, contextAfter, domain, useAI);
    const cached = sentenceCache.get(key);
    if (cached) {
      res.json({ ...cached, latencyMs: Math.round(performance.now() - t0) });
      return;
    }

    // 1) Try exact-pattern hit from correction memory (per domain).
    const exactKey = tokens.map((t) => t.toLowerCase()).join(" ");
    const exact = deps.corrections.exactMatch(exactKey, domain);

    // 2) Run local beam search regardless — exact match still provides best,
    //    but we want alternatives + word candidates for the UI.
    const beam = decode(tokens, {
      beamWidth, maxAlternatives: 10,
      contextBefore, contextAfter, domain,
      phrases: deps.phrases, corrections: deps.corrections,
    });

    let prediction = beam.best;
    let source: PredictResponse["source"] = "local";
    let confidence = beam.confidence;
    let alternatives = beam.alternatives;

    if (exact) {
      prediction = exact;
      source = "exact";
      confidence = Math.max(confidence, 0.99);
      // Bubble the beam best below the exact match so the user can still pick it.
      alternatives = [beam.best, ...beam.alternatives].filter((s, i, a) =>
        s && s !== exact && a.indexOf(s) === i
      );
    }

    // 3) Optional AI rerank — only when warranted, never blocks past the timeout.
    let aiSuggestions: string[] | undefined;
    const shouldAskAI =
      useAI &&
      deps.ai.available() &&
      source !== "exact" &&
      (confidence < deps.aiConfidenceThreshold || tokens.length >= deps.aiLongSentence);

    if (shouldAskAI) {
      const ai = await rerankWithTimeout(
        deps.ai,
        {
          compressedTokens: tokens,
          wordCandidates: beam.wordCandidates,
          contextBefore, contextAfter, domain,
          instruction: DEFAULT_INSTRUCTION,
        },
        deps.aiConfig.timeoutMs,
      );
      if (ai) {
        // Always surface AI output as suggestions, deduplicated against the
        // local prediction so the user sees genuinely-new completions.
        const merged: string[] = [];
        const seen = new Set<string>([prediction]);
        for (const s of [ai.prediction, ...ai.alternatives]) {
          const v = s.trim();
          if (!v || seen.has(v)) continue;
          seen.add(v); merged.push(v);
        }
        if (merged.length > 0) aiSuggestions = merged;

        // Only promote AI to the primary prediction when local was clearly
        // weak. Otherwise keep both visible (local primary + ai suggestions).
        if (aiClearlyBetter(confidence, deps.aiConfidenceThreshold)) {
          prediction = ai.prediction;
          source = "ai";
          confidence = Math.max(confidence, 0.9);
          if (ai.alternatives.length) alternatives = ai.alternatives;
        }
      }
    }

    const resp: PredictResponse = {
      prediction,
      alternatives,
      wordCandidates: beam.wordCandidates,
      confidence,
      latencyMs: Math.round(performance.now() - t0),
      source,
      aiAvailable: deps.ai.available(),
      ...(aiSuggestions ? { aiSuggestions } : {}),
    };
    sentenceCache.set(key, resp);
    res.json(resp);
  };
}
