import React from "react";

interface Props {
  alternatives: string[];
  onPromote: (sentence: string) => void;
}

export function CandidatePanel({ alternatives, onPromote }: Props) {
  if (alternatives.length === 0) return null;
  return (
    <section className="card">
      <label className="label">Alternative reconstructions</label>
      <ul className="alternatives">
        {alternatives.map((alt) => (
          <li key={alt}>
            <button className="alt-button" onClick={() => onPromote(alt)}>
              {alt}
            </button>
          </li>
        ))}
      </ul>
    </section>
  );
}
