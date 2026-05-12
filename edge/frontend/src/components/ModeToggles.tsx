import React from "react";

interface Props {
  useAI: boolean;
  setUseAI: (v: boolean) => void;
  aiAvailable: boolean;
}

export function ModeToggles({ useAI, setUseAI, aiAvailable }: Props) {
  return (
    <div className="toggles">
      <div className="toggle-group" role="radiogroup" aria-label="Prediction source">
        <button
          className={!useAI ? "toggle active" : "toggle"}
          onClick={() => setUseAI(false)}
          role="radio"
          aria-checked={!useAI}
        >
          Local only
        </button>
        <button
          className={useAI ? "toggle active" : "toggle"}
          onClick={() => setUseAI(true)}
          role="radio"
          aria-checked={useAI}
          disabled={!aiAvailable}
          title={aiAvailable ? "Use MiniMax to rerank low-confidence predictions" : "Configure MINIMAX_API_BASE_URL to enable"}
        >
          MiniMax AI
        </button>
      </div>
    </div>
  );
}
