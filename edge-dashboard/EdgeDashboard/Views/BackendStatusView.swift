import SwiftUI

struct BackendStatusView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let model = model.health {
                Text("MiniMax: \(model.aiAvailable ? "ready" : "off")")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let err = model.healthError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                Task { await model.refreshHealth() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh backend status")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        if model.healthError != nil { return .red }
        if model.health != nil { return .green }
        return .gray
    }

    private var statusLabel: String {
        if model.healthError != nil { return "Backend unreachable" }
        if let h = model.health { return "Backend up · \(h.aiModel)" }
        return "Checking…"
    }
}
