import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ConnectionsTab()
                .tabItem { Label("Connections", systemImage: "link") }
            ChannelsTab()
                .tabItem { Label("Channels", systemImage: "number") }
            DMsTab()
                .tabItem { Label("DMs", systemImage: "bubble.left.and.bubble.right") }
            BehaviorTab()
                .tabItem { Label("Behavior", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 560, height: 480)
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
    @Environment(Services.self) private var services

    @State private var search: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search channels", text: $search)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await services.directory.refreshChannels() }
                } label: {
                    if services.directory.loadingChannels {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(services.directory.loadingChannels)
            }
            .padding()

            if let err = services.directory.channelsError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            List {
                Section {
                    if services.directory.channels.isEmpty {
                        Text(emptyMessage)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(filteredChannels) { channel in
                            Toggle(isOn: bindingForChannel(channel.id)) {
                                ChannelRow(channel: channel)
                            }
                        }
                    }
                } header: {
                    Text("Channels the bot can see")
                } footer: {
                    Text("Root messages in checked channels forward to SMS. Thread replies forward only when they @mention you.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            }
        }
        .task {
            if services.directory.channels.isEmpty {
                await services.directory.refreshChannels()
            }
        }
    }

    private var filteredChannels: [SlackAPI.ChannelInfo] {
        let q = search.lowercased()
        if q.isEmpty { return services.directory.channels }
        return services.directory.channels.filter { ($0.name ?? "").lowercased().contains(q) }
    }

    private var emptyMessage: String {
        if services.directory.loadingChannels { return "Loading channels…" }
        return "No channels yet. Click refresh, or invite the bot into a channel and try again."
    }

    private func bindingForChannel(_ id: String) -> Binding<Bool> {
        Binding(
            get: { appData.watchedChannelIDs.contains(id) },
            set: { isOn in
                if isOn { appData.watchedChannelIDs.insert(id) }
                else { appData.watchedChannelIDs.remove(id) }
            }
        )
    }
}

private struct ChannelRow: View {
    let channel: SlackAPI.ChannelInfo

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(channel.name ?? channel.id)
        }
    }

    private var icon: String {
        if channel.isMPIM == true { return "person.2" }
        if channel.isPrivate == true { return "lock" }
        return "number"
    }
}

private struct DMsTab: View {
    @Environment(AppData.self) private var appData
    @Environment(Services.self) private var services

    @State private var search: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search users", text: $search)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await services.directory.refreshUsers() }
                } label: {
                    if services.directory.loadingUsers {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(services.directory.loadingUsers)
            }
            .padding()

            if let err = services.directory.usersError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            List {
                Section {
                    if services.directory.users.isEmpty {
                        Text(emptyMessage)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(filteredUsers) { user in
                            Toggle(isOn: bindingForUser(user.id)) {
                                UserRow(user: user)
                            }
                        }
                    }
                } header: {
                    Text("Forward DMs from")
                } footer: {
                    Text("DMs to you from checked users get SMS-forwarded. Bot must have im:history scope and the user must DM you (not the other way around) for events to flow.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            if services.directory.users.isEmpty {
                await services.directory.refreshUsers()
            }
        }
    }

    private var filteredUsers: [SlackAPI.UserInfo] {
        let q = search.lowercased()
        if q.isEmpty { return services.directory.users }
        return services.directory.users.filter {
            $0.bestName.lowercased().contains(q) || $0.name.lowercased().contains(q)
        }
    }

    private var emptyMessage: String {
        if services.directory.loadingUsers { return "Loading users…" }
        return "No users yet. Click refresh."
    }

    private func bindingForUser(_ id: String) -> Binding<Bool> {
        Binding(
            get: { appData.watchedUserIDs.contains(id) },
            set: { isOn in
                if isOn { appData.watchedUserIDs.insert(id) }
                else { appData.watchedUserIDs.remove(id) }
            }
        )
    }
}

private struct UserRow: View {
    let user: SlackAPI.UserInfo

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(user.bestName)
            if user.bestName != user.name {
                Text("@\(user.name)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
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
