import SwiftUI

struct KeyboardSetupStatusRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "keyboard")
                    .foregroundStyle(.blue)
                Text("Translating Keyboard")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            Text("Add the keyboard in Settings → General → Keyboard → Keyboards. Allow Full Access is not required for shorthand expansion.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
