import React from "react";
import type { WordCandidate } from "../../../shared/types.js";

interface Props {
  wc: WordCandidate;
  current: string;
  onPick: (word: string) => void;
}

export function WordChip({ wc, current, onPick }: Props) {
  return (
    <section className="card">
      <div className="chip-head">
        <span className="label">Candidates for “{wc.token}”</span>
        <span className="muted small">{Math.round(wc.confidence * 100)}% confidence</span>
      </div>
      <div className="candidate-list">
        {wc.candidates.map((c) => (
          <button
            key={c}
            className={c === current ? "candidate current" : "candidate"}
            onClick={() => onPick(c)}
          >
            {c}
          </button>
        ))}
      </div>
    </section>
  );
}
