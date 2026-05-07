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

    struct UserInfo: Decodable {
        let id: String
        let realName: String?
        let displayName: String?
        let name: String

        private enum CodingKeys: String, CodingKey {
            case id, name
            case realName = "real_name"
            case profileWrapper = "profile"
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
        }
    }

    struct ChannelInfo: Decodable {
        let id: String
        let name: String?
        let isIM: Bool?
        let user: String?

        private enum CodingKeys: String, CodingKey {
            case id, name, user
            case isIM = "is_im"
        }
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
