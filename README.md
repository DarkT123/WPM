# Translating Keyboard / Edge

A workspace exploring **fast, context-aware predictive keyboards** — where the user types a tiny compressed representation of each word and the system reconstructs the full sentence using a local dictionary, n-grams, phrase memory, learned corrections, and (optionally) a self-hosted MiniMax API.

The flagship example:

```
input:    i wa to ma a pr ma re ap
output:   i want to make a prediction market research app
```

You type the first letter or two of each word; Edge fills in the rest using context.

## What's in this repo

| Folder | What it is | Status |
| --- | --- | --- |
| **[`edge/`](edge/)** | Main TS/Node + React workspace. Prefix-based predictive keyboard backend + web UI. Beam search over a 600-word dictionary, bigrams/trigrams per domain, JSON-persisted correction memory, MiniMax adapter, backslash key correction. | Active |
| **[`edge-dashboard/`](edge-dashboard/)** | Native macOS SwiftUI dashboard for the Edge backend. Live predict, AI completions panel, corrections log, backend status. XcodeGen-generated project. | Active |
| **[`edgetype/`](edgetype/)** | Earlier prototype using first/last-letter encoding (`te qk bn fx` → "the quick brown fox") instead of prefixes. Kept for reference and benchmarking. | Frozen |
| **[`TranslatingKeyboard*/`](TranslatingKeyboard/)** | Original iOS keyboard extension that started this project — translates text inline as you type using the Claude API. Swift + UIKit + XcodeGen. | Maintenance |
| **`Shared/`** | Swift code shared between the iOS app and its keyboard extension (App Group defaults, etc.). | — |

## Quick start (Edge — the main thing)

Requirements: Node 20+, npm 10+.

```bash
cd edge
npm install
npm run dev
```

- Backend: `http://localhost:3002`
- Frontend: `http://localhost:5174` (Vite proxies `/api/*` to the backend)

Open the frontend, type `i wa to ma a pr ma re ap`, and watch the prediction update in ~3 ms. Press `\` to cycle the most-uncertain word, `Shift+\` backward, `Alt+\` to cycle whole-sentence alternatives, `Cmd+\` to accept and teach.

Tests:

```bash
cd edge && npm test       # 9 Vitest suites
cd edge && npm run bench  # latency benchmarks
```

## Quick start (macOS Dashboard)

Requirements: macOS 13+, Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd edge-dashboard
bash setup.sh             # installs xcodegen via Homebrew if needed, then generates the project
open EdgeDashboard.xcodeproj
```

In Xcode: set your Team in Signing & Capabilities, then `Cmd+R`. The dashboard talks to the backend on `http://localhost:3002` by default — change in Settings if you've remapped the port.

## Architecture at a glance

```
┌────────────────────┐      ┌──────────────────────────────────────────────┐
│  Web UI (Vite)     │◀────▶│  Edge backend  (edge/backend)                │
│  edge/frontend     │      │                                              │
│  port 5174         │      │  ┌──────────────────────────────────────┐   │
└────────────────────┘      │  │  Decoder                              │   │
                            │  │   tokenParser → candidateGenerator    │   │
┌────────────────────┐      │  │     → beamSearch                      │   │
│  macOS Dashboard   │◀────▶│  │       (scorer + phraseMemory +        │   │
│  edge-dashboard    │      │  │        correctionMemory + confidence) │   │
│  SwiftUI           │      │  └──────────────────────────────────────┘   │
└────────────────────┘      │                                              │
                            │  AI: MiniMax adapter (LLMClient interface)   │
                            │  Storage: backend/data/corrections.json      │
                            │  port 3002                                   │
                            └──────────────────────────────────────────────┘
```

Key properties:

- **Local-first.** Predictions return in ≤30 ms — AI is reranking, never blocking. Hard 200 ms timeout on the MiniMax call; on timeout you keep the local result.
- **Modular decoder.** Every stage is independently testable. See [`edge/backend/src/decoder/`](edge/backend/src/decoder/).
- **Adapter pattern for AI.** Implement [`LLMClient`](edge/backend/src/ai/llmClient.ts) to plug in a different provider; the routes don't care.
- **Six domains** — `general`, `school`, `business`, `coding`, `texting`, `research` — weight different phrase tables.
- **Keyboard-first correction.** `\` and its modifiers cover every UI affordance.

## Compressed-input grammar

| token | meaning |
| --- | --- |
| `t` | 1-letter prefix — any word starting with T |
| `th` | 2-letter prefix — any word starting with TH |
| `the` | literal word (3+ letters) |
| `a`, `i` | literal one-letter words |
| `.` `,` `!` `?` | punctuation, kept attached to the previous word |

For deeper docs on the decoder, scoring, MiniMax wiring, and the future-IME roadmap, see [edge/README.md](edge/README.md). The dashboard is documented at [edge-dashboard/README.md](edge-dashboard/README.md).

## Development workflow

The pieces are designed to evolve independently:

- **Decoder tweaks** → edit files in [`edge/backend/src/decoder/`](edge/backend/src/decoder/), `cd edge && npm test`.
- **UI changes** → [`edge/frontend/src/`](edge/frontend/src/), hot-reloaded by Vite.
- **Dashboard UI** → [`edge-dashboard/EdgeDashboard/Views/`](edge-dashboard/EdgeDashboard/Views/), rebuild in Xcode.
- **Bigger pivots** → write the plan in `edge/HANDOFF.md` and hand off to a separate Claude Code session; the most recent example is the first-letter+last-letter → prefix encoding migration documented there.

## Secrets and gitignore

- **Never commit `.env`.** Put your MiniMax key in [`edge/backend/.env`](edge/backend/.env) (create it from `.env.example`). The rule `.env` in [`edge/.gitignore`](edge/.gitignore) covers it at any depth.
- Tighten file permissions on the env file if you share this Mac with anyone:
  ```bash
  chmod 600 edge/backend/.env
  ```
- Never paste API keys into chat, screenshots, or commit messages. Rotate immediately if leaked.

## Status

- ✅ Edge backend: prefix-based decoder, MiniMax adapter, correction memory with prefix-successor boosts, 9 Vitest suites passing, `<1 ms` median decode for typical sentences.
- ✅ Edge web frontend: ghost-text prediction, AI-completions panel, backslash correction, domain selector.
- ✅ macOS dashboard: live predict, corrections log, backend status, MiniMax toggle. Builds cleanly under `xcodebuild`.
- 🚧 iOS Translating Keyboard: the original keyboard extension lives separately from Edge and is on maintenance only — it does inline translation, not predictive autocomplete.

## Roadmap

- Wrap the Edge decoder in a macOS **Input Method Kit** extension so it can drive the system text input directly, with the dashboard becoming its settings & teaching surface.
- TSF wrapper for Windows.
- Bundle a real frequency corpus (SUBTLEX or Google Books unigrams) at `edge/backend/data/words.txt`.
- Personal-vocabulary learning from full typing history, not only corrections.
- On-device LLM via Core ML so the AI rerank works offline.
