import React from "react";

interface Props {
  index: number;
  token: string;
  candidates: string[];
  current: string;
  onPick: (word: string) => void;
  onClose: () => void;
}

export function WordCandidates({ index, token, candidates, current, onPick, onClose }: Props) {
  return (
    <div className="candidates-popup">
      <div className="candidates-head">
        <strong>Word {index + 1}</strong>
        <span className="muted"> · token “{token}”</span>
        <button className="link" onClick={onClose}>close</button>
      </div>
      <div className="candidate-list">
        {candidates.map((c) => (
          <button
            key={c}
            className={c === current ? "candidate current" : "candidate"}
            onClick={() => onPick(c)}
          >
            {c}
          </button>
        ))}
      </div>
    </div>
  );
}
