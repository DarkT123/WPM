# Edge

A context-aware predictive keyboard prototype. You type only the **first letter or two** of each word. Edge reconstructs the full sentence using a local dictionary, bigrams, trigrams, per-domain phrase memory, your own corrections, and — optionally — a self-hosted MiniMax API for the hard cases.

```
input:    i wa to ma a pr ma re ap
output:   i want to make a prediction market research app
```

A shorter example: `th qu br fo` → `the quick brown fox`.

## What makes this hard

Prefix encoding is less ambiguous on average than first+last-letter encoding, but it is far from unambiguous. `wa` alone could be **want**, **was**, **way**, **wait**, **walk**, **war**, **walked**, **wave**, **wash**, **warm**, **warn**, **water**… The only way to pick the right one is **context**:

- `i wa to` → "i want to" beats "i was to" because of the `i want` bigram *and* the strong `want to` bigram immediately after.
- `wa to ma a prediction` → looking ahead at "make a prediction" pushes `ma` to **make**, which in turn pushes `wa` to **want**.

One-letter prefixes are even more ambiguous (every `t` token has thousands of candidates), so cross-word context and learned corrections are the load-bearing pieces. Edge never decodes a word in isolation — every word is scored against its left and right neighbours, with corrections boosting `(prev → prefix → word)` tuples so a single accepted sentence reshapes future predictions for similar contexts.

## Compressed input grammar

| token   | meaning                                                          |
| ------- | ---------------------------------------------------------------- |
| `t`     | 1-letter prefix — any word starting with **t**                   |
| `th`    | 2-letter prefix — any word starting with **th**                  |
| `the`   | a literal word (3+ letters) — preserved verbatim                 |
| `a`, `i`| literal one-letter words                                         |
| `.`, `,`| literal punctuation — kept attached to the previous word         |

## Backslash correction

The correction system is keyboard-only. You never have to touch the mouse.

| key            | action                                                              |
| -------------- | ------------------------------------------------------------------- |
| `\`            | cycle the **currently selected word** forward through its candidates|
| `Shift+\`      | cycle that word backward                                            |
| `Alt+\`        | cycle the **whole sentence** through ranked alternatives            |
| `Cmd+\` / `Ctrl+\` | **accept** the displayed sentence and teach Edge to prefer it   |

If no word is explicitly selected, `\` targets the **most uncertain** word automatically. The UI shows which word the next `\` will change.

Every accepted correction is stored two ways:

- as an **exact-pattern hit** keyed on the literal compressed input (so repeat queries return `source: "exact"`), and
- as a per-`(prev word, prefix → word)` **successor boost** that generalizes — accepting `i was` once nudges every future `… wa …` after the same prev word toward `was`, even on unrelated sentences.

## AI suggestions

When `useAI` is on and MiniMax responds inside the 200ms cutoff, its top guess and alternatives are returned in a new `aiSuggestions` field alongside the local prediction. The user sees both: local stays the deterministic primary, MiniMax shows as click-to-teach options. Local is only swapped out for AI when local confidence is clearly low.

AI suggestions are also folded into the **Alt+\\** cycle after local alternatives, so the keyboard can rotate through them without touching the mouse. Cmd+\\ on a cycled AI sentence teaches it as the correction, exactly like any other accept.

## Layout

```
edge/
├── backend/                  # Express + TypeScript decoder + AI adapter
│   ├── src/
│   │   ├── decoder/{tokenParser,candidateGenerator,scorer,phraseMemory,
│   │   │             correctionMemory,confidence,beamSearch,dictionary}.ts
│   │   ├── ai/{llmClient,minimaxClient}.ts
│   │   ├── routes/{predict,learn}.ts
│   │   ├── cache.ts
│   │   └── index.ts
│   └── tests/                # Vitest suites: parser, candidates, beam,
│                             # cycling, memory, prefix-successors, MiniMax,
│                             # confidence, benchmark
├── frontend/                 # React + Vite UI
│   └── src/{App,api,styles}.tsx + components/{...,AISuggestionsPanel}
├── shared/{types,cycle}.ts   # API types + backslash cycling logic (shared with tests)
└── README.md
```

## Setup

Requirements: Node 20+, npm 10+.

```bash
cd edge
npm install
cp backend/.env.example backend/.env   # optional — only needed for MiniMax
```

## Run

```bash
npm run dev
```

- **backend** → `http://localhost:3002`
- **frontend** → `http://localhost:5174` (Vite proxies `/api/*` to the backend)

Open the frontend and try the example input `i wa to ma a pr ma re ap`. The prediction updates as you type (debounced ~60ms). Confidence is colour-coded — high (green), medium (white), low (amber-dotted). Press `\` to start correcting.

## Configuring MiniMax

Set in `backend/.env`:

```
MINIMAX_API_BASE_URL=https://api.minimax.chat
MINIMAX_API_KEY=your-key
MINIMAX_MODEL=abab6.5-chat
MINIMAX_TIMEOUT_MS=200

AI_CONFIDENCE_THRESHOLD=0.6
AI_LONG_SENTENCE=8
```

The MiniMax adapter speaks the OpenAI-compatible chat-completions shape (`POST {base}/v1/chat/completions`). It is only called when:

- the user has toggled "MiniMax AI" on, **and**
- local confidence is below `AI_CONFIDENCE_THRESHOLD`, **or** the sentence has at least `AI_LONG_SENTENCE` tokens.

The local decoder always runs first and is returned immediately. The MiniMax call has a hard 200ms timeout — if it doesn't beat the timeout, you keep the local prediction. **The UI never blocks waiting for AI.** When MiniMax does respond, its output is surfaced in `aiSuggestions` alongside the local prediction; it only replaces the primary prediction when local confidence is clearly low.

The adapter is behind the `LLMClient` interface in `backend/src/ai/llmClient.ts`. To swap in a different provider, implement that interface and wire it in `backend/src/index.ts`.

## Adding a larger dictionary

Edge ships with a curated frequency list embedded in `backend/src/decoder/dictionary.ts`. To swap in a real corpus (SUBTLEX-US, Google Books unigrams, etc.):

1. Drop a tab- or space-separated `word<TAB>freq` file at `backend/data/words.txt`.
2. Restart the backend. The loader merges your file with the starter list and takes the higher frequency where both contain the same word.

## How to test

```bash
npm test            # all Vitest suites
npm run bench       # latency benchmarks only
```

Suites:

| suite                          | what it covers                                                              |
| ------------------------------ | --------------------------------------------------------------------------- |
| `tokenParser.test.ts`          | parses 1- and 2-letter prefixes, literals (incl. `a`/`i`), punctuation, case |
| `candidateGenerator.test.ts`   | startsWith matching, 50-cap, case-insensitivity, unknown-prefix passthrough  |
| `beamSearch.test.ts`           | reconstructs the canonical example, context bias, right-context look-ahead, domains, 1-letter prefix decode, punctuation, per-word confidence |
| `correctionCycle.test.ts`      | `\` / `Shift+\` / `Alt+\` / `Cmd+\` semantics; most-uncertain targeting    |
| `correctionMemory.test.ts`     | exact-pattern hits per domain, token-to-word boosts, prefix-successor records, persistence, schema-version wipe, recovery from corrupt file |
| `prefixSuccessor.test.ts`      | a single learned `(prev → prefix → word)` reshapes future predicts; boost does not leak across different prev words; domain → general half-weight fallback |
| `phraseMemory.test.ts`         | curated and learned bigrams/trigrams, domain weighting, snapshot/restore     |
| `minimax.test.ts`              | OpenAI-style + MiniMax-style response parsing, 500/invalid JSON fallback, 200ms timeout, Authorization header |
| `confidence.test.ts`           | sentence and word confidence monotonicity + bounds                           |
| `benchmark.test.ts`            | median local decode < 30ms for 9 tokens, < 15ms for 5 tokens                 |

Manual smoke test:

```bash
curl -s http://localhost:3002/api/predict -H 'content-type: application/json' \
  -d '{"tokens":["i","wa","to","ma","a","pr","ma","re","ap"],
       "contextBefore":"","contextAfter":"","domain":"general","useAI":false}'

curl -s http://localhost:3002/api/learn -H 'content-type: application/json' \
  -d '{"compressed":"pr ma","corrected":"prediction market","domain":"business"}'
```

## Testing latency

`npm run bench` runs 200 iterations of two example sentences and prints median / p95 / mean to the console, asserting median < 30ms (long) and < 15ms (short). The benchmark warms up the dictionary index before sampling.

For interactive latency, the UI shows live `latency_ms` and the prediction `source` (`local`, `exact`, `ai`) in the top-right badge. If the badge stays on `local` even with MiniMax enabled, either confidence was high enough that we didn't call it, the call didn't beat the 200ms cutoff, or local confidence wasn't low enough to promote AI to primary (in which case AI completions still show up in the **AI completions** panel).

## Future: turning this into a real macOS or Windows input method

- [ ] Wrap predict/learn in a macOS **Input Method Kit** (IMK) component that routes raw key events to the in-process decoder (no HTTP).
- [ ] Equivalent on Windows via **TSF** (Text Services Framework).
- [ ] Replace the JSON correction store with SQLite when write volume crosses ~hundreds per minute.
- [ ] Bundle a larger frequency list and a real bigram/trigram table (Google Books 1-gram + 2-gram).
- [ ] Train personal vocabulary from the user's full typing history, not just corrections.
- [ ] On-device LLM via Core ML / ONNX so the AI rerank works offline.
- [ ] Adaptive AI gating: if local confidence has been high all session, skip the rerank entirely; if the user accepts AI predictions, lower the confidence threshold.

## Architecture principles

- **Local-first.** The UI sees a local prediction in ≤30ms — AI is rerank, never blocking.
- **Modular decoder.** `tokenParser → candidateGenerator → beamSearch (scorer + phraseMemory + correctionMemory) → confidence`. Each module is independently testable.
- **Adapter pattern for AI.** `LLMClient` interface; `MiniMaxClient` is the default impl. Drop in others without touching the routes.
- **Domain-aware.** Six built-in domains weight different phrase tables. Adding a new domain is one entry in `phraseMemory.ts` plus an option in `DomainSelector.tsx`.
- **Keyboard-first correction.** `\` and its modifiers cover every UI affordance.
- **Every correction generalizes.** Corrections are stored as exact-pattern hits *and* as `(prev word, prefix → word)` successor boosts, so a single taught sentence improves predictions for unrelated inputs that share the same context.
- **No hidden hot paths.** Caches are explicit; the predict route invalidates the sentence cache on every `/api/learn`.
