import Foundation
import os

/// Structured errors encountered during encrypted container operations.
public enum EncryptionError: Error, Sendable, LocalizedError, Equatable {
    case creationFailed(String)
    case attachFailed(String)
    case detachFailed(String)
    case missingPassphrase(String)
    case containerNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .creationFailed(let msg): return "Encrypted container creation failed: \(msg)"
        case .attachFailed(let msg): return "Failed to mount encrypted container: \(msg)"
        case .detachFailed(let msg): return "Failed to unmount encrypted container: \(msg)"
        case .missingPassphrase(let msg): return "Missing encryption passphrase: \(msg)"
        case .containerNotFound(let path): return "Encrypted container not found at: \(path)"
        }
    }
}

/// Actor managing native macOS encrypted APFS Sparsebundle containers (AES-256).
public actor EncryptedStorageManager {
    private let logger = Logger(subsystem: "com.otterkeep", category: "EncryptedStorage")

    public init() {}

    /// Checks whether an encrypted sparsebundle exists at the specified URL.
    /// - Parameter url: Container path URL.
    public func containerExists(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Creates a new dynamically-expanding AES-256 encrypted APFS Sparsebundle container.
    /// - Parameters:
    ///   - bundleURL: Target path URL ending with `.sparsebundle`.
    ///   - volumeName: APFS volume display name inside the container.
    ///   - passphrase: Encryption password.
    ///   - maxSizeGB: Maximum logical capacity cap in gigabytes (default: 1000 GB).
    public func createContainer(
        at bundleURL: URL,
        volumeName: String = "OtterKeepBackup",
        passphrase: String,
        maxSizeGB: Int = 1000
    ) async throws {
        let bundlePath = bundleURL.standardizedFileURL.path(percentEncoded: false)
        if FileManager.default.fileExists(atPath: bundlePath) {
            logger.info("Encrypted container already exists at: \(bundlePath)")
            return
        }

        let parentDir = bundleURL.deletingLastPathComponent().standardizedFileURL.path(percentEncoded: false)
        try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = [
            "create",
            "-size", "\(maxSizeGB)g",
            "-fs", "APFS",
            "-type", "SPARSEBUNDLE",
            "-encryption", "AES-256",
            "-volname", volumeName,
            "-stdinpass",
            bundlePath
        ]

        let stdinPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardError = errorPipe

        try process.run()

        if let passData = "\(passphrase)\n".data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(passData)
            try? stdinPipe.fileHandleForWriting.close()
        }

        async let errTask = Task.detached { errorPipe.fileHandleForReading.readDataToEndOfFile() }.value

        process.waitUntilExit()
        let errData = await errTask

        if process.terminationStatus != 0 {
            let errStr = String(data: errData, encoding: .utf8) ?? "Unknown hdiutil error"
            logger.error("Failed to create encrypted sparsebundle: \(errStr)")
            throw EncryptionError.creationFailed(errStr)
        }

        logger.info("Successfully initialized AES-256 encrypted APFS container: \(bundleURL.lastPathComponent)")
    }

    /// Mounts an encrypted sparsebundle using the provided passphrase and returns the mounted volume URL.
    /// - Parameters:
    ///   - bundleURL: The `.sparsebundle` URL.
    ///   - passphrase: Decryption passphrase.
    /// - Returns: File URL pointing to the mounted APFS filesystem root.
    public func mountContainer(at bundleURL: URL, passphrase: String) async throws -> URL {
        let bundlePath = bundleURL.standardizedFileURL.path(percentEncoded: false)

        // Check if already mounted
        if let existingMount = getMountPoint(for: bundleURL) {
            logger.info("Container is already mounted at: \(existingMount.path)")
            return existingMount
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = [
            "attach",
            bundlePath,
            "-stdinpass",
            "-plist",
            "-nobrowse"
        ]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        if let passData = "\(passphrase)\n".data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(passData)
            try? stdinPipe.fileHandleForWriting.close()
        }

        async let outTask = Task.detached { stdoutPipe.fileHandleForReading.readDataToEndOfFile() }.value
        async let errTask = Task.detached { stderrPipe.fileHandleForReading.readDataToEndOfFile() }.value

        process.waitUntilExit()

        let outData = await outTask
        let attachErrData = await errTask

        guard process.terminationStatus == 0 else {
            let errStr = String(data: attachErrData, encoding: .utf8) ?? "Authentication or attachment failed"
            logger.error("hdiutil attach failed: \(errStr)")
            throw EncryptionError.attachFailed(errStr)
        }
        if let plist = try? PropertyListSerialization.propertyList(from: outData, options: [], format: nil) as? [String: Any],
           let entities = plist["system-entities"] as? [[String: Any]] {
            for entity in entities {
                if let mountPoint = entity["mount-point"] as? String {
                    let mountURL = URL(fileURLWithPath: mountPoint)
                    logger.info("Encrypted container mounted successfully at: \(mountPoint)")
                    return mountURL
                }
            }
        }

        // Fallback: query mount point via hdiutil info
        if let mountURL = getMountPoint(for: bundleURL) {
            return mountURL
        }

        throw EncryptionError.attachFailed("Could not determine mount point for attached container")
    }

    /// Unmounts / detaches an attached encrypted container disk.
    /// - Parameter mountPoint: The mounted filesystem URL.
    public func unmountContainer(at mountPoint: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = [
            "detach",
            mountPoint.standardizedFileURL.path(percentEncoded: false),
            "-force"
        ]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? "hdiutil detach error"
            logger.warning("Notice: hdiutil detach returned error: \(errStr)")
            throw EncryptionError.detachFailed(errStr)
        }

        logger.info("Successfully unmounted container from: \(mountPoint.path)")
    }

    /// Queries the current mount point of a container if currently attached.
    /// - Parameter bundleURL: Container URL.
    /// - Returns: Mount point URL if attached, nil otherwise.
    public func getMountPoint(for bundleURL: URL) -> URL? {
        let bundlePath = bundleURL.standardizedFileURL.path(percentEncoded: false)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                  let images = plist["images"] as? [[String: Any]] else {
                return nil
            }

            for image in images {
                if let imagePath = image["image-path"] as? String,
                   URL(fileURLWithPath: imagePath).standardizedFileURL.path(percentEncoded: false) == bundlePath,
                   let entities = image["system-entities"] as? [[String: Any]] {
                    for entity in entities {
                        if let mp = entity["mount-point"] as? String {
                            return URL(fileURLWithPath: mp)
                        }
                    }
                }
            }
        } catch {
            return nil
        }
        return nil
    }
}
