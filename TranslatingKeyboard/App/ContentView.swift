import SwiftUI

struct ContentView: View {
    @State private var selected: Tab = .home

    enum Tab: Hashable { case home, editor, settings }

    var body: some View {
        TabView(selection: $selected) {
            NavigationStack {
                HomeView(
                    onOpenEditor: { selected = .editor },
                    onOpenSettings: { selected = .settings }
                )
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(Tab.home)

            NavigationStack {
                ShorthandEditorView(expander: AppServices.shared.expander)
            }
            .tabItem { Label("Try it", systemImage: "text.cursor") }
            .tag(Tab.editor)

            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemImage: "gear") }
            .tag(Tab.settings)
        }
    }
}
