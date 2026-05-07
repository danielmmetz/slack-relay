import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class SlackDirectory {
    private(set) var channels: [SlackAPI.ChannelInfo] = []
    private(set) var loading: Bool = false
    private(set) var lastError: String? = nil

    private let credentials: Credentials
    private let logger = Logger(subsystem: "com.danielmmetz.relay", category: "directory")

    init(credentials: Credentials) {
        self.credentials = credentials
    }

    func refreshChannels() async {
        let token = credentials.slackBotToken
        guard !token.isEmpty else {
            lastError = "bot token not configured"
            return
        }
        loading = true
        lastError = nil
        defer { loading = false }
        do {
            var collected: [SlackAPI.ChannelInfo] = []
            var cursor: String? = nil
            repeat {
                let page = try await SlackAPI.conversationsList(token: token, cursor: cursor)
                collected.append(contentsOf: page.channels.filter { $0.isMember == true })
                cursor = page.nextCursor
                if collected.count >= 1000 { break }
            } while cursor?.isEmpty == false
            channels = collected.sorted { ($0.name ?? "") < ($1.name ?? "") }
        } catch {
            lastError = String(describing: error)
            logger.error("refresh: \(String(describing: error), privacy: .public)")
        }
    }
}
