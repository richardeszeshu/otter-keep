# Storage Engine & Provider Internals

OtterKeep abstracts local and remote storage via a unified provider protocol (`StorageProvider`), enabling transparent switching between local APFS cloning, network shares, and cloud object stores.

---

## 1. APFS Copy-on-Write (Reflink) Engine

The `APFSFileSystemProvider` leverages Darwin kernel `clonefile()` system calls:

```c
#include <sys/clonefile.h>

int clonefile(const char *src, const char *dst, uint32_t flags);
```

### Cloning Semantics
1. **Intra-Volume Reflink**: When the source and destination are on the same APFS container, `clonefile()` creates an instantaneous block clone. No data extents are copied; disk allocation is 0 bytes.
2. **Snapshot CoW Target**: When backing up from an internal disk to an external APFS drive, the engine copies only newly created/modified data blocks. Unchanged files across historical snapshots are reflink-cloned from the preceding snapshot on the destination volume.
3. **Fallback File System Provider**: For non-APFS volumes (HFS+, ExFAT, SMB mounts), `FallbackFileSystemProvider` performs streaming POSIX file copies with SHA-256 validation.

---

## 2. Remote Replication Providers

OtterKeep supports offsite replication for 3-2-1 compliance:

* **S3 Storage Provider (`S3StorageProvider`)**: Implements AWS Signature Version 4 (`S3Signer`) over URLSession. Supports streaming multipart uploads, custom S3 endpoints (Cloudflare R2, MinIO, Backblaze B2), and Path-Style addressing.
* **SFTP Storage Provider (`SFTPStorageProvider`)**: Handles SSH-2 secure file transfer with both private key and password authentication. Command arguments are sanitized to prevent shell injection, and exit codes are verified.
* **WebDAV Storage Provider (`WebDAVStorageProvider`)**: Connects to Nextcloud, ownCloud, and NAS WebDAV endpoints with atomic chunked uploads complying with RFC 4918.
* **Network Share Mounter (`NetworkShareMounter`)**: Mounts SMB/NFS network shares dynamically via Darwin `mount_smbfs`, storing credentials in the macOS Keychain.
* **Client-Side Encryptor (`ClientSideEncryptor`)**: Employs AES-GCM-256 authenticated encryption with PBKDF2-HMAC-SHA256 (600,000 rounds) key derivation.

---

## 3. Data Scrubber & Integrity Verification

The `DataScrubberEngine` and `ChecksumCalculator` continuously verify snapshot integrity:
* Calculates hardware-accelerated SHA-256 checksums using CommonCrypto.
* Detects silent bit-rot on storage media and flags corrupted blocks before they can overwrite healthy backups.
* Records verification results into `scrub_audit_logs` in the SQLite catalog.

---

## 4. WORM Immutability (Write-Once, Read-Many)

To protect historical snapshots against accidental deletion, tampering, or ransomware attacks, OtterKeep applies Darwin POSIX file flags (`chflags`):
* `UF_IMMUTABLE` (0x0002): Prevents file modification, renaming, or deletion even by administrator accounts until explicitly unlocked.
* Snapshot folders are marked immutable immediately upon completion, and unlocked only during policy-governed pruning by `RetentionManager`.
