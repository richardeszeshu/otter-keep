# Testing Standards & Verification Suite

This document describes the test architecture and verification benchmarks of OtterKeep v1.4.0.

---

## 1. Test Architecture & Runner

OtterKeep tests are orchestrated via a standalone integration harness: **`OtterKeepTestRunner`**.

### Running the Test Suite
```bash
swift run OtterKeepTestRunner
```

Expected output:
```
================================================================================
🦦 OTTERKEEP 1.4.0 (BUILD 1400) SYSTEM INTEGRATION TEST SUITE & BENCHMARK
================================================================================
...
Total Tests Run : 50
Passed          : 50
Failed          : 0
Success Rate    : 100.0%
================================================================================
🎉 ALL TESTS PASSED SUCCESSFULLY WITH ZERO FAILURES!
```

---

## 2. The 10 Test Modules

The test suite systematically exercises all core systems:

1. **System, Version & SemVer Subsystem Integrity**: Verifies v1.4.0 (Build 1400) alignment across all package components and audits `Distribution/appcast.xml`.
2. **APFS Copy-on-Write, Storage Drivers & Filesystem Fidelity**: Tests `clonefile(2)` block sharing, hardlink fallback, xattr preservation, and driver registries.
3. **SQLite Database Engine, Transactions & Crash Consistency**: Validates WAL mode pragmas, batch indexing, connection closure (`PRAGMA wal_checkpoint(TRUNCATE)`), and snapshot cascading deletions.
4. **Incremental Backup Lifecycle & Change Detection**: Tests GitIgnore glob parsing, APFS nanosecond timestamp tolerances, ransomware anomaly detection, and cooperative scanning yields.
5. **Client-Side Cryptography & Security Integrity**: Tests OKENC2 (600,000 PBKDF2 iterations), DSENC1 legacy decryption compatibility, tamper resistance, and streaming SHA-256 calculators.
6. **IPC, Process Security & Peer UID Validation**: Tests `AF_UNIX` bounds, socket permissions (0600), and `getpeereid` authentication.
7. **Privacy-Preserving Observability & Diagnostics**: Validates `LogPrivacySanitizer` token scrubbing and dual-tier diagnostic logger safety.
8. **Apple Photos Backup Architecture & iCloud Eviction**: Tests export structures, metadata extraction, and `EphemeralStorageGuard` buffering.
9. **Bilingual Localization Completeness & Parity**: Verifies 100% key coverage across English and Hungarian dictionaries and format specifier parity.
10. **Modern UI Design System & Three-Tier Error Recovery**: Validates color tokens, configuration archive JSON serialization, and multi-profile tracking.
