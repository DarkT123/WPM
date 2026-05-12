# EdgeType

A predictive-keyboard prototype where you type only the **first and last letter of each word**, and the system reconstructs the most likely full sentence using a local dictionary, n-gram scoring, beam search, and (optionally) a self-hosted AI completion API.

```
input:   te qk bn fx
output:  the quick brown fox
```

## Why this is hard

First/last-letter typing creates massive ambiguity. The compressed token `te` can be **the**, **time**, **take**, **true**, **tide**, **tone**, **tree**, **trade**, **table**… and so on. A 6-token sentence with ~30 candidates per token has on the order of 10⁸ possible sentences. EdgeType does **not** try to be deterministic — it scores candidate sentences using:

- word frequency (common words preferred over obscure ones)
- bigrams (natural word adjacency)
- user-correction history (your typing teaches the model)
- context continuity (last word of the previous sentence carries over)
- optional LLM rerank via your Mac-mini AI service

…and exposes alternatives so you can correct it when it guesses wrong.

## Layout

```
edgetype/
├── backend/      # Express + TypeScript prediction service
├── frontend/     # React + Vite UI
├── shared/       # API request/response types shared by both
├── package.json  # workspaces + dev/build/test scripts
└── README.md
```

## Setup

Requirements: Node 20+, npm 10+.

```bash
cd edgetype
npm install            # installs both workspaces
cp backend/.env.example backend/.env   # optional — only needed if you use the AI API
```

## Run

```bash
npm run dev
```

This starts:

- **backend** on `http://localhost:3001`
- **frontend** on `http://localhost:5173` (Vite dev server, proxies `/api/*` to the backend)

Open `http://localhost:5173` and type compressed tokens separated by spaces.

## Connecting your Mac-mini AI API

The backend calls `POST {AI_API_BASE_URL}/complete` with:

```json
{
  "compressedTokens": ["te", "qk", "bn", "fx"],
  "wordCandidates": [
    { "token": "te", "candidates": ["the", "time", "take", "..."] }
  ],
  "contextBefore": "",
  "instruction": "Reconstruct the most likely sentence. Every output word must match the corresponding first and last letter constraint unless correcting an obvious user typo."
}
```

Your service should respond with:

```json
{ "prediction": "the quick brown fox", "alternatives": ["..."] }
```

Configure `backend/.env`:

```
AI_API_BASE_URL=http://your-mac-mini.local:8080
AI_API_KEY=optional-bearer-token
AI_TIMEOUT_MS=150
```

The backend always runs local beam search in parallel. If the AI doesn't respond within `AI_TIMEOUT_MS` (default 150ms) or returns a bad response, EdgeType falls back to the local prediction transparently. Mismatched words (where AI output violates the first/last-letter constraint) are flagged in the UI rather than silently corrected, since the instruction allows it to fix obvious typos.

In the UI, toggle **"Send to AI"** to opt in.

## Adding a larger frequency list

EdgeType ships with a curated starter list of common English words embedded in `backend/src/prediction/dictionary.ts`. To swap in a real frequency table:

1. Place a tab- or whitespace-separated file at `backend/data/words.txt`:
   ```
   the     22038615
   of      9942406
   and     7588412
   ...
   ```
   (SUBTLEX-US, Google Books unigrams, or any similar source works.)
2. Restart the backend. The loader merges your file with the starter list, taking the higher frequency where both contain the same word.

## How to test

```bash
npm test                       # runs all Vitest suites in backend/
npm test -w backend -- --watch # watch mode while iterating
```

Test suites:

- `candidates.test.ts` — first/last matching, case, single-letter, top-50 cap, unknown-token passthrough.
- `beamSearch.test.ts` — reconstructs example sentences, beam width respected, word boosts move ranking.
- `ai.test.ts` — AI 200 / 500 / timeout paths and mismatch flagging.
- `learning.test.ts` — corrections persist across instances, boosts and bigrams accumulate.

Manual smoke test:

```bash
curl -s http://localhost:3001/api/predict \
  -H 'content-type: application/json' \
  -d '{"tokens":["te","qk","bn","fx"],"contextBefore":"","useAI":false}'
# → { "prediction": "the quick brown fox", "alternatives": [...], "latencyMs": 4, "source": "local", ... }

curl -s http://localhost:3001/api/learn \
  -H 'content-type: application/json' \
  -d '{"compressed":"te qk bn fx","corrected":"the quick brown fox"}'
# → { "ok": true }
```

## Example compressed inputs

| compressed              | likely reconstruction           |
| ----------------------- | -------------------------------- |
| `te qk bn fx`           | the quick brown fox              |
| `we ae gg to te pe`     | we are going to the place        |
| `is ws a gd dy`         | it was a good day *(approx)*     |
| `pn ms ae cg fe`        | prediction markets are changing finance *(approx — depends on dictionary)* |

The closer your dictionary is to your typing domain, the better the reconstruction.

## Future: turning this into a real macOS input method

The current prototype is a web app for fast iteration. The path to a real keyboard:

- [ ] Wrap the predict/learn API in a macOS **Input Method Kit** (IMK) extension; route key events to `/api/predict` in-process.
- [ ] Replace the JSON correction store with SQLite (better-sqlite3) for higher write volume.
- [ ] Bundle a larger frequency list (SUBTLEX-US ~70k words is plenty).
- [ ] Learn personal vocabulary from the user's own typing history, not just corrections.
- [ ] On-device LLM: run the AI rerank in Core ML instead of an HTTP call, so it works offline.
- [ ] Add adaptive timing: if local confidence is high, skip the AI call entirely.
- [ ] Multi-script support — current beam search assumes Latin alphabet.

## Architecture notes

- **Local-first.** Predictions run in-process; the AI service is opt-in.
- **Always parallel.** When AI is enabled, local beam search still runs so the latency floor is whichever finishes first.
- **Constraint validation.** AI output is checked against the first/last-letter rule; violations are flagged, not dropped — the spec allows AI to correct obvious typos.
- **Caches.** Token-level candidate lookup is indexed at startup; full-sentence predictions are LRU-cached and invalidated on every `/api/learn`.
- **No global state.** The store, caches, and indices are addressable for testing; tests reset them between cases.
