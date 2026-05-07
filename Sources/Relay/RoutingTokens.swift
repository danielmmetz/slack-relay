import Foundation

struct TokenEntry: Codable, Equatable {
    var token: Int
    var channelID: String
    var sourceTS: String
    var threadAnchor: String?
    var isDM: Bool
}

struct RoutingTokens: Codable, Equatable {
    static let counterMax = 1000
    static let maxEntries = 200

    var counter: Int = 0
    var lastToken: Int? = nil
    var entries: [TokenEntry] = []

    mutating func allocate(channelID: String, sourceTS: String, threadAnchor: String?, isDM: Bool) -> Int {
        let token = counter
        counter = (counter + 1) % Self.counterMax
        entries.removeAll { $0.token == token }
        entries.append(TokenEntry(
            token: token,
            channelID: channelID,
            sourceTS: sourceTS,
            threadAnchor: threadAnchor,
            isDM: isDM
        ))
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        lastToken = token
        return token
    }

    func entry(for token: Int) -> TokenEntry? {
        entries.first(where: { $0.token == token })
    }

    var last: TokenEntry? {
        guard let lastToken else { return nil }
        return entry(for: lastToken)
    }
}
