import Foundation
import CryptoKit

/// Thread-safe privacy and PII (Personally Identifiable Information) sanitizer for diagnostic logs.
///
/// Ensures that logs can be shared for troubleshooting without exposing:
/// - Usernames (current user, system user accounts)
/// - Home directory paths
/// - Private folder names and file names
/// - Volume names
/// - Email addresses
/// - Sensitive authentication tokens
///
/// While strictly preserving diagnostic context:
/// - File extensions (.pdf, .sqlite, .jpg, .tmp, etc.)
/// - File sizes and byte counts
/// - Profiling UUIDs
/// - POSIX / APFS error codes (EACCES, ENOENT, ENOSPC, etc.)
public struct LogPrivacySanitizer: Sendable {

    /// Current username identifiers to redact.
    private static let currentUsername: String = NSUserName()
    private static let currentFullUsername: String = NSFullUserName()
    private static let homeDirPath: String = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)

    // Precompiled regular expressions for credentials, tokens, webhooks, and AWS keys
    private static let authHeaderRegex: NSRegularExpression = {
        (try? NSRegularExpression(
            pattern: #"(?i)(Authorization\s*:\s*)(Bearer\s+[A-Za-z0-9_\-\.]+)|(Basic\s+[A-Za-z0-9+/=]+)|(AWS4-HMAC-SHA256\s+[^\r\n]+)"#,
            options: []
        )) ?? NSRegularExpression()
    }()

    private static let queryParamRegex: NSRegularExpression = {
        (try? NSRegularExpression(
            pattern: #"(?i)([?&](?:token|key|secret|password|signature|access_token|auth)=)[^&\s]+"#,
            options: []
        )) ?? NSRegularExpression()
    }()

    private static let webhookURLRegex: NSRegularExpression = {
        (try? NSRegularExpression(
            pattern: #"https://(?:hooks\.slack\.com/services|discord(?:app)?\.com/api/webhooks)/[A-Za-z0-9/_]+"#,
            options: []
        )) ?? NSRegularExpression()
    }()

    private static let awsKeyRegex: NSRegularExpression = {
        (try? NSRegularExpression(
            pattern: #"\b(AKIA|ASIA)[0-9A-Z]{16}\b"#,
            options: []
        )) ?? NSRegularExpression()
    }()

    private static let urlPasswordRegex: NSRegularExpression = {
        (try? NSRegularExpression(
            pattern: #"(?i)([a-z]+://[^:]+:)([^@\s]+)(@)"#,
            options: []
        )) ?? NSRegularExpression()
    }()

    // Precompiled regular expressions for high-performance log sanitization
    private static let emailRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}"#, options: [])) ?? NSRegularExpression()
    }()

    private static let genericUserPathRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: #"/Users/[^/\s"':]+"#, options: [])) ?? NSRegularExpression()
    }()

    private static let volumePathRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: #"/Volumes/[^/\s"':]+"#, options: [])) ?? NSRegularExpression()
    }()

    private static let pathInQuotesOrMessageRegex: NSRegularExpression = {
        // Matches paths like '/Users/...' or '/Volumes/...' or '/private/var/...' or standalone Unix paths
        (try? NSRegularExpression(pattern: #"((?:/Users|/Volumes|/private/var|~)[^\s"':;,()<>]+)"#, options: [])) ?? NSRegularExpression()
    }()

    /// Sanitizes an entire log message string, removing usernames, private paths, and sensitive PII.
    /// - Parameter message: Raw log message text.
    /// - Returns: Redacted and sanitized message string safe for sharing.
    public static func sanitize(_ message: String) -> String {
        guard !message.isEmpty else { return message }

        var text = message

        // 0. Redact credentials and authorization tokens FIRST before filesystem path matching
        text = urlPasswordRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: "$1<SECRET>$3")
        text = authHeaderRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: "$1<REDACTED_AUTH>")
        text = queryParamRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: "$1<REDACTED>")
        text = webhookURLRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: "https://<WEBHOOK_ENDPOINT_REDACTED>")
        text = awsKeyRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: "<AWS_ACCESS_KEY_ID>")

        // 1. Redact exact Home Directory Path
        if !homeDirPath.isEmpty {
            text = text.replacingOccurrences(of: homeDirPath, with: "<USER_HOME>")
        }

        // 2. Redact current full user name and short user name
        if !currentFullUsername.isEmpty && currentFullUsername.count > 1 {
            text = text.replacingOccurrences(of: currentFullUsername, with: "<USER>")
        }
        if !currentUsername.isEmpty && currentUsername.count > 1 {
            text = text.replacingOccurrences(of: currentUsername, with: "<USER>")
        }

        // 3. Redact any other user paths (/Users/<anyone>)
        text = genericUserPathRegex.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: text.utf16.count),
            withTemplate: "/Users/<USER>"
        )

        // 4. Sanitize paths found in text (preserve extensions and structure, redact private names)
        text = sanitizePathsInText(text)

        // 5. Redact volume names (/Volumes/<Name>)
        text = volumePathRegex.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: text.utf16.count),
            withTemplate: "/Volumes/<VOLUME>"
        )

        // 6. Redact Email addresses
        text = emailRegex.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: text.utf16.count),
            withTemplate: "<EMAIL>"
        )

        return text
    }

    /// Finds and sanitizes embedded file paths in a log message string.
    private static func sanitizePathsInText(_ text: String) -> String {
        let nsString = text as NSString
        let matches = pathInQuotesOrMessageRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        guard !matches.isEmpty else { return text }

        var result = text
        // Iterate in reverse order so ranges stay valid
        for match in matches.reversed() {
            let pathRange = match.range(at: 1)
            let rawPath = nsString.substring(with: pathRange)
            let sanitizedPath = sanitizeSinglePath(rawPath)
            if let swiftRange = Range(pathRange, in: result) {
                result.replaceSubrange(swiftRange, with: sanitizedPath)
            }
        }
        return result
    }

    /// Sanitizes an individual file or directory path.
    /// Preserves standard application paths (e.g. `.otterkeep/manifest.sqlite`), but redacts
    /// personal folder names and file names, preserving file extensions.
    public static func sanitizeSinglePath(_ path: String) -> String {
        // If it's a known internal OtterKeep database/log path, keep safe suffix
        if path.contains(".otterkeep") {
            let parts = path.components(separatedBy: ".otterkeep")
            let suffix = parts.count > 1 ? ".otterkeep" + parts[1] : ".otterkeep"
            return "<APP_STORAGE>/" + suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        var normalized = path
        var prefix = ""

        if normalized.hasPrefix("<USER_HOME>") {
            prefix = "<USER_HOME>"
            normalized = String(normalized.dropFirst("<USER_HOME>".count))
        } else if normalized.hasPrefix("~") {
            prefix = "<USER_HOME>"
            normalized = String(normalized.dropFirst(1))
        } else if normalized.hasPrefix("/Users/<USER>") {
            prefix = "<USER_HOME>"
            normalized = String(normalized.dropFirst("/Users/<USER>".count))
        } else if normalized.hasPrefix("/Volumes/") {
            let volumeComponents = normalized.components(separatedBy: "/")
            if volumeComponents.count >= 3 {
                prefix = "/Volumes/<VOLUME>"
                normalized = "/" + volumeComponents.dropFirst(3).joined(separator: "/")
            }
        }

        let segments = normalized.split(separator: "/", omittingEmptySubsequences: true)
        if segments.isEmpty {
            return prefix.isEmpty ? "<PATH>" : prefix
        }

        var sanitizedSegments: [String] = []
        for (index, segment) in segments.enumerated() {
            let str = String(segment)
            let isLast = (index == segments.count - 1)

            // Known system / safe root folder names
            let safeFolderNames: Set<String> = [
                "Applications", "Library", "System", "Documents", "Downloads",
                "Desktop", "Pictures", "Music", "Movies", "Photos", "root"
            ]

            if !isLast && safeFolderNames.contains(str) {
                sanitizedSegments.append(str)
                continue
            }

            if isLast {
                // Check if it's a file with an extension
                let ext = (str as NSString).pathExtension
                if !ext.isEmpty && ext.count <= 10 {
                    let hash = deterministicShortHash(str)
                    sanitizedSegments.append("<FILE_\(hash)>.\(ext)")
                } else if safeFolderNames.contains(str) {
                    sanitizedSegments.append(str)
                } else {
                    let hash = deterministicShortHash(str)
                    sanitizedSegments.append("<DIR_\(hash)>")
                }
            } else {
                let hash = deterministicShortHash(str)
                sanitizedSegments.append("<DIR_\(hash)>")
            }
        }

        let body = sanitizedSegments.joined(separator: "/")
        if prefix.isEmpty {
            return "/" + body
        } else {
            return prefix + (body.isEmpty ? "" : "/" + body)
        }
    }

    /// Computes a short 6-character hexadecimal hash for consistent correlation during a single debug session without revealing the original name.
    private static func deterministicShortHash(_ input: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(6).description
    }
}
