import Foundation
import Darwin

/// Cross-process advisory lock preventing simultaneous backup or maintenance operations on the same profile.
///
/// Uses POSIX `flock(2)` on `~/.otterkeep/locks/<uuid>.lock` to ensure that if a backup is currently
/// executing in the GUI, any subsequent attempts from CLI or background LaunchAgent for that profile
/// are immediately rejected (Option 1) without file corruption or race conditions.
public final class ProfileExecutionLock: Sendable {
    /// Shared singleton instance.
    public static let shared = ProfileExecutionLock()

    private init() {}

    /// Attempts to acquire an exclusive lock for a given profile ID.
    /// - Parameter profileId: Unique profile identifier.
    /// - Returns: A non-nil `LockToken` on success; `nil` if already locked by another process.
    public func acquireLock(for profileId: UUID) -> LockToken? {
        let lockDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".otterkeep/locks", isDirectory: true)
        try? FileManager.default.createDirectory(at: lockDir, withIntermediateDirectories: true)
        let lockFile = lockDir.appendingPathComponent("\(profileId.uuidString).lock")

        let fd = open(lockFile.path(percentEncoded: false), O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return nil }

        // Non-blocking exclusive lock check
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return nil
        }

        return LockToken(fileDescriptor: fd, fileURL: lockFile)
    }

    /// Opaque RAII token holding the acquired file lock. Automatically releases upon deinit.
    public final class LockToken: @unchecked Sendable {
        private var fd: Int32
        private let fileURL: URL
        private var isReleased = false
        private let lock = NSLock()

        init(fileDescriptor: Int32, fileURL: URL) {
            self.fd = fileDescriptor
            self.fileURL = fileURL
        }

        /// Releases the held lock. The zero-byte lock file is retained to prevent POSIX flock inode race conditions across concurrent processes.
        public func release() {
            lock.lock()
            defer { lock.unlock() }
            guard !isReleased else { return }
            flock(fd, LOCK_UN)
            close(fd)
            // Do NOT unlink fileURL. Leaving the 0-byte lock file avoids inode allocation race conditions across CLI, GUI, and background daemons.
            isReleased = true
        }

        deinit {
            release()
        }
    }
}
