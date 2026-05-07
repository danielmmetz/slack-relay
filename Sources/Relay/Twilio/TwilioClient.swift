import Foundation
import OSLog

enum TwilioError: Error, CustomStringConvertible {
    case missingCredentials
    case badEndpoint
    case http(Int, String)
    case responseDecode(String)

    var description: String {
        switch self {
        case .missingCredentials: return "missing Twilio credentials"
        case .badEndpoint: return "bad endpoint url"
        case .http(let code, let body):
            return body.isEmpty ? "http \(code)" : "http \(code): \(body)"
        case .responseDecode(let s): return "decoding response: \(s)"
        }
    }
}

@MainActor
final class TwilioClient {
    static let bodyCapBytes: Int = 1500

    private let credentials: Credentials
    private let session = URLSession(configuration: .default)
    private let logger = Logger(subsystem: "com.danielmmetz.relay", category: "twilio")

    init(credentials: Credentials) {
        self.credentials = credentials
    }

    @discardableResult
    func sendSMS(body: String) async throws -> String {
        let sid = credentials.twilioAccountSID
        let token = credentials.twilioAuthToken
        let from = credentials.twilioFromNumber
        let to = credentials.twilioToPhone
        guard !sid.isEmpty, !token.isEmpty, !from.isEmpty, !to.isEmpty else {
            throw TwilioError.missingCredentials
        }

        let trimmed = Self.trim(body)

        guard let url = URL(string: "https://api.twilio.com/2010-04-01/Accounts/\(sid)/Messages.json") else {
            throw TwilioError.badEndpoint
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let basic = Data("\(sid):\(token)".utf8).base64EncodedString()
        req.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formEncode([
            "From": from,
            "To": to,
            "Body": trimmed,
        ])

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw TwilioError.responseDecode("not an HTTP response")
        }
        if http.statusCode != 201 {
            throw TwilioError.http(http.statusCode, Self.errorMessage(from: data))
        }
        struct CreateResp: Decodable { let sid: String }
        do {
            let r = try JSONDecoder().decode(CreateResp.self, from: data)
            logger.info("sent sid=\(r.sid, privacy: .public)")
            return r.sid
        } catch {
            throw TwilioError.responseDecode(String(describing: error))
        }
    }

    private static func trim(_ body: String) -> String {
        guard body.utf8.count > bodyCapBytes else { return body }
        var truncated = body
        while truncated.utf8.count > bodyCapBytes - 1 {
            truncated.removeLast()
        }
        return truncated + "…"
    }

    private static func formEncode(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        let parts = fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        return Data(parts.joined(separator: "&").utf8)
    }

    private static func errorMessage(from data: Data) -> String {
        struct ErrResp: Decodable { let code: Int?; let message: String? }
        if let e = try? JSONDecoder().decode(ErrResp.self, from: data), let msg = e.message {
            if let code = e.code { return "\(msg) (code \(code))" }
            return msg
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
