import React from "react";

interface Props {
  willCycleWord?: string;
  memoryStatus?: string;
}

export function KeyHintBar({ willCycleWord, memoryStatus }: Props) {
  return (
    <section className="card hints">
      <div className="hint-row">
        <kbd>\</kbd>
        <span className="muted">cycle current word forward</span>
        <kbd>⇧ \</kbd>
        <span className="muted">cycle backward</span>
        <kbd>⌥ \</kbd>
        <span className="muted">cycle whole sentence</span>
        <kbd>⌘ \</kbd>
        <span className="muted">accept &amp; teach</span>
      </div>
      <div className="hint-row">
        {willCycleWord ? (
          <span className="hint-target">
            next <kbd>\</kbd> will cycle <strong>“{willCycleWord}”</strong>
          </span>
        ) : (
          <span className="muted">no word selected — type to start</span>
        )}
        {memoryStatus && <span className="muted memory">· {memoryStatus}</span>}
      </div>
    </section>
  );
}
