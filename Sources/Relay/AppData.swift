import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AppData {
    var watchedChannelIDs: Set<String> { didSet { save() } }
    var watchedUserIDs: Set<String> { didSet { save() } }
    var skipOwnMessages: Bool { didSet { save() } }
    var routingTokens: RoutingTokens { didSet { save() } }
    var lastSeenTwilioDate: Date? { didSet { save() } }

    private let url: URL
    private static let logger = Logger(subsystem: "com.danielmmetz.relay", category: "appdata")

    init() {
        url = Self.stateFileURL()
        let snapshot = Self.load(url: url)
        watchedChannelIDs = snapshot.watchedChannelIDs
        watchedUserIDs = snapshot.watchedUserIDs
        skipOwnMessages = snapshot.skipOwnMessages
        routingTokens = snapshot.routingTokens
        lastSeenTwilioDate = snapshot.lastSeenTwilioDate
    }

    private struct Snapshot: Codable {
        var watchedChannelIDs: Set<String> = []
        var watchedUserIDs: Set<String> = []
        var skipOwnMessages: Bool = true
        var routingTokens: RoutingTokens = RoutingTokens()
        var lastSeenTwilioDate: Date? = nil

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let ids = try c.decodeIfPresent(Set<String>.self, forKey: .watchedChannelIDs) {
                watchedChannelIDs = ids
            } else if let text = try c.decodeIfPresent(String.self, forKey: .watchedChannelsText) {
                watchedChannelIDs = AppData.parseIDs(text)
            } else {
                watchedChannelIDs = []
            }
            if let ids = try c.decodeIfPresent(Set<String>.self, forKey: .watchedUserIDs) {
                watchedUserIDs = ids
            } else if let text = try c.decodeIfPresent(String.self, forKey: .watchedUsersText) {
                watchedUserIDs = AppData.parseIDs(text)
            } else {
                watchedUserIDs = []
            }
            skipOwnMessages = try c.decodeIfPresent(Bool.self, forKey: .skipOwnMessages) ?? true
            routingTokens = try c.decodeIfPresent(RoutingTokens.self, forKey: .routingTokens) ?? RoutingTokens()
            lastSeenTwilioDate = try c.decodeIfPresent(Date.self, forKey: .lastSeenTwilioDate)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(watchedChannelIDs, forKey: .watchedChannelIDs)
            try c.encode(watchedUserIDs, forKey: .watchedUserIDs)
            try c.encode(skipOwnMessages, forKey: .skipOwnMessages)
            try c.encode(routingTokens, forKey: .routingTokens)
            try c.encodeIfPresent(lastSeenTwilioDate, forKey: .lastSeenTwilioDate)
        }

        private enum CodingKeys: String, CodingKey {
            case watchedChannelIDs, watchedChannelsText
            case watchedUserIDs, watchedUsersText
            case skipOwnMessages, routingTokens, lastSeenTwilioDate
        }
    }

    nonisolated fileprivate static func parseIDs(_ text: String) -> Set<String> {
        Set(
            text.split(whereSeparator: { $0.isNewline || $0 == "," })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }

    private func save() {
        var snapshot = Snapshot()
        snapshot.watchedChannelIDs = watchedChannelIDs
        snapshot.watchedUserIDs = watchedUserIDs
        snapshot.skipOwnMessages = skipOwnMessages
        snapshot.routingTokens = routingTokens
        snapshot.lastSeenTwilioDate = lastSeenTwilioDate
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            Self.logger.error("saving \(self.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(url: URL) -> Snapshot {
        guard let data = try? Data(contentsOf: url) else { return Snapshot() }
        do {
            return try JSONDecoder().decode(Snapshot.self, from: data)
        } catch {
            logger.error("loading \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public); resetting")
            return Snapshot()
        }
    }

    private static func stateFileURL() -> URL {
        let bundle = Bundle.main.bundleIdentifier ?? "com.danielmmetz.relay"
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent(bundle, isDirectory: true).appendingPathComponent("state.json")
    }
}
