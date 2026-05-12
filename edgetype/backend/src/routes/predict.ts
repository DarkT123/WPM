import type { Request, Response } from "express";
import type { PredictRequest, PredictResponse } from "../../../shared/types.js";
import { beamSearch } from "../prediction/beamSearch.js";
import { callAI, aiConfigFromEnv } from "../ai/client.js";
import type { CorrectionsStore } from "../learning/store.js";
import { LRU } from "../cache.js";

interface CacheEntry extends PredictResponse {}
const sentenceCache = new LRU<string, CacheEntry>(128);

export function invalidatePredictCache(): void {
  sentenceCache.clear();
}

function cacheKey(req: PredictRequest, includeAI: boolean): string {
  return `${includeAI ? "ai" : "local"}|${req.contextBefore}|${req.tokens.join(" ")}`;
}

function normalizeTokens(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((t) => (typeof t === "string" ? t.trim().toLowerCase() : ""))
    .filter(Boolean);
}

export function makePredictHandler(corrections: CorrectionsStore) {
  return async function predictHandler(req: Request, res: Response): Promise<void> {
    const t0 = performance.now();
    const body = (req.body ?? {}) as Partial<PredictRequest>;
    const tokens = normalizeTokens(body.tokens);
    const contextBefore = typeof body.contextBefore === "string" ? body.contextBefore : "";
    const useAI = body.useAI === true;
    const beamWidth = Number(req.query.beam ?? process.env.BEAM_WIDTH ?? 20) || 20;

    if (tokens.length === 0) {
      res.json({
        prediction: "",
        alternatives: [],
        wordCandidates: [],
        latencyMs: 0,
        source: "local",
      } satisfies PredictResponse);
      return;
    }

    const key = cacheKey({ tokens, contextBefore, useAI }, useAI);
    const cached = sentenceCache.get(key);
    if (cached) {
      res.json({ ...cached, latencyMs: Math.round(performance.now() - t0) });
      return;
    }

    // Local beam search runs in parallel with the optional AI call.
    const localPromise: Promise<PredictResponse> = (async () => {
      const exact = corrections.exactMatch(tokens.join(" "));
      const beam = beamSearch(tokens, {
        beamWidth,
        contextBefore,
        learnedBigrams: corrections.learnedBigrams(),
        wordBoosts: corrections.wordBoosts(),
      });
      const prediction = exact ?? beam.best;
      const alternatives = exact
        ? [beam.best, ...beam.alternatives].filter((s, i, a) => s && s !== exact && a.indexOf(s) === i)
        : beam.alternatives;
      return {
        prediction,
        alternatives,
        wordCandidates: beam.wordCandidates,
        latencyMs: 0,
        source: "local",
      } satisfies PredictResponse;
    })();

    let result: PredictResponse;
    if (useAI) {
      const localPreview = await localPromise;
      const aiResult = await callAI(tokens, localPreview.wordCandidates, contextBefore, aiConfigFromEnv());
      if (aiResult) {
        const aiAlternatives = aiResult.alternatives.length
          ? aiResult.alternatives
          : [localPreview.prediction, ...localPreview.alternatives].filter((s) => s && s !== aiResult.prediction);
        result = {
          prediction: aiResult.prediction,
          alternatives: aiAlternatives,
          wordCandidates: localPreview.wordCandidates,
          latencyMs: 0,
          source: "ai",
          mismatchedWords: aiResult.mismatchedWords.length ? aiResult.mismatchedWords : undefined,
        };
      } else {
        result = localPreview;
      }
    } else {
      result = await localPromise;
    }

    result.latencyMs = Math.round(performance.now() - t0);
    sentenceCache.set(key, result);
    res.json(result);
  };
}
