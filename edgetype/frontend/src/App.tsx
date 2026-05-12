import React, { useEffect, useMemo, useRef, useState } from "react";
import type { PredictResponse, WordCandidates as WC } from "../../shared/types.js";
import { predict, learn } from "./api.js";
import { ModeToggles, type Mode } from "./components/ModeToggles.js";
import { LatencyBadge } from "./components/LatencyBadge.js";
import { CompressedInput } from "./components/CompressedInput.js";
import { Prediction } from "./components/Prediction.js";
import { WordCandidates } from "./components/WordCandidates.js";
import { CandidatePanel } from "./components/CandidatePanel.js";
import { KeyboardUI } from "./components/KeyboardUI.js";

function tokensOf(s: string): string[] {
  return s.trim().split(/\s+/).filter(Boolean);
}

export function App() {
  const [compressed, setCompressed] = useState("te qk bn fx");
  const [contextBefore, setContextBefore] = useState("");
  const [mode, setMode] = useState<Mode>("local");
  const [correctionMode, setCorrectionMode] = useState(false);

  const [prediction, setPrediction] = useState<string>("");
  const [alternatives, setAlternatives] = useState<string[]>([]);
  const [wordCandidates, setWordCandidates] = useState<WC[]>([]);
  const [latencyMs, setLatencyMs] = useState<number | null>(null);
  const [source, setSource] = useState<PredictResponse["source"] | null>(null);
  const [mismatched, setMismatched] = useState<Set<number>>(new Set());
  const [activeIndex, setActiveIndex] = useState<number | null>(null);

  // Edited words: when user picks a different candidate, we store it here so
  // it survives further refetches until they hit Save Correction.
  const [overrides, setOverrides] = useState<Record<number, string>>({});

  const abortRef = useRef<AbortController | null>(null);

  const tokens = useMemo(() => tokensOf(compressed), [compressed]);

  useEffect(() => {
    abortRef.current?.abort();
    if (tokens.length === 0) {
      setPrediction("");
      setAlternatives([]);
      setWordCandidates([]);
      setLatencyMs(null);
      setSource(null);
      setMismatched(new Set());
      return;
    }
    const ctrl = new AbortController();
    abortRef.current = ctrl;
    const handle = setTimeout(async () => {
      try {
        const result = await predict(
          { tokens, contextBefore, useAI: mode === "ai" },
          ctrl.signal
        );
        setPrediction(result.prediction);
        setAlternatives(result.alternatives);
        setWordCandidates(result.wordCandidates);
        setLatencyMs(result.latencyMs);
        setSource(result.source);
        setMismatched(new Set(result.mismatchedWords ?? []));
        setOverrides({}); // reset overrides when the underlying tokens/context/mode change
        setActiveIndex(null);
      } catch (err) {
        if ((err as { name?: string })?.name !== "AbortError") {
          // eslint-disable-next-line no-console
          console.error(err);
        }
      }
    }, 80); // debounce typing
    return () => {
      clearTimeout(handle);
      ctrl.abort();
    };
  }, [tokens.join(" "), contextBefore, mode]);

  const displayedWords = useMemo(() => {
    const base = prediction.split(/\s+/).filter(Boolean);
    return base.map((w, i) => overrides[i] ?? w);
  }, [prediction, overrides]);

  function pickWord(index: number, word: string) {
    setOverrides((prev) => ({ ...prev, [index]: word }));
    setActiveIndex(null);
  }

  function promoteAlternative(alt: string) {
    const words = alt.split(/\s+/).filter(Boolean);
    const next: Record<number, string> = {};
    for (let i = 0; i < words.length; i++) next[i] = words[i]!;
    setOverrides(next);
    setActiveIndex(null);
  }

  async function saveCorrection() {
    const corrected = displayedWords.join(" ").trim();
    if (!corrected) return;
    if (corrected.split(/\s+/).length !== tokens.length) {
      alert("Correction must have the same number of words as compressed tokens.");
      return;
    }
    try {
      await learn({ compressed: tokens.join(" "), corrected });
      // Re-predict so the new exactMatch and boosts are reflected.
      const result = await predict({ tokens, contextBefore, useAI: mode === "ai" });
      setPrediction(result.prediction);
      setAlternatives(result.alternatives);
      setWordCandidates(result.wordCandidates);
      setLatencyMs(result.latencyMs);
      setSource(result.source);
      setMismatched(new Set(result.mismatchedWords ?? []));
      setOverrides({});
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error(err);
      alert("Failed to save correction. Is the backend running?");
    }
  }

  return (
    <div className="page">
      <header className="header">
        <div>
          <h1>EdgeType</h1>
          <p className="muted">Type only the first and last letter of each word — let the system fill in the rest.</p>
        </div>
        <div className="header-right">
          <ModeToggles
            mode={mode}
            setMode={setMode}
            correctionMode={correctionMode}
            setCorrectionMode={setCorrectionMode}
          />
          <LatencyBadge latencyMs={latencyMs} source={source} />
        </div>
      </header>

      <CompressedInput
        value={compressed}
        onChange={setCompressed}
        contextBefore={contextBefore}
        setContextBefore={setContextBefore}
      />

      <Prediction
        words={displayedWords}
        mismatched={mismatched}
        onPickWord={(i) => setActiveIndex(i === activeIndex ? null : i)}
        activeIndex={activeIndex}
      />

      {activeIndex !== null && wordCandidates[activeIndex] && (
        <WordCandidates
          index={activeIndex}
          token={wordCandidates[activeIndex]!.token}
          candidates={wordCandidates[activeIndex]!.candidates}
          current={displayedWords[activeIndex] ?? ""}
          onPick={(w) => pickWord(activeIndex, w)}
          onClose={() => setActiveIndex(null)}
        />
      )}

      {correctionMode && (
        <div className="card correction-bar">
          <button className="primary" onClick={saveCorrection}>
            Save correction
          </button>
          <span className="muted">
            Click a word above to swap it for an alternative, then save to teach EdgeType.
          </span>
        </div>
      )}

      <CandidatePanel alternatives={alternatives} onPromote={promoteAlternative} />

      <KeyboardUI
        onAppend={(ch) => setCompressed((s) => s + ch)}
        onBackspace={() => setCompressed((s) => s.slice(0, -1))}
        onSpace={() => setCompressed((s) => s + " ")}
        onClear={() => setCompressed("")}
      />

      <footer className="footer">
        <p className="muted">
          Examples: <code>te qk bn fx</code>, <code>we ae gg to te pe</code>, <code>is ws a gd dy</code>.
        </p>
      </footer>
    </div>
  );
}
