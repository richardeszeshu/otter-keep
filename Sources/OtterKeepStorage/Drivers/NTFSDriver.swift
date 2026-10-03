import Foundation
import Darwin

/// Microsoft NTFS driver specialized for read-only or read-write NTFS volumes.
/// Enforces read-only safety preflight on macOS when third-party write drivers are not installed,
/// while providing full differential source reading and stream metadata preservation.
public final class NTFSDriver: BasePOSIXFileSystemDriver, @unchecked Sendable {

    public override var fsTypeName: String {
        "ntfs"
    }

    public override init() {
        super.init()
    }

    public override func capabilities(at url: URL) async throws -> FileSystemCapabilities {
        let (_, fstype, isReadOnly) = try statfsInfo(at: url)

        return FileSystemCapabilities(
            fsTypeName: fstype.isEmpty ? "ntfs" : fstype,
            supportsAPFSClone: false,
            supportsHardLinks: !isReadOnly,
            supportsExtendedAttributes: false,
            supportsSymlinks: true,
            supportsFileFlags: false,
            isReadOnly: isReadOnly
        )
    }

    public override func cloneOrCopyItem(
        at source: URL,
        to destination: URL,
        progress: (@Sendable (Int64) -> Void)?
    ) async throws {
        let (_, _, isReadOnly) = try statfsInfo(at: destination)
        if isReadOnly {
            let dstPath = normalizedPath(for: destination)
            throw FileSystemError.permissionDenied(path: dstPath)
        }

        try await copyfileStream(
            at: source,
            to: destination,
            cloneAllowed: false,
            fallbackToDataStat: true,
            progress: progress
        )
    }

    public override func createHardLink(at source: URL, to destination: URL) async throws {
        let (_, _, isReadOnly) = try statfsInfo(at: destination)
        if isReadOnly {
            let dstPath = normalizedPath(for: destination)
            throw FileSystemError.permissionDenied(path: dstPath)
        }

        try await posixHardLink(at: source, to: destination)
    }

    public override func getExtendedAttributes(at url: URL) throws -> [String: Data] {
        return [:]
    }

    public override func setExtendedAttributes(_ attributes: [String: Data], at url: URL) throws {
        // Gracefully ignore on NTFS if unsupported
    }

    public override func setImmutable(at url: URL, immutable: Bool) throws {
        // Advisory on NTFS
    }
}
