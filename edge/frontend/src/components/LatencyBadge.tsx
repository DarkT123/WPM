import React from "react";
import type { PredictionSource } from "../../../shared/types.js";

interface Props {
  latencyMs: number | null;
  source: PredictionSource | null;
  confidence: number | null;
}

export function LatencyBadge({ latencyMs, source, confidence }: Props) {
  return (
    <div className="latency">
      <span className={`src-pill ${source ?? "local"}`}>{source ?? "—"}</span>
      <span className="latency-num">{latencyMs == null ? "—" : `${latencyMs} ms`}</span>
      <span className="conf-num" title="Sentence confidence">
        {confidence == null ? "" : `${Math.round(confidence * 100)}%`}
      </span>
    </div>
  );
}
