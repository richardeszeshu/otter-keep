import Foundation
import os

/// Metadata representation of an available application update.
public struct SoftwareUpdateInfo: Sendable, Equatable {
    /// Semantic version string (e.g. "1.7.1").
    public let version: String
    /// Build sequence number (e.g. "1710").
    public let buildNumber: String
    /// Release notes or changelog summary.
    public let releaseNotes: String
    /// Direct download or release page URL.
    public let downloadURL: URL
    /// Release publication timestamp.
    public let publicationDate: Date
    /// Whether this update addresses critical security flaws or breaking bugs.
    public let isCritical: Bool

    public init(
        version: String,
        buildNumber: String,
        releaseNotes: String,
        downloadURL: URL,
        publicationDate: Date = Date(),
        isCritical: Bool = false
    ) {
        self.version = version
        self.buildNumber = buildNumber
        self.releaseNotes = releaseNotes
        self.downloadURL = downloadURL
        self.publicationDate = publicationDate
        self.isCritical = isCritical
    }
}

/// Lifecycle state of the software update checker.
public enum UpdateCheckStatus: Sendable, Equatable {
    case idle
    case checking
    case updateAvailable(SoftwareUpdateInfo)
    case upToDate
    case failed(String)

    public var statusDescription: String {
        switch self {
        case .idle:
            return "Idle"
        case .checking:
            return "Checking for updates..."
        case .updateAvailable(let info):
            return "Update available: v\(info.version)"
        case .upToDate:
            return "OtterKeep is up to date"
        case .failed(let err):
            return "Check failed: \(err)"
        }
    }
}

/// Coordinator managing in-app software update discovery, semantic version evaluation, and Sparkle appcast integration.
public actor SoftwareUpdateCoordinator {
    public static let shared = SoftwareUpdateCoordinator()
    private let logger = Logger(subsystem: "com.otterkeep", category: "UpdateCoordinator")

    private static let autoCheckKey = "OtterKeep.AutoCheckForUpdates"
    private static let lastCheckKey = "OtterKeep.LastUpdateCheckDate"

    /// Default public appcast feed URL.
    public static let defaultAppcastURL = URL(string: "https://raw.githubusercontent.com/richardeszes/OtterKeep/main/Distribution/appcast.xml")!

    public private(set) var latestStatus: UpdateCheckStatus = .idle
    public private(set) var lastCheckDate: Date?
    private var mockUpdateInfo: SoftwareUpdateInfo?

    public init() {
        let ts = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        if ts > 0 {
            self.lastCheckDate = Date(timeIntervalSince1970: ts)
        }
    }

    /// Whether automatic background checking for updates is enabled.
    public var automaticallyChecksForUpdates: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.autoCheckKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.autoCheckKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.autoCheckKey)
        }
    }

    /// Current running application version.
    public nonisolated var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? CoreEngine.version
    }

    /// Current running application build number.
    public nonisolated var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? CoreEngine.buildNumber
    }

    /// Injects mock update info for automated testing without network access.
    public func setMockUpdateInfo(_ info: SoftwareUpdateInfo?) {
        self.mockUpdateInfo = info
    }

    /// Compares two semantic version strings (e.g. "1.7.0" vs "1.7.1").
    /// Returns `.orderedAscending` if v1 < v2, `.orderedSame` if equal, `.orderedDescending` if v1 > v2.
    public static func compareVersions(_ v1: String, _ v2: String) -> ComparisonResult {
        let clean1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
        let clean2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))

        let parts1 = clean1.split(separator: ".").compactMap { Int($0) }
        let parts2 = clean2.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(parts1.count, parts2.count)
        for i in 0..<maxCount {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 < p2 { return .orderedAscending }
            if p1 > p2 { return .orderedDescending }
        }
        return .orderedSame
    }

    /// Returns `true` if `candidate` version is strictly newer than `current` version.
    public static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        compareVersions(current, candidate) == .orderedAscending
    }

    /// Checks for available updates by querying the Sparkle appcast feed.
    public func checkForUpdates(appcastURL: URL? = nil) async -> UpdateCheckStatus {
        latestStatus = .checking
        let now = Date()
        self.lastCheckDate = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastCheckKey)

        if let mock = mockUpdateInfo {
            if Self.isVersion(mock.version, newerThan: currentVersion) {
                let status = UpdateCheckStatus.updateAvailable(mock)
                self.latestStatus = status
                return status
            } else {
                let status = UpdateCheckStatus.upToDate
                self.latestStatus = status
                return status
            }
        }

        let feedURL = appcastURL ?? Self.defaultAppcastURL
        var req = URLRequest(url: feedURL)
        req.timeoutInterval = 10
        req.setValue("OtterKeep-Sparkle/2.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let status = UpdateCheckStatus.failed("Server returned error status")
                self.latestStatus = status
                return status
            }

            // Parse simple Appcast XML
            if let update = parseAppcastXML(data: data) {
                if Self.isVersion(update.version, newerThan: currentVersion) {
                    let status = UpdateCheckStatus.updateAvailable(update)
                    self.latestStatus = status
                    return status
                }
            }

            let status = UpdateCheckStatus.upToDate
            self.latestStatus = status
            return status
        } catch {
            let status = UpdateCheckStatus.failed(error.localizedDescription)
            self.latestStatus = status
            return status
        }
    }

    private func parseAppcastXML(data: Data) -> SoftwareUpdateInfo? {
        guard let xmlString = String(data: data, encoding: .utf8) else { return nil }

        // Find enclosure or item
        var version = ""
        var build = ""
        var downloadURL: URL?
        var releaseNotes = ""

        if let range = xmlString.range(of: "sparkle:shortVersionString=\"") {
            let rest = xmlString[range.upperBound...]
            if let end = rest.firstIndex(of: "\"") {
                version = String(rest[..<end])
            }
        }

        if let range = xmlString.range(of: "sparkle:version=\"") {
            let rest = xmlString[range.upperBound...]
            if let end = rest.firstIndex(of: "\"") {
                build = String(rest[..<end])
            }
        }

        if let range = xmlString.range(of: "url=\"") {
            let rest = xmlString[range.upperBound...]
            if let end = rest.firstIndex(of: "\"") {
                downloadURL = URL(string: String(rest[..<end]))
            }
        }

        if let range = xmlString.range(of: "<description><![CDATA[") {
            let rest = xmlString[range.upperBound...]
            if let end = rest.range(of: "]]></description>") {
                releaseNotes = String(rest[..<end.lowerBound])
            }
        }

        guard !version.isEmpty, let dURL = downloadURL ?? URL(string: "https://github.com/richardeszes/OtterKeep/releases") else {
            return nil
        }

        return SoftwareUpdateInfo(
            version: version,
            buildNumber: build.isEmpty ? version : build,
            releaseNotes: releaseNotes,
            downloadURL: dURL,
            publicationDate: Date(),
            isCritical: false
        )
    }
}
