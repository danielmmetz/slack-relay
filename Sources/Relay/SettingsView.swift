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
    @Environment(Services.self) private var services

    @State private var twilioSending: Bool = false
    @State private var twilioStatus: String = ""
    @State private var twilioStatusOK: Bool = true

    var body: some View {
        @Bindable var c = credentials
        Form {
            Section("Twilio") {
                TextField("Account SID", text: $c.twilioAccountSID, prompt: Text("AC…"))
                SecureField("Auth Token", text: $c.twilioAuthToken)
                TextField("From number", text: $c.twilioFromNumber, prompt: Text("+14155551234"))
                TextField("Your phone", text: $c.twilioToPhone, prompt: Text("+14155555678"))
                HStack {
                    Button("Send test SMS") {
                        Task { await sendTestSMS() }
                    }
                    .disabled(twilioSending || !twilioReady(c))
                    if twilioSending {
                        ProgressView().controlSize(.small)
                    }
                    if !twilioStatus.isEmpty {
                        Text(twilioStatus)
                            .font(.caption)
                            .foregroundStyle(twilioStatusOK ? Color.secondary : Color.red)
                            .lineLimit(2)
                    }
                    Spacer()
                }
            }
            Section("Slack") {
                SecureField("App-level token", text: $c.slackAppToken, prompt: Text("xapp-…"))
                SecureField("Bot token", text: $c.slackBotToken, prompt: Text("xoxb-…"))
                SecureField("User token", text: $c.slackUserToken, prompt: Text("xoxp-…"))
                Button("Test Slack connection") {}.disabled(true)
            }
        }
        .formStyle(.grouped)
    }

    private func twilioReady(_ c: Credentials) -> Bool {
        !c.twilioAccountSID.isEmpty
            && !c.twilioAuthToken.isEmpty
            && !c.twilioFromNumber.isEmpty
            && !c.twilioToPhone.isEmpty
    }

    private func sendTestSMS() async {
        twilioSending = true
        twilioStatus = ""
        defer { twilioSending = false }
        do {
            let sid = try await services.twilio.sendSMS(body: "Test from Relay")
            twilioStatusOK = true
            twilioStatus = "sent: \(sid)"
        } catch {
            twilioStatusOK = false
            twilioStatus = String(describing: error)
        }
    }
}

private struct ChannelsTab: View {
    @Environment(AppData.self) private var appData

    var body: some View {
        @Bindable var d = appData
        Form {
            Section {
                TextField(
                    "Channel IDs (one per line, e.g. C0123456)",
                    text: $d.watchedChannelsText,
                    axis: .vertical
                )
                .lineLimit(4...10)
                .monospaced()
                .textFieldStyle(.roundedBorder)
            } header: {
                Text("Channels to forward")
            } footer: {
                Text("Root messages forward; thread replies forward only when they @mention you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField(
                    "User IDs (one per line, e.g. U0123456)",
                    text: $d.watchedUsersText,
                    axis: .vertical
                )
                .lineLimit(3...8)
                .monospaced()
                .textFieldStyle(.roundedBorder)
            } header: {
                Text("DMs from users")
            } footer: {
                Text("Get user IDs from a Slack profile → \"…\" → \"Copy member ID\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct BehaviorTab: View {
    @Environment(AppState.self) private var appState
    @Environment(AppData.self) private var appData

    var body: some View {
        @Bindable var appState = appState
        @Bindable var appData = appData
        Form {
            Section {
                Toggle("Paused", isOn: $appState.paused)
            } footer: {
                Text("When paused, Slack stays connected but no SMS is sent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Skip my own messages", isOn: $appData.skipOwnMessages)
            } footer: {
                Text("When on, messages you post in watched channels aren't forwarded. Turn off for testing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
