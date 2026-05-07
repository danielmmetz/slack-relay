import SwiftUI

@main
struct RelayApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(appState)
        } label: {
            Image(systemName: appState.menuBarSymbolName)
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
