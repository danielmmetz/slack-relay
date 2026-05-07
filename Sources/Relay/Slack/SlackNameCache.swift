import Foundation
import OSLog

actor SlackNameCache {
    private var users: [String: Entry] = [:]
    private var channels: [String: Entry] = [:]
    private let ttl: TimeInterval = 3600

    private let logger = Logger(subsystem: "com.danielmmetz.relay", category: "names")

    private struct Entry {
        var value: String
        var fetchedAt: Date
    }

    func userName(id: String, token: String) async -> String {
        if let entry = users[id], Date().timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.value
        }
        do {
            let info = try await SlackAPI.userInfo(id: id, token: token)
            let name = (info.displayName?.isEmpty == false ? info.displayName : nil)
                ?? info.realName
                ?? info.name
            users[id] = Entry(value: name, fetchedAt: Date())
            return name
        } catch {
            logger.error("user \(id, privacy: .public): \(String(describing: error), privacy: .public)")
            return id
        }
    }

    func channelName(id: String, token: String) async -> String {
        if let entry = channels[id], Date().timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.value
        }
        do {
            let info = try await SlackAPI.conversationInfo(id: id, token: token)
            let name = info.name ?? id
            channels[id] = Entry(value: name, fetchedAt: Date())
            return name
        } catch {
            logger.error("channel \(id, privacy: .public): \(String(describing: error), privacy: .public)")
            return id
        }
    }
}
