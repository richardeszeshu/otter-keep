# Changelog

All notable changes to OtterKeep are documented in this file in accordance with [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.4.0] - 2026-10-07 (Build 1400)

### 🌟 Release Summary
Version **1.4.0** is an intensive engineering and stability release focusing on core architecture hardening, filesystem fidelity, multi-process IPC security, complete test redesign, and comprehensive documentation rewrite with 100% English-Hungarian parity. No new user-facing features were introduced, ensuring maximum focus on rock-solid dependability.

### 🛡️ Core Backend & Architecture
- **Safe External Volume Ejection**: Added explicit database closure (`DatabaseEngine.close()`) utilizing `sqlite3_close_v2` and `PRAGMA wal_checkpoint(TRUNCATE)` prior to disk auto-unmounting. Completely prevents unmount locks when backing up to external USB/Thunderbolt drives.
- **Cooperative Multitasking & Battery Friendliness**: Introduced cooperative task suspension (`await Task.yield()`) every 250 scanned directory items in `FileTreeScanner`, keeping CPU core temperatures low and preventing UI stutters.
- **IPC Peer Validation**: Hardened local Unix domain socket IPC in `SingleInstanceManager` with Darwin `getpeereid(clientFD, &peerUID, &peerGID)` checks, strictly rejecting connections from unauthorized OS users (`peerUID != geteuid()`).
- **Path Traversal Protection**: Implemented canonical path resolution (`resolvingSymlinksInPath()`) across IPC handlers to prevent directory traversal vectors during remote restore requests.
- **Localized Restore Collisions**: Added type-safe localized suffix formatting (`.restoredSuffixFormat`) resolving cleanly to ` (visszaállított %d)` in Hungarian and ` (restored %d)` in English.
- **Subsystem SemVer Alignment**: Aligned all package dependencies and subsystems (`OtterKeepStorage: 1.1.1`, `OtterKeepDatabase: 1.1.1`, `OtterKeepCore: 1.2.2`, `OtterKeepUI: 1.3.2`, `OtterKeepCLI: 1.1.1`, `OtterKeepFinderSyncExtension: 1.0.1`).

### 🧪 Integration Test Suite Redesign
- **Total Test Redesign**: Completely overhauled and replaced legacy tests with a modern 10-module benchmark suite (`OtterKeepTestRunner`) covering 50 thorough system integration tests with 100% pass rate:
  1. System & Version SemVer Alignment (Build 1400 / Appcast audit)
  2. APFS Copy-on-Write (`clonefile`), Hardlinks, and xattr Preservation
  3. SQLite WAL Database Engine, Diff Engine, and Timeline Queries
  4. Differential Incremental Backup Engine and Ransomware Guard
  5. OKENC2 (600,000 PBKDF2 rounds) & DSENC1 Legacy Decryption Compatibility
  6. IPC Bounds, Socket Permissions (0600), and Peer UID Enforcement
  7. Privacy-Preserving Logging & Dual-Tier Diagnostics
  8. Apple Photos Backup, Ephemeral Cache Guards, and XMP Sidecars
  9. 100% English-Hungarian Bilingual Localization Parity
  10. Modern Sanctuary UI Design System & Three-Tier Error Recovery

### 🔄 Full Snapshot Restore & Recovery Engine
- **Full Snapshot Restoration**: Implemented end-to-end full snapshot restore capabilities across Core (`StorageRestorationEngine`), UI (`RestoreExplorerView`), and CLI (`otterkeep restore --snapshot-id <id> --full`).
- **Atomic Restoration Safeguards**: Transaction-safe staging and atomic in-place file restoration preserving POSIX permissions, creation timestamps, and extended attributes (`xattrs`).
- **Interactive Restore Feedback & Diff Modals**: Enhanced restore progress telemetry (`OperationFeedbackModalView`) and pre-restoration snapshot diff sheet inspector with storage provider abstraction.

### 🎨 Settings & Profile Experience Modernization
- **Equal-Height Card Layouts**: Re-architected multi-column card rows in `SettingsView` (Language, Appearance, Startup, and Permission HUD) and `ProfileRulesAndMaintenanceView` (Retention Consolidation and Disaster Recovery) using native SwiftUI `Grid` and `GridRow` containers with `.frame(maxHeight: .infinity)`, ensuring pixel-aligned card heights.
- **Contextual Profile Metadata & Identifiers**: Cleaned up the global Preferences window by removing the technical profile UUID card list. Added a discreet, dedicated *Profile Identifiers & Metadata* section at the bottom of the Profile Settings view featuring monospaced UUIDs and a one-click clipboard copy action.
- **De-cluttered Profile Rules**: Replaced bulky, redundant directory selection cards with a sleek, single-row `folderSummaryHeader` banner linking directly to the Main Dashboard overview pipeline.
- **Bilingual Localization Parity**: Extended `Localization.swift` with Hungarian and English strings for the new profile metadata and system information sections.

### 📖 Documentation & Community
- **Documentation Overhaul**: Authored 15 brand-new, drift-free guides spanning architecture specifications, storage engine mechanics, database schemas, security manuals, CLI references, and 5 end-user guides in complete English and Hungarian parity.
- **Distribution Packages**: Updated Sparkle 2.0 appcast feed (`Distribution/appcast.xml`) and Homebrew formula template (`Distribution/otterkeep.rb.template`) targeting v1.4.0.
