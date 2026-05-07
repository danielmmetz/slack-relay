import SwiftUI

@main
struct RelayApp: App {
    @State private var appState: AppState
    @State private var credentials: Credentials
    @State private var appData: AppData
    @State private var services: Services

    init() {
        let appState = AppState()
        let credentials = Credentials()
        let appData = AppData()
        let services = Services(appState: appState, credentials: credentials, appData: appData)
        _appState = State(initialValue: appState)
        _credentials = State(initialValue: credentials)
        _appData = State(initialValue: appData)
        _services = State(initialValue: services)
    }

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
                .environment(credentials)
                .environment(appData)
                .environment(services)
        }
    }
}
