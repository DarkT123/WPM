# Edge — handoff prompt (continue in a fresh Claude Code session)

Paste everything below into the new terminal. It's self-contained — the new session won't have prior context.

---

I'm continuing a project at `/Users/andyzhao/Translating keyboard/`. Read `edge/README.md` and `edge-dashboard/README.md` first; full architecture is there. Then read this whole brief before changing anything.

## What I want changed

Replace the current **first/last-letter** encoding with a **prefix-based** encoding.

- The user types the **first letter or two** of each word.
- The system completes the sentence using context, n-grams, phrase memory, and (optionally) MiniMax.
- It also returns **AI suggestions** alongside the local pick, even when AI isn't the primary source.
- **Every correction is stored and used** to improve future predictions — both as an exact-pattern hit and as boosts that generalize.

New canonical example:

```
input:   i wa to ma a pr ma re ap
output:  i want to make a prediction market research app
```

`wa` → prefix `wa` → "want" / "was" / "wait" / "walk" / "war" / "wave"… ranked by frequency + context.

## What to keep

- The decoder pipeline shape: `tokenParser → candidateGenerator → beamSearch (uses scorer + phraseMemory + correctionMemory + confidence)`. Beam search itself does not change.
- The MiniMax adapter in `edge/backend/src/ai/minimaxClient.ts`, 200ms timeout, OpenAI-compatible body.
- Correction persistence at `edge/backend/data/corrections.json` via `correctionMemory.ts`.
- Backslash correction cycling shared via `edge/shared/cycle.ts`.
- 9 backend test suites should still pass after the changes (`cd edge && npm test`).

## Concrete file changes

1. **`edge/backend/src/decoder/tokenParser.ts`**
   - Drop `kind: "edge"` (first+last) and `kind: "lenEdge"` (t3e). Remove related code paths.
   - Add `kind: "prefix"` for 1- or 2-letter tokens. Field: `prefix: string`.
   - Keep `kind: "literal"` (3+ letters, no digit) and `kind: "punct"`.
   - Update `matchesToken` so a candidate must `startsWith(prefix)` case-insensitively.

2. **`edge/backend/src/decoder/candidateGenerator.ts`**
   - Replace `byEdge` and `byLenEdge` indexes with a prefix index: `Map<string, WordEntry[]>` keyed by 1-letter and 2-letter prefixes of every dictionary word, sorted by descending frequency.
   - Top-50 cap per token. Unknown-prefix passthrough so the sentence still reconstructs.

3. **`edge/backend/src/decoder/scorer.ts`**
   - No structural change. Keep log-freq + bigram + trigram + right-context + obscurity penalty.
   - The `correctionMemory.wordBoost(token, word, domain)` call already keys by token string, which after the parser change becomes the prefix. That gives you prefix → word boosts for free.
   - **Add** a `prefixSuccessorBoost(prevWord, prefix, word, domain)` lookup. This is the strongest signal for a prefix system: confirmed `(prev=is, prefix=wa) → was` should dominate `(prev=he, prefix=wa) → walked`. Plumb it through `stepScore`.

4. **`edge/backend/src/decoder/correctionMemory.ts`**
   - Add storage for `prefixSuccessors`: `Record<Domain, Map<"prev|prefix|word", number>>`.
   - On `record(...)`, for each i increment `prefixSuccessors[domain]["<prev>|<prefix>|<word>"]`.
   - Persist alongside existing fields. Bump file format version so old `corrections.json` doesn't break decoding (or wipe on schema mismatch — call out either choice in the PR).

5. **`edge/backend/src/routes/predict.ts`**
   - Always run local beam search and return its result with `source: "local"` (or `"exact"` when there's a pattern hit).
   - When `useAI: true` AND `ai.available()`, fire MiniMax in parallel (subject to the existing confidence/length gates) and include its output in a **new** response field: `aiSuggestions: string[]`. Do **not** swap the primary `prediction` field for the AI result unless the AI's confidence is clearly higher — let the user see both.
   - Cache aggressively; invalidate on `/api/learn`.
   - Update `edge/shared/types.ts` `PredictResponse` to include `aiSuggestions?: string[]`.

6. **`edge/backend/tests/`** — update and extend:
   - `tokenParser.test.ts`: replace edge/lenEdge tests with prefix tests. `parseToken("t")` → `{ kind: "prefix", prefix: "t" }`; `parseToken("th")` → `{ kind: "prefix", prefix: "th" }`; `parseToken("the")` → `{ kind: "literal" }`. Keep punctuation tests.
   - `candidateGenerator.test.ts`: every candidate must `startsWith(prefix)`; 50-cap; case-insensitivity; unknown-prefix passthrough.
   - `beamSearch.test.ts`: replace the canonical example. New canonical: tokens `["i", "wa", "to", "ma", "a", "pr", "ma", "re", "ap"]` → `"i want to make a prediction market research app"`. Also add a 1-letter-prefix variant and confirm context still picks the right word.
   - New file `prefixSuccessor.test.ts`: after `record("i wa to", "i was to", "general")`, a fresh predict for `["i", "wa", "to"]` picks `was` over `want` because the prefix-successor table now has `(i|wa) → was`. (Pick whichever pair makes the test sharp.)
   - Keep `correctionMemory.test.ts`, `phraseMemory.test.ts`, `minimax.test.ts`, `confidence.test.ts`, `correctionCycle.test.ts`, `benchmark.test.ts`. Adjust their input strings to the new format where the old ones were edge tokens.
   - `benchmark.test.ts`: keep median < 30ms for 9 tokens, < 15ms for 5 tokens.

7. **`edge/frontend/src/`**
   - `App.tsx`: change `compressed` default to `"i wa to ma a pr ma re ap"`. No wire-format changes.
   - `components/CompressedInput.tsx`: update placeholder text.
   - Add `components/AISuggestionsPanel.tsx` that renders `result.aiSuggestions ?? []` between the prediction and the existing alternatives. Each row click should call `learn(...)` with the suggestion as the correction.
   - `components/GhostPrediction.tsx`: per-word tooltip already shows `wc.token` (now the prefix); no change.

8. **`edge-dashboard/EdgeDashboard/`**
   - `API/Models.swift`: add `let aiSuggestions: [String]?` to `PredictResponse`.
   - `Views/LivePredictView.swift`: add an "AI completions" `GroupBox` between Prediction and Alternative sentences, rendering `model.aiSuggestions ?? []`. Click-to-teach uses the existing `model.teach(corrected:)` path.
   - `README.md`: update example.

9. **READMEs**
   - `edge/README.md` and `edge-dashboard/README.md`: rewrite the "Compressed input grammar" section. New table: `t` = 1-letter prefix; `th` = 2-letter prefix; `the` = literal; `a` / `i` = literal one-letter words; `./,` = punctuation.
   - Update the canonical example everywhere ("the quick brown fox" is still nice for the README — use both).
   - Update the "Why this is hard" section: prefix encoding is less ambiguous on average than first+last, but one-letter prefixes still hit dozens of options, so cross-word context and corrections are the load-bearing pieces.

## Acceptance criteria

- `cd edge && npm test` → 100% pass.
- `cd edge && npm run bench` → median < 30ms for 9-token input.
- `curl -s http://localhost:3002/api/predict -H 'content-type: application/json' -d '{"tokens":["i","wa","to","ma","a","pr","ma","re","ap"],"contextBefore":"","contextAfter":"","domain":"general","useAI":false}'` → `prediction: "i want to make a prediction market research app"`.
- After `POST /api/learn` with that input + corrected output, a repeat predict in the same domain returns `source: "exact"`.
- `cd edge-dashboard && xcodebuild -project EdgeDashboard.xcodeproj -scheme EdgeDashboard -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/edge-build CODE_SIGNING_ALLOWED=NO build` → `BUILD SUCCEEDED`. Clean `/tmp/edge-build` after.

## Approach

Don't rebuild from scratch. Walk the dependency graph: parser → candidate generator → scorer addition (prefixSuccessor) → correctionMemory storage → routes (aiSuggestions) → shared types → tests → frontend → dashboard. The beam search and confidence modules don't need to change. The dictionary likely needs no changes — `want`, `make`, `prediction`, `market`, `research`, `app` are already in there. If a needed word is missing, add it with a sensible frequency rather than scaling the whole list.

## Security

- Do **not** log, echo, hardcode, or commit any MiniMax API key. The user previously had one leaked in chat and has rotated. Read the key only via `process.env.MINIMAX_API_KEY` in `edge/backend/src/ai/minimaxClient.ts`. Never write it to files outside `.env` (which is `.gitignored`).
- Do **not** add a `Bash:*` blanket permission. If you hit permission prompts, ask before broadening.
