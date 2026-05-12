# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository shape

This directory is a workspace containing **four loosely-related sub-projects**. They are not a monorepo — each is independently buildable and has its own dependencies. Always `cd` into the relevant sub-project before running commands.

| Path | What it is | Stack |
| --- | --- | --- |
| `TranslatingKeyboard/` + `TranslatingKeyboardExtension/` + `Shared/` + root `project.yml` | iOS app + system keyboard extension that translates typed English to a target language via the Claude API | Swift, SwiftUI, XcodeGen |
| `edge/` | Predictive-keyboard prototype where you type only first/last letter of each word; decoder + optional MiniMax LLM rerank. The **current** iteration of the predictive-keyboard idea. | Node 20+, TypeScript, Express, React, Vite, Vitest |
| `edgetype/` | Earlier prototype of the same first/last-letter idea. Superseded by `edge/`, but still runnable. | Same as `edge/` |
| `edge-dashboard/` | macOS app that talks to the `edge/` backend over HTTP (status, predict, learn). Requires `edge/` running on `localhost:3002`. | Swift, SwiftUI, XcodeGen |

**The iOS TranslatingKeyboard and the Edge/EdgeType predictive keyboards are two different products** that happen to live in the same parent folder. Don't conflate them.

## TranslatingKeyboard (iOS)

The Xcode project is generated from `project.yml` via XcodeGen. **Do not hand-edit `TranslatingKeyboard.xcodeproj/`** — regenerate it.

```bash
bash setup.sh                       # installs XcodeGen (via brew) and generates the xcodeproj
open TranslatingKeyboard.xcodeproj  # then build/run from Xcode
```

Targets:
- `TranslatingKeyboard` — container app (settings, API key entry, onboarding).
- `TranslatingKeyboardExtension` — the actual keyboard (app extension). Embeds into the container.

Both targets include the `Shared/` directory (Language, TranslationTone, ClaudeTranslationService, SharedDefaults).

Critical architecture points:
- **App Group is the bridge.** Container app and extension share state via `UserDefaults(suiteName: "group.com.yourname.translatingkeyboard")` in `Shared/Utilities/SharedDefaults.swift`. The suite name in code, both `.entitlements` files, and the Xcode App Group capability **must all match**, or the extension can't read the API key the container app wrote. `SharedDefaults.init` `fatalError`s if the suite isn't configured.
- **Keyboard extensions require "Allow Full Access"** to make network calls (the Claude API). `KeyboardViewModel.refreshSettings(hasFullAccess:)` is fed this from `UIInputViewController.hasFullAccess` and the UI surfaces an error if it's off.
- **Keyboard extensions don't run on the simulator** for network-using flows — test on a real device.
- Translation uses Claude via `Shared/Services/ClaudeTranslationService.swift` (model: `claude-haiku-4-5-20251001`, endpoint `https://api.anthropic.com/v1/messages`). Translation is debounced ~600ms in `KeyboardViewModel.scheduleTranslation()` and the previous task is cancelled on each keystroke.
- The view model uses Swift's `@Observable` macro (iOS 17+, matches `deploymentTarget: "17.0"`).

There is no test target wired up in `project.yml`.

## edge/ (current predictive-keyboard prototype)

Workspace with two sub-packages: `backend/` (Express + TS) and `frontend/` (React + Vite). `shared/` is plain TS imported by both via relative paths.

```bash
cd edge
npm install
npm run dev      # runs backend (:3002) + frontend (:5174) concurrently
npm test         # runs Vitest in backend
npm run bench    # latency benchmark only — backend/tests/benchmark.test.ts
npm run build    # tsc for backend, tsc -b && vite build for frontend
```

Single test file:
```bash
npm test -w backend -- tests/beamSearch.test.ts
npm test -w backend -- --watch                    # watch mode
```

Decoder pipeline (`backend/src/decoder/`) — each stage is independently tested:
```
tokenParser  → candidateGenerator → beamSearch (scorer + phraseMemory + correctionMemory) → confidence
```

- `tokenParser.ts` parses the compressed input grammar: `te` (first/last letters), `t3e` (length-pinned), literal words (`the`, `a`, `i`), and punctuation.
- `phraseMemory.ts` and `correctionMemory.ts` are persistent — they read/write JSON under `backend/data/` (gitignored). `CorrectionMemory` is wired into `phraseMemory` at construction time in `src/index.ts`.
- **Cache invalidation:** `routes/learn.ts` must call `invalidatePredictCache()` (in `routes/predict.ts`) on every learn, otherwise stale predictions stick. The cache is keyed on tokens + context + domain + `useAI`.
- **AI is rerank, never blocking.** Local beam search always runs and is the floor. The MiniMax adapter is only consulted when `useAI` is on AND (confidence < `AI_CONFIDENCE_THRESHOLD` OR tokens.length ≥ `AI_LONG_SENTENCE`), AND it must beat a hard 200ms timeout — otherwise the local prediction is returned. `LLMClient` interface in `ai/llmClient.ts` is the swap point for non-MiniMax providers.
- Six fixed domains: `general | school | business | coding | texting | research` (validated in `routes/predict.ts`). Adding one requires updates in both `phraseMemory.ts` and `frontend/src/components/DomainSelector.tsx`.
- Backslash correction semantics live in `shared/cycle.ts` and are tested via `tests/correctionCycle.test.ts` — these are shared between server-side logic and the frontend UI.

Config via `backend/.env` (see `edge/README.md` for the keys). `.env` is gitignored.

Latency contract: `tests/benchmark.test.ts` asserts median local decode <30ms for 9 tokens and <15ms for 5 tokens. Don't regress this without intent.

## edgetype/ (earlier prototype)

Same layout as `edge/` but simpler — no per-domain weighting, no backslash cycle protocol, no MiniMax-specific adapter (generic `/complete` POST instead). Backend on `:3001`, frontend on `:5173`. Commands mirror `edge/` (`npm run dev`, `npm test`, etc.).

**Default to working in `edge/`, not `edgetype/`**, unless the user specifically points to edgetype. The two are not kept in sync.

## edge-dashboard/ (macOS, observes edge/)

```bash
cd edge-dashboard
bash setup.sh                  # installs XcodeGen and generates EdgeDashboard.xcodeproj
open EdgeDashboard.xcodeproj
```

Hits `http://localhost:3002` by default (`EdgeAPI.swift`) — **the `edge/` backend must be running** or the app will show transport errors. The base URL is settable at runtime via `EdgeAPI.setBaseURL`.

## Conventions across the workspace

- **Xcode projects are generated, not committed source.** `project.yml` is the source of truth for both Swift projects. If `xcodeproj` contents seem stale, run `xcodegen generate` rather than editing pbxproj.
- **App Group identifiers and bundle IDs in `project.yml` use the placeholder `com.yourname.*`.** The user needs to swap these for their own dev team's prefix when signing — don't assume the placeholder is real.
- **The Edge backends persist state to JSON files under `backend/data/`** (gitignored). When tests need a clean state, they instantiate fresh stores rather than relying on shared global state — keep this pattern when adding new persistent stores.
