import Foundation
import Darwin

/// Registry and factory for resolving and dispatching filesystem-specific drivers (`FileSystemDriver`).
public final class FileSystemDriverRegistry: @unchecked Sendable {

    /// Shared singleton instance.
    public static let shared = FileSystemDriverRegistry()

    private let lock = NSLock()
    private var drivers: [String: FileSystemDriver] = [:]
    private let fallbackDriver: FileSystemDriver

    /// Initializes a new `FileSystemDriverRegistry` pre-populated with standard Apple and Windows filesystem drivers.
    public init() {
        let apfs = APFSDriver()
        let exfat = ExFATDriver()
        let ntfs = NTFSDriver()
        let fat = FATDriver()
        let generic = GenericPOSIXDriver()

        self.fallbackDriver = generic
        self.drivers = [
            "apfs": apfs,
            "exfat": exfat,
            "ntfs": ntfs,
            "msdos": fat,
            "fat": fat,
            "fat32": fat,
            "generic": generic
        ]
    }

    /// Registers or replaces a driver for a specific filesystem type key.
    /// - Parameters:
    ///   - driver: The `FileSystemDriver` instance.
    ///   - typeName: The filesystem type identifier string (e.g. "apfs", "exfat", "ext4").
    public func register(driver: FileSystemDriver, forFSType typeName: String) {
        lock.lock()
        defer { lock.unlock() }
        drivers[typeName.lowercased()] = driver
    }

    /// Resolves the filesystem driver by type name.
    /// - Parameter typeName: The filesystem type string.
    /// - Returns: The registered `FileSystemDriver`, or `GenericPOSIXDriver` if unrecognized.
    public func driver(forFSType typeName: String) -> FileSystemDriver {
        lock.lock()
        defer { lock.unlock() }
        let key = typeName.lowercased()
        if let direct = drivers[key] {
            return direct
        }
        if key.contains("ntfs") {
            return drivers["ntfs"] ?? fallbackDriver
        }
        if key.contains("fat") || key.contains("msdos") {
            return drivers["msdos"] ?? fallbackDriver
        }
        return fallbackDriver
    }

    /// Resolves the appropriate filesystem driver for the volume hosting the specified URL via `statfs(2)`.
    /// - Parameter url: The file or directory URL to inspect.
    /// - Returns: The corresponding `FileSystemDriver`.
    public func driver(for url: URL) -> FileSystemDriver {
        var path = url.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }

        var fs = statfs()
        let res = statfs(path, &fs)
        guard res == 0 else {
            return fallbackDriver
        }

        let fstype = withUnsafePointer(to: &fs.f_fstypename) { ptr -> String in
            let rawPtr = UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            return String(cString: rawPtr)
        }

        return driver(forFSType: fstype)
    }
}
