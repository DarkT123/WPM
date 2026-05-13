# Lazily eval set

`test_cases.json` is a 100+-case test set with two axes:

1. **Gate behavior** — does `ExpansionGate.check(...)` correctly skip or proceed for this `(compressed_input, context, focused_app)` triple?
2. **AI behavior** — for "proceed + should_expand: true" cases, does the configured AI provider return a structured-JSON expansion whose output covers every letter of the compressed token in order?

Coverage:

- 47 shorthand-style sentences that should expand (`expand-*`)
- 20 single English words that should NOT expand (`no-expand-word-*`)
- 5 URL-context cases (`no-expand-url-*`)
- 3 file-path cases (`no-expand-path-*`)
- 2 email cases (`no-expand-email-*`)
- 3 code-context cases (`no-expand-code-*`)
- 2 identifier cases (`no-expand-identifier-*`)
- 7 shell-command cases (`no-expand-shell-*`)
- 5 excluded-app cases (`no-expand-app-*`) — Terminal / VS Code / Xcode / iTerm / 1Password
- 2 aggressive-mode cases that should *proceed* despite being normal words
- 7 boundary cases mixing shorthand with English words

## Building the runner

```bash
cd "/Users/andyzhao/Translating keyboard"
SDK=$(xcrun --sdk macosx --show-sdk-path)
swiftc -O -sdk "$SDK" -target arm64-apple-macos13 \
  eval/runner.swift \
  ShorthandMac/ExpansionGate.swift \
  ShorthandMac/MiniMaxClient.swift \
  ShorthandMac/EnvLoader.swift \
  Shared/Services/NorvigTop10k.swift \
  -framework AppKit -framework ApplicationServices \
  -o eval/runner
```

## Running

```bash
# Gate-only (no AI calls — fast, no API key needed):
eval/runner --no-ai

# Full run (hits the AI for every "should expand" case; needs MINIMAX_API_KEY):
eval/runner

# A single case:
eval/runner --only=expand-001
```

Each line prints `✓` or `✗` followed by the case ID and (if failed) the actual gate decision / AI response. The footer summarizes:

- gate-correct count
- AI-call count
- valid-JSON rate
- letter-coverage match rate
- median + p95 latency

Exit code is non-zero if any case failed.

## What "AI correct" means

A response is correct if either:

1. After normalizing (lowercase, strip non-letters), it matches one of the test's `acceptable_outputs`, **or**
2. Every letter of the original compressed token appears in the output in order (letter-coverage). This is a forgiving fallback for cases where multiple natural sentences are equally valid.

This means the runner only catches the worst failures — the AI dropping letters, hallucinating, or wrapping its output in `<think>` blocks the parser can't strip. For nuanced quality you still want a human read.

## What this doesn't cover

- Manual UI flows (Cmd+Z, click-to-swap, panel placement).
- Multi-keystroke flows like "user types, undoes, retypes".
- Provider-specific quirks (rate limits, reasoning timeouts).
- Bundle-ID detection in real apps (the runner stubs `focused_bundle_id` from the case file — production reads it from `NSWorkspace.shared.frontmostApplication`).

For those, exercise the live app.
