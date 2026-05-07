import Foundation

struct ParsedReply: Equatable {
    var token: Int?
    var tokenIsExplicit: Bool
    var threadFlag: Bool
    var textWithoutToken: String
    var fullBody: String
}

enum ReplyParser {
    static func parse(_ body: String) -> ParsedReply {
        let initial = body.trimmingCharacters(in: .whitespacesAndNewlines)
        var rest = initial
        var threadFlag = false

        if rest.hasPrefix("t[") || rest.hasPrefix("t ") {
            threadFlag = true
            rest = rest.hasPrefix("t[")
                ? String(rest.dropFirst(1))
                : String(rest.dropFirst(2))
        } else if rest == "t" {
            return ParsedReply(token: nil, tokenIsExplicit: false, threadFlag: true, textWithoutToken: "", fullBody: "")
        }

        let bodyAfterFlag = rest

        if let bracketEnd = matchBracketed(rest) {
            let token = Int(rest[rest.index(after: rest.startIndex)..<bracketEnd])
            let after = rest[rest.index(after: bracketEnd)...].trimmingCharacters(in: .whitespacesAndNewlines)
            return ParsedReply(
                token: token,
                tokenIsExplicit: true,
                threadFlag: threadFlag,
                textWithoutToken: after,
                fullBody: bodyAfterFlag
            )
        }

        if let (n, after) = matchColon(rest) {
            return ParsedReply(
                token: n,
                tokenIsExplicit: true,
                threadFlag: threadFlag,
                textWithoutToken: after,
                fullBody: bodyAfterFlag
            )
        }

        if let (n, after) = matchImplicit(rest) {
            return ParsedReply(
                token: n,
                tokenIsExplicit: false,
                threadFlag: threadFlag,
                textWithoutToken: after,
                fullBody: bodyAfterFlag
            )
        }

        return ParsedReply(
            token: nil,
            tokenIsExplicit: false,
            threadFlag: threadFlag,
            textWithoutToken: bodyAfterFlag,
            fullBody: bodyAfterFlag
        )
    }

    private static func matchBracketed(_ s: String) -> String.Index? {
        guard s.hasPrefix("[") else { return nil }
        var i = s.index(after: s.startIndex)
        while i < s.endIndex, s[i].isASCII, s[i].isNumber {
            i = s.index(after: i)
        }
        guard i < s.endIndex, s[i] == "]", i > s.index(after: s.startIndex) else { return nil }
        return i
    }

    private static func matchColon(_ s: String) -> (Int, String)? {
        var i = s.startIndex
        while i < s.endIndex, s[i].isASCII, s[i].isNumber {
            i = s.index(after: i)
        }
        guard i > s.startIndex, i < s.endIndex, s[i] == ":" else { return nil }
        let token = Int(s[s.startIndex..<i])
        let after = s[s.index(after: i)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return token.map { ($0, after) }
    }

    private static func matchImplicit(_ s: String) -> (Int, String)? {
        var i = s.startIndex
        var digits = 0
        while i < s.endIndex, s[i].isASCII, s[i].isNumber, digits < 3 {
            i = s.index(after: i)
            digits += 1
        }
        guard digits > 0, i < s.endIndex, s[i].isWhitespace else { return nil }
        guard let n = Int(s[s.startIndex..<i]), n <= 999 else { return nil }
        let after = s[s.index(after: i)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (n, after)
    }
}
