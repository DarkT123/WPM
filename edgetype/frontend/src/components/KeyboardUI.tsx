import React from "react";

interface Props {
  onAppend: (s: string) => void;
  onBackspace: () => void;
  onSpace: () => void;
  onClear: () => void;
}

const ROWS = ["qwertyuiop", "asdfghjkl", "zxcvbnm"];

export function KeyboardUI({ onAppend, onBackspace, onSpace, onClear }: Props) {
  return (
    <section className="card keyboard">
      <label className="label">On-screen keyboard (tap-test mode)</label>
      <div className="kb-rows">
        {ROWS.map((row) => (
          <div key={row} className="kb-row">
            {row.split("").map((ch) => (
              <button key={ch} className="kb-key" onClick={() => onAppend(ch)}>
                {ch}
              </button>
            ))}
          </div>
        ))}
        <div className="kb-row">
          <button className="kb-key kb-wide" onClick={onSpace}>space</button>
          <button className="kb-key kb-wide" onClick={onBackspace}>⌫</button>
          <button className="kb-key kb-wide" onClick={onClear}>clear</button>
        </div>
      </div>
    </section>
  );
}
