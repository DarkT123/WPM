import React from "react";

interface Props {
  alternatives: string[];
  onPromote: (sentence: string) => void;
}

export function AlternativesPanel({ alternatives, onPromote }: Props) {
  if (alternatives.length === 0) return null;
  return (
    <section className="card">
      <label className="label">Alternative sentences (Alt+\ to cycle)</label>
      <ul className="alternatives">
        {alternatives.map((alt, i) => (
          <li key={alt + i}>
            <button className="alt-button" onClick={() => onPromote(alt)}>{alt}</button>
          </li>
        ))}
      </ul>
    </section>
  );
}
