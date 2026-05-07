import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class Credentials {
    var twilioAccountSID: String { didSet { persist() } }
    var twilioAuthToken: String { didSet { persist() } }
    var twilioFromNumber: String { didSet { persist() } }
    var twilioToPhone: String { didSet { persist() } }
    var slackAppToken: String { didSet { persist() } }
    var slackBotToken: String { didSet { persist() } }
    var slackUserToken: String { didSet { persist() } }

    private static let account = "credentials.v1"
    private static let logger = Logger(subsystem: "com.danielmmetz.relay", category: "credentials")

    init() {
        let snap = Self.load()
        twilioAccountSID = snap.twilioAccountSID
        twilioAuthToken = snap.twilioAuthToken
        twilioFromNumber = snap.twilioFromNumber
        twilioToPhone = snap.twilioToPhone
        slackAppToken = snap.slackAppToken
        slackBotToken = snap.slackBotToken
        slackUserToken = snap.slackUserToken
    }

    private struct Snapshot: Codable {
        var twilioAccountSID = ""
        var twilioAuthToken = ""
        var twilioFromNumber = ""
        var twilioToPhone = ""
        var slackAppToken = ""
        var slackBotToken = ""
        var slackUserToken = ""

        var allEmpty: Bool {
            twilioAccountSID.isEmpty && twilioAuthToken.isEmpty
                && twilioFromNumber.isEmpty && twilioToPhone.isEmpty
                && slackAppToken.isEmpty && slackBotToken.isEmpty
                && slackUserToken.isEmpty
        }
    }

    private static func load() -> Snapshot {
        do {
            guard let raw = try Keychain.get(account: account) else { return Snapshot() }
            return try JSONDecoder().decode(Snapshot.self, from: Data(raw.utf8))
        } catch {
            logger.error("loading: \(error.localizedDescription, privacy: .public)")
            return Snapshot()
        }
    }

    private func persist() {
        let snap = Snapshot(
            twilioAccountSID: twilioAccountSID,
            twilioAuthToken: twilioAuthToken,
            twilioFromNumber: twilioFromNumber,
            twilioToPhone: twilioToPhone,
            slackAppToken: slackAppToken,
            slackBotToken: slackBotToken,
            slackUserToken: slackUserToken
        )
        do {
            if snap.allEmpty {
                try Keychain.delete(account: Self.account)
                return
            }
            let data = try JSONEncoder().encode(snap)
            let raw = String(decoding: data, as: UTF8.self)
            try Keychain.set(account: Self.account, value: raw)
        } catch {
            Self.logger.error("persisting: \(error.localizedDescription, privacy: .public)")
        }
    }
}
