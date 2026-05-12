import SwiftUI

enum DashboardSection: String, Hashable, CaseIterable, Identifiable {
    case livePredict, corrections, settings
    var id: String { rawValue }
    var label: String {
        switch self {
        case .livePredict: return "Live predict"
        case .corrections: return "Corrections"
        case .settings: return "Settings"
        }
    }
    var systemImage: String {
        switch self {
        case .livePredict: return "keyboard"
        case .corrections: return "clock.arrow.circlepath"
        case .settings: return "gear"
        }
    }
}

struct DashboardView: View {
    @StateObject private var model = AppModel()
    @State private var selection: DashboardSection? = .livePredict

    var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $selection) { s in
                NavigationLink(value: s) {
                    Label(s.label, systemImage: s.systemImage)
                }
            }
            .navigationTitle("Edge")
            .frame(minWidth: 180)
        } detail: {
            VStack(spacing: 0) {
                BackendStatusView(model: model)
                Divider()
                switch selection ?? .livePredict {
                case .livePredict: LivePredictView(model: model)
                case .corrections: CorrectionsLogView(model: model)
                case .settings:    SettingsView(model: model)
                }
            }
        }
        .task {
            await model.refreshHealth()
            model.schedulePredict()
        }
    }
}

#Preview {
    DashboardView()
}
