import Foundation
import OSLog

@MainActor
final class Router {
    private let appState: AppState
    private let appData: AppData
    private let credentials: Credentials
    private let twilio: TwilioClient
    private let names: SlackNameCache
    private let logger = Logger(subsystem: "com.danielmmetz.relay", category: "router")

    init(
        appState: AppState,
        appData: AppData,
        credentials: Credentials,
        twilio: TwilioClient,
        names: SlackNameCache
    ) {
        self.appState = appState
        self.appData = appData
        self.credentials = credentials
        self.twilio = twilio
        self.names = names
    }

    func handle(_ event: SlackEvent) async {
        if appState.paused { return }
        guard shouldForward(event) else { return }
        guard let channelID = event.channel, let sourceTS = event.ts else { return }

        let isDM = event.channelType == "im"
        let isThreadReply = event.threadTS != nil && event.threadTS != event.ts
        let token = appData.routingTokens.allocate(
            channelID: channelID,
            sourceTS: sourceTS,
            threadAnchor: isThreadReply ? event.threadTS : nil,
            isDM: isDM
        )

        let formatted = await format(event)
        let body = "\(formatted) [\(token)]"

        do {
            try await twilio.sendSMS(body: body)
        } catch {
            logger.error("forwarding: \(String(describing: error), privacy: .public)")
        }
    }

    func handleInbound(_ sms: InboundSMS) async {
        if appState.paused { return }
        let parsed = ReplyParser.parse(sms.body)

        var entry: TokenEntry?
        var text: String

        if let candidate = parsed.token {
            if let found = appData.routingTokens.entry(for: candidate) {
                entry = found
                text = parsed.textWithoutToken
            } else if parsed.tokenIsExplicit {
                _ = try? await twilio.sendSMS(body: "unknown msg id \(candidate)")
                return
            } else {
                entry = appData.routingTokens.last
                text = parsed.fullBody
            }
        } else {
            entry = appData.routingTokens.last
            text = parsed.textWithoutToken
        }

        guard let target = entry else {
            _ = try? await twilio.sendSMS(body: "no recent message to reply to")
            return
        }
        if text.isEmpty { return }

        let userToken = credentials.slackUserToken
        guard !userToken.isEmpty else {
            _ = try? await twilio.sendSMS(body: "Slack user token not configured")
            return
        }

        let threadTS: String?
        if target.isDM {
            threadTS = nil
        } else if let anchor = target.threadAnchor {
            threadTS = anchor
        } else if parsed.threadFlag {
            threadTS = target.sourceTS
        } else {
            threadTS = nil
        }

        do {
            _ = try await SlackAPI.chatPostMessage(
                token: userToken,
                channel: target.channelID,
                text: text,
                threadTS: threadTS
            )
            logger.info("posted to \(target.channelID, privacy: .public) thread=\(threadTS ?? "-", privacy: .public)")
        } catch {
            logger.error("posting: \(String(describing: error), privacy: .public)")
            _ = try? await twilio.sendSMS(body: "post failed: \(String(describing: error))")
        }
    }

    private static let allowedSubtypes: Set<String> = ["file_share", "thread_broadcast"]

    private func shouldForward(_ event: SlackEvent) -> Bool {
        if let subtype = event.subtype, !Self.allowedSubtypes.contains(subtype) {
            return false
        }
        if appData.skipOwnMessages,
           let user = event.user,
           let selfID = appState.selfUserID,
           user == selfID {
            return false
        }
        let isThreadReply = event.threadTS != nil && event.threadTS != event.ts

        if event.channelType == "im" {
            guard let user = event.user else { return false }
            return appData.watchedUserIDs.contains(user)
        }

        guard let channel = event.channel else { return false }
        if !appData.watchedChannelIDs.contains(channel) { return false }

        if isThreadReply {
            guard let selfID = appState.selfUserID, !selfID.isEmpty else { return false }
            return event.text?.contains("<@\(selfID)>") ?? false
        }
        return true
    }

    private func format(_ event: SlackEvent) async -> String {
        let token = credentials.slackBotToken
        let isDM = event.channelType == "im"
        let isThreadReply = event.threadTS != nil && event.threadTS != event.ts

        let userName: String
        if let userID = event.user {
            userName = await names.userName(id: userID, token: token)
        } else {
            userName = "?"
        }

        let prefix: String
        if isDM {
            prefix = "[DM from \(userName)]"
        } else {
            let channelName: String
            if let channelID = event.channel {
                channelName = await names.channelName(id: channelID, token: token)
            } else {
                channelName = "?"
            }
            prefix = isThreadReply
                ? "[#\(channelName) from \(userName) (thread)]"
                : "[#\(channelName) from \(userName)]"
        }

        var body = await unparse(event.text ?? "", token: token)
        if body.isEmpty, let files = event.files, !files.isEmpty {
            let names = files.compactMap(\.name).joined(separator: ", ")
            body = names.isEmpty ? "[file]" : "[file: \(names)]"
        }

        return body.isEmpty ? prefix : "\(prefix) \(body)"
    }

    private func unparse(_ text: String, token: String) async -> String {
        guard text.contains("<") else { return text }
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: "<([^<>]+)>")
        } catch {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex
        for match in matches {
            guard let mRange = Range(match.range, in: text),
                  let inner = Range(match.range(at: 1), in: text) else { continue }
            result += text[cursor..<mRange.lowerBound]
            result += await replace(inner: String(text[inner]), token: token)
            cursor = mRange.upperBound
        }
        result += text[cursor...]
        return result
    }

    private func replace(inner: String, token: String) async -> String {
        let parts = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let head = String(parts.first ?? "")
        let alias = parts.count > 1 ? String(parts[1]) : nil

        if head.hasPrefix("@") {
            let id = String(head.dropFirst())
            let resolved = await names.userName(id: id, token: token)
            return "@\(resolved)"
        }
        if head.hasPrefix("#") {
            if let alias { return "#\(alias)" }
            let id = String(head.dropFirst())
            let resolved = await names.channelName(id: id, token: token)
            return "#\(resolved)"
        }
        if head.hasPrefix("!") {
            let bare = String(head.dropFirst())
            return "@\(bare)"
        }
        return head
    }
}
