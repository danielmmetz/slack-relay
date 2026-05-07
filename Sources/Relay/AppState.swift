import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var paused: Bool = false
    var slackConnected: Bool = false
    var twilioLastPollAt: Date? = nil
    var twilioLastPollOk: Bool = true

    var menuBarSymbolName: String {
        if paused { return "pause.circle" }
        return "bubble.left.and.bubble.right"
    }

    var statusLine: String {
        if paused { return "Paused" }
        if !slackConnected { return "Slack disconnected" }
        if !twilioLastPollOk { return "Twilio polling failed" }
        return "Connected"
    }
}
