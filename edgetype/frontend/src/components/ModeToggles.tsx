import React from "react";

export type Mode = "local" | "ai";

interface Props {
  mode: Mode;
  setMode: (m: Mode) => void;
  correctionMode: boolean;
  setCorrectionMode: (b: boolean) => void;
}

export function ModeToggles({ mode, setMode, correctionMode, setCorrectionMode }: Props) {
  return (
    <div className="toggles">
      <div className="toggle-group" role="radiogroup" aria-label="Prediction source">
        <button
          className={mode === "local" ? "toggle active" : "toggle"}
          onClick={() => setMode("local")}
          role="radio"
          aria-checked={mode === "local"}
        >
          Local only
        </button>
        <button
          className={mode === "ai" ? "toggle active" : "toggle"}
          onClick={() => setMode("ai")}
          role="radio"
          aria-checked={mode === "ai"}
        >
          Send to AI
        </button>
      </div>
      <label className="checkbox">
        <input
          type="checkbox"
          checked={correctionMode}
          onChange={(e) => setCorrectionMode(e.target.checked)}
        />
        Correction mode
      </label>
    </div>
  );
}
