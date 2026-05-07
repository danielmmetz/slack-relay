import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class SlackDirectory {
    private(set) var channels: [SlackAPI.ChannelInfo] = []
    private(set) var loadingChannels: Bool = false
    private(set) var channelsError: String? = nil

    private(set) var users: [SlackAPI.UserInfo] = []
    private(set) var loadingUsers: Bool = false
    private(set) var usersError: String? = nil

    private let credentials: Credentials
    private let logger = Logger(subsystem: "com.danielmmetz.relay", category: "directory")

    init(credentials: Credentials) {
        self.credentials = credentials
    }

    func refreshChannels() async {
        let token = credentials.slackBotToken
        guard !token.isEmpty else {
            channelsError = "bot token not configured"
            return
        }
        loadingChannels = true
        channelsError = nil
        defer { loadingChannels = false }
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
            channelsError = String(describing: error)
            logger.error("channels refresh: \(String(describing: error), privacy: .public)")
        }
    }

    func refreshUsers() async {
        let token = credentials.slackBotToken
        guard !token.isEmpty else {
            usersError = "bot token not configured"
            return
        }
        loadingUsers = true
        usersError = nil
        defer { loadingUsers = false }
        do {
            var collected: [SlackAPI.UserInfo] = []
            var cursor: String? = nil
            repeat {
                let page = try await SlackAPI.usersList(token: token, cursor: cursor)
                collected.append(contentsOf: page.members.filter { isVisible($0) })
                cursor = page.nextCursor
                if collected.count >= 5000 { break }
            } while cursor?.isEmpty == false
            users = collected.sorted { $0.bestName.localizedCaseInsensitiveCompare($1.bestName) == .orderedAscending }
        } catch {
            usersError = String(describing: error)
            logger.error("users refresh: \(String(describing: error), privacy: .public)")
        }
    }

    private func isVisible(_ user: SlackAPI.UserInfo) -> Bool {
        !user.isBot && !user.isAppUser && !user.deleted && user.id != "USLACKBOT"
    }
}
