import Foundation
import os

/// Thread-safe manager responsible for persisting and synchronizing the global Finder Integration state.
///
/// Ensures both the host application and the sandboxed Finder Sync Extension share a synchronized
/// enabled/disabled setting across process boundaries.
public final class FinderIntegrationStore: @unchecked Sendable {
    public static let shared = FinderIntegrationStore()

    private let lock = NSLock()
    private let logger = Logger(subsystem: "com.otterkeep", category: "FinderIntegrationStore")
    private let userDefaultsKey = "isFinderIntegrationEnabled"

    /// Real user home directory URL resolved via POSIX getpwuid to avoid sandbox redirection discrepancies.
    public var realUserHome: URL {
        if let pw = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Primary settings JSON path (`~/.otterkeep/settings.json`).
    public var settingsFileURL: URL {
        realUserHome.appendingPathComponent(".otterkeep/settings.json")
    }

    /// Sandboxed container settings JSON path.
    public var containerSettingsFileURL: URL {
        realUserHome.appendingPathComponent("Library/Containers/com.otterkeep.OtterKeepApp.FinderSync/Data/.otterkeep/settings.json")
    }

    private init() {}

    /// Returns `true` if Finder integration is globally enabled; defaults to `true`.
    public var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }

        // 1. Try UserDefaults
        if let val = UserDefaults.standard.object(forKey: userDefaultsKey) as? Bool {
            logger.info("isEnabled from UserDefaults: \(val)")
            return val
        }

        // 2. Candidate JSON settings paths (evaluating primary, container, and local container home)
        var candidateURLs = [settingsFileURL, containerSettingsFileURL]
        let currentHomeSettings = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".otterkeep/settings.json")
        if !candidateURLs.contains(currentHomeSettings) {
            candidateURLs.append(currentHomeSettings)
        }

        for candidateURL in candidateURLs {
            if let fileValue = readFromFile(url: candidateURL) {
                logger.info("isEnabled from file '\(candidateURL.path)': \(fileValue)")
                return fileValue
            }
        }

        logger.info("isEnabled fallback: true")
        // Default to enabled
        return true
    }

    /// Sets the global Finder integration state and mirrors it across configuration files and notifications.
    public func setEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }

        UserDefaults.standard.set(enabled, forKey: userDefaultsKey)
        LocalizationManager.shared.settings.finderIntegrationEnabled = enabled

        // Mirror to JSON files so non-app-group sandboxed appex can read the state
        writeToFile(enabled: enabled, url: settingsFileURL)
        writeToFile(enabled: enabled, url: containerSettingsFileURL)
        let currentHomeSettings = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".otterkeep/settings.json")
        if currentHomeSettings != settingsFileURL && currentHomeSettings != containerSettingsFileURL {
            writeToFile(enabled: enabled, url: currentHomeSettings)
        }

        logger.info("Finder Integration set to: \(enabled ? "ENABLED" : "DISABLED")")

        // Broadcast notification across processes
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.otterkeep.finderIntegrationChanged"),
            object: nil,
            userInfo: ["enabled": enabled],
            deliverImmediately: true
        )
    }

    private func readFromFile(url: URL) -> Bool? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let val = dict["finderIntegrationEnabled"] as? Bool else {
            return nil
        }
        return val
    }

    private func writeToFile(enabled: Bool, url: URL) {
        let parentDir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        var dict: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = existing
        }

        dict["finderIntegrationEnabled"] = enabled

        if let outData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) {
            try? outData.write(to: url, options: .atomic)
        }
    }
}
