import type { Request, Response } from "express";
import type { LearnRequest, LearnResponse } from "../../../shared/types.js";
import type { CorrectionsStore } from "../learning/store.js";
import { invalidatePredictCache } from "./predict.js";

export function makeLearnHandler(corrections: CorrectionsStore) {
  return function learnHandler(req: Request, res: Response): void {
    const body = (req.body ?? {}) as Partial<LearnRequest>;
    const compressed = typeof body.compressed === "string" ? body.compressed : "";
    const corrected = typeof body.corrected === "string" ? body.corrected : "";

    if (!compressed.trim() || !corrected.trim()) {
      res.status(400).json({ error: "compressed and corrected are required" });
      return;
    }

    try {
      corrections.record(compressed, corrected);
      invalidatePredictCache();
      const out: LearnResponse = { ok: true };
      res.json(out);
    } catch (err) {
      res.status(400).json({ error: err instanceof Error ? err.message : "invalid correction" });
    }
  };
}
