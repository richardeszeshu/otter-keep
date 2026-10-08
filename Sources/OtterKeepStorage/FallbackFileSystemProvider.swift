import Foundation

/// Portable filesystem provider implementation providing compatibility fallback
/// for non-APFS external storage devices and alternative filesystem formats.
public final class FallbackFileSystemProvider: FileSystemProvider, Sendable {

    private let apfsFallback: APFSFileSystemProvider

    /// Initializes a new `FallbackFileSystemProvider` instance.
    public init() {
        self.apfsFallback = APFSFileSystemProvider()
    }

    /// Inspects and returns filesystem capabilities, marking APFS cloning as unsupported.
    /// - Parameter url: The URL to inspect.
    /// - Returns: A `FileSystemCapabilities` structure with `supportsAPFSClone = false`.
    public func capabilities(at url: URL) async throws -> FileSystemCapabilities {
        let baseCaps = try await apfsFallback.capabilities(at: url)
        return FileSystemCapabilities(
            fsTypeName: baseCaps.fsTypeName,
            supportsAPFSClone: false,
            supportsHardLinks: baseCaps.supportsHardLinks,
            supportsExtendedAttributes: baseCaps.supportsExtendedAttributes,
            supportsSymlinks: baseCaps.supportsSymlinks,
            supportsFileFlags: baseCaps.supportsFileFlags,
            isReadOnly: baseCaps.isReadOnly
        )
    }


    /// Queries storage capacity metrics via the underlying provider.
    /// - Parameter url: Target volume URL.
    /// - Returns: A `StorageCapacity` metric structure.
    public func storageCapacity(at url: URL) throws -> StorageCapacity {
        try apfsFallback.storageCapacity(at: url)
    }

    /// Retrieves detailed metadata for an item.
    /// - Parameter url: Target item URL.
    /// - Returns: A `FileMetadata` descriptor.
    public func metadata(at url: URL) throws -> FileMetadata {
        try apfsFallback.metadata(at: url)
    }

    /// Clones an item by falling back to metadata-preserving copying.
    /// - Parameters:
    ///   - source: Source file URL.
    ///   - destination: Target destination URL.
    public func cloneItem(at source: URL, to destination: URL) async throws {
        try await copyItemPreservingMetadata(at: source, to: destination, progress: nil)
    }

    /// Creates a POSIX hard link pointing from source to destination.
    /// - Parameters:
    ///   - source: Source file URL.
    ///   - destination: Destination URL.
    public func createHardLink(at source: URL, to destination: URL) async throws {
        try await apfsFallback.createHardLink(at: source, to: destination)
    }

    /// Copies an item while preserving full metadata, ACLs, and attributes.
    /// - Parameters:
    ///   - source: Source URL.
    ///   - destination: Destination URL.
    ///   - progress: Optional progress callback.
    public func copyItemPreservingMetadata(
        at source: URL,
        to destination: URL,
        progress: (@Sendable (Int64) -> Void)?
    ) async throws {
        try await apfsFallback.copyItemPreservingMetadata(at: source, to: destination, progress: progress)
    }

    /// Atomically moves or renames an item.
    /// - Parameters:
    ///   - source: Source URL.
    ///   - destination: Destination URL.
    public func atomicMove(from source: URL, to destination: URL) async throws {
        try await apfsFallback.atomicMove(from: source, to: destination)
    }

    /// Retrieves extended attributes from the specified item.
    /// - Parameter url: Target item URL.
    /// - Returns: Dictionary of attribute names and binary data.
    public func getExtendedAttributes(at url: URL) throws -> [String: Data] {
        try apfsFallback.getExtendedAttributes(at: url)
    }

    /// Writes extended attributes to the specified item.
    /// - Parameters:
    ///   - attributes: Dictionary of extended attributes.
    ///   - url: Target item URL.
    public func setExtendedAttributes(_ attributes: [String: Data], at url: URL) throws {
        try apfsFallback.setExtendedAttributes(attributes, at: url)
    }

    /// Removes a file or directory.
    /// - Parameter url: Target item URL to delete.
    public func removeItem(at url: URL) throws {
        try apfsFallback.removeItem(at: url)
    }

    /// Creates a directory and any intermediate parent folders if needed.
    /// - Parameter url: Target directory URL.
    public func createDirectory(at url: URL) throws {
        try apfsFallback.createDirectory(at: url)
    }

    /// Sets or removes the BSD file immutability flag (`UF_IMMUTABLE`).
    /// - Parameters:
    ///   - url: Target item URL.
    ///   - immutable: True to lock, false to unlock.
    public func setImmutable(at url: URL, immutable: Bool) throws {
        try apfsFallback.setImmutable(at: url, immutable: immutable)
    }

    /// Queries whether the BSD file immutability flag is set on the item.
    /// - Parameter url: Target item URL.
    /// - Returns: True if immutable.
    public func isFileImmutable(at url: URL) throws -> Bool {
        try apfsFallback.isFileImmutable(at: url)
    }
}
