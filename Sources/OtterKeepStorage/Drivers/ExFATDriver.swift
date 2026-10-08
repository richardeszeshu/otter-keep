import Foundation
import Darwin

/// Microsoft exFAT driver specialized for cross-platform flash drives and external hard drives.
/// Handles 10ms timestamp resolution, lack of POSIX hardlinks/symlinks, and stream-based data copying.
public final class ExFATDriver: BasePOSIXFileSystemDriver, @unchecked Sendable {

    public override var fsTypeName: String {
        "exfat"
    }

    public override init() {
        super.init()
    }

    public override func capabilities(at url: URL) async throws -> FileSystemCapabilities {
        let (_, fstype, isReadOnly) = try statfsInfo(at: url)

        return FileSystemCapabilities(
            fsTypeName: fstype.isEmpty ? "exfat" : fstype,
            supportsAPFSClone: false,
            supportsHardLinks: false,
            supportsExtendedAttributes: false,
            supportsSymlinks: false,
            supportsFileFlags: false,
            isReadOnly: isReadOnly
        )
    }

    public override func cloneOrCopyItem(
        at source: URL,
        to destination: URL,
        progress: (@Sendable (Int64) -> Void)?
    ) async throws {
        try await copyfileStream(
            at: source,
            to: destination,
            cloneAllowed: false,
            fallbackToDataStat: true,
            progress: progress
        )
    }

    public override func createHardLink(at source: URL, to destination: URL) async throws {
        throw FileSystemError.unsupportedOperation("POSIX hard links are not supported on exFAT volumes.")
    }

    public override func getExtendedAttributes(at url: URL) throws -> [String: Data] {
        // Native exFAT does not store Darwin extended attributes
        return [:]
    }

    public override func setExtendedAttributes(_ attributes: [String: Data], at url: URL) throws {
        // Gracefully ignore on exFAT without failing backup
    }

    public override func setImmutable(at url: URL, immutable: Bool, recursive: Bool) throws {
        // BSD chflags are not supported on exFAT volumes; treated as non-blocking advisory
    }

    public override func setImmutable(at url: URL, immutable: Bool) throws {
        // BSD chflags are not supported on exFAT volumes; treated as non-blocking advisory
    }

    public override func isFileImmutable(at url: URL) throws -> Bool {
        return false
    }
}
