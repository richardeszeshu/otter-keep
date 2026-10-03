import Foundation

/// Errors related to configuration export, import, and schema validation.
public enum ConfigurationArchiveError: LocalizedError, Sendable, Equatable {
    case invalidArchiveFormat(String)
    case unsupportedSchemaVersion(Int)
    case emptyProfiles
    case invalidProfile(String)
    case ioError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArchiveFormat(let reason):
            return "\(L10n.t(.importConfigInvalidFile)) (\(reason))"
        case .unsupportedSchemaVersion(let version):
            return "Unsupported configuration schema version: \(version)"
        case .emptyProfiles:
            return "Configuration archive contains no backup profiles."
        case .invalidProfile(let name):
            return "Configuration contains invalid profile: \(name)"
        case .ioError(let msg):
            return msg
        }
    }
}

/// Portable, serialized configuration archive containing all profiles, user settings, and photos backup parameters.
public struct ConfigurationExportArchive: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    /// Schema version for forward/backward compatibility validation.
    public var schemaVersion: Int
    /// Application version creating the archive.
    public var appVersion: String
    /// ISO8601 timestamp of export.
    public var exportDate: Date
    /// Configured backup profiles.
    public var profiles: [BackupProfile]
    /// Application preferences and settings.
    public var settings: AppSettings
    /// Optional Apple Photos backup configuration.
    public var photosConfig: PhotosBackupConfiguration?

    public init(
        schemaVersion: Int = ConfigurationExportArchive.currentSchemaVersion,
        appVersion: String = CoreEngine.version,
        exportDate: Date = Date(),
        profiles: [BackupProfile],
        settings: AppSettings,
        photosConfig: PhotosBackupConfiguration? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.exportDate = exportDate
        self.profiles = profiles
        self.settings = settings
        self.photosConfig = photosConfig
    }
}

/// Central manager coordinating atomic JSON export, import, and structural validation of OtterKeep configuration archives.
public final class ConfigurationBackupManager: Sendable {
    public static let shared = ConfigurationBackupManager()

    public init() {}

    /// Creates an in-memory `ConfigurationExportArchive` model.
    public func createArchive(
        profiles: [BackupProfile],
        settings: AppSettings,
        photosConfig: PhotosBackupConfiguration? = nil
    ) -> ConfigurationExportArchive {
        ConfigurationExportArchive(
            schemaVersion: ConfigurationExportArchive.currentSchemaVersion,
            appVersion: CoreEngine.version,
            exportDate: Date(),
            profiles: profiles,
            settings: settings,
            photosConfig: photosConfig
        )
    }

    /// Encodes configuration archive into pretty-printed, deterministic JSON data.
    public func exportConfigurationData(
        profiles: [BackupProfile],
        settings: AppSettings,
        photosConfig: PhotosBackupConfiguration? = nil
    ) throws -> Data {
        let archive = createArchive(profiles: profiles, settings: settings, photosConfig: photosConfig)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    /// Atomically writes configuration archive to destination URL with secure 0600 file permissions.
    public func exportConfiguration(
        to url: URL,
        profiles: [BackupProfile],
        settings: AppSettings,
        photosConfig: PhotosBackupConfiguration? = nil
    ) throws {
        let data = try exportConfigurationData(profiles: profiles, settings: settings, photosConfig: photosConfig)
        let parentDir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Decodes and validates a `ConfigurationExportArchive` from raw JSON data.
    public func parseArchive(from data: Data) throws -> ConfigurationExportArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let archive = try decoder.decode(ConfigurationExportArchive.self, from: data)
            try validateArchive(archive)
            return archive
        } catch let err as ConfigurationArchiveError {
            throw err
        } catch {
            throw ConfigurationArchiveError.invalidArchiveFormat(error.localizedDescription)
        }
    }

    /// Reads, decodes, and validates a `ConfigurationExportArchive` from a file on disk.
    public func parseArchive(from url: URL) throws -> ConfigurationExportArchive {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigurationArchiveError.ioError("File not found at \(url.path)")
        }
        let data = try Data(contentsOf: url)
        return try parseArchive(from: data)
    }

    /// Validates structural integrity and constraints of a configuration archive.
    public func validateArchive(_ archive: ConfigurationExportArchive) throws {
        guard archive.schemaVersion >= 1 else {
            throw ConfigurationArchiveError.unsupportedSchemaVersion(archive.schemaVersion)
        }
        guard !archive.profiles.isEmpty else {
            throw ConfigurationArchiveError.emptyProfiles
        }
        for profile in archive.profiles {
            let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw ConfigurationArchiveError.invalidProfile("Profile name cannot be empty")
            }
            guard !profile.sourceURL.path.isEmpty, !profile.destinationURL.path.isEmpty else {
                throw ConfigurationArchiveError.invalidProfile(name)
            }
        }
    }
}
