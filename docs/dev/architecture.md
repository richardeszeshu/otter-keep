# OtterKeep Architecture Blueprint

This document specifies the technical architecture of OtterKeep v1.4.0, detailing concurrency boundaries, actor isolation, multi-subsystem topology, and IPC security.

---

## 1. Subsystem Decomposition

OtterKeep is partitioned into modular, decoupled Swift packages:

| Package | Purpose | Isolation & Concurrency |
| :--- | :--- | :--- |
| **`OtterKeepStorage`** | Low-level filesystem I/O, APFS `clonefile`, POSIX hardlinks, xattr, SFTP | Actor-isolated providers (`APFSFileSystemProvider`, `SFTPStorageProvider`) |
| **`OtterKeepDatabase`** | SQLite WAL cataloging, schema migrations, diffing, and timeline indexing | Actor-isolated `DatabaseEngine`, `SnapshotDiffEngine` |
| **`OtterKeepCore`** | Backup session orchestration, scanner, anomaly guard, restore engine, encryption | Actor-isolated coordinators (`BackupSessionCoordinator`, `PhotosBackupCoordinator`) |
| **`OtterKeepUI`** | SwiftUI sanctuary interface, menu bar popovers, timeline explorer | `@MainActor` isolated `AppState` and views |
| **`OtterKeepCLI`** | Standalone command-line utility (`otterkeep-cli`) | Headless Swift execution communicating via IPC |
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
└────────────────────────────┘ └─────────────────────────┘
```

---

## 3. Crash Consistency & Database Handle Management

A critical architectural invariant in v1.4.0 is connection lifecycle hygiene:
1. **Connection Lifecycle**: `DatabaseEngine` maintains an explicit `isOpen: Bool` state.
2. **Ejection Safety**: Before volume ejection or during error recovery, `await database.close()` is executed. This performs:
   - `PRAGMA wal_checkpoint(TRUNCATE);`
   - `sqlite3_close_v2(db);`
3. **Handle Release**: Releasing all open file descriptors ensures macOS disk arbitration (`diskarbitrationd` / `NSWorkspace`) can unmount and power down external media without locks.

---

## 4. Multi-Process IPC Security

The communication channel between `otterkeep-cli`, the Finder extension, and the main GUI app is hardened:
- **Transport**: POSIX Unix Domain Sockets (`AF_UNIX`) bound to `~/.otterkeep/gui.sock`.
- **Permissions**: Base directory restricted to `0700`, socket file restricted to `0600`.
- **Buffer Safety**: Path length strictly validated against Darwin `sockaddr_un` limit (104 bytes).
- **Peer UID Validation**: Connections are validated using `getpeereid(clientFD, &peerUID, &peerGID)` ensuring `peerUID == geteuid()`.
