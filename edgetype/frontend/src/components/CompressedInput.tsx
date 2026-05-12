import React from "react";

interface Props {
  value: string;
  onChange: (v: string) => void;
  contextBefore: string;
  setContextBefore: (v: string) => void;
}

export function CompressedInput({ value, onChange, contextBefore, setContextBefore }: Props) {
  const tokens = value.trim().split(/\s+/).filter(Boolean);

  return (
    <section className="card">
      <label className="label">Context (optional)</label>
      <input
        className="context"
        value={contextBefore}
        onChange={(e) => setContextBefore(e.target.value)}
        placeholder="Earlier sentence — helps the bigram score"
      />

      <label className="label">Compressed input</label>
      <textarea
        className="compressed"
        rows={2}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder="e.g. te qk bn fx"
        spellCheck={false}
        autoFocus
      />

      <div className="chips">
        {tokens.map((t, i) => (
          <span key={`${t}-${i}`} className="chip" title={`token ${i + 1}`}>
            {t}
          </span>
        ))}
        {tokens.length === 0 && <span className="chip muted">no tokens yet</span>}
      </div>
    </section>
  );
}
