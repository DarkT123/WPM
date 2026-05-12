import SwiftUI

struct LivePredictView: View {
    @ObservedObject var model: AppModel
    @State private var editing: String = ""
    @State private var showCorrection: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Inputs
                GroupBox("Compressed input") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $model.compressed)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 48, maxHeight: 80)
                            .onChange(of: model.compressed) { _ in model.schedulePredict() }

                        HStack(spacing: 8) {
                            TextField("Context before (optional)", text: $model.contextBefore)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: model.contextBefore) { _ in model.schedulePredict() }
                            TextField("Context after (optional)", text: $model.contextAfter)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: model.contextAfter) { _ in model.schedulePredict() }
                        }

                        HStack {
                            DomainPicker(domain: $model.domain)
                                .frame(maxWidth: 180)
                                .onChange(of: model.domain) { _ in model.schedulePredict() }
                            Toggle("Use MiniMax AI", isOn: $model.useAI)
                                .onChange(of: model.useAI) { _ in model.schedulePredict() }
                                .disabled(model.health?.aiAvailable == false)
                            Spacer()
                            metricsBadge
                        }
                    }
                    .padding(8)
                }

                if let err = model.predictError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                // Prediction
                GroupBox("Prediction") {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.prediction.isEmpty {
                            Text("Start typing compressed tokens above.")
                                .foregroundStyle(.secondary)
                                .italic()
                                .padding(.vertical, 12)
                        } else {
                            Text(model.prediction)
                                .font(.system(.title2, design: .rounded).weight(.semibold))
                                .textSelection(.enabled)

                            // Per-word confidence row
                            FlowRow(spacing: 6) {
                                ForEach(Array(model.wordCandidates.enumerated()), id: \.offset) { _, wc in
                                    WordChip(wc: wc)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // AI completions (shown alongside the local prediction so the
                // user can compare both. Click-to-teach uses the same path as
                // alternatives, which records the correction and re-fetches.)
                if !model.aiSuggestions.isEmpty {
                    GroupBox("AI completions") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("From MiniMax — click to teach Edge.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(model.aiSuggestions, id: \.self) { suggestion in
                                Button {
                                    Task { await model.teach(corrected: suggestion) }
                                } label: {
                                    HStack {
                                        Text(suggestion)
                                            .font(.system(.body, design: .monospaced))
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                        Image(systemName: "sparkles")
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Alternatives
                if !model.alternatives.isEmpty {
                    GroupBox("Alternative sentences") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(model.alternatives, id: \.self) { alt in
                                Button {
                                    Task { await model.teach(corrected: alt) }
                                } label: {
                                    HStack {
                                        Text(alt)
                                            .font(.system(.body, design: .monospaced))
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                        Image(systemName: "checkmark.circle")
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Teach (manual correction)
                GroupBox("Teach Edge (manual correction)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type the correct sentence with one word per compressed token, then submit.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("e.g. i want to make a prediction market research app", text: $editing)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            Button("Submit correction") {
                                Task { await model.teach(corrected: editing); editing = "" }
                            }
                            .disabled(editing.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if let err = model.learnError {
                            Label(err, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    }
                    .padding(8)
                }
            }
            .padding(16)
        }
        .navigationTitle("Live predict")
    }

    private var metricsBadge: some View {
        HStack(spacing: 8) {
            if let s = model.source {
                Text(s.rawValue.uppercased())
                    .font(.caption.monospaced().bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(sourceColor(s).opacity(0.2), in: Capsule())
                    .foregroundStyle(sourceColor(s))
            }
            if let ms = model.latencyMs {
                Text("\(ms) ms")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if model.sentenceConfidence > 0 {
                Text("\(Int((model.sentenceConfidence * 100).rounded()))%")
                    .font(.caption.monospaced())
                    .foregroundStyle(.blue)
            }
        }
    }

    private func sourceColor(_ s: PredictionSource) -> Color {
        switch s {
        case .local, .phrase: return .green
        case .exact: return .teal
        case .ai: return .purple
        }
    }
}

// MARK: - WordChip

private struct WordChip: View {
    let wc: WordCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(wc.selected)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(color)
            Text("\(wc.token) · \(Int((wc.confidence * 100).rounded()))%")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        .help(wc.candidates.prefix(8).joined(separator: ", "))
    }

    private var color: Color {
        if wc.confidence >= 0.85 { return .green }
        if wc.confidence >= 0.65 { return .primary }
        return .orange
    }
}

// MARK: - FlowRow (simple flowing horizontal layout for the chips)

private struct FlowRow<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content
    init(spacing: CGFloat = 6, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }
    var body: some View {
        // Simple wrap using HStack inside ScrollView — for an MVP this is enough
        // and avoids a custom Layout. macOS 13+ doesn't have ViewThatFits with
        // Layout, so we fall back to a horizontally-scrolling HStack which still
        // reads nicely as a "confidence row" under the prediction.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) { content() }
        }
    }
}
