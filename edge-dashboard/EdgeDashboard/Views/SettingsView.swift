import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Backend") {
                TextField("Edge backend URL", text: $model.backendURLString)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Apply") {
                        model.applyBaseURL()
                        Task { await model.refreshHealth(); model.schedulePredict() }
                    }
                    Button("Test connection") {
                        Task { await model.refreshHealth() }
                    }
                }
                if let h = model.health {
                    LabeledContent("AI available", value: h.aiAvailable ? "yes" : "no")
                    LabeledContent("AI model", value: h.aiModel)
                    LabeledContent("AI timeout", value: "\(h.aiTimeoutMs) ms")
                }
                if let err = model.healthError {
                    Text(err).foregroundStyle(.red).font(.callout)
                }
            }

            Section("About") {
                Text("Edge Dashboard talks to the Edge backend at the URL above. The backend persists corrections to `backend/data/corrections.json` and optionally calls MiniMax for low-confidence reranking.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
