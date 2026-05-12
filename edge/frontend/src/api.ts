import type {
  PredictRequest, PredictResponse, LearnRequest, LearnResponse,
} from "../../shared/types.js";

export async function predict(req: PredictRequest, signal?: AbortSignal): Promise<PredictResponse> {
  const resp = await fetch("/api/predict", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(req),
    signal,
  });
  if (!resp.ok) throw new Error(`predict failed: ${resp.status}`);
  return (await resp.json()) as PredictResponse;
}

export async function learn(req: LearnRequest): Promise<LearnResponse> {
  const resp = await fetch("/api/learn", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(req),
  });
  if (!resp.ok) throw new Error(`learn failed: ${resp.status}`);
  return (await resp.json()) as LearnResponse;
}

export async function health(): Promise<{ ok: boolean; aiAvailable: boolean; aiModel: string }> {
  const resp = await fetch("/api/health");
  return (await resp.json()) as { ok: boolean; aiAvailable: boolean; aiModel: string };
}
