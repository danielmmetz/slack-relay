import Foundation

@MainActor
@Observable
final class Services {
    let slack: SlackClient
    let twilio: TwilioClient
    let names: SlackNameCache
    let router: Router

    init(appState: AppState, credentials: Credentials, appData: AppData) {
        let nameCache = SlackNameCache()
        let twilioClient = TwilioClient(credentials: credentials)
        let routerInstance = Router(
            appState: appState,
            appData: appData,
            credentials: credentials,
            twilio: twilioClient,
            names: nameCache
        )
        let slackClient = SlackClient(appState: appState, credentials: credentials)
        slackClient.onMessage = { [routerInstance] event in
            Task { await routerInstance.handle(event) }
        }

        names = nameCache
        twilio = twilioClient
        router = routerInstance
        slack = slackClient

        slack.start()
    }
}
