# Edge Dashboard

A native macOS SwiftUI app that talks to the [Edge backend](../edge) — type compressed tokens (1- or 2-letter prefixes), see the predicted sentence live, browse alternatives and AI completions, teach corrections, and watch the backend's health pill in the corner.

```
   ┌──────────────────────────────────────────────────────────┐
   │ ● Backend up · abab6.5-chat        MiniMax: ready    [↻] │
   ├───────────┬──────────────────────────────────────────────┤
   │ Live      │  Compressed input                            │
   │ Corrections│  ┌──────────────────────────────────────┐   │
   │ Settings  │  │ i wa to ma a pr ma re ap             │   │
   │           │  └──────────────────────────────────────┘   │
   │           │  Prediction                                  │
   │           │  i want to make a prediction market         │
   │           │  research app                  LOCAL 3ms 99% │
   │           │                                              │
   │           │  AI completions (click to teach)             │
   │           │  · i want to make a prediction-market        │
   │           │    research application                      │
   └───────────┴──────────────────────────────────────────────┘
```

## Setup

Requirements: macOS 13+, Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd edge-dashboard
bash setup.sh           # installs xcodegen via Homebrew if needed, then generates the project
open EdgeDashboard.xcodeproj
```

In Xcode:
1. Select the **EdgeDashboard** target → **Signing & Capabilities** → set your Team.
2. (Optional) change bundle id from `com.yourname.edge.dashboard`.
3. **Cmd+R** to build & run.

Start the backend in a separate terminal:

```bash
cd ../edge
npm install
npm run dev            # backend on http://localhost:3002
```

## Sections

- **Live predict** — compressed input, context fields, domain picker, AI toggle, live prediction with per-word confidence chips, **AI completions** panel (shown when MiniMax responds inside the timeout), alternatives panel, and a manual correction form.
- **Corrections** — log of corrections taught this session (the backend persists its own copy in `backend/data/corrections.json`).
- **Settings** — backend URL, AI availability, test connection.

## What runs where

- The dashboard never decodes locally — it always asks the backend.
- The backend's local decoder runs in ≤30ms; the dashboard debounces input at 80ms.
- If MiniMax is configured (via `MINIMAX_API_BASE_URL` in `edge/backend/.env`), toggling **Use MiniMax AI** asks the server to consult it for low-confidence sentences. The server enforces a 200ms hard timeout and falls back to the local prediction silently. Successful AI calls return their output in `aiSuggestions` alongside the local prediction so both are visible.

## Files

```
edge-dashboard/
├── project.yml                       # XcodeGen project definition
├── setup.sh                          # generates EdgeDashboard.xcodeproj
└── EdgeDashboard/
    ├── EdgeDashboardApp.swift        # @main entry
    ├── Info.plist
    ├── EdgeDashboard.entitlements    # App Sandbox + network client
    ├── API/
    │   ├── Models.swift              # Codable mirrors of edge/shared/types.ts
    │   └── EdgeAPI.swift             # URLSession actor with timeouts
    └── Views/
        ├── DashboardView.swift       # NavigationSplitView shell
        ├── AppModel.swift            # ObservableObject — single source of truth
        ├── BackendStatusView.swift   # health pill
        ├── LivePredictView.swift     # main predict UI (incl. AI completions GroupBox)
        ├── CorrectionsLogView.swift  # session log
        ├── SettingsView.swift        # backend URL + about
        └── DomainPicker.swift        # 6-domain dropdown
```

## Why no embedded backend?

The Edge backend already runs as a Node process and is faster to iterate than a Swift port. The dashboard's only job is to be a nice native client. When the project moves to a real macOS input method (see `edge/README.md`'s Future section), the decoder can be ported in-process — at that point this dashboard becomes the settings & teaching surface for the IME, not a standalone tool.
