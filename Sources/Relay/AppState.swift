import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var paused: Bool = false
    var slackConnected: Bool = false
    var twilioLastPollAt: Date? = nil
    var twilioLastPollOk: Bool = true
    var selfUserID: String? = nil

    var menuBarSymbolName: String {
        if paused { return "pause.circle" }
        return "bubble.left.and.bubble.right"
    }

    var statusLine: String {
        if paused { return "Paused" }
        if !slackConnected { return "Slack disconnected" }
        if !twilioLastPollOk {
            if let at = twilioLastPollAt {
                let f = DateFormatter()
                f.dateFormat = "HH:mm"
                return "Twilio polling failed at \(f.string(from: at))"
            }
            return "Twilio polling failed"
        }
        return "Connected"
    }
}
