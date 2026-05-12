import express from "express";
import cors from "cors";
import { join } from "node:path";
import { CorrectionsStore } from "./learning/store.js";
import { makePredictHandler } from "./routes/predict.js";
import { makeLearnHandler } from "./routes/learn.js";

const PORT = Number(process.env.PORT ?? 3001);

const corrections = new CorrectionsStore(join(process.cwd(), "data", "corrections.json"));

const app = express();
app.use(cors());
app.use(express.json({ limit: "1mb" }));

app.get("/api/health", (_req, res) => {
  res.json({ ok: true, aiConfigured: Boolean(process.env.AI_API_BASE_URL) });
});

app.post("/api/predict", makePredictHandler(corrections));
app.post("/api/learn", makeLearnHandler(corrections));

app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`[edgetype] backend listening on http://localhost:${PORT}`);
});
