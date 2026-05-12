import type { Request, Response } from "express";
import type { Domain, LearnRequest, LearnResponse } from "../../../shared/types.js";
import type { CorrectionMemory } from "../decoder/correctionMemory.js";
import { invalidatePredictCache } from "./predict.js";

function isValidDomain(d: unknown): d is Domain {
  return typeof d === "string" && ["general", "school", "business", "coding", "texting", "research"].includes(d);
}

export function makeLearnHandler(corrections: CorrectionMemory) {
  return function learnHandler(req: Request, res: Response): void {
    const body = (req.body ?? {}) as Partial<LearnRequest>;
    const compressed = typeof body.compressed === "string" ? body.compressed : "";
    const corrected = typeof body.corrected === "string" ? body.corrected : "";
    const domain: Domain = isValidDomain(body.domain) ? body.domain : "general";

    if (!compressed.trim() || !corrected.trim()) {
      res.status(400).json({ error: "compressed and corrected are required" });
      return;
    }
    try {
      corrections.record(compressed, corrected, domain);
      invalidatePredictCache();
      const out: LearnResponse = { ok: true };
      res.json(out);
    } catch (err) {
      res.status(400).json({ error: err instanceof Error ? err.message : "invalid correction" });
    }
  };
}
