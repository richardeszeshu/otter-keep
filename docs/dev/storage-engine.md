# Storage Engine & Filesystem Fidelity

This document details the mechanics of `OtterKeepStorage`, including APFS Copy-on-Write cloning, fallback mechanisms, extended attribute handling, and filesystem driver capabilities.

---

## 1. APFS Copy-on-Write via `clonefile(2)`

The Apple File System (APFS) natively supports block sharing through the Darwin `clonefile(2)` system call:

```swift
// Direct Darwin clonefile invocation
let result = clonefile(sourcePath, destPath, Int32(CLONE_NOFOLLOW))
guard result == 0 else {
    let err = errno
    throw FileSystemError.cloneFailed(err)
}
```

### Advantages
- **Instantaneous Completion**: Operates entirely in metadata space without moving raw physical blocks.
- **Zero Additional Storage**: Storage blocks are shared between the historical snapshot and the new snapshot until modifications occur.
- **Independent Inodes**: The cloned file receives a distinct inode, ensuring subsequent modifications to one version do not alter the other.

---

## 2. Fallback Storage Strategies

For non-APFS volumes (such as HFS+, SMB network shares, or external exFAT/NTFS drives):

1. **POSIX Hardlinks (`link(2)`)**:
   Used when backing up to filesystems supporting hardlinks (e.g. HFS+ or standard NFS/SMB mounts). Hardlinks share storage blocks but share inodes, requiring unlink-before-write handling.
2. **Standard File Copy (`copyfile(3)`)**:
   Used on FAT32/exFAT drives where neither CoW nor hardlinks are available. Preserves modification times with timestamp tolerances (`0.02s` on exFAT, `2.0s` on FAT32).

---

## 3. Metadata Preservation & Extended Attributes

OtterKeep preserves comprehensive POSIX and macOS filesystem metadata:
- **Extended Attributes (`xattr`)**: Handled via `listxattr`, `getxattr`, and `setxattr` with `XATTR_NOFOLLOW`. Preserves Finder tags, quarantine flags, and custom user metadata.
- **Access Control Lists (ACLs)**: Preserved where supported by target filesystem drivers.
- **File Flags & Permissions**: POSIX permissions (`posixPermissions`) and creation/modification timestamps.

---

## 4. FileSystemDriverRegistry

The storage subsystem abstracts destination capabilities via `FileSystemCapabilities`:
- `supportsClonefile`: `true` on APFS.
- `supportsHardlinks`: `true` on APFS, HFS+.
- `supportsExtendedAttributes`: `true` on APFS, HFS+.
- `isReadOnly`: `true` on native macOS NTFS drivers.
- `timestampResolution`: `0.001s` (APFS nanosecond resolution), `0.02s` (exFAT), `2.0s` (FAT).
