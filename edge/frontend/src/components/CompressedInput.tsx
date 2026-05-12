import React from "react";

interface Props {
  value: string;
  onChange: (v: string) => void;
  contextBefore: string;
  setContextBefore: (v: string) => void;
  contextAfter: string;
  setContextAfter: (v: string) => void;
  inputRef?: React.RefObject<HTMLTextAreaElement>;
}

export function CompressedInput({
  value, onChange, contextBefore, setContextBefore, contextAfter, setContextAfter, inputRef,
}: Props) {
  const tokens = value.trim().split(/\s+/).filter(Boolean);
  return (
    <section className="card">
      <div className="ctx-row">
        <div className="ctx-cell">
          <label className="label">Context before</label>
          <input className="context" value={contextBefore} onChange={(e) => setContextBefore(e.target.value)} placeholder="optional" />
        </div>
        <div className="ctx-cell">
          <label className="label">Context after</label>
          <input className="context" value={contextAfter} onChange={(e) => setContextAfter(e.target.value)} placeholder="optional" />
        </div>
      </div>
      <label className="label">Compressed input</label>
      <textarea
        ref={inputRef}
        className="compressed"
        rows={2}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder="e.g. i wa to ma a pr ma re ap"
        spellCheck={false}
        autoFocus
      />
      <div className="chips">
        {tokens.map((t, i) => (
          <span key={`${t}-${i}`} className="chip" title={`token ${i + 1}`}>{t}</span>
        ))}
        {tokens.length === 0 && <span className="chip muted">no tokens yet</span>}
      </div>
    </section>
  );
}
