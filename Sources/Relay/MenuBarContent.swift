import SwiftUI

struct MenuBarContent: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        Text(appState.statusLine)
        Divider()
        Toggle("Paused", isOn: $appState.paused)
        Divider()
        SettingsLink {
            Text("Open Settings…")
        }
        Divider()
        Button("Quit Relay") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
