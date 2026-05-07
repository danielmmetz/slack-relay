import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class Credentials {
    var twilioAccountSID: String { didSet { persist(.twilioAccountSID, twilioAccountSID) } }
    var twilioAuthToken: String { didSet { persist(.twilioAuthToken, twilioAuthToken) } }
    var twilioFromNumber: String { didSet { persist(.twilioFromNumber, twilioFromNumber) } }
    var twilioToPhone: String { didSet { persist(.twilioToPhone, twilioToPhone) } }
    var slackAppToken: String { didSet { persist(.slackAppToken, slackAppToken) } }
    var slackBotToken: String { didSet { persist(.slackBotToken, slackBotToken) } }
    var slackUserToken: String { didSet { persist(.slackUserToken, slackUserToken) } }

    private static let logger = Logger(subsystem: "com.danielmmetz.relay", category: "credentials")

    init() {
        twilioAccountSID = Self.load(.twilioAccountSID)
        twilioAuthToken = Self.load(.twilioAuthToken)
        twilioFromNumber = Self.load(.twilioFromNumber)
        twilioToPhone = Self.load(.twilioToPhone)
        slackAppToken = Self.load(.slackAppToken)
        slackBotToken = Self.load(.slackBotToken)
        slackUserToken = Self.load(.slackUserToken)
    }

    enum Account: String {
        case twilioAccountSID = "twilio.account_sid"
        case twilioAuthToken = "twilio.auth_token"
        case twilioFromNumber = "twilio.from_number"
        case twilioToPhone = "twilio.to_phone"
        case slackAppToken = "slack.app_token"
        case slackBotToken = "slack.bot_token"
        case slackUserToken = "slack.user_token"
    }

    private static func load(_ account: Account) -> String {
        do {
            return try Keychain.get(account: account.rawValue) ?? ""
        } catch {
            logger.error("loading \(account.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return ""
        }
    }

    private func persist(_ account: Account, _ value: String) {
        do {
            if value.isEmpty {
                try Keychain.delete(account: account.rawValue)
            } else {
                try Keychain.set(account: account.rawValue, value: value)
            }
        } catch {
            Self.logger.error("persisting \(account.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
