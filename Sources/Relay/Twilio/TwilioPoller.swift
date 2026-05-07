import Foundation
import OSLog

struct InboundSMS {
    let sid: String
    let from: String
    let body: String
    let dateSent: Date
}

@MainActor
final class TwilioPoller {
    var onInbound: ((InboundSMS) -> Void)?

    private let appState: AppState
    private let appData: AppData
    private let credentials: Credentials

    private let session = URLSession(configuration: .default)
    private let logger = Logger(subsystem: "com.danielmmetz.relay", category: "twilio.poll")

    private var loopTask: Task<Void, Never>?
    private var seenSIDs: [String] = []
    private static let seenCapacity = 200
    private static let pollInterval: TimeInterval = 30

    init(appState: AppState, appData: AppData, credentials: Credentials) {
        self.appState = appState
        self.appData = appData
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
        if let t = loopTask { _ = await t.value }
        loopTask = nil
    }

    private func runLoop() async {
        if appData.lastSeenTwilioDate == nil {
            appData.lastSeenTwilioDate = Date()
        }
        while !Task.isCancelled {
            let configured = !credentials.twilioAccountSID.isEmpty
                && !credentials.twilioAuthToken.isEmpty
                && !credentials.twilioToPhone.isEmpty

            if appState.paused || !configured {
                if (try? await Task.sleep(for: .seconds(5))) == nil { break }
                continue
            }

            do {
                let messages = try await fetchRecent()
                let cursor = appData.lastSeenTwilioDate ?? .distantPast
                var newest = cursor
                let inbound = messages
                    .filter { $0.dateSent > cursor }
                    .filter { !seenSIDs.contains($0.sid) }
                    .sorted { $0.dateSent < $1.dateSent }

                for sms in inbound {
                    rememberSID(sms.sid)
                    onInbound?(sms)
                    if sms.dateSent > newest { newest = sms.dateSent }
                }
                if newest > cursor { appData.lastSeenTwilioDate = newest }

                appState.twilioLastPollAt = Date()
                appState.twilioLastPollOk = true
            } catch {
                logger.error("poll: \(String(describing: error), privacy: .public)")
                appState.twilioLastPollOk = false
            }

            if (try? await Task.sleep(for: .seconds(Self.pollInterval))) == nil { break }
        }
    }

    private func rememberSID(_ sid: String) {
        seenSIDs.append(sid)
        if seenSIDs.count > Self.seenCapacity {
            seenSIDs.removeFirst(seenSIDs.count - Self.seenCapacity)
        }
    }

    private func fetchRecent() async throws -> [InboundSMS] {
        let sid = credentials.twilioAccountSID
        let token = credentials.twilioAuthToken
        let to = credentials.twilioToPhone

        var components = URLComponents(string: "https://api.twilio.com/2010-04-01/Accounts/\(sid)/Messages.json")!
        components.queryItems = [
            URLQueryItem(name: "To", value: to),
            URLQueryItem(name: "PageSize", value: "50"),
        ]
        guard let url = components.url else {
            throw TwilioError.badEndpoint
        }
        var req = URLRequest(url: url)
        let basic = Data("\(sid):\(token)".utf8).base64EncodedString()
        req.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await session.data(for: req)
        if let h = resp as? HTTPURLResponse, h.statusCode != 200 {
            throw TwilioError.http(h.statusCode, String(decoding: data, as: UTF8.self))
        }
        return try Self.decodeMessages(data)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    private static func decodeMessages(_ data: Data) throws -> [InboundSMS] {
        struct Wire: Decodable {
            let messages: [Message]
        }
        struct Message: Decodable {
            let sid: String
            let from: String
            let direction: String
            let body: String?
            let date_sent: String?
        }
        let wire = try JSONDecoder().decode(Wire.self, from: data)
        return wire.messages.compactMap { m in
            guard m.direction.hasPrefix("inbound") else { return nil }
            guard let dateString = m.date_sent, let date = dateFormatter.date(from: dateString) else { return nil }
            return InboundSMS(sid: m.sid, from: m.from, body: m.body ?? "", dateSent: date)
        }
    }
}
