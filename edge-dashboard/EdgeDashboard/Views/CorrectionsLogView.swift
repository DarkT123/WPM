import SwiftUI

struct CorrectionsLogView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if model.corrections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No corrections taught this session.")
                        .foregroundStyle(.secondary)
                    Text("Submit one from Live predict, then it appears here.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.corrections) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(entry.domain.label)
                                .font(.caption2.monospaced())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.blue.opacity(0.15), in: Capsule())
                                .foregroundStyle(.blue)
                            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text(entry.compressed)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.tertiary)
                            Text(entry.corrected)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Corrections (\(model.corrections.count))")
    }
}
