import React from "react";
import type { PredictionSource } from "../../../shared/types.js";

interface Props {
  latencyMs: number | null;
  source: PredictionSource | null;
}

export function LatencyBadge({ latencyMs, source }: Props) {
  return (
    <div className="latency">
      <span className={source === "ai" ? "src-pill ai" : "src-pill local"}>
        {source ?? "—"}
      </span>
      <span className="latency-num">{latencyMs == null ? "—" : `${latencyMs} ms`}</span>
    </div>
  );
}
