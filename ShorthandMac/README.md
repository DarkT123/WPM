# Lazily

A system-wide macOS app that lets you type a compressed, no-space version of a sentence — then press `.` to expand it into a clean full sentence using an LLM that knows the text around your cursor.

```
type:     iwgotosch.
get:      I want to go to school.

type:     thedogranhome.
get:      The dog ran home.

type:     tdrh.
get:      The dog ran home.
```

The shorthand is flexible — type the first letter of each word, the first two, partial words, or full words mashed together. Whatever you want. More letters = more accurate expansion. Normal writing with spaces is never touched.

## How it works

| Stage | Component |
| --- | --- |
| Capture every keystroke system-wide | `KeystrokeInterceptor.swift` — `CGEventTap` with a self-injection sentinel |
| Buffer the run of letters since the last word boundary | (same) |
| On `.` if the buffered token is 2–80 letters: consume the period, fire expansion | (same) |
| Locate caret + read surrounding text via Accessibility API | `CaretLocator.swift` |
| Send `{ compressed_input, context_before, context_after, style_notes, recent_corrections }` to an OpenAI-compatible chat endpoint | `MiniMaxClient.swift` |
| Receive structured JSON `{ should_expand, expanded_sentence, confidence, alternatives }` | (same) |
| Backspace the original token, inject the expanded sentence + `.` | `KeystrokeInterceptor.injectReplacement` |
| Show a floating non-activating panel with the 3 alternatives + **Undo** | `SuggestionPanel.swift` |

If the AI sets `should_expand: false` (e.g. you typed a real English word and pressed period), the swallowed `.` is reinserted and your text is untouched.

## Setup

Requires macOS 13+ and an OpenAI-compatible AI provider (xAI, MiniMax, Groq, DeepSeek, or OpenAI itself).

1. Create `.env` in the workspace root:

   ```
   MINIMAX_API_KEY=<your key>
   MINIMAX_API_BASE_URL=https://api.x.ai/v1        # or whichever provider
   MINIMAX_MODEL=grok-4-fast-non-reasoning           # or gpt-4o-mini, etc.
   MINIMAX_TIMEOUT_MS=5000
   ```

2. Build and run:

   ```bash
   SDK=$(xcrun --sdk macosx --show-sdk-path)
   swiftc -O -sdk "$SDK" -target arm64-apple-macos13 \
     ShorthandMac/*.swift Shared/Services/*.swift Shared/Utilities/*.swift \
     -framework AppKit -framework SwiftUI -framework ApplicationServices \
     -o ~/Lazily
   ~/Lazily
   ```

3. Grant Accessibility permission in System Settings → Privacy & Security → Accessibility (the app prompts you). Toggle **Active**. Try `iwgotosch.` in Notes.

## Files

| File | Role |
| --- | --- |
| `LazilyApp.swift` (formerly `ShorthandMacApp.swift`) | SwiftUI `@main`, settings window |
| `AppState.swift` | `@MainActor` coordinator. Wires interceptor → AI → panel. Tracks last expansion for swap/undo. |
| `KeystrokeInterceptor.swift` | `CGEventTap`, buffer, period trigger, backspace+inject |
| `MiniMaxClient.swift` | OpenAI-compatible client, prompt, structured-JSON parser |
| `CaretLocator.swift` | AX caret rect + surrounding text |
| `SuggestionPanel.swift` | Floating `NSPanel` with expanding / expanded / error states |
| `ContentView.swift` | Settings window: toggle, AX status, style notes, live buffer, examples |
| `EnvLoader.swift` | Reads `.env` from workspace root |

## Notes

- The binary is adhoc-signed at build time, so macOS treats every rebuild as a new app for Accessibility. If a rebuild seems unresponsive, remove the old entry from System Settings → Accessibility and re-add the new one.
- The interceptor never touches text that contains spaces. The only way to trigger expansion is to type letters with no spaces and then `.`.
- Style notes are appended to the AI's system prompt — useful for "casual", "student writing", "always use Oxford comma", etc.
