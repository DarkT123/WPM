import SwiftUI

@main
struct EdgeDashboardApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .frame(minWidth: 820, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
    }
}
