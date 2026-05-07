import Foundation
import OSLog

enum SlackError: Error, CustomStringConvertible {
    case openingConnection(String)
    case disconnected(String)
    case http(Int)

    var description: String {
        switch self {
        case .openingConnection(let s): return "opening connection: \(s)"
        case .disconnected(let s): return "disconnected: \(s)"
        case .http(let code): return "http \(code)"
        }
    }
}

@MainActor
final class SlackClient {
    var onMessage: ((SlackEvent) -> Void)?

    private let appState: AppState
    private let credentials: Credentials

    private let session = URLSession(configuration: .default)
    private let logger = Logger(subsystem: "com.danielmmetz.relay", category: "slack")

    private var loopTask: Task<Void, Never>?
    private var ws: URLSessionWebSocketTask?
    private var reconnectAttempt: Int = 0

    init(appState: AppState, credentials: Credentials) {
        self.appState = appState
        self.credentials = credentials
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() async {
        loopTask?.cancel()
        ws?.cancel(with: .goingAway, reason: nil)
        ws = nil
        if let t = loopTask { _ = await t.value }
        loopTask = nil
        appState.slackConnected = false
    }

    private func runLoop() async {
        while !Task.isCancelled {
            let appToken = credentials.slackAppToken
            let botToken = credentials.slackBotToken

            if appState.paused || appToken.isEmpty || botToken.isEmpty {
                appState.slackConnected = false
                if (try? await Task.sleep(for: .seconds(5))) == nil { break }
                continue
            }

            await resolveSelfUserIDIfNeeded()

            do {
                let url = try await openConnection(appToken: appToken)
                try await pump(url: url)
                reconnectAttempt = 0
            } catch is CancellationError {
                break
            } catch {
                logger.error("loop: \(String(describing: error), privacy: .public)")
            }

            appState.slackConnected = false
            ws = nil

            let delay = min(60, 1 << min(reconnectAttempt, 6))
            reconnectAttempt += 1
            if (try? await Task.sleep(for: .seconds(delay))) == nil { break }
        }
        appState.slackConnected = false
    }

    private func resolveSelfUserIDIfNeeded() async {
        guard appState.selfUserID == nil else { return }
        let userToken = credentials.slackUserToken
        guard !userToken.isEmpty else { return }
        do {
            let info = try await SlackAPI.authTest(token: userToken)
            appState.selfUserID = info.userID
            logger.info("self user_id=\(info.userID, privacy: .public)")
        } catch {
            logger.error("auth.test: \(String(describing: error), privacy: .public)")
        }
    }

    private func openConnection(appToken: String) async throws -> URL {
        guard let endpoint = URL(string: "https://slack.com/api/apps.connections.open") else {
            throw SlackError.openingConnection("bad endpoint url")
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await session.data(for: req)
        if let h = resp as? HTTPURLResponse, h.statusCode != 200 {
            throw SlackError.http(h.statusCode)
        }
        struct Resp: Decodable { let ok: Bool; let url: String?; let error: String? }
        let r = try JSONDecoder().decode(Resp.self, from: data)
        guard r.ok, let s = r.url, let u = URL(string: s) else {
            throw SlackError.openingConnection(r.error ?? "unknown")
        }
        return u
    }

    private func pump(url: URL) async throws {
        let task = session.webSocketTask(with: url)
        ws = task
        task.resume()
        while !Task.isCancelled {
            let frame = try await task.receive()
            try await handle(frame: frame)
        }
    }

    private func handle(frame: URLSessionWebSocketTask.Message) async throws {
        let data: Data
        switch frame {
        case .string(let s): data = Data(s.utf8)
        case .data(let d): data = d
        @unknown default: return
        }

        let env = try JSONDecoder().decode(SlackEnvelope.self, from: data)

        switch env.type {
        case "hello":
            logger.info("hello")
            appState.slackConnected = true
        case "events_api":
            if let id = env.envelopeID {
                try await ack(envelopeID: id)
            }
            if let ev = env.payload?.event, ev.type == "message" {
                logger.info(
                    "msg ch=\(ev.channel ?? "?", privacy: .public) ts=\(ev.ts ?? "?", privacy: .public) thread=\(ev.threadTS ?? "-", privacy: .public) sub=\(ev.subtype ?? "-", privacy: .public) text=\(ev.text ?? "", privacy: .public)"
                )
                onMessage?(ev)
            }
        case "disconnect":
            throw SlackError.disconnected(env.reason ?? "")
        default:
            logger.debug("type=\(env.type, privacy: .public)")
        }
    }

    private func ack(envelopeID: String) async throws {
        guard let task = ws else { return }
        let payload = ["envelope_id": envelopeID]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try await task.send(.data(data))
    }
}
