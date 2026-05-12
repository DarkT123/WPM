import express from "express";
import cors from "cors";
import { join } from "node:path";
import { PhraseMemory } from "./decoder/phraseMemory.js";
import { CorrectionMemory } from "./decoder/correctionMemory.js";
import { makePredictHandler } from "./routes/predict.js";
import { makeLearnHandler } from "./routes/learn.js";
import { MiniMaxClient, miniMaxConfigFromEnv } from "./ai/minimaxClient.js";

const PORT = Number(process.env.PORT ?? 3002);

const phrases = new PhraseMemory();
const corrections = new CorrectionMemory(
  join(process.cwd(), "data", "corrections.json"),
  phrases,
);
const aiConfig = miniMaxConfigFromEnv();
const ai = new MiniMaxClient(aiConfig);

const app = express();
app.use(cors());
app.use(express.json({ limit: "1mb" }));

app.get("/api/health", (_req, res) => {
  res.json({
    ok: true,
    aiAvailable: ai.available(),
    aiModel: aiConfig.model,
    aiTimeoutMs: aiConfig.timeoutMs,
  });
});

app.post("/api/predict", makePredictHandler({
  phrases, corrections, ai, aiConfig,
  aiConfidenceThreshold: Number(process.env.AI_CONFIDENCE_THRESHOLD ?? "0.6") || 0.6,
  aiLongSentence: Number(process.env.AI_LONG_SENTENCE ?? "8") || 8,
}));
app.post("/api/learn", makeLearnHandler(corrections));

app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`[edge] backend listening on http://localhost:${PORT}  (AI: ${ai.available() ? "configured" : "disabled"})`);
});
