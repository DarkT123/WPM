import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = SharedDefaults.shared.apiKey ?? ""
    @State private var isKeyVisible: Bool = false
    @State private var showKeySaved: Bool = false

    var body: some View {
        Form {
            Section("Keyboard Status") {
                KeyboardSetupStatusRow()
            }

            Section {
                Text("AI mode is not enabled yet. The current build uses an on-device dictionary and bigram model to expand shorthand. When AI mode ships, your saved key will be used to refine low-confidence expansions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    if isKeyVisible {
                        TextField("sk-ant-api...", text: $apiKey)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField("Enter Claude API Key (optional, reserved for AI mode)", text: $apiKey)
                            .font(.system(.body, design: .monospaced))
                    }

                    Button {
                        isKeyVisible.toggle()
                    } label: {
                        Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button("Save API Key") {
                    SharedDefaults.shared.apiKey = apiKey.isEmpty ? nil : apiKey
                    SharedDefaults.shared.synchronize()
                    showKeySaved = true
                }
                .disabled(apiKey.isEmpty && SharedDefaults.shared.apiKey == nil)

                if showKeySaved {
                    Label("Saved to Keychain", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } header: {
                Text("Claude API Key")
            } footer: {
                Text("Stored in the iOS Keychain. Get a key at console.anthropic.com.")
                    .font(.caption)
            }

            Section {
                Text("Type shorthand using the first 1–2 letters of each word with no spaces, end with “.”. Single-letter words “i” and “a” are handled automatically.")
                    .font(.footnote)
                Text("Example: thdoraho. → the dog ran home")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            } header: {
                Text("How shorthand works")
            }
        }
        .onChange(of: apiKey) {
            showKeySaved = false
        }
    }
}
