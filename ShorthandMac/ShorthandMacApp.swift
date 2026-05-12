import SwiftUI

@main
struct ShorthandMacApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("Shorthand") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 460, minHeight: 540)
                .onAppear { state.refreshAccessibility() }
        }
        .windowResizability(.contentSize)
    }
}
