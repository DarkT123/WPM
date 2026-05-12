import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type {
  Domain, PredictResponse, WordCandidate,
} from "../../shared/types.js";
import { applyBackslash, defaultSelectedIndex, mostUncertainWordIndex } from "../../shared/cycle.js";
import { predict, learn, health } from "./api.js";
import { ModeToggles } from "./components/ModeToggles.js";
import { LatencyBadge } from "./components/LatencyBadge.js";
import { DomainSelector } from "./components/DomainSelector.js";
import { CompressedInput } from "./components/CompressedInput.js";
import { GhostPrediction } from "./components/GhostPrediction.js";
import { WordChip } from "./components/WordChip.js";
import { AlternativesPanel } from "./components/AlternativesPanel.js";
import { AISuggestionsPanel } from "./components/AISuggestionsPanel.js";
import { KeyHintBar } from "./components/KeyHintBar.js";

function tokensOf(s: string): string[] {
  return s.trim().split(/\s+/).filter(Boolean);
}

function splitWords(sentence: string): string[] {
  return sentence.trim().split(/\s+/).filter(Boolean);
}

export function App() {
  const [compressed, setCompressed] = useState("i wa to ma a pr ma re ap");
  const [contextBefore, setContextBefore] = useState("");
  const [contextAfter, setContextAfter] = useState("");
  const [useAI, setUseAI] = useState(false);
  const [aiAvailable, setAiAvailable] = useState(false);
  const [aiModel, setAiModel] = useState<string>("");
  const [domain, setDomain] = useState<Domain>("general");

  // Server-derived prediction state.
  const [prediction, setPrediction] = useState<string>("");
  const [alternatives, setAlternatives] = useState<string[]>([]);
  const [aiSuggestions, setAiSuggestions] = useState<string[]>([]);
  const [wordCandidates, setWordCandidates] = useState<WordCandidate[]>([]);
  const [confidence, setConfidence] = useState<number | null>(null);
  const [latencyMs, setLatencyMs] = useState<number | null>(null);
  const [source, setSource] = useState<PredictResponse["source"] | null>(null);

  // Editable view state. `words` is what the user actually sees and what gets
  // taught on accept. It's seeded from prediction but corrections write into it.
  const [words, setWords] = useState<string[]>([]);
  const [selected, setSelected] = useState<number | null>(null);
  const [memoryStatus, setMemoryStatus] = useState<string>("");

  const abortRef = useRef<AbortController | null>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  const tokens = useMemo(() => tokensOf(compressed), [compressed]);

  // Initial health check so we know whether the MiniMax toggle is meaningful.
  useEffect(() => {
    health().then((h) => { setAiAvailable(h.aiAvailable); setAiModel(h.aiModel); }).catch(() => {});
  }, []);

  // Debounced predict whenever inputs change.
  useEffect(() => {
    abortRef.current?.abort();
    if (tokens.length === 0) {
      setPrediction(""); setAlternatives([]); setAiSuggestions([]);
      setWordCandidates([]); setWords([]); setSelected(null);
      setConfidence(null); setLatencyMs(null); setSource(null);
      return;
    }
    const ctrl = new AbortController();
    abortRef.current = ctrl;
    const handle = setTimeout(async () => {
      try {
        const result = await predict(
          { tokens, contextBefore, contextAfter, domain, useAI },
          ctrl.signal,
        );
        setPrediction(result.prediction);
        setAlternatives(result.alternatives);
        setAiSuggestions(result.aiSuggestions ?? []);
        setWordCandidates(result.wordCandidates);
        setConfidence(result.confidence);
        setLatencyMs(result.latencyMs);
        setSource(result.source);
        const nextWords = splitWords(result.prediction);
        setWords(nextWords);
        // Default selection: most uncertain word, for instant backslash targeting.
        setSelected(defaultSelectedIndex({ wordCandidates: result.wordCandidates }));
      } catch (err) {
        if ((err as { name?: string })?.name !== "AbortError") {
          // eslint-disable-next-line no-console
          console.error(err);
        }
      }
    }, 60); // tight debounce — keep up with fast typing
    return () => { clearTimeout(handle); ctrl.abort(); };
  }, [tokens.join(" "), contextBefore, contextAfter, domain, useAI]);

  const willCycleIndex = useMemo(() => {
    if (selected != null) return selected;
    return mostUncertainWordIndex(wordCandidates);
  }, [selected, wordCandidates]);

  const willCycleWord = willCycleIndex >= 0 ? words[willCycleIndex] : undefined;

  // Backslash key handler — captures at document level so it doesn't insert
  // into the textarea.
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if (e.key !== "\\") return;
      e.preventDefault();
      e.stopPropagation();
      const result = applyBackslash(
        {
          words, selected, wordCandidates, alternatives,
          aiSuggestions, originalPrediction: prediction,
        },
        { shift: e.shiftKey, alt: e.altKey, meta: e.metaKey || e.ctrlKey },
      );
      if (result.kind === "noop") return;
      if (result.kind === "word") {
        setWords(result.words);
        setSelected(result.index);
        return;
      }
      if (result.kind === "sentence") {
        setWords(result.words);
        setSelected(null);
        return;
      }
      if (result.kind === "accept") {
        void saveCorrection(result.sentence);
      }
    }
    // Capture: register before the textarea sees the key.
    document.addEventListener("keydown", onKeyDown, { capture: true });
    return () => document.removeEventListener("keydown", onKeyDown, { capture: true } as any);
  }, [words, selected, wordCandidates, alternatives, aiSuggestions, prediction]);

  const saveCorrection = useCallback(async (sentence: string) => {
    const corrected = sentence.trim();
    if (!corrected) return;
    const correctedWords = splitWords(corrected);
    if (correctedWords.length !== tokens.length) {
      setMemoryStatus("⚠ correction must have the same word count as tokens");
      return;
    }
    try {
      await learn({ compressed: tokens.join(" "), corrected, domain });
      setMemoryStatus(`✓ taught: ${tokens.join(" ")} → ${corrected}`);
      // Re-predict so exact-match kicks in and confidence reflects new memory.
      const result = await predict({ tokens, contextBefore, contextAfter, domain, useAI });
      setPrediction(result.prediction);
      setAlternatives(result.alternatives);
      setAiSuggestions(result.aiSuggestions ?? []);
      setWordCandidates(result.wordCandidates);
      setConfidence(result.confidence);
      setLatencyMs(result.latencyMs);
      setSource(result.source);
      setWords(splitWords(result.prediction));
      setSelected(defaultSelectedIndex({ wordCandidates: result.wordCandidates }));
    } catch (err) {
      setMemoryStatus("⚠ failed to save correction — is the backend running?");
      // eslint-disable-next-line no-console
      console.error(err);
    }
  }, [tokens, contextBefore, contextAfter, domain, useAI]);

  function pickFromCandidates(word: string) {
    if (selected == null) return;
    setWords((prev) => {
      const next = [...prev];
      next[selected] = word;
      return next;
    });
  }

  function promoteAlternative(alt: string) {
    setWords(splitWords(alt));
    setSelected(null);
  }

  function teachSuggestion(suggestion: string) {
    void saveCorrection(suggestion);
  }

  return (
    <div className="page">
      <header className="header">
        <div>
          <h1>Edge</h1>
          <p className="muted">
            Type just the first letter or two of each word — Edge predicts the rest from context.
            Press <kbd>\</kbd> to correct.
          </p>
        </div>
        <div className="header-right">
          <DomainSelector value={domain} onChange={setDomain} />
          <ModeToggles useAI={useAI} setUseAI={setUseAI} aiAvailable={aiAvailable} />
          <LatencyBadge latencyMs={latencyMs} source={source} confidence={confidence} />
        </div>
      </header>

      <CompressedInput
        value={compressed}
        onChange={setCompressed}
        contextBefore={contextBefore}
        setContextBefore={setContextBefore}
        contextAfter={contextAfter}
        setContextAfter={setContextAfter}
        inputRef={inputRef}
      />

      <GhostPrediction
        words={words}
        wordCandidates={wordCandidates}
        selected={selected}
        onSelect={(i) => setSelected(i === selected ? null : i)}
        willCycleIndex={willCycleIndex >= 0 ? willCycleIndex : null}
      />

      <KeyHintBar willCycleWord={willCycleWord} memoryStatus={memoryStatus} />

      {selected != null && wordCandidates[selected] && (
        <WordChip
          wc={wordCandidates[selected]}
          current={words[selected] ?? wordCandidates[selected].selected}
          onPick={pickFromCandidates}
        />
      )}

      <AISuggestionsPanel suggestions={aiSuggestions} onTeach={teachSuggestion} />

      <AlternativesPanel alternatives={alternatives} onPromote={promoteAlternative} />

      <footer className="footer">
        <p className="muted">
          Examples: <code>i wa to ma a pr ma re ap</code>, <code>th qu br fo</code>.
          {aiAvailable && <> · MiniMax model: <code>{aiModel}</code></>}
        </p>
      </footer>
    </div>
  );
}
