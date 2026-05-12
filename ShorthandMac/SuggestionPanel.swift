import AppKit
import SwiftUI

/// Borderless, non-activating floating panel that hovers next to the user's
/// caret. Doesn't steal focus from whatever app they're typing in. SwiftUI
/// `Button`s inside still receive clicks and fire their actions.
@MainActor
final class SuggestionPanel {

    private let panel: NSPanel
    private let host: NSHostingController<SuggestionsRoot>

    /// Last-snapshotted list. Updated by `show(at:suggestions:onPick:)`.
    private(set) var currentSuggestions: [String] = []

    init() {
        let initial = SuggestionsRoot(suggestions: [], onPick: { _ in })
        let host = NSHostingController(rootView: initial)
        host.view.frame = NSRect(x: 0, y: 0, width: 360, height: 120)
        self.host = host

        let panel = NSPanel(
            contentRect: host.view.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.contentViewController = host
        panel.alphaValue = 0
        self.panel = panel
    }

    func show(at topLeft: NSPoint, suggestions: [String], onPick: @escaping (Int) -> Void) {
        currentSuggestions = suggestions
        host.rootView = SuggestionsRoot(suggestions: suggestions, onPick: onPick)
        // Re-size to fit content (3 rows + chrome).
        let h: CGFloat = CGFloat(min(3, suggestions.count)) * 30 + 16
        let size = NSSize(width: 360, height: h)
        panel.setContentSize(size)
        panel.setFrameTopLeftPoint(topLeft)
        panel.orderFrontRegardless()
        // Fade in if it was hidden.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        currentSuggestions = []
        panel.orderOut(nil)
        panel.alphaValue = 0
    }
}

// MARK: - SwiftUI content

private struct SuggestionsRoot: View {
    let suggestions: [String]
    let onPick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(suggestions.prefix(3).enumerated()), id: \.offset) { idx, sentence in
                SuggestionRow(index: idx + 1, sentence: sentence) {
                    onPick(idx)
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
        )
    }
}

private struct SuggestionRow: View {
    let index: Int
    let sentence: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("\(index)")
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Color.gray.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                Text(sentence)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
