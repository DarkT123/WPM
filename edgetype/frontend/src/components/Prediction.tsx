import React from "react";

interface Props {
  words: string[];
  mismatched: Set<number>;
  onPickWord: (index: number) => void;
  activeIndex: number | null;
}

export function Prediction({ words, mismatched, onPickWord, activeIndex }: Props) {
  if (words.length === 0) {
    return (
      <section className="card prediction empty">
        <p className="muted">Start typing compressed tokens to see a prediction.</p>
      </section>
    );
  }
  return (
    <section className="card prediction">
      <label className="label">Predicted sentence</label>
      <div className="sentence">
        {words.map((w, i) => (
          <button
            key={i}
            type="button"
            className={[
              "word",
              mismatched.has(i) ? "mismatch" : "",
              activeIndex === i ? "active" : "",
            ].filter(Boolean).join(" ")}
            onClick={() => onPickWord(i)}
          >
            {w}
          </button>
        ))}
      </div>
      {mismatched.size > 0 && (
        <p className="hint">
          ⚠ Words highlighted in amber didn't match their token's first/last letter — the AI may have corrected a typo.
        </p>
      )}
    </section>
  );
}
