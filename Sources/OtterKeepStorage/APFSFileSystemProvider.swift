import Foundation

/// Backward-compatible alias mapping APFSFileSystemProvider to the unified DefaultFileSystemProvider.
/// The storage layer dynamically routes operations via FileSystemDriverRegistry and specialized drivers.
public typealias APFSFileSystemProvider = DefaultFileSystemProvider
