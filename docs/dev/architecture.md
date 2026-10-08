# OtterKeep Architecture Blueprint

This document specifies the technical architecture of OtterKeep v1.5.0, detailing concurrency boundaries, actor isolation, multi-subsystem topology, and modern data verification pipelines.

---

## 1. Subsystem Decomposition

OtterKeep is partitioned into modular, decoupled Swift packages:

| Package | Purpose | Isolation & Concurrency |
| :--- | :--- | :--- |
| **`OtterKeepStorage`** | Low-level filesystem I/O, APFS `clonefile`, POSIX hardlinks, xattr, BSD `uchg`, SFTP, S3, Backblaze B2 | Actor-isolated providers (`APFSFileSystemProvider`, `B2StorageProvider`, `S3StorageProvider`, `SFTPStorageProvider`) |
| **`OtterKeepDatabase`** | SQLite WAL cataloging, schema migrations, diffing, Myers LCS text diffing, timeline indexing | Actor-isolated `DatabaseEngine`, `SnapshotDiffEngine`, sendable `TextDiffEngine` |
| **`OtterKeepCore`** | Backup session orchestration, background data scrubber, replication catch-up, anomaly guard, restore engine, encryption | Actor-isolated coordinators (`BackupSessionCoordinator`, `DataScrubberEngine`, `ReplicationCatchUpCoordinator`, `PhotosBackupCoordinator`) |
| **`OtterKeepUI`** | SwiftUI sanctuary interface, menu bar popovers, side-by-side diff modal, timeline explorer | `@MainActor` isolated `AppState` and views |
| **`OtterKeepCLI`** | Standalone command-line utility (`otterkeep`) | Headless Swift execution communicating via IPC or direct core engine |
| **`OtterKeepFinderSyncExtension`**| Context-menu integration in macOS Finder | Sandboxed App Extension communicating over Darwin IPC |

---

## 2. Concurrency & Actor Model

OtterKeep is fully compliant with **Swift 6 Strict Concurrency** (`-swift-version 6 -enable-upcoming-feature StrictConcurrency`):

```
┌────────────────────────────────────────────────────────┐
│                      @MainActor                        │
│             AppState  •  SwiftUI Views                 │
└───────────────────────────┬────────────────────────────┘
                            │ await
┌───────────────────────────▼────────────────────────────┐
│              actor BackupSessionCoordinator            │
│  - State Machine: idle -> scanning -> backingUp        │
│  - Cooperative yields: Task.yield() every 250 items    │
│  - Power management: IOPMAssertion lifecycle           │
└─────────────┬────────────────────────────┬─────────────┘
              │ await                      │ await
┌─────────────▼──────────────┐ ┌───────────▼─────────────┐
│    actor DatabaseEngine    │ │  actor APFSFileSystem   │
│ - SQLite3 connection locks │ │ - clonefile(2) syscalls │
│ - WAL checkpoint on close  │ │ - xattr / ACL handling  │
│ - WORM lock metadata       │ │ - BSD uchg immutability │
└─────────────┬──────────────┘ └─────────────────────────┘
              │
┌─────────────▼──────────────┐
│  actor DataScrubberEngine  │
│ - I/O QoS: .background     │
│ - Periodic SHA-256 verify  │
│ - Thermal state monitoring │
└────────────────────────────┘
```

---

## 3. Crash Consistency & Database Handle Management

A critical architectural invariant in OtterKeep is connection lifecycle hygiene:
1. **Connection Lifecycle**: `DatabaseEngine` maintains an explicit `isOpen: Bool` state.
2. **Ejection Safety**: Before volume ejection or during error recovery, `await database.close()` is executed. This performs:
   - `PRAGMA wal_checkpoint(TRUNCATE);`
   - `sqlite3_close_v2(db);`
3. **Handle Release**: Releasing all open file descriptors ensures macOS disk arbitration (`diskarbitrationd` / `NSWorkspace`) can unmount and power down external media without locks.

---

## 4. Multi-Process IPC Security

The communication channel between `otterkeep` CLI, the Finder extension, and the main GUI app is hardened:
- **Transport**: POSIX Unix Domain Sockets (`AF_UNIX`) bound to `~/.otterkeep/gui.sock`.
- **Permissions**: Base directory restricted to `0700`, socket file restricted to `0600`.
- **Buffer Safety**: Path length strictly validated against Darwin `sockaddr_un` limit (104 bytes).
- **Peer UID Validation**: Connections are validated using `getpeereid(clientFD, &peerUID, &peerGID)` ensuring `peerUID == geteuid()`.

---

## 5. Side-by-Side Content Comparison Engine

Introduced in v1.5.0, `TextDiffEngine` provides point-in-time file inspection:
- **LCS Alignment**: Implements the Myers Longest Common Subsequence (LCS) dynamic programming algorithm to produce aligned `SideBySideDiffLine` structures.
- **Binary Detection**: Automatically analyzes initial byte buffers for null bytes (`0x00`) or non-UTF8 payloads. If binary, it reports comprehensive metadata deltas (sizes, SHA-256 hashes, mtime) without polluting UI buffers.
- **UI & CLI Integration**: Rendered visually in `SideBySideDiffModalView` and in terminal via `otterkeep diff --side-by-side`.

---

## 6. Silent Background Data Scrubber

`DataScrubberEngine` protects long-term historical snapshots against silent bit-rot:
- **Low-Priority Execution**: Tasks are dispatched using `Task(priority: .background)`, automatically mapped to Darwin `QOS_CLASS_BACKGROUND`.
- **Thermal & I/O Governance**: Monitors `ProcessInfo.processInfo.thermalState` to pause on thermal spikes, and injects micro-sleeps between file blocks.
- **Proactive Notification**: Mismatches between live SHA-256 hashes and the database manifest trigger macOS User Notifications and write audit trails into SQLite.

---

## 7. WORM Immutability & Retention Immunity

Enforces regulatory and ransomware-resistant immutability:
- **Filesystem Level**: Applies BSD `chflags(2)` with `UF_IMMUTABLE` (`uchg`), blocking even administrative file deletion without explicit unflagging.
- **Catalog Level**: Snapshots carry `locked_until` timestamps. `RetentionManager` GFS rotation unconditionally excludes active locked snapshots from pruning.

---

## 8. Parallel Multi-Destination & Catch-Up Replication

Enables true 3-2-1 resilient backups:
- **Parallel Dispatch**: Local APFS CoW snapshot creation executes concurrently with secondary cloud (Backblaze B2, S3) and network (SMB, SFTP) transfers.
- **Decoupled Failure & Catch-Up**: Network interruptions to remote endpoints do not fail the local backup. Unreached destinations are queued into `pending_replications` and caught up by `ReplicationCatchUpCoordinator` upon reconnection.

---

## 9. Dataless iCloud Drive Change Detection

Prevents unintended APFS kernel faults and unwanted cellular/network downloads:
- **Metadata-Only Verification**: Detects `isDatalessICloud` files and compares them strictly using `fileSize` and `modificationTime`.
- **Zero Payload Access**: Skips sparse sample hashing and full cryptographic reads for dataless files, guaranteeing zero forced downloads during scans.

