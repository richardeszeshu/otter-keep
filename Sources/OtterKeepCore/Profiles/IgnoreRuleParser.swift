import Foundation

/// Gitignore-stílusú minta-értékelő szabály.
public struct GitIgnoreRule: Sendable, Equatable {
    public let originalPattern: String
    public let isNegative: Bool           // '!' kezdetű szabály
    public let isDirectoryOnly: Bool       // '/' végű szabály
    public let isRooted: Bool              // '/' jellel kezdődik (adott mappagyökérre érvényes)
    public let regex: NSRegularExpression?

    public init?(pattern: String) {
        var p = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty || p.hasPrefix("#") { return nil }

        var neg = false
        if p.hasPrefix("!") {
            neg = true
            p = String(p.dropFirst())
        }

        var dirOnly = false
        if p.hasSuffix("/") {
            dirOnly = true
            p = String(p.dropLast())
        }

        var rooted = false
        if p.hasPrefix("/") {
            rooted = true
            p = String(p.dropFirst())
        }

        self.originalPattern = pattern
        self.isNegative = neg
        self.isDirectoryOnly = dirOnly
        self.isRooted = rooted
        self.regex = Self.buildRegex(from: p, rooted: rooted)
    }

    private static func buildRegex(from pattern: String, rooted: Bool) -> NSRegularExpression? {
        // Glob átalakítása Regexre (*, ?, **)
        var regexStr = "^"
        if !rooted {
            regexStr += "(?:.*/)?"
        }
        var i = pattern.startIndex
        while i < pattern.endIndex {
            let c = pattern[i]
            if c == "*" {
                let nextIdx = pattern.index(after: i)
                if nextIdx < pattern.endIndex && pattern[nextIdx] == "*" {
                    regexStr += ".*"
                    i = pattern.index(after: nextIdx)
                    continue
                } else {
                    regexStr += "[^/]*"
                }
            } else if c == "?" {
                regexStr += "[^/]"
            } else if [".", "(", ")", "+", "|", "^", "$", "{", "}", "\\", "[", "]"].contains(c) {
                regexStr += "\\" + String(c)
            } else {
                regexStr += String(c)
            }
            i = pattern.index(after: i)
        }
        regexStr += "(?:/.*)?$"
        return try? NSRegularExpression(pattern: regexStr, options: [.caseInsensitive])
    }

    public func matches(relativePath: String, isDirectory: Bool) -> Bool {
        if isDirectoryOnly && !isDirectory { return false }
        guard let regex = regex else { return false }
        let range = NSRange(location: 0, length: relativePath.utf16.count)
        return regex.firstMatch(in: relativePath, range: range) != nil
    }
}

/// Egy adott könyvtárhoz tartozó ignorálási kontextus.
public struct DirectoryIgnoreContext: Sendable {
    public let baseRelativePath: String
    public let rules: [GitIgnoreRule]
    public let isExclusionMarkerPresent: Bool

    public init(baseRelativePath: String, rules: [GitIgnoreRule], isExclusionMarkerPresent: Bool) {
        self.baseRelativePath = baseRelativePath
        self.rules = rules
        self.isExclusionMarkerPresent = isExclusionMarkerPresent
    }
}
