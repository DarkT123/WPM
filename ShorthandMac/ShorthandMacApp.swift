import SwiftUI

@main
struct LazilyApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("Lazily") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 460, minHeight: 540)
                .onAppear { state.refreshAccessibility() }
        }
        .windowResizability(.contentSize)
    }
}
