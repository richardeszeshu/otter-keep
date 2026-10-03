import Foundation
import os
import OtterKeepStorage

/// Enforces a strict capacity boundary on temporary in-flight asset downloads to prevent local SSD saturation.
public actor EphemeralStorageGuard {
    private let maxInFlightBytes: Int64
    private var currentInFlightBytes: Int64 = 0
    private let temporaryDirectoryURL: URL
    private let logger = Logger(subsystem: "com.otterkeep", category: "EphemeralGuard")

    /// Initializes an `EphemeralStorageGuard` instance.
    /// - Parameters:
    ///   - maxInFlightBytes: Maximum bytes allowed in the transient buffer (default: 512 MB).
    ///   - temporaryDirectoryURL: Optional explicit directory URL for temporary downloads.
    public init(
        maxInFlightBytes: Int64 = 512 * 1024 * 1024,
        temporaryDirectoryURL: URL? = nil
    ) {
        self.maxInFlightBytes = maxInFlightBytes
        if let dir = temporaryDirectoryURL {
            self.temporaryDirectoryURL = dir
        } else {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("OtterKeepPhotosStream", isDirectory: true)
            self.temporaryDirectoryURL = tmp
        }
        try? FileManager.default.createDirectory(at: self.temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    /// Suspends execution until sufficient in-flight capacity is available for downloading the requested byte size.
    /// - Parameter estimatedBytes: The expected byte size of the pending download.
    public func acquireInFlightCapacity(for estimatedBytes: Int64) async {
        let needed = max(1024 * 1024, estimatedBytes)
        while currentInFlightBytes + needed > maxInFlightBytes && currentInFlightBytes > 0 {
            // Backoff briefly to allow concurrent workers to commit and evict files
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        currentInFlightBytes += needed
    }

    /// Releases previously acquired in-flight capacity once an asset has been transferred to its destination.
    /// - Parameter estimatedBytes: The released byte size.
    public func releaseInFlightCapacity(for estimatedBytes: Int64) {
        let needed = max(1024 * 1024, estimatedBytes)
        currentInFlightBytes = max(0, currentInFlightBytes - needed)
    }

    /// Current allocated in-flight buffer size in bytes.
    public var currentBufferBytes: Int64 {
        currentInFlightBytes
    }

    /// Creates a unique temporary file URL within the scratch workspace for staging an asset download.
    /// - Parameters:
    ///   - prefix: File name prefix.
    ///   - fileExtension: Target file extension.
    /// - Returns: Unique temporary destination file URL.
    public func createTemporaryFileURL(prefix: String, fileExtension: String) -> URL {
        let filename = "\(prefix)_\(UUID().uuidString).\(fileExtension)"
        return temporaryDirectoryURL.appendingPathComponent(filename)
    }

    /// Immediately deletes a temporary file from disk and releases associated local resources.
    /// - Parameter url: The temporary file URL to delete.
    public func evictTemporaryFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Purges all temporary staging files created during the Photos backup session.
    public func cleanupAllTemporaryFiles() {
        if let items = try? FileManager.default.contentsOfDirectory(at: temporaryDirectoryURL, includingPropertiesForKeys: nil) {
            for item in items {
                try? FileManager.default.removeItem(at: item)
            }
        }
        currentInFlightBytes = 0
    }
}
