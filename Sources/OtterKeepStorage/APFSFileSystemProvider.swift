import Foundation
import Darwin

/// Default macOS storage engine providing unified filesystem abstraction across APFS, exFAT, NTFS, and FAT
/// via the dynamic `FileSystemDriverRegistry` and specialized `FileSystemDriver` implementations.
public final class APFSFileSystemProvider: FileSystemProvider, Sendable {

    private let registry: FileSystemDriverRegistry

    /// Initializes a new `APFSFileSystemProvider` instance.
    /// - Parameter registry: Driver registry to use for driver resolution (defaults to `FileSystemDriverRegistry.shared`).
    public init(registry: FileSystemDriverRegistry = .shared) {
        self.registry = registry
    }

    // MARK: - Capabilities & Metrics

    /// Inspects and returns filesystem capabilities for the volume hosting the specified URL.
    /// - Parameter url: The URL to inspect.
    /// - Returns: A `FileSystemCapabilities` structure describing volume support flags.
    public func capabilities(at url: URL) async throws -> FileSystemCapabilities {
        try await registry.driver(for: url).capabilities(at: url)
    }

    /// Queries total, free, and available storage capacities on the volume hosting the specified URL.
    /// - Parameter url: The URL to inspect.
    /// - Returns: A `StorageCapacity` structure with capacity metrics in bytes.
    public func storageCapacity(at url: URL) throws -> StorageCapacity {
        try registry.driver(for: url).storageCapacity(at: url)
    }

    /// Retrieves detailed POSIX and Darwin metadata for an item.
    /// - Parameter url: The file or directory URL.
    /// - Returns: A `FileMetadata` descriptor.
    public func metadata(at url: URL) throws -> FileMetadata {
        try registry.driver(for: url).metadata(at: url)
    }

    // MARK: - Cloning & Transfer Operations

    /// Clones a file or directory using the destination filesystem driver's optimal method (CoW reflink or stream copy).
    /// - Parameters:
    ///   - source: Source file URL.
    ///   - destination: Destination URL where the clone will be created.
    public func cloneItem(at source: URL, to destination: URL) async throws {
        try await registry.driver(for: destination).cloneOrCopyItem(at: source, to: destination, progress: nil)
    }

    /// Creates a POSIX hard link pointing from source to destination if supported by the destination filesystem driver.
    /// - Parameters:
    ///   - source: Existing file URL.
    ///   - destination: New hard link URL.
    public func createHardLink(at source: URL, to destination: URL) async throws {
        try await registry.driver(for: destination).createHardLink(at: source, to: destination)
    }

    /// Copies an item while preserving full metadata, ACLs, flags, and extended attributes.
    /// - Parameters:
    ///   - source: Source URL.
    ///   - destination: Destination URL.
    ///   - progress: Optional callback invoked with cumulative bytes transferred.
    public func copyItemPreservingMetadata(
        at source: URL,
        to destination: URL,
        progress: (@Sendable (Int64) -> Void)?
    ) async throws {
        try await registry.driver(for: destination).cloneOrCopyItem(at: source, to: destination, progress: progress)
    }

    /// Atomically moves or renames an item within the same filesystem.
    /// - Parameters:
    ///   - source: Existing source URL.
    ///   - destination: Target destination URL.
    public func atomicMove(from source: URL, to destination: URL) async throws {
        try await registry.driver(for: source).atomicMove(from: source, to: destination)
    }

    // MARK: - Extended Attributes (xattr)

    /// Retrieves all extended attributes (xattrs) for the specified item.
    /// - Parameter url: Target file URL.
    /// - Returns: A dictionary mapping attribute names to raw binary Data.
    public func getExtendedAttributes(at url: URL) throws -> [String: Data] {
        try registry.driver(for: url).getExtendedAttributes(at: url)
    }

    /// Writes extended attributes (xattrs) to the specified item.
    /// - Parameters:
    ///   - attributes: Dictionary of attribute names and data values.
    ///   - url: Target file URL.
    public func setExtendedAttributes(_ attributes: [String: Data], at url: URL) throws {
        try registry.driver(for: url).setExtendedAttributes(attributes, at: url)
    }

    // MARK: - Directory & Flag Utilities

    /// Removes a file or directory hierarchy.
    /// - Parameter url: Item URL to delete.
    public func removeItem(at url: URL) throws {
        try registry.driver(for: url).removeItem(at: url)
    }

    /// Creates a directory and any intermediate parent folders if needed.
    /// - Parameter url: Directory URL to create.
    public func createDirectory(at url: URL) throws {
        try registry.driver(for: url).createDirectory(at: url)
    }

    /// Sets or removes the BSD file immutability flag (`UF_IMMUTABLE`) via the driver.
    /// - Parameters:
    ///   - url: Target item URL.
    ///   - immutable: True to set `UF_IMMUTABLE`, false to clear.
    public func setImmutable(at url: URL, immutable: Bool) throws {
        try registry.driver(for: url).setImmutable(at: url, immutable: immutable)
    }
}

/// Backward-compatible alias for the default filesystem provider.
public typealias DefaultFileSystemProvider = APFSFileSystemProvider
