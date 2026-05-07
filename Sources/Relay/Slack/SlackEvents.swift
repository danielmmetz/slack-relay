import Foundation

struct SlackEnvelope: Decodable {
    let type: String
    let envelopeID: String?
    let payload: SlackPayload?
    let reason: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case envelopeID = "envelope_id"
        case payload
        case reason
    }
}

struct SlackPayload: Decodable {
    let event: SlackEvent
}

struct SlackEvent: Decodable {
    let type: String
    let channel: String?
    let user: String?
    let ts: String?
    let threadTS: String?
    let text: String?
    let subtype: String?
    let channelType: String?
    let files: [SlackFile]?

    private enum CodingKeys: String, CodingKey {
        case type, channel, user, ts, text, subtype, files
        case threadTS = "thread_ts"
        case channelType = "channel_type"
    }
}

struct SlackFile: Decodable {
    let name: String?
}
