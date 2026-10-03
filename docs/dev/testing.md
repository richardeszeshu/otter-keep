# OtterKeep 1.0.0 Test Suite & Quality Engineering Matrix

## Overview

OtterKeep 1.0.0 features a completely modern, deterministic, end-to-end integration and system test suite implemented in pure Swift 6 (`Sources/OtterKeepTestRunner/main.swift`). The test runner verifies all critical system boundaries, low-level macOS APFS behaviors, SQLite transactional integrity, zero-knowledge encryption, process security, background synchronization, and bilingual UI components.

Execution entrypoint:
```bash
swift run OtterKeepTestRunner
```

---

## Architecture & Testing Methodology

1. **Isolation & Determinism**: Every storage, database, or lifecycle test operates inside an isolated, cryptographically unique temporary sandbox directory created on the current volume and thoroughly cleaned up after execution.
2. **Native macOS Sequoia Integrations**: Direct invocation and verification of Darwin `clonefile(2)` Copy-on-Write semantics, POSIX file descriptors, `statfs`, and Darwin extended attributes (`xattr`).
3. **Swift 6 Strict Concurrency**: All test cases adhere to actor boundaries (`@MainActor`, actor-isolated `DatabaseEngine`, `EphemeralStorageGuard`, and `SoftwareUpdateCoordinator`).
4. **Zero Flakiness**: No reliance on third-party network services or external mock servers; all protocols (S3 signer, SFTP argument escaping, Sparkle appcast update evaluation, iCloud status checks) are tested deterministically.

---

## Complete Test Matrix (10 Core Domains, 40 Tests)

| # | Module & Domain | Test Name | Key Assertions / Verifications |
|---|-----------------|-----------|--------------------------------|
| **1.1** | **Module 1: System & Version Integrity** | `testCoreEngineMetadataAndSlogans` | Version 1.0.0, build sequence 1000, bundle ID `com.otterkeep.desktop`, HU and EN brand taglines & lore. |
| **1.2** | | `testSemanticVersionComparison` | Semver ordering (`.orderedAscending`, `.orderedSame`, `.orderedDescending`), prefix stripping (`v1.0.0`). |
| **1.3** | | `testSparkleAppcastCoordinatorLogic` | `SoftwareUpdateCoordinator` mock injection, update discovery lifecycle, up-to-date state. |
| **2.1** | **Module 2: APFS CoW & Storage Provider** | `testAPFSCapabilitiesAndCapacity` | `APFSFileSystemProvider.capabilities(at:)`, hardlink support, xattr support, volume free/available bytes. |
| **2.2** | | `testAPFSCloneCoWIndependence` | `clonefile(2)` reflink creation, inode independence (`inodeA != inodeB`), mutation isolation on source file. |
| **2.3** | | `testPOSIXHardlinkFallback` | POSIX hardlink creation, inode equality (`inodeA == inodeB`), surviving source file deletion. |
| **2.4** | | `testExtendedAttributesPreservation` | `setExtendedAttributes` / `getExtendedAttributes`, Darwin `copyItemPreservingMetadata` xattr preservation. |
| **2.5** | | `testAtomicDirectoryMove` | `atomicMove(from:to:)` via POSIX `rename(2)`, ensuring atomic promotion and elimination of staging folders. |
| **2.6** | | `testFallbackStorageProvider` | `FallbackFileSystemProvider` reporting `supportsAPFSClone = false`, transparent fallback to metadata copy. |
| **3.1** | **Module 3: SQLite Database Engine & Snapshots** | `testSQLiteWALModeAndPragmas` | `PRAGMA journal_mode = WAL`, `PRAGMA busy_timeout = 10000`, database schema creation, zero initial records. |
| **3.2** | | `testSnapshotCatalogBatchIndexing` | `insertSnapshot`, `listSnapshots`, `BEGIN IMMEDIATE TRANSACTION` batch insertion of 50 `FileCatalogRecord`s. |
| **3.3** | | `testSnapshotDiffEngine` | `SnapshotDiffEngine.computeDiff`: accurately partitions `added`, `modified`, `deleted`, calculates net byte deltas. |
| **3.4** | | `testSnapshotTimelineQueries` | `listVersions(ofRelativePath:)`: multi-snapshot reverse-chronological file revision indexing. |
| **3.5** | | `testCrossSnapshotGlobalSearch` | `searchFilesAcrossSnapshots(query:)`: SQL `LIKE` filtering across snapshot records. |
| **4.1** | **Module 4: Incremental Backup Lifecycle** | `testGitIgnoreRuleParsing` | `GitIgnoreRule`: glob wildcards (`*.tmp`), directory-only rules (`build/`), rooted patterns (`/root.log`), negations (`!keep.tmp`). |
| **4.2** | | `testDifferentialChangeDetector` | `ChangeDetector`: compares current scan against prior catalog using mtime, byte size, and inode markers. |
| **4.3** | | `testRansomwareAnomalyGuard` | Rate-of-change anomaly threshold (>20%), mass deletion safeguard, detection of suspicious extensions (`.crypto`, `.locked`, `.wncry`). |
| **4.4** | | `testEndToEndBackupLifecycle` | `BackupSessionCoordinator`: initial full snapshot followed by second incremental snapshot, manifest persistence. |
| **5.1** | **Module 5: Client-Side Cryptography** | `testOKENC2PBKDF2Encryption` | AES-256-GCM authenticated encryption using PBKDF2-HMAC-SHA256 (600,000 rounds) and `OKENC2\0` magic header. |
| **5.2** | | `testDSENC1LegacyBackwardCompatibility` | Seamless decryption of legacy DataSquirrel `DSENC1\0` envelopes (HKDF-SHA256 key derivation). |
| **5.3** | | `testCryptoTamperResistance` | Bit-flip in ciphertext throwing `authenticationMismatch`, wrong password rejection, truncated header rejection (`invalidHeader`). |
| **5.4** | | `testChecksumAndSampleHash` | `ChecksumCalculator.computeSHA256` (64 hex characters) and `FastHashCalculator.computeSamplingHash` sparse head/mid/tail digest. |
| **6.1** | **Module 6: IPC & Process Security** | `testAFUnixBufferBoundsValidation` | Verification of Darwin `sockaddr_un` 104-byte limit on `sun_path`, preventing stack buffer overflow vulnerabilities. |
| **6.2** | | `testPOSIXSocketAndDirectoryPermissions` | Validation of POSIX permissions: `0o700` (`rwx------`) for application state directory, `0o600` (`rw-------`) for socket. |
| **6.3** | | `testSFTPShellArgumentSanitization` | Neutralization of shell injection attacks (`$(rm -rf /)`, quotes, semicolons) via POSIX single-quote escaping. |
| **6.4** | | `testSingleInstanceManagerForwarding` | `SingleInstanceMessage` JSON encoding/decoding, socket path resolution, and activation messaging. |
| **7.1** | **Module 7: Privacy-Preserving Logging** | `testLogPrivacySanitizerRedaction` | Scrubbing of Bearer tokens (`<REDACTED_AUTH>`), AWS Access Key IDs (`<AWS_ACCESS_KEY_ID>`), Webhook URLs, query params, and home paths. |
| **7.2** | | `testDualTierLoggingRetention` | Filtering of `.debug` entries during normal operation vs. retention in ring buffer when verbose logging is enabled. |
| **7.3** | | `testDebugFileLoggerNonOverwriting` | Collision avoidance: creating timestamped non-overwriting `.log` files across consecutive sessions. |
| **8.1** | **Module 8: Photos Backup & iCloud Eviction** | `testPhotosConfigurationSchemes` | `PhotosBackupConfiguration`: date hierarchy, album hierarchy, flat export schemes, Codable persistence. |
| **8.2** | | `testPhotoMetadataExtractorXMP` | `PhotoMetadataExtractor.generateXMPSidecar`: valid XMP packet structure, EXIF timestamps, GPS coords, XML entity escaping. |
| **8.3** | | `testEphemeralStorageGuard` | Rate-limiting in-flight asset downloads, buffer acquisition/release, temporary staging file creation and eviction. |
| **8.4** | | `testICloudEvictionController` | Free disk space safeguard (2 GB threshold), local vs ubiquitous status checks, `ICloudError.lowDiskSpace` formatting. |
| **9.1** | **Module 9: Bilingual Localization** | `testBilingualLocalizationKeyCoverage` | 100% of all `L10n.Key` enumeration cases exist in both Hungarian and English dictionaries (`hasExplicitTranslation`). |
| **9.2** | | `testBilingualStringsNonEmpty` | 100% of translated strings in both languages are non-empty after whitespace trimming. |
| **9.3** | | `testLocalizationFormatters` | `L10n.format` string interpolation with numeric and string arguments across both languages. |
| **10.1** | **Module 10: Modern UI Design System** | `testOtterThemeDynamicColors` | `OtterTheme` dynamic color tokens: `otterAmber`, `oceanicTeal`, `deepSeaNavy`, `pebbleGrey`, `accentPurple`. |
| **10.2** | | `testAppThemeModeProperties` | Theme presentation mapping: system (`nil`), light (`.light`), dark (`.dark`), SF Symbol icons (`sun.max.fill`, etc.). |
| **10.3** | | `testOtterAboutViewPresentation` | `OtterAboutView` instantiation, `AboutWindowController` presentation singleton. |
| **10.4** | | `testAppStateRootNavigation` | `@Observable AppState`: switching between `.dashboard`, `.photos`, `.logs`, `.settings`, and invoking `openAbout()`. |

---

## Execution Report

```text
================================================================================
🦦 OTTERKEEP 1.0.0 (BUILD 1000) SYSTEM INTEGRATION TEST SUITE & BENCHMARK
================================================================================

🔹 Module 1: System & Version Integrity
  ✓ 1.1 CoreEngine Metadata & Slogans (0.9 ms)
  ✓ 1.2 Semantic Version Parser & Comparison (0.5 ms)
  ✓ 1.3 Sparkle Appcast Coordinator Logic (4.2 ms)

🔹 Module 2: APFS Copy-on-Write & Storage Provider
  ✓ 2.1 APFS Volume Capabilities & Capacity Metrics (1.4 ms)
  ✓ 2.2 APFS clonefile(2) CoW Data Independence (5.2 ms)
  ✓ 2.3 POSIX Hardlink Fallback & Inode Consistency (1.3 ms)
  ✓ 2.4 Extended Attributes (xattr) Preservation (1.1 ms)
  ✓ 2.5 Atomic Directory Tree Renaming (atomicMove) (1.5 ms)
  ✓ 2.6 Fallback Storage Provider Non-APFS Behavior (0.9 ms)

🔹 Module 3: SQLite Database Engine & Snapshots
  ✓ 3.1 SQLite WAL Mode, Pragmas & Schema Creation (9.1 ms)
  ✓ 3.2 Snapshot Cataloging & Batch File Indexing (5.6 ms)
  ✓ 3.3 Snapshot Diff Engine Added, Modified & Deleted (1.0 ms)
  ✓ 3.4 Multi-Snapshot Timeline Queries (listVersions) (4.7 ms)
  ✓ 3.5 Cross-Snapshot Global File Search (4.2 ms)

🔹 Module 4: Incremental Backup Lifecycle & Change Detection
  ✓ 4.1 GitIgnore-Style Rule Parser (Globs & Negations) (1.8 ms)
  ✓ 4.2 Differential Change Detector (Mtime & Size & Inode) (0.2 ms)
  ✓ 4.3 Ransomware Anomaly Guard Anomaly Sensitivity (0.1 ms)
  ✓ 4.4 End-to-End Backup Lifecycle (Initial + Incremental) (93.9 ms)

🔹 Module 5: Client-Side Cryptography & Security Hardening
  ✓ 5.1 OKENC2 PBKDF2-HMAC-SHA256 (600,000 Rounds) Encryption (337.8 ms)
  ✓ 5.2 DSENC1 Legacy HKDF Backward Compatibility Decryption (0.2 ms)
  ✓ 5.3 Cryptographic Tamper Resistance & Wrong Password Rejection (506.2 ms)
  ✓ 5.4 SHA-256 Checksum & Fast Sparse Sample Hash (35.5 ms)

🔹 Module 6: IPC & Process Security
  ✓ 6.1 AF_UNIX sockaddr_un 104-Byte Buffer Overflow Bounds Check (0.0 ms)
  ✓ 6.2 POSIX Socket Permissions (0600) & Directory (0700) (0.8 ms)
  ✓ 6.3 SFTP Shell Argument Injection Neutralization (0.0 ms)
  ✓ 6.4 SingleInstanceManager Forwarding & Reentrancy (0.2 ms)

🔹 Module 7: Privacy-Preserving Logging & Dual-Tier Diagnostics
  ✓ 7.1 LogPrivacySanitizer PII, Tokens, AWS & Webhook Scrubbing (0.5 ms)
  ✓ 7.2 Dual-Tier Diagnostic Logger (Normal vs Verbose Retention) (2.6 ms)
  ✓ 7.3 Debug File Logger Append-Only & Non-Overwriting Guarantee (1.6 ms)

🔹 Module 8: Photos Backup & iCloud Eviction
  ✓ 8.1 Photos Configuration Schemes (Date, Album, Flat) (0.4 ms)
  ✓ 8.2 PhotoMetadataExtractor XMP Sidecar Generation (0.4 ms)
  ✓ 8.3 EphemeralStorageGuard Rate Limiting & Eviction (1.0 ms)
  ✓ 8.4 iCloud Eviction Controller Safeguards & Status (1.2 ms)

🔹 Module 9: Bilingual Localization Completeness
  ✓ 9.1 100% Localization Key Existence in Hungarian & English (0.4 ms)
  ✓ 9.2 Non-Empty Translated Strings for Hungarian & English (1.0 ms)
  ✓ 9.3 Localization Variadic Formatter Consistency (0.2 ms)

🔹 Module 10: Modern UI Design System & About State
  ✓ 10.1 OtterTheme Dynamic Color Tokens & Contrast (0.2 ms)
  ✓ 10.2 AppThemeMode Presentation & SF Symbol Mapping (0.0 ms)
  ✓ 10.3 OtterAboutView Brand Metadata & About Controller (0.1 ms)
  ✓ 10.4 AppState Root Navigation & Profile Switching (230.4 ms)

================================================================================
📊 TEST EXECUTION SUMMARY
================================================================================
Total Tests Run : 40
Passed          : 40
Failed          : 0
Elapsed Time    : 1.26 seconds
Success Rate    : 100.0%
================================================================================

🎉 ALL TESTS PASSED SUCCESSFULLY WITH ZERO FAILURES!
```

---

## Continuous Integration & Developer Workflow

To run the test suite locally or in CI:

```bash
# Build the test executable
swift build --product OtterKeepTestRunner

# Execute the test suite
swift run OtterKeepTestRunner
```

Any exit code other than `0` indicates a regression or test failure.
