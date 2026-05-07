import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ConnectionsTab()
                .tabItem { Label("Connections", systemImage: "link") }
            ChannelsTab()
                .tabItem { Label("Channels", systemImage: "number") }
            BehaviorTab()
                .tabItem { Label("Behavior", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 560, height: 440)
    }
}

private struct ConnectionsTab: View {
    var body: some View {
        Form {
            Section("Twilio") {
                Text("Not configured").foregroundStyle(.secondary)
            }
            Section("Slack") {
                Text("Not configured").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ChannelsTab: View {
    var body: some View {
        ContentUnavailableView(
            "Connect Slack to load channels",
            systemImage: "number",
            description: Text("Configure Slack tokens in the Connections tab.")
        )
    }
}

private struct BehaviorTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Toggle("Paused", isOn: $appState.paused)
        }
        .formStyle(.grouped)
    }
}
