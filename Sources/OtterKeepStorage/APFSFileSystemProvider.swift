import Foundation
import Darwin

/// Native macOS APFS and Darwin storage engine providing low-level Copy-on-Write cloning,
/// extended attribute manipulation, metadata-preserving file transfers, and WORM protection.
public final class APFSFileSystemProvider: FileSystemProvider, Sendable {

    /// Initializes a new `APFSFileSystemProvider` instance.
    public init() {}

    private func normalizedPath(for url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    // MARK: - FileSystemProvider Capabilities & Capacity

    /// Inspects and returns filesystem capabilities for the volume hosting the specified URL.
    /// - Parameter url: The URL to inspect.
    /// - Returns: A `FileSystemCapabilities` structure describing volume support flags.
    public func capabilities(at url: URL) async throws -> FileSystemCapabilities {
        var fs = statfs()
        let path = normalizedPath(for: url)
        let result = statfs(path, &fs)
        guard result == 0 else {
            let err = errno
            throw FileSystemError.unknown("statfs error (\(path)): [errno \(err)] \(String(cString: strerror(err)))")
        }

        let fstype = withUnsafePointer(to: &fs.f_fstypename) { ptr -> String in
            let rawPtr = UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            return String(cString: rawPtr)
        }

        let isAPFS = fstype.lowercased() == "apfs"
        let isReadOnly = (fs.f_flags & UInt32(MNT_RDONLY)) != 0

        return FileSystemCapabilities(
            fsTypeName: fstype,
            supportsAPFSClone: isAPFS,
            supportsHardLinks: true,
            supportsExtendedAttributes: true,
            isReadOnly: isReadOnly
        )
    }

    /// Queries total, free, and available storage capacities on the volume hosting the specified URL.
    /// - Parameter url: The URL to inspect.
    /// - Returns: A `StorageCapacity` structure with capacity metrics in bytes.
    public func storageCapacity(at url: URL) throws -> StorageCapacity {
        var fs = statfs()
        let path = normalizedPath(for: url)
        let result = statfs(path, &fs)
        guard result == 0 else {
            let err = errno
            throw FileSystemError.unknown("statfs error (\(path)): [errno \(err)] \(String(cString: strerror(err)))")
        }

        let blockSize = Int64(fs.f_bsize)
        let total = Int64(fs.f_blocks) * blockSize
        let free = Int64(fs.f_bfree) * blockSize
        let avail = Int64(fs.f_bavail) * blockSize

        return StorageCapacity(
            totalBytes: max(0, total),
            freeBytes: max(0, free),
            availableBytes: max(0, avail)
        )
    }

    /// Retrieves detailed POSIX and Darwin metadata for an item.
    /// - Parameter url: The file or directory URL.
    /// - Returns: A `FileMetadata` descriptor.
    public func metadata(at url: URL) throws -> FileMetadata {
        let path = normalizedPath(for: url)
        var st = stat()
        let res = lstat(path, &st)
        guard res == 0 else {
            let err = errno
            if err == ENOENT {
                throw FileSystemError.itemNotFound(path: path)
            } else if err == EACCES {
                throw FileSystemError.permissionDenied(path: path)
            }
            throw FileSystemError.unknown("lstat error (\(path)): [errno \(err)] \(String(cString: strerror(err)))")
        }

        let isDir = (st.st_mode & S_IFMT) == S_IFDIR
        let isLnk = (st.st_mode & S_IFMT) == S_IFLNK
        let mtime = Date(
            timeIntervalSince1970: Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000.0
        )

        return FileMetadata(
            url: url,
            size: Int64(st.st_size),
            modificationTime: mtime,
            inode: UInt64(st.st_ino),
            posixPermissions: UInt16(st.st_mode & 0o7777),
            isDirectory: isDir,
            isSymlink: isLnk
        )
    }

    // MARK: - Cloning (APFS Copy-on-Write)

    /// Clones a file or directory on the same APFS volume using Copy-on-Write (reflink).
    /// - Parameters:
    ///   - source: Source file URL.
    ///   - destination: Destination URL where the clone will be created.
    public func cloneItem(at source: URL, to destination: URL) async throws {
        let srcPath = normalizedPath(for: source)
        let dstPath = normalizedPath(for: destination)

        if FileManager.default.fileExists(atPath: dstPath) {
            throw FileSystemError.itemAlreadyExists(path: dstPath)
        }

        let flags = UInt32(CLONE_NOFOLLOW)
        let res = clonefile(srcPath, dstPath, flags)
        guard res == 0 else {
            let err = errno
            if err == ENOENT {
                throw FileSystemError.itemNotFound(path: srcPath)
            } else if err == EEXIST {
                throw FileSystemError.itemAlreadyExists(path: dstPath)
            } else if err == EACCES || err == EPERM {
                throw FileSystemError.permissionDenied(path: dstPath)
            } else if err == ENOSPC {
                throw FileSystemError.notEnoughSpace(requiredBytes: 0, availableBytes: 0)
            } else if err == EXDEV || err == ENOTSUP {
                // Cross-device or unsupported APFS clone; fall back to metadata-preserving copy
                try await copyItemPreservingMetadata(at: source, to: destination, progress: nil)
                return
            }
            throw FileSystemError.cloneFailed(
                path: srcPath,
                errno: err,
                message: String(cString: strerror(err))
            )
        }
    }

    // MARK: - Hard Links

    /// Creates a POSIX hard link pointing from source to destination.
    /// - Parameters:
    ///   - source: Existing file URL.
    ///   - destination: New hard link URL.
    public func createHardLink(at source: URL, to destination: URL) async throws {
        let srcPath = normalizedPath(for: source)
        let dstPath = normalizedPath(for: destination)

        let res = link(srcPath, dstPath)
        guard res == 0 else {
            let err = errno
            if err == ENOENT {
                throw FileSystemError.itemNotFound(path: srcPath)
            } else if err == EEXIST {
                throw FileSystemError.itemAlreadyExists(path: dstPath)
            } else if err == EACCES || err == EPERM {
                throw FileSystemError.permissionDenied(path: dstPath)
            } else if err == EXDEV {
                throw FileSystemError.hardLinkFailed(
                    path: srcPath,
                    errno: err,
                    message: "Cross-device hard links are not supported by POSIX (EXDEV)"
                )
            }
            throw FileSystemError.hardLinkFailed(
                path: srcPath,
                errno: err,
                message: String(cString: strerror(err))
            )
        }
    }

    // MARK: - Darwin copyfile Transfer

    private final class ProgressContext {
        let callback: (@Sendable (Int64) -> Void)?
        init(callback: (@Sendable (Int64) -> Void)?) {
            self.callback = callback
        }
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
        let srcPath = normalizedPath(for: source)
        let dstPath = normalizedPath(for: destination)

        // Handle directories gracefully if encountered
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: srcPath, isDirectory: &isDir), isDir.boolValue {
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                progress?(0)
                return
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }

        guard let state = copyfile_state_alloc() else {
            throw FileSystemError.copyFailed(path: srcPath, errno: ENOMEM, message: "copyfile_state_alloc failed")
        }
        defer {
            copyfile_state_free(state)
        }

        let context = ProgressContext(callback: progress)

        if progress != nil {
            let callback: copyfile_callback_t = { (what, stage, state, src, dst, ctx) -> Int32 in
                guard let ctx = ctx else { return COPYFILE_CONTINUE }
                let progressCtx = Unmanaged<ProgressContext>.fromOpaque(ctx).takeUnretainedValue()

                if what == COPYFILE_COPY_DATA && stage == COPYFILE_PROGRESS {
                    var bytesCopied: off_t = 0
                    copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &bytesCopied)
                    progressCtx.callback?(Int64(bytesCopied))
                }
                return COPYFILE_CONTINUE
            }

            let ctxPointer = Unmanaged.passUnretained(context).toOpaque()
            copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
            copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), ctxPointer)
        }

        // COPYFILE_ALL encompasses data, xattrs, stat, flags, and ACLs.
        // COPYFILE_NOFOLLOW preserves symbolic links as links.
        // COPYFILE_CLONE attempts APFS CoW cloning whenever supported by the filesystem.
        let flags: copyfile_flags_t = copyfile_flags_t(COPYFILE_ALL | COPYFILE_NOFOLLOW | COPYFILE_CLONE)

        let res = copyfile(srcPath, dstPath, state, flags)
        guard res == 0 else {
            let err = errno
            // Clean up any partially written or half-finished destination file on copy failure
            _ = unlink(dstPath)
            if err == ENOENT {
                throw FileSystemError.itemNotFound(path: srcPath)
            } else if err == EEXIST {
                throw FileSystemError.itemAlreadyExists(path: dstPath)
            } else if err == EACCES || err == EPERM {
                throw FileSystemError.permissionDenied(path: dstPath)
            } else if err == ENOSPC {
                throw FileSystemError.notEnoughSpace(requiredBytes: 0, availableBytes: 0)
            }
            throw FileSystemError.copyFailed(
                path: srcPath,
                errno: err,
                message: String(cString: strerror(err))
            )
        }

        // If the progress callback was not invoked during instantaneous APFS clone, report the file size.
        if let progress = progress {
            var bytesCopied: off_t = 0
            copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &bytesCopied)
            if bytesCopied == 0 {
                var st = stat()
                if lstat(dstPath, &st) == 0 {
                    bytesCopied = st.st_size
                }
            }
            progress(Int64(bytesCopied))
        }
    }

    // MARK: - Atomic Renaming & Move

    /// Atomically moves or renames an item within the same filesystem.
    /// - Parameters:
    ///   - source: Existing source URL.
    ///   - destination: Target destination URL.
    public func atomicMove(from source: URL, to destination: URL) async throws {
        let srcPath = normalizedPath(for: source)
        let dstPath = normalizedPath(for: destination)

        let res = rename(srcPath, dstPath)
        guard res == 0 else {
            let err = errno
            throw FileSystemError.atomicMoveFailed(
                source: srcPath,
                destination: dstPath,
                errno: err,
                message: String(cString: strerror(err))
            )
        }
    }

    // MARK: - Extended Attributes (xattr)

    /// Retrieves all extended attributes (xattrs) for the specified item.
    /// - Parameter url: Target file URL.
    /// - Returns: A dictionary mapping attribute names to raw binary Data.
    public func getExtendedAttributes(at url: URL) throws -> [String: Data] {
        let path = normalizedPath(for: url)
        let bufferSize = listxattr(path, nil, 0, XATTR_NOFOLLOW)
        guard bufferSize >= 0 else {
            let err = errno
            if err == ENOENT { throw FileSystemError.itemNotFound(path: path) }
            throw FileSystemError.attributeOperationFailed(
                path: path,
                name: "*list*",
                errno: err,
                message: String(cString: strerror(err))
            )
        }

        if bufferSize == 0 {
            return [:]
        }

        var nameBuffer = [CChar](repeating: 0, count: bufferSize)
        let fetchedSize = listxattr(path, &nameBuffer, bufferSize, XATTR_NOFOLLOW)
        guard fetchedSize >= 0 else {
            let err = errno
            throw FileSystemError.attributeOperationFailed(
                path: path,
                name: "*list*",
                errno: err,
                message: String(cString: strerror(err))
            )
        }

        var attributes: [String: Data] = [:]
        var currentIndex = 0
        while currentIndex < fetchedSize {
            let name = nameBuffer.withUnsafeBufferPointer { buf in
                String(cString: buf.baseAddress! + currentIndex)
            }
            currentIndex += name.utf8.count + 1

            let valSize = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
            if valSize > 0 {
                var dataBuffer = Data(count: valSize)
                let readSize = dataBuffer.withUnsafeMutableBytes { ptr in
                    getxattr(path, name, ptr.baseAddress, valSize, 0, XATTR_NOFOLLOW)
                }
                if readSize >= 0 {
                    attributes[name] = dataBuffer
                }
            } else if valSize == 0 {
                attributes[name] = Data()
            }
        }

        return attributes
    }

    /// Writes extended attributes (xattrs) to the specified item.
    /// - Parameters:
    ///   - attributes: Dictionary of attribute names and data values.
    ///   - url: Target file URL.
    public func setExtendedAttributes(_ attributes: [String: Data], at url: URL) throws {
        let path = normalizedPath(for: url)
        for (name, data) in attributes {
            let res: Int32 = data.withUnsafeBytes { rawPtr in
                setxattr(path, name, rawPtr.baseAddress, data.count, 0, XATTR_NOFOLLOW)
            }
            guard res == 0 else {
                let err = errno
                throw FileSystemError.attributeOperationFailed(
                    path: path,
                    name: name,
                    errno: err,
                    message: String(cString: strerror(err))
                )
            }
        }
    }

    // MARK: - Directory & Flag Utilities

    /// Removes a file or directory hierarchy.
    /// - Parameter url: Item URL to delete.
    public func removeItem(at url: URL) throws {
        let path = normalizedPath(for: url)
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Creates a directory and any intermediate parent folders if needed.
    /// - Parameter url: Directory URL to create.
    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Sets or removes the BSD file immutability flag (`UF_IMMUTABLE`) and hardens POSIX permissions for local tamper protection.
    /// - Parameters:
    ///   - url: Target item URL.
    ///   - immutable: True to set `UF_IMMUTABLE` and read-only mode, false to clear.
    public func setImmutable(at url: URL, immutable: Bool) throws {
        let path = normalizedPath(for: url)

        // 1. If unlocking, restore POSIX write permissions first
        if !immutable {
            var st = stat()
            if lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR {
                _ = chmod(path, st.st_mode | mode_t(0o700))
            }
        }

        // 2. Adjust BSD chflags (using lchflags to safely operate on symlinks without following)
        let flags: UInt32 = immutable ? UInt32(UF_IMMUTABLE) : 0
        let res = lchflags(path, flags)
        guard res == 0 else {
            let err = errno
            throw FileSystemError.attributeOperationFailed(
                path: path,
                name: "flags",
                errno: err,
                message: String(cString: strerror(err))
            )
        }

        // 3. If locking, remove POSIX write bits on directories for defense-in-depth against accidental unlinking
        if immutable {
            var st = stat()
            if lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR {
                _ = chmod(path, st.st_mode & ~mode_t(0o222))
            }
        }
    }
}
