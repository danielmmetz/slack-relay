import Foundation

@MainActor
@Observable
final class Services {
    let slack: SlackClient
    let twilio: TwilioClient

    init(appState: AppState, credentials: Credentials) {
        slack = SlackClient(appState: appState, credentials: credentials)
        twilio = TwilioClient(credentials: credentials)
        slack.start()
    }
}
