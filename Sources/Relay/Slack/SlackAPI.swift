import Foundation

enum SlackAPIError: Error, CustomStringConvertible {
    case http(Int)
    case notOK(String)
    case decode(String)

    var description: String {
        switch self {
        case .http(let code): return "http \(code)"
        case .notOK(let s): return "slack error: \(s)"
        case .decode(let s): return "decode: \(s)"
        }
    }
}

private struct SlackStatus: Decodable {
    let ok: Bool
    let error: String?
}

enum SlackAPI {
    private static let session = URLSession(configuration: .default)
    private static let base = URL(string: "https://slack.com/api/")!

    struct AuthTestResponse: Decodable {
        let userID: String
        let user: String
        let teamID: String

        private enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case user
            case teamID = "team_id"
        }
    }

    struct UserInfo: Decodable, Identifiable, Equatable {
        let id: String
        let realName: String?
        let displayName: String?
        let name: String
        let isBot: Bool
        let isAppUser: Bool
        let deleted: Bool

        var bestName: String {
            if let dn = displayName, !dn.isEmpty { return dn }
            if let rn = realName, !rn.isEmpty { return rn }
            return name
        }

        private enum CodingKeys: String, CodingKey {
            case id, name, deleted
            case realName = "real_name"
            case profileWrapper = "profile"
            case isBot = "is_bot"
            case isAppUser = "is_app_user"
        }

        private struct Profile: Decodable {
            let displayName: String?
            private enum CodingKeys: String, CodingKey { case displayName = "display_name" }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            realName = try c.decodeIfPresent(String.self, forKey: .realName)
            let profile = try c.decodeIfPresent(Profile.self, forKey: .profileWrapper)
            displayName = profile?.displayName
            isBot = try c.decodeIfPresent(Bool.self, forKey: .isBot) ?? false
            isAppUser = try c.decodeIfPresent(Bool.self, forKey: .isAppUser) ?? false
            deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        }
    }

    struct UsersListResponse {
        let members: [UserInfo]
        let nextCursor: String
    }

    struct ChannelInfo: Decodable, Identifiable, Equatable {
        let id: String
        let name: String?
        let isIM: Bool?
        let isMPIM: Bool?
        let isPrivate: Bool?
        let isMember: Bool?
        let user: String?

        private enum CodingKeys: String, CodingKey {
            case id, name, user
            case isIM = "is_im"
            case isMPIM = "is_mpim"
            case isPrivate = "is_private"
            case isMember = "is_member"
        }
    }

    struct ConversationsListResponse {
        let channels: [ChannelInfo]
        let nextCursor: String
    }

    static func authTest(token: String) async throws -> AuthTestResponse {
        try await call(method: "auth.test", token: token, payload: AuthTestResponse.self) { _ in }
    }

    static func userInfo(id: String, token: String) async throws -> UserInfo {
        struct Wrapper: Decodable { let user: UserInfo }
        let w = try await call(method: "users.info", token: token, payload: Wrapper.self) { items in
            items.append(URLQueryItem(name: "user", value: id))
        }
        return w.user
    }

    static func conversationInfo(id: String, token: String) async throws -> ChannelInfo {
        struct Wrapper: Decodable { let channel: ChannelInfo }
        let w = try await call(method: "conversations.info", token: token, payload: Wrapper.self) { items in
            items.append(URLQueryItem(name: "channel", value: id))
        }
        return w.channel
    }

    static func usersList(token: String, cursor: String? = nil, limit: Int = 200) async throws -> UsersListResponse {
        struct Wrapper: Decodable {
            let members: [UserInfo]
            let responseMetadata: Meta?
            struct Meta: Decodable {
                let nextCursor: String?
                private enum CodingKeys: String, CodingKey { case nextCursor = "next_cursor" }
            }
            private enum CodingKeys: String, CodingKey {
                case members
                case responseMetadata = "response_metadata"
            }
        }
        let w = try await call(method: "users.list", token: token, payload: Wrapper.self) { items in
            items.append(URLQueryItem(name: "limit", value: String(limit)))
            if let cursor, !cursor.isEmpty {
                items.append(URLQueryItem(name: "cursor", value: cursor))
            }
        }
        return UsersListResponse(members: w.members, nextCursor: w.responseMetadata?.nextCursor ?? "")
    }

    static func conversationsList(token: String, cursor: String? = nil, limit: Int = 200) async throws -> ConversationsListResponse {
        struct Wrapper: Decodable {
            let channels: [ChannelInfo]
            let responseMetadata: Meta?
            struct Meta: Decodable {
                let nextCursor: String?
                private enum CodingKeys: String, CodingKey { case nextCursor = "next_cursor" }
            }
            private enum CodingKeys: String, CodingKey {
                case channels
                case responseMetadata = "response_metadata"
            }
        }
        let w = try await call(method: "conversations.list", token: token, payload: Wrapper.self) { items in
            items.append(URLQueryItem(name: "types", value: "public_channel,private_channel,mpim"))
            items.append(URLQueryItem(name: "exclude_archived", value: "true"))
            items.append(URLQueryItem(name: "limit", value: String(limit)))
            if let cursor, !cursor.isEmpty {
                items.append(URLQueryItem(name: "cursor", value: cursor))
            }
        }
        return ConversationsListResponse(channels: w.channels, nextCursor: w.responseMetadata?.nextCursor ?? "")
    }

    struct PostMessageResponse: Decodable {
        let channel: String?
        let ts: String?
    }

    static func chatPostMessage(token: String, channel: String, text: String, threadTS: String?) async throws -> PostMessageResponse {
        try await call(method: "chat.postMessage", token: token, payload: PostMessageResponse.self) { items in
            items.append(URLQueryItem(name: "channel", value: channel))
            items.append(URLQueryItem(name: "text", value: text))
            if let threadTS {
                items.append(URLQueryItem(name: "thread_ts", value: threadTS))
            }
        }
    }

    private static func call<T: Decodable>(
        method: String,
        token: String,
        payload _: T.Type,
        addParams: (inout [URLQueryItem]) -> Void
    ) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(method))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        var items: [URLQueryItem] = []
        addParams(&items)
        var components = URLComponents()
        components.queryItems = items
        req.httpBody = components.percentEncodedQuery?.data(using: .utf8) ?? Data()

        let (data, resp) = try await session.data(for: req)
        if let h = resp as? HTTPURLResponse, h.statusCode != 200 {
            throw SlackAPIError.http(h.statusCode)
        }
        let status: SlackStatus
        do {
            status = try JSONDecoder().decode(SlackStatus.self, from: data)
        } catch {
            throw SlackAPIError.decode(String(describing: error))
        }
        guard status.ok else {
            throw SlackAPIError.notOK(status.error ?? "unknown")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SlackAPIError.decode(String(describing: error))
        }
    }
}
