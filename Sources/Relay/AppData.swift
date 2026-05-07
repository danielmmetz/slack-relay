import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AppData {
    var watchedChannelsText: String { didSet { save() } }
    var watchedUsersText: String { didSet { save() } }
    var skipOwnMessages: Bool { didSet { save() } }
    var routingTokens: RoutingTokens { didSet { save() } }
    var lastSeenTwilioDate: Date? { didSet { save() } }

    var watchedChannelIDs: Set<String> { Self.parseIDs(watchedChannelsText) }
    var watchedUserIDs: Set<String> { Self.parseIDs(watchedUsersText) }

    private let url: URL
    private static let logger = Logger(subsystem: "com.danielmmetz.relay", category: "appdata")

    init() {
        url = Self.stateFileURL()
        let snapshot = Self.load(url: url)
        watchedChannelsText = snapshot.watchedChannelsText
        watchedUsersText = snapshot.watchedUsersText
        skipOwnMessages = snapshot.skipOwnMessages
        routingTokens = snapshot.routingTokens
        lastSeenTwilioDate = snapshot.lastSeenTwilioDate
    }

    private struct Snapshot: Codable {
        var watchedChannelsText: String = ""
        var watchedUsersText: String = ""
        var skipOwnMessages: Bool = true
        var routingTokens: RoutingTokens = RoutingTokens()
        var lastSeenTwilioDate: Date? = nil

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            watchedChannelsText = try c.decodeIfPresent(String.self, forKey: .watchedChannelsText) ?? ""
            watchedUsersText = try c.decodeIfPresent(String.self, forKey: .watchedUsersText) ?? ""
            skipOwnMessages = try c.decodeIfPresent(Bool.self, forKey: .skipOwnMessages) ?? true
            routingTokens = try c.decodeIfPresent(RoutingTokens.self, forKey: .routingTokens) ?? RoutingTokens()
            lastSeenTwilioDate = try c.decodeIfPresent(Date.self, forKey: .lastSeenTwilioDate)
        }

        private enum CodingKeys: String, CodingKey {
            case watchedChannelsText, watchedUsersText, skipOwnMessages, routingTokens, lastSeenTwilioDate
        }
    }

    private static func parseIDs(_ text: String) -> Set<String> {
        Set(
            text.split(whereSeparator: { $0.isNewline || $0 == "," })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }

    private func save() {
        var snapshot = Snapshot()
        snapshot.watchedChannelsText = watchedChannelsText
        snapshot.watchedUsersText = watchedUsersText
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
