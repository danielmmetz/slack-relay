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
    @Environment(Credentials.self) private var credentials

    var body: some View {
        @Bindable var c = credentials
        Form {
            Section("Twilio") {
                LabeledContent("Account SID") {
                    TextField("AC…", text: $c.twilioAccountSID)
                }
                LabeledContent("Auth Token") {
                    SecureField("auth token", text: $c.twilioAuthToken)
                }
                LabeledContent("From number") {
                    TextField("+14155551234", text: $c.twilioFromNumber)
                }
                LabeledContent("Your phone") {
                    TextField("+14155555678", text: $c.twilioToPhone)
                }
                Button("Send test SMS") {}.disabled(true)
            }
            Section("Slack") {
                LabeledContent("App-level token") {
                    SecureField("xapp-…", text: $c.slackAppToken)
                }
                LabeledContent("Bot token") {
                    SecureField("xoxb-…", text: $c.slackBotToken)
                }
                LabeledContent("User token") {
                    SecureField("xoxp-…", text: $c.slackUserToken)
                }
                Button("Test Slack connection") {}.disabled(true)
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
