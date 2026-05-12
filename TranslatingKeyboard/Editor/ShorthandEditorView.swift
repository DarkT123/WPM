import SwiftUI

struct ShorthandEditorView: View {
    @StateObject private var viewModel: EditorViewModel

    init(expander: SentenceExpander) {
        _viewModel = StateObject(wrappedValue: EditorViewModel(expander: expander))
    }

    var body: some View {
        VStack(spacing: 0) {
            ShorthandTextView(text: $viewModel.text, viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemBackground))

            Divider()
            footer
        }
        .navigationTitle("Editor")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let last = viewModel.lastExpansion {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Latest expansion")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(last.sentence)
                            .font(.callout.monospaced())
                            .lineLimit(2)
                            .truncationMode(.tail)
                        Text("Confidence \(Int((last.confidence * 100).rounded()))% · \(last.tokens.joined(separator: "·"))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if viewModel.hasPendingCorrection {
                        Button("Save edit") {
                            viewModel.commitPendingCorrection()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } else {
                Text("Type the first 1–2 letters of each word with no spaces, then press “.” to expand. Normal sentences pass through unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemBackground))
    }
}
