import React from "react";

interface Props {
  suggestions: string[];
  /** Called when the user clicks a suggestion — teach it as the correction. */
  onTeach: (sentence: string) => void;
}

export function AISuggestionsPanel({ suggestions, onTeach }: Props) {
  if (suggestions.length === 0) return null;
  return (
    <section className="card">
      <label className="label">AI completions (click to teach Edge)</label>
      <ul className="alternatives">
        {suggestions.map((s, i) => (
          <li key={s + i}>
            <button
              className="alt-button"
              onClick={() => onTeach(s)}
              title="Click to teach Edge this completion"
            >
              {s}
            </button>
          </li>
        ))}
      </ul>
    </section>
  );
}
