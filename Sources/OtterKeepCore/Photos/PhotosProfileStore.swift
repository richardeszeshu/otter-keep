import Foundation

/// Thread-safe persistence store for Apple Photos backup profile settings (`~/.otterkeep/photos_profile.json`).
public final class PhotosProfileStore: @unchecked Sendable {
    /// Shared singleton instance.
    public static let shared = PhotosProfileStore()

    private let lock = NSLock()
    private let fileManager = FileManager.default

    /// Base configuration directory URL.
    public var storageDirectory: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".otterkeep", isDirectory: true)
    }

    /// Full file path URL to `photos_profile.json`.
    public var configFileURL: URL {
        storageDirectory.appendingPathComponent("photos_profile.json")
    }

    private init() {
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        let dir = storageDirectory
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Loads the Photos backup configuration from disk, falling back to a default configuration if missing.
    /// - Returns: Decoded or default `PhotosBackupConfiguration`.
    public func loadConfiguration() -> PhotosBackupConfiguration {
        lock.lock()
        defer { lock.unlock() }

        createDirectoryIfNeeded()
        let file = configFileURL

        if fileManager.fileExists(atPath: file.path) {
            do {
                let data = try Data(contentsOf: file)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(PhotosBackupConfiguration.self, from: data)
            } catch {
                // Fallback to default config on parse error
            }
        }

        let defaultConfig = PhotosBackupConfiguration()
        try? saveConfigurationUnlocked(defaultConfig)
        return defaultConfig
    }

    /// Persists the specified configuration to disk atomically.
    /// - Parameter config: The configuration to save.
    public func saveConfiguration(_ config: PhotosBackupConfiguration) throws {
        lock.lock()
        defer { lock.unlock() }
        try saveConfigurationUnlocked(config)
    }

    private func saveConfigurationUnlocked(_ config: PhotosBackupConfiguration) throws {
        createDirectoryIfNeeded()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(config)
        try data.write(to: configFileURL, options: .atomic)
    }
}
