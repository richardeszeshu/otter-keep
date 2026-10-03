import Foundation
import os
import Darwin
import OtterKeepStorage

/// Utility guarding against torn reads, open-file mutations, and mid-transfer modifications during live backups.
public enum LiveFileConsistencyGuard {
    private static let logger = Logger(subsystem: "com.otterkeep", category: "ConsistencyGuard")

    /// Copies a source file while verifying that the source was not mutated mid-transfer (anti-torn-read).
    /// Retries up to `maxRetries` if intra-transfer mutation is detected.
    /// - Parameters:
    ///   - storage: Filesystem provider.
    ///   - sourceURL: Source file URL.
    ///   - destinationURL: Destination file URL.
    ///   - maxRetries: Maximum retries if mutation is detected (default: 2).
    ///   - progress: Optional transfer progress callback.
    public static func copyConsistent(
        storage: FileSystemProvider,
        sourceURL: URL,
        destinationURL: URL,
        maxRetries: Int = 2,
        progress: (@Sendable (Int64) -> Void)? = nil
    ) async throws {
        let srcPath = sourceURL.standardizedFileURL.path(percentEncoded: false)
        var attempts = 0

        while attempts <= maxRetries {
            attempts += 1

            // 1. Pre-copy stat
            var preStat = stat()
            guard lstat(srcPath, &preStat) == 0 else {
                throw FileSystemError.itemNotFound(path: srcPath)
            }

            // 2. Perform copy
            try await storage.copyItemPreservingMetadata(at: sourceURL, to: destinationURL, progress: progress)

            // 3. Post-copy stat to ensure source was stable
            var postStat = stat()
            if lstat(srcPath, &postStat) == 0 {
                let sizeChanged = preStat.st_size != postStat.st_size
                let mtimeChanged = preStat.st_mtimespec.tv_sec != postStat.st_mtimespec.tv_sec ||
                                   preStat.st_mtimespec.tv_nsec != postStat.st_mtimespec.tv_nsec

                if sizeChanged || mtimeChanged {
                    logger.warning("Live file mutation (torn read risk) detected during copy of '\(sourceURL.lastPathComponent)' (Attempt \(attempts)/\(maxRetries + 1))")
                    if attempts <= maxRetries {
                        try? storage.removeItem(at: destinationURL)
                        try await Task.sleep(nanoseconds: 100_000_000) // 100ms pause for write to settle
                        continue
                    } else {
                        LogManager.shared.log(
                            "Notice: File '\(sourceURL.lastPathComponent)' was mutated during backup copy (torn read risk). The latest captured state was preserved.",
                            level: .warning,
                            category: "Backup"
                        )
                    }
                }
            }

            return
        }
    }
}
