import AppKit
import SwiftUI

/// Borderless, non-activating floating panel that hovers next to the
/// user's caret. Doesn't steal focus from whatever app they're typing in.
///
/// Two states:
///   • `.expanding(compressed)` — shown while AI is in flight.
///   • `.expanded(picked, alternatives, ...)` — after a successful
///     expansion. The user can click an alternative to swap, or Undo
///     to revert to the original compressed token + period.
@MainActor
final class SuggestionPanel {

    private let panel: NSPanel
    private let host: NSHostingController<PanelRoot>

    init() {
        let initial = PanelRoot(state: .idle)
        let host = NSHostingController(rootView: initial)
        host.view.frame = NSRect(x: 0, y: 0, width: 380, height: 60)
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

    func showExpanding(at topLeft: NSPoint, compressed: String) {
        host.rootView = PanelRoot(state: .expanding(compressed: compressed))
        let h: CGFloat = 44
        let size = NSSize(width: 380, height: h)
        panel.setContentSize(size)
        panel.setFrameTopLeftPoint(topLeft)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            panel.animator().alphaValue = 1
        }
    }

    func showExpanded(at topLeft: NSPoint,
                      picked: String,
                      alternatives: [String],
                      onSwap: @escaping (String) -> Void,
                      onUndo: @escaping () -> Void) {
        host.rootView = PanelRoot(state: .expanded(
            picked: picked,
            alternatives: Array(alternatives.prefix(3)),
            onSwap: onSwap,
            onUndo: onUndo
        ))
        let rowCount = min(3, alternatives.count)
        let h: CGFloat = CGFloat(rowCount) * 28 + 76
        let size = NSSize(width: 380, height: h)
        panel.setContentSize(size)
        panel.setFrameTopLeftPoint(topLeft)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            panel.animator().alphaValue = 1
        }
    }

    /// Low-confidence: AI returned a guess but Lazily didn't touch the
    /// user's text. Panel offers "Did you mean…" with up-to-3 picks.
    /// Pressing 1/2/3 applies the corresponding pick; clicking does too.
    func showSuggestion(at topLeft: NSPoint,
                        compressed: String,
                        candidates: [String],
                        onPick: @escaping (Int) -> Void,
                        onDismiss: @escaping () -> Void) {
        host.rootView = PanelRoot(state: .suggesting(
            compressed: compressed,
            candidates: Array(candidates.prefix(3)),
            onPick: onPick,
            onDismiss: onDismiss
        ))
        let rowCount = min(3, candidates.count)
        let h: CGFloat = CGFloat(rowCount) * 28 + 56
        let size = NSSize(width: 380, height: h)
        panel.setContentSize(size)
        panel.setFrameTopLeftPoint(topLeft)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            panel.animator().alphaValue = 1
        }
    }

    func showError(at topLeft: NSPoint, message: String) {
        host.rootView = PanelRoot(state: .error(message: message))
        let size = NSSize(width: 380, height: 56)
        panel.setContentSize(size)
        panel.setFrameTopLeftPoint(topLeft)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        panel.orderOut(nil)
        panel.alphaValue = 0
    }
}

// MARK: - SwiftUI content

private enum PanelState {
    case idle
    case expanding(compressed: String)
    case expanded(picked: String,
                  alternatives: [String],
                  onSwap: (String) -> Void,
                  onUndo: () -> Void)
    case suggesting(compressed: String,
                    candidates: [String],
                    onPick: (Int) -> Void,
                    onDismiss: () -> Void)
    case error(message: String)
}

private struct PanelRoot: View {
    let state: PanelState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch state {
            case .idle:
                EmptyView()
            case .expanding(let compressed):
                ExpandingView(compressed: compressed)
            case .expanded(let picked, let alts, let onSwap, let onUndo):
                ExpandedView(picked: picked, alternatives: alts, onSwap: onSwap, onUndo: onUndo)
            case .suggesting(let compressed, let candidates, let onPick, let onDismiss):
                SuggestingView(compressed: compressed, candidates: candidates, onPick: onPick, onDismiss: onDismiss)
            case .error(let message):
                ErrorView(message: message)
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

private struct ExpandingView: View {
    let compressed: String
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).scaleEffect(0.7)
            Text("Expanding")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(compressed)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }
}

private struct ExpandedView: View {
    let picked: String
    let alternatives: [String]
    let onSwap: (String) -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text(picked)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Button(action: onUndo) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Undo")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            if !alternatives.isEmpty {
                Divider().padding(.vertical, 2)
                ForEach(Array(alternatives.prefix(3).enumerated()), id: \.offset) { idx, alt in
                    AlternativeRow(index: idx + 1, sentence: alt) {
                        onSwap(alt)
                    }
                }
            }
        }
    }
}

private struct AlternativeRow: View {
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

private struct SuggestingView: View {
    let compressed: String
    let candidates: [String]
    let onPick: (Int) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Did you mean")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(compressed)
                    .font(.system(.caption, design: .monospaced))
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            ForEach(Array(candidates.prefix(3).enumerated()), id: \.offset) { idx, c in
                AlternativeRow(index: idx + 1, sentence: c) {
                    onPick(idx)
                }
            }
        }
    }
}

private struct ErrorView: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
