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
                styleNotesCard
                bufferCard
                examplesCard
            }
            .padding(20)
        }
        .frame(minWidth: 460, minHeight: 640)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Shorthand")
                .font(.title.weight(.semibold))
            Text("Type the first letter of each word with no spaces. A floating panel by your cursor shows 3 suggestions — click 1/2/3 to pick, or just type “.” to auto-apply #1.")
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
                     ? "Shorthand can read and rewrite keystrokes in any app."
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
                    Text(state.aiEnabled ? "MiniMax AI enabled" : "MiniMax AI disabled")
                        .font(.subheadline.weight(.semibold))
                    if state.aiInFlight {
                        ProgressView().controlSize(.small).scaleEffect(0.6)
                    }
                }
                Text(state.aiEnabled
                     ? "Local suggestions appear instantly; AI reranks them after ~250 ms of typing pause with proper capitalization, grammar, and context awareness."
                     : "Add MINIMAX_API_KEY to /Users/andyzhao/Translating\u{00A0}keyboard/.env, then quit and relaunch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var styleNotesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Style notes (fed to the AI as system prompt)")
                .font(.subheadline.weight(.semibold))
            Text("Example: \"casual tone, lowercase except proper nouns, use Oxford comma\".")
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
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

            if let s = state.lastShorthand, let e = state.lastExpansion {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars").font(.caption2).foregroundStyle(.green)
                    Text(s)
                        .font(.system(.caption, design: .monospaced))
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    Text(e).font(.caption)
                    Spacer(minLength: 0)
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
            ExampleRow(input: "iwtm.", output: "i want to make.")
            ExampleRow(input: "iwtmapmr.", output: "i want to make a prediction market research.")
            Text("As you type, the floating panel shows 3 candidates. Click 1, 2, or 3 to pick — or hit “.” to take #1 + a period.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
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
