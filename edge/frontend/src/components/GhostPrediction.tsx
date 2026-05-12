import React from "react";
import type { WordCandidate } from "../../../shared/types.js";

interface Props {
  words: string[];
  wordCandidates: WordCandidate[];
  selected: number | null;
  onSelect: (i: number) => void;
  willCycleIndex: number | null;
}

function confidenceClass(c: number): string {
  if (c >= 0.85) return "conf-high";
  if (c >= 0.65) return "conf-mid";
  return "conf-low";
}

export function GhostPrediction({ words, wordCandidates, selected, onSelect, willCycleIndex }: Props) {
  if (words.length === 0) {
    return (
      <section className="card prediction empty">
        <p className="muted">Start typing compressed tokens. Edge predicts as you type — backslash to correct.</p>
      </section>
    );
  }
  return (
    <section className="card prediction">
      <label className="label">Predicted sentence (ghost text)</label>
      <div className="ghost-row">
        {words.map((w, i) => {
          const conf = wordCandidates[i]?.confidence ?? 1;
          const isSel = selected === i;
          const willCycle = willCycleIndex === i;
          return (
            <button
              key={i}
              type="button"
              className={[
                "ghost-word",
                confidenceClass(conf),
                isSel ? "selected" : "",
                willCycle ? "will-cycle" : "",
              ].filter(Boolean).join(" ")}
              onClick={() => onSelect(i)}
              title={`token "${wordCandidates[i]?.token ?? ""}" — ${Math.round(conf * 100)}% confidence`}
            >
              {w}
            </button>
          );
        })}
      </div>
    </section>
  );
}
