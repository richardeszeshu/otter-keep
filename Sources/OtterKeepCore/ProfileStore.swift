import Foundation

/// Thread-safe persistence store managing backup profile configurations stored in `~/.otterkeep/profiles.json`.
public final class ProfileStore: @unchecked Sendable {
    /// Shared singleton instance.
    public static let shared = ProfileStore()

    private let lock = NSLock()
    private let fileManager = FileManager.default

    /// Real user home directory URL resolved via POSIX getpwuid to avoid sandbox redirection discrepancies.
    public var realUserHome: URL {
        if let pw = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
        }
        return fileManager.homeDirectoryForCurrentUser
    }

    /// Base storage directory (`~/.otterkeep/`).
    public var storageDirectory: URL {
        realUserHome.appendingPathComponent(".otterkeep", isDirectory: true)
    }

    /// Full path to the `profiles.json` configuration file.
    public var profilesFileURL: URL {
        storageDirectory.appendingPathComponent("profiles.json")
    }

    private init() {
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        let dir = storageDirectory
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // Enforce strict 0700 permissions on ~/.otterkeep/
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
    }

    /// Loads all configured backup profiles from disk. If no profiles exist, creates and persists a default initial profile.
    /// - Returns: Array of `BackupProfile` instances.
    public func loadProfiles() -> [BackupProfile] {
        lock.lock()
        defer { lock.unlock() }

        createDirectoryIfNeeded()
        return loadProfilesUnlocked()
    }

    /// Persists an array of backup profiles to disk atomically.
    /// - Parameter profiles: Array of profiles to write.
    public func saveProfiles(_ profiles: [BackupProfile]) throws {
        lock.lock()
        defer { lock.unlock() }
        try saveProfilesUnlocked(profiles)
    }

    private func saveProfilesUnlocked(_ profiles: [BackupProfile]) throws {
        createDirectoryIfNeeded()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profiles)
        try data.write(to: profilesFileURL, options: .atomic)
        // Enforce strict 0600 permissions on profiles.json
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: profilesFileURL.path)

        // Mirror to sandboxed FinderSync AppExtension container
        let realHome: URL
        if let pw = getpwuid(getuid()) {
            realHome = URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
        } else {
            realHome = fileManager.homeDirectoryForCurrentUser
        }
        let containerDir = realHome
            .appendingPathComponent("Library/Containers/com.otterkeep.OtterKeepApp.FinderSync/Data/.otterkeep", isDirectory: true)
        if !fileManager.fileExists(atPath: containerDir.path) {
            try? fileManager.createDirectory(at: containerDir, withIntermediateDirectories: true)
        }
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: containerDir.path)
        let containerFile = containerDir.appendingPathComponent("profiles.json")
        try? data.write(to: containerFile, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: containerFile.path)

        // Broadcast profile change to FinderSync extension
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.otterkeep.finderIntegrationChanged"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    /// Updates an existing profile by ID or appends it if not present.
    /// - Parameter profile: The profile to update or add.
    public func updateProfile(_ profile: BackupProfile) throws {
        lock.lock()
        defer { lock.unlock() }

        var current = loadProfilesUnlocked()
        if let idx = current.firstIndex(where: { $0.id == profile.id }) {
            current[idx] = profile
        } else {
            current.append(profile)
        }
        try saveProfilesUnlocked(current)
    }

    /// Deletes a profile by ID, ensuring at least one profile remains in the list.
    /// - Parameter id: Unique profile UUID.
    public func deleteProfile(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        var current = loadProfilesUnlocked()
        guard current.count > 1 else { return }
        if let removed = current.first(where: { $0.id == id }) {
            KeychainManager.deletePassphrase(for: id)
            KeychainManager.deleteSecret(for: id.uuidString)
            KeychainManager.deleteSecret(for: "s3_\(id.uuidString)")
            KeychainManager.deleteSecret(for: "smb_\(id.uuidString)")
            KeychainManager.deleteSecret(for: "webdav_\(id.uuidString)")
            KeychainManager.deleteSecret(for: "sftp_\(id.uuidString)")
            KeychainManager.deleteSecret(for: "webhook_\(id.uuidString)")
            for dest in removed.copyJobConfig.destinations {
                KeychainManager.deleteSecret(for: dest.id.uuidString)
                KeychainManager.deleteSecret(for: "s3_\(dest.id.uuidString)")
                KeychainManager.deleteSecret(for: "smb_\(dest.id.uuidString)")
                KeychainManager.deleteSecret(for: "webdav_\(dest.id.uuidString)")
                KeychainManager.deleteSecret(for: "sftp_\(dest.id.uuidString)")
            }
        }
        current.removeAll(where: { $0.id == id })
        try saveProfilesUnlocked(current)
    }

    private func loadProfilesUnlocked() -> [BackupProfile] {
        var candidateFiles: [URL] = [profilesFileURL]
        if let pw = getpwuid(getuid()) {
            let realHome = URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
            let realPath = realHome.appendingPathComponent(".otterkeep/profiles.json")
            if !candidateFiles.contains(realPath) {
                candidateFiles.insert(realPath, at: 0)
            }
            let realContainerPath = realHome
                .appendingPathComponent("Library/Containers/com.otterkeep.OtterKeepApp.FinderSync/Data/.otterkeep/profiles.json")
            if !candidateFiles.contains(realContainerPath) {
                candidateFiles.append(realContainerPath)
            }
        }
        let currentHomeContainer = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".otterkeep/profiles.json")
        if !candidateFiles.contains(currentHomeContainer) {
            candidateFiles.append(currentHomeContainer)
        }

        for file in candidateFiles {
            if fileManager.fileExists(atPath: file.path),
               let data = try? Data(contentsOf: file) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let list = try? decoder.decode([BackupProfile].self, from: data), !list.isEmpty {
                    return list
                }
            }
        }
        return [createDefaultInitialProfile()]
    }

    /// Creates a default initial profile pointing to standard user Documents and a local backup destination.
    /// - Returns: A standard `BackupProfile`.
    public func createDefaultInitialProfile() -> BackupProfile {
        let home = realUserHome
        return BackupProfile(
            name: BackupProfile.defaultProfileName,
            sourceURL: home.appendingPathComponent("Documents"),
            destinationURL: home.appendingPathComponent("OtterKeep_Backups"),
            excludePatterns: ["*.tmp", ".DS_Store", "node_modules", "DerivedData"]
        )
    }
}
