import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                toggleCard
                accessibilityCard
                aiCard
                safetyCard
                styleNotesCard
                bufferCard
                examplesCard
            }
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 640)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lazily")
                .font(.title.weight(.semibold))
            Text("Type a compressed sentence with no spaces. Use as many letters per word as you want. Press “.” to expand it into a clean full sentence. Normal writing with spaces is never touched.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var toggleCard: some View {
        HStack(spacing: 14) {
            Image(systemName: state.isEnabled ? "wand.and.stars" : "power")
                .font(.title)
                .foregroundStyle(state.isEnabled ? .green : .secondary)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.isEnabled ? "Active" : "Inactive")
                    .font(.headline)
                Text(state.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { state.isEnabled },
                set: { _ in state.toggle() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.large)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var accessibilityCard: some View {
        let granted = state.hasAccessibility
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: granted ? "checkmark.shield" : "exclamationmark.shield")
                .font(.title3)
                .foregroundStyle(granted ? .green : .orange)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(granted ? "Accessibility granted" : "Accessibility required")
                    .font(.subheadline.weight(.semibold))
                Text(granted
                     ? "Lazily can read and rewrite keystrokes in any app."
                     : "Open System Settings → Privacy & Security → Accessibility, enable this app, then toggle Active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !granted {
                Button("Open Settings") { state.requestAccessibility() }
                    .controlSize(.small)
            } else {
                Button("Re-check") { state.refreshAccessibility() }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var aiCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: state.aiEnabled ? "sparkles" : "sparkles.slash")
                .font(.title3)
                .foregroundStyle(state.aiEnabled ? .purple : .secondary)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(state.aiEnabled ? "AI expansion enabled" : "AI expansion disabled")
                        .font(.subheadline.weight(.semibold))
                    if state.aiInFlight {
                        ProgressView().controlSize(.small).scaleEffect(0.6)
                        Text("expanding…").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(state.aiEnabled
                     ? "When you press “.” on a compressed shorthand token, the AI infers word boundaries, missing connectors, capitalization and grammar — using up to 500 characters around your cursor as context."
                     : "Add MINIMAX_API_KEY to /Users/andyzhao/Translating\u{00A0}keyboard/.env, then quit and relaunch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let err = state.aiLastError {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("Last AI call: \(err)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 4)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Safety")
                        .font(.subheadline.weight(.semibold))
                    Text("Lazily never expands inside Terminal, IDEs, password managers, or text that looks like a URL / file path / email / code identifier. It also doesn’t expand normal English words like “hello.” or “thanks.” — unless you turn on aggressive mode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            Toggle(isOn: $state.aggressiveMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aggressive mode")
                        .font(.caption.weight(.semibold))
                    Text("Allow expansion even when the typed token is a normal English word. Off by default.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if let skip = state.lastGateSkipReason {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Last skip: \(skip)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }

            DisclosureGroup {
                Text("Terminal · iTerm2 · Alacritty · Kitty · WezTerm · Hyper · VS Code · Cursor · Windsurf · Xcode · Sublime Text · JetBrains IDEs · 1Password · Bitwarden · LastPass · Dashlane · KeePassXC")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            } label: {
                Text("Excluded apps")
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var styleNotesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Style notes (fed to the AI as system prompt)")
                .font(.subheadline.weight(.semibold))
            Text("Example: “casual tone, lowercase except proper nouns, student writing — don’t make it overly formal”.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $state.styleNotes)
                .font(.callout)
                .frame(minHeight: 60, maxHeight: 100)
                .padding(6)
                .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
                )
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var bufferCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live buffer")
                .font(.subheadline.weight(.semibold))
            HStack {
                Text(state.bufferDisplay.isEmpty ? "(empty — start typing letters)" : state.bufferDisplay)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(state.bufferDisplay.isEmpty ? .secondary : .primary)
                Spacer(minLength: 0)
                if state.aiInFlight {
                    ProgressView().controlSize(.small).scaleEffect(0.55)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

            if let compressed = state.lastCompressed, let expanded = state.lastExpansion {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars").font(.caption2).foregroundStyle(.green)
                        Text(compressed)
                            .font(.system(.caption, design: .monospaced))
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                        Text(expanded).font(.caption)
                        Spacer(minLength: 0)
                    }
                    if !state.lastAlternatives.isEmpty {
                        Text("Alternatives: " + state.lastAlternatives.joined(separator: " • "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var examplesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try these in any app")
                .font(.subheadline.weight(.semibold))
            ExampleRow(input: "tdrh.", output: "the dog ran home.")
            ExampleRow(input: "thdorah.", output: "the dog ran home.")
            ExampleRow(input: "tdranhome.", output: "the dog ran home.")
            ExampleRow(input: "iwgotosch.", output: "I want to go to school.")
            ExampleRow(input: "thedogranhome.", output: "the dog ran home.")
            Text("Mix as much or as little detail as you want — more letters = more accurate expansion. Press “.” to expand. Normal sentences with spaces stay untouched.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ExampleRow: View {
    let input: String
    let output: String
    var body: some View {
        HStack(spacing: 8) {
            Text(input)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
            Text(output).font(.caption).foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }
}
