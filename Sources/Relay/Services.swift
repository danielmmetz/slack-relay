import Foundation

@MainActor
final class Services {
    let slack: SlackClient

    init(appState: AppState, credentials: Credentials) {
        slack = SlackClient(appState: appState, credentials: credentials)
        slack.start()
    }
}
