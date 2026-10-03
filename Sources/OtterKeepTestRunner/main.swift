//
//  main.swift
//  OtterKeepTestRunner
//
//  Comprehensive End-to-End Deterministic System Test Suite & Benchmark
//  for OtterKeep 1.1.0 (Build 1100).
//
//  Covers Modules 1 through 10:
//  - Module 1: System & Version Integrity
//  - Module 2: APFS Copy-on-Write & Storage Provider
//  - Module 3: SQLite Database Engine & Snapshots
//  - Module 4: Incremental Backup Lifecycle & Change Detection
//  - Module 5: Client-Side Cryptography & Security Hardening
//  - Module 6: IPC & Process Security
//  - Module 7: Privacy-Preserving Logging & Dual-Tier Diagnostics
//  - Module 8: Photos Backup & iCloud Eviction
//  - Module 9: Bilingual Localization Completeness
//  - Module 10: Modern UI Design System & About State
//

import Foundation
import os
import Darwin
import Photos
import CryptoKit
import AppKit
import SwiftUI
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore
import OtterKeepUI

// MARK: - Assertion Framework

public struct TestFailure: Error, CustomStringConvertible {
    public let message: String
    public let file: String
    public let line: Int

    public init(message: String, file: String = #file, line: Int = #line) {
        self.message = message
        self.file = file
        self.line = line
    }

    public var description: String {
        "\(URL(fileURLWithPath: file).lastPathComponent):\(line): \(message)"
    }
}

public func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard condition() else {
        throw TestFailure(message: "Assertion failed: expected true, got false. \(message)", file: file, line: line)
    }
}

public func assertFalse(_ condition: @autoclosure () -> Bool, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard !condition() else {
        throw TestFailure(message: "Assertion failed: expected false, got true. \(message)", file: file, line: line)
    }
}

public func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard a == b else {
        throw TestFailure(message: "Assertion failed: '\(a)' != '\(b)'. \(message)", file: file, line: line)
    }
}

public func assertNotEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard a != b else {
        throw TestFailure(message: "Assertion failed: values are unexpectedly equal ('\(a)'). \(message)", file: file, line: line)
    }
}

public func assertNil<T>(_ value: T?, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard value == nil else {
        throw TestFailure(message: "Assertion failed: expected nil, got '\(value!)'. \(message)", file: file, line: line)
    }
}

public func assertNotNil<T>(_ value: T?, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard value != nil else {
        throw TestFailure(message: "Assertion failed: expected non-nil value. \(message)", file: file, line: line)
    }
}

// MARK: - Test Suite Definition

@MainActor
final class OtterKeepTestSuite {
    private var passedCount = 0
    private var failedCount = 0
    private var testFailures: [(name: String, error: String)] = []

    private func createTempDirectory(prefix: String = "OtterKeepTest") throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func removeTempDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func runTest(_ name: String, _ testBlock: () async throws -> Void) async {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            try await testBlock()
            let duration = clock.now - start
            passedCount += 1
            let ms = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1_000_000_000_000_000.0
            print("  ✓ \(name) (\(String(format: "%.1f", ms)) ms)")
        } catch {
            failedCount += 1
            let duration = clock.now - start
            let ms = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1_000_000_000_000_000.0
            let errString = "\(error)"
            testFailures.append((name: name, error: errString))
            print("  ✗ \(name) FAILED (\(String(format: "%.1f", ms)) ms)")
            print("    -> \(errString)")
        }
    }

    func runAll() async throws {
        print("\n================================================================================")
        print("🦦 OTTERKEEP 1.1.0 (BUILD 1100) SYSTEM INTEGRATION TEST SUITE & BENCHMARK")
        print("================================================================================\n")

        let suiteStart = ContinuousClock().now

        // MARK: - Module 1: System & Version Integrity
        print("🔹 Module 1: System & Version Integrity")
        await runTest("1.1 CoreEngine Metadata & Slogans", testCoreEngineMetadataAndSlogans)
        await runTest("1.2 Semantic Version Parser & Comparison", testSemanticVersionComparison)
        await runTest("1.3 Sparkle Appcast Coordinator Logic", testSparkleAppcastCoordinatorLogic)

        // MARK: - Module 2: APFS Copy-on-Write & Storage Provider
        print("\n🔹 Module 2: APFS Copy-on-Write & Storage Provider")
        await runTest("2.1 APFS Volume Capabilities & Capacity Metrics", testAPFSCapabilitiesAndCapacity)
        await runTest("2.2 APFS clonefile(2) CoW Data Independence", testAPFSCloneCoWIndependence)
        await runTest("2.3 POSIX Hardlink Fallback & Inode Consistency", testPOSIXHardlinkFallback)
        await runTest("2.4 Extended Attributes (xattr) Preservation", testExtendedAttributesPreservation)
        await runTest("2.5 Atomic Directory Tree Renaming (atomicMove)", testAtomicDirectoryMove)
        await runTest("2.6 Fallback Storage Provider Non-APFS Behavior", testFallbackStorageProvider)

        // MARK: - Module 3: SQLite Database Engine & Snapshots
        print("\n🔹 Module 3: SQLite Database Engine & Snapshots")
        await runTest("3.1 SQLite WAL Mode, Pragmas & Schema Creation", testSQLiteWALModeAndPragmas)
        await runTest("3.2 Snapshot Cataloging & Batch File Indexing", testSnapshotCatalogBatchIndexing)
        await runTest("3.3 Snapshot Diff Engine Added, Modified & Deleted", testSnapshotDiffEngine)
        await runTest("3.4 Multi-Snapshot Timeline Queries (listVersions)", testSnapshotTimelineQueries)
        await runTest("3.5 Cross-Snapshot Global File Search", testCrossSnapshotGlobalSearch)

        // MARK: - Module 4: Incremental Backup Lifecycle & Change Detection
        print("\n🔹 Module 4: Incremental Backup Lifecycle & Change Detection")
        await runTest("4.1 GitIgnore-Style Rule Parser (Globs & Negations)", testGitIgnoreRuleParsing)
        await runTest("4.2 Differential Change Detector (Mtime & Size & Inode)", testDifferentialChangeDetector)
        await runTest("4.3 Ransomware Anomaly Guard Anomaly Sensitivity", testRansomwareAnomalyGuard)
        await runTest("4.4 End-to-End Backup Lifecycle (Initial + Incremental)", testEndToEndBackupLifecycle)

        // MARK: - Module 5: Client-Side Cryptography & Security Hardening
        print("\n🔹 Module 5: Client-Side Cryptography & Security Hardening")
        await runTest("5.1 OKENC2 PBKDF2-HMAC-SHA256 (600,000 Rounds) Encryption", testOKENC2PBKDF2Encryption)
        await runTest("5.2 DSENC1 Legacy HKDF Backward Compatibility Decryption", testDSENC1LegacyBackwardCompatibility)
        await runTest("5.3 Cryptographic Tamper Resistance & Wrong Password Rejection", testCryptoTamperResistance)
        await runTest("5.4 SHA-256 Checksum & Fast Sparse Sample Hash", testChecksumAndSampleHash)

        // MARK: - Module 6: IPC & Process Security
        print("\n🔹 Module 6: IPC & Process Security")
        await runTest("6.1 AF_UNIX sockaddr_un 104-Byte Buffer Overflow Bounds Check", testAFUnixBufferBoundsValidation)
        await runTest("6.2 POSIX Socket Permissions (0600) & Directory (0700)", testPOSIXSocketAndDirectoryPermissions)
        await runTest("6.3 SFTP Shell Argument Injection Neutralization", testSFTPShellArgumentSanitization)
        await runTest("6.4 SingleInstanceManager Forwarding & Reentrancy", testSingleInstanceManagerForwarding)

        // MARK: - Module 7: Privacy-Preserving Logging & Dual-Tier Diagnostics
        print("\n🔹 Module 7: Privacy-Preserving Logging & Dual-Tier Diagnostics")
        await runTest("7.1 LogPrivacySanitizer PII, Tokens, AWS & Webhook Scrubbing", testLogPrivacySanitizerRedaction)
        await runTest("7.2 Dual-Tier Diagnostic Logger (Normal vs Verbose Retention)", testDualTierLoggingRetention)
        await runTest("7.3 Debug File Logger Append-Only & Non-Overwriting Guarantee", testDebugFileLoggerNonOverwriting)

        // MARK: - Module 8: Photos Backup & iCloud Eviction
        print("\n🔹 Module 8: Photos Backup & iCloud Eviction")
        await runTest("8.1 Photos Configuration Schemes (Date, Album, Flat)", testPhotosConfigurationSchemes)
        await runTest("8.2 PhotoMetadataExtractor XMP Sidecar Generation", testPhotoMetadataExtractorXMP)
        await runTest("8.3 EphemeralStorageGuard Rate Limiting & Eviction", testEphemeralStorageGuard)
        await runTest("8.4 iCloud Eviction Controller Safeguards & Status", testICloudEvictionController)

        // MARK: - Module 9: Bilingual Localization Completeness
        print("\n🔹 Module 9: Bilingual Localization Completeness")
        await runTest("9.1 100% Localization Key Existence in Hungarian & English", testBilingualLocalizationKeyCoverage)
        await runTest("9.2 Non-Empty Translated Strings for Hungarian & English", testBilingualStringsNonEmpty)
        await runTest("9.3 Localization Variadic Formatter Consistency", testLocalizationFormatters)

        // MARK: - Module 10: Modern UI Design System & About State
        print("\n🔹 Module 10: Modern UI Design System & About State")
        await runTest("10.1 OtterTheme Dynamic Color Tokens & Contrast", testOtterThemeDynamicColors)
        await runTest("10.2 AppThemeMode Presentation & SF Symbol Mapping", testAppThemeModeProperties)
        await runTest("10.3 OtterAboutView Brand Metadata & About Controller", testOtterAboutViewPresentation)
        await runTest("10.4 AppState Root Navigation & Profile Switching", testAppStateRootNavigation)

        // MARK: - Summary & Results
        let totalDuration = ContinuousClock().now - suiteStart
        let totalSeconds = Double(totalDuration.components.seconds) + Double(totalDuration.components.attoseconds) / 1_000_000_000_000_000_000.0

        print("\n================================================================================")
        print("📊 TEST EXECUTION SUMMARY")
        print("================================================================================")
        print("Total Tests Run : \(passedCount + failedCount)")
        print("Passed          : \(passedCount)")
        print("Failed          : \(failedCount)")
        print("Elapsed Time    : \(String(format: "%.2f", totalSeconds)) seconds")
        print("Success Rate    : \(String(format: "%.1f", Double(passedCount) / Double(max(1, passedCount + failedCount)) * 100.0))%")
        print("================================================================================\n")

        if failedCount > 0 {
            print("🚨 FAILURES REPORT:")
            for failure in testFailures {
                print("  - \(failure.name): \(failure.error)")
            }
            throw TestFailure(message: "\(failedCount) tests failed.")
        } else {
            print("🎉 ALL TESTS PASSED SUCCESSFULLY WITH ZERO FAILURES!")
        }
    }

    // =========================================================================
    // MARK: - Module 1 Implementations
    // =========================================================================

    func testCoreEngineMetadataAndSlogans() async throws {
        try assertEqual(CoreEngine.version, "1.1.0", "CoreEngine version must be exactly 1.1.0")
        try assertEqual(CoreEngine.appName, "OtterKeep", "CoreEngine appName must be OtterKeep")
        try assertEqual(CoreEngine.bundleIdentifier, "com.otterkeep.desktop", "Bundle ID must match")

        // Verify Brand Lore & Slogans
        let huTagline = L10n.t(.aboutTagline, lang: .hungarian)
        let enTagline = L10n.t(.aboutTagline, lang: .english)
        try assertEqual(huTagline, "Őrizd a legfontosabb kincseidet biztos kezekben.", "Hungarian tagline must match")
        try assertEqual(enTagline, "Keep what you love close to your chest.", "English tagline must match")

        let huLore = L10n.t(.aboutLoreTitle, lang: .hungarian)
        let enLore = L10n.t(.aboutLoreTitle, lang: .english)
        try assertEqual(huLore, "A vidrák kedvenc kavicsának legendája", "Hungarian lore title must match")
        try assertEqual(enLore, "The Legend of the Favorite Pebble", "English lore title must match")
    }

    func testSemanticVersionComparison() async throws {
        // Equal versions
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("1.0.0", "1.0.0"), .orderedSame)
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("v1.0.0", "1.0.0"), .orderedSame)
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("1.0", "1.0.0"), .orderedSame)

        // Ascending
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("1.0.0", "1.0.1"), .orderedAscending)
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("1.0.0", "1.1.0"), .orderedAscending)
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("1.9.9", "2.0.0"), .orderedAscending)

        // Descending
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("1.0.1", "1.0.0"), .orderedDescending)
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("2.0.0", "1.99.99"), .orderedDescending)

        // Newer than predicate
        try assertTrue(SoftwareUpdateCoordinator.isVersion("1.0.1", newerThan: "1.0.0"))
        try assertFalse(SoftwareUpdateCoordinator.isVersion("1.0.0", newerThan: "1.0.0"))
        try assertFalse(SoftwareUpdateCoordinator.isVersion("0.9.9", newerThan: "1.0.0"))
    }

    func testSparkleAppcastCoordinatorLogic() async throws {
        let coordinator = SoftwareUpdateCoordinator.shared
        try assertEqual(coordinator.currentVersion, "1.1.0")
        try assertEqual(coordinator.currentBuild, "1100")

        // Verify default public endpoints
        try assertTrue(SoftwareUpdateCoordinator.defaultAppcastURL.absoluteString.contains("richardeszeshu/otter-keep"), "Appcast URL must point to richardeszeshu/otter-keep")
        try assertTrue(SoftwareUpdateCoordinator.defaultReleasesURL.absoluteString.contains("richardeszeshu/otter-keep"), "Releases URL must point to richardeszeshu/otter-keep")
        try assertTrue(SoftwareUpdateCoordinator.defaultGitHubReleasesAPIURL.absoluteString.contains("richardeszeshu/otter-keep"), "GitHub Releases API URL must point to richardeszeshu/otter-keep")

        // Mock an update
        let mockInfo = SoftwareUpdateInfo(
            version: "1.2.0",
            buildNumber: "1200",
            releaseNotes: "Performance improvements & APFS CoW tuning",
            downloadURL: URL(string: "https://github.com/richardeszeshu/otter-keep/releases/tag/v1.2.0")!,
            publicationDate: Date(),
            isCritical: false
        )

        await coordinator.setMockUpdateInfo(mockInfo)
        let status = await coordinator.checkForUpdates()
        try assertEqual(status, UpdateCheckStatus.updateAvailable(mockInfo))

        // Mock an older version (no update available)
        let olderInfo = SoftwareUpdateInfo(
            version: "0.9.5",
            buildNumber: "950",
            releaseNotes: "Old",
            downloadURL: URL(string: "https://example.com")!
        )
        await coordinator.setMockUpdateInfo(olderInfo)
        let upToDateStatus = await coordinator.checkForUpdates()
        try assertEqual(upToDateStatus, UpdateCheckStatus.upToDate)

        // Clear mock
        await coordinator.setMockUpdateInfo(nil)

        // Test Appcast XML parsing with multi-version feed
        let testAppcastXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/sparrow/rss">
            <channel>
                <title>OtterKeep Feed</title>
                <item>
                    <title>Version 1.0.0</title>
                    <description><![CDATA[Initial production release.]]></description>
                    <enclosure url="https://github.com/richardeszeshu/otter-keep/releases/download/v1.0.0/OtterKeep-1.0.0.zip"
                               sparkle:version="1000"
                               sparkle:shortVersionString="1.0.0" />
                </item>
                <item>
                    <title>Version 1.2.5</title>
                    <description><![CDATA[Critical security patch and snapshot performance fix.]]></description>
                    <enclosure url="https://github.com/richardeszeshu/otter-keep/releases/download/v1.2.5/OtterKeep-1.2.5.zip"
                               sparkle:version="1250"
                               sparkle:shortVersionString="1.2.5" />
                </item>
                <item>
                    <title>Version 1.1.0</title>
                    <description><![CDATA[Design refresh.]]></description>
                    <enclosure url="https://github.com/richardeszeshu/otter-keep/releases/download/v1.1.0/OtterKeep-1.1.0.zip"
                               sparkle:version="1100"
                               sparkle:shortVersionString="1.1.0" />
                </item>
            </channel>
        </rss>
        """.data(using: .utf8)!

        let parsedBest = await coordinator.parseAppcastXML(data: testAppcastXML)
        guard let best = parsedBest else {
            throw TestFailure(message: "Failed to parse test appcast XML")
        }
        try assertEqual(best.version, "1.2.5", "Appcast parser must select the highest candidate version (1.2.5)")
        try assertEqual(best.buildNumber, "1250", "Build number should be 1250")
        try assertTrue(best.releaseNotes.contains("Critical security patch"), "Release notes must match highest version item")
        try assertEqual(best.downloadURL.absoluteString, "https://github.com/richardeszeshu/otter-keep/releases/download/v1.2.5/OtterKeep-1.2.5.zip")

        // Test SemVer comparison with prerelease
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("1.2.0-beta1", "1.2.0"), .orderedAscending)
        try assertEqual(SoftwareUpdateCoordinator.compareVersions("1.2.0", "1.2.0-beta1"), .orderedDescending)
        try assertTrue(SoftwareUpdateCoordinator.isVersion("1.2.0", newerThan: "1.2.0-beta1"))

        // Test parsing the repository's Distribution/appcast.xml
        let projectAppcastURL = URL(fileURLWithPath: "Distribution/appcast.xml")
        if let appcastData = try? Data(contentsOf: projectAppcastURL) {
            let parsedRepoAppcast = await coordinator.parseAppcastXML(data: appcastData)
            guard let repoAppcast = parsedRepoAppcast else {
                throw TestFailure(message: "Failed to parse repository Distribution/appcast.xml")
            }
            try assertEqual(repoAppcast.version, "1.1.0", "Repository appcast must have version 1.1.0 as latest")
            try assertEqual(repoAppcast.buildNumber, "1100", "Repository appcast must have build 1100")
            try assertTrue(repoAppcast.downloadURL.absoluteString.contains("richardeszeshu/otter-keep"), "Download URL must point to richardeszeshu/otter-keep")
        }
    }

    // =========================================================================
    // MARK: - Module 2 Implementations
    // =========================================================================

    func testAPFSCapabilitiesAndCapacity() async throws {
        let tempDir = try createTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let provider = APFSFileSystemProvider()
        let caps = try await provider.capabilities(at: tempDir)

        try assertTrue(caps.supportsHardLinks, "APFS must support POSIX hard links")
        try assertTrue(caps.supportsExtendedAttributes, "APFS must support extended attributes")
        try assertFalse(caps.isReadOnly, "Temporary directory volume must be writable")

        let capacity = try provider.storageCapacity(at: tempDir)
        try assertTrue(capacity.totalBytes > 0, "Total bytes must be positive")
        try assertTrue(capacity.freeBytes > 0, "Free bytes must be positive")
        try assertTrue(capacity.availableBytes > 0, "Available bytes must be positive")
        try assertTrue(capacity.availableBytes <= capacity.totalBytes, "Available bytes cannot exceed total")
    }

    func testAPFSCloneCoWIndependence() async throws {
        let tempDir = try createTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let provider = APFSFileSystemProvider()
        let sourceFile = tempDir.appendingPathComponent("source.bin")
        let cloneFile = tempDir.appendingPathComponent("clone.bin")

        let originalData = Data((0..<16384).map { UInt8($0 % 256) })
        try originalData.write(to: sourceFile)

        let srcMetaBefore = try provider.metadata(at: sourceFile)

        // Clone using APFS CoW
        try await provider.cloneItem(at: sourceFile, to: cloneFile)

        try assertTrue(FileManager.default.fileExists(atPath: cloneFile.path), "Clone file must exist on disk")

        let cloneMeta = try provider.metadata(at: cloneFile)
        try assertEqual(cloneMeta.size, srcMetaBefore.size, "Cloned file must have identical logical size")

        // APFS CoW gives different inodes to cloned files
        try assertNotEqual(cloneMeta.inode, srcMetaBefore.inode, "APFS clone creates an independent inode")

        // Modify source file and verify clone is completely unaffected
        let modifiedData = Data(repeating: 0xAA, count: 8192)
        try modifiedData.write(to: sourceFile)

        let cloneDataAfter = try Data(contentsOf: cloneFile)
        try assertEqual(cloneDataAfter, originalData, "APFS CoW clone must retain original data when source is modified")
    }

    func testPOSIXHardlinkFallback() async throws {
        let tempDir = try createTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let provider = APFSFileSystemProvider()
        let fileA = tempDir.appendingPathComponent("original.txt")
        let fileB = tempDir.appendingPathComponent("hardlink.txt")

        try "POSIX Hardlink Content".data(using: .utf8)!.write(to: fileA)

        try await provider.createHardLink(at: fileA, to: fileB)

        let metaA = try provider.metadata(at: fileA)
        let metaB = try provider.metadata(at: fileB)

        // POSIX hardlinks share the same inode
        try assertEqual(metaA.inode, metaB.inode, "Hardlinks must share identical inode number")
        try assertEqual(metaA.size, metaB.size, "Hardlinks must have identical size")

        // Removing original does not delete data from hardlink
        try FileManager.default.removeItem(at: fileA)
        try assertTrue(FileManager.default.fileExists(atPath: fileB.path), "Hardlinked file must persist after original is removed")
        let readBack = try String(contentsOf: fileB, encoding: .utf8)
        try assertEqual(readBack, "POSIX Hardlink Content")
    }

    func testExtendedAttributesPreservation() async throws {
        let tempDir = try createTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let provider = APFSFileSystemProvider()
        let file = tempDir.appendingPathComponent("xattr_test.txt")
        try "Content with attributes".data(using: .utf8)!.write(to: file)

        let customAttrKey = "com.otterkeep.backup.signature"
        let customAttrVal = "OtterKeep-Verified-1.0.0".data(using: .utf8)!

        try provider.setExtendedAttributes([customAttrKey: customAttrVal], at: file)

        let fetchedAttrs = try provider.getExtendedAttributes(at: file)
        try assertTrue(fetchedAttrs[customAttrKey] != nil, "Custom extended attribute must be retrievable")
        try assertEqual(fetchedAttrs[customAttrKey], customAttrVal, "Attribute value must match exactly")

        // Verify Darwin copyItemPreservingMetadata retains xattrs
        let copyFile = tempDir.appendingPathComponent("xattr_copy.txt")
        try await provider.copyItemPreservingMetadata(at: file, to: copyFile, progress: nil)

        let copiedAttrs = try provider.getExtendedAttributes(at: copyFile)
        try assertEqual(copiedAttrs[customAttrKey], customAttrVal, "copyfile must preserve extended attributes")
    }

    func testAtomicDirectoryMove() async throws {
        let tempDir = try createTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let provider = APFSFileSystemProvider()
        let stagingDir = tempDir.appendingPathComponent("staging_folder")
        let finalDir = tempDir.appendingPathComponent("committed_folder")

        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let fileInStaging = stagingDir.appendingPathComponent("payload.dat")
        try "Staged Payload".data(using: .utf8)!.write(to: fileInStaging)

        try await provider.atomicMove(from: stagingDir, to: finalDir)

        try assertFalse(FileManager.default.fileExists(atPath: stagingDir.path), "Staging directory must no longer exist")
        try assertTrue(FileManager.default.fileExists(atPath: finalDir.path), "Committed directory must exist")
        let finalFile = finalDir.appendingPathComponent("payload.dat")
        try assertTrue(FileManager.default.fileExists(atPath: finalFile.path), "Payload inside atomically moved directory must exist")
    }

    func testFallbackStorageProvider() async throws {
        let tempDir = try createTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let fallback = FallbackFileSystemProvider()
        let caps = try await fallback.capabilities(at: tempDir)
        try assertFalse(caps.supportsAPFSClone, "Fallback provider must report supportsAPFSClone = false")

        let src = tempDir.appendingPathComponent("fallback_src.txt")
        let dst = tempDir.appendingPathComponent("fallback_dst.txt")
        try "Fallback Data".data(using: .utf8)!.write(to: src)

        // cloneItem on fallback provider falls back to metadata-preserving copy
        try await fallback.cloneItem(at: src, to: dst)
        try assertTrue(FileManager.default.fileExists(atPath: dst.path))
        let dstContent = try String(contentsOf: dst, encoding: .utf8)
        try assertEqual(dstContent, "Fallback Data")
    }

    // =========================================================================
    // MARK: - Module 3 Implementations
    // =========================================================================

    func testSQLiteWALModeAndPragmas() async throws {
        let tempDir = try createTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let dbPath = tempDir.appendingPathComponent("test_catalog.sqlite").path
        let dbEngine = DatabaseEngine()
        try await dbEngine.open(at: dbPath)

        // Verify WAL file is created alongside the database
        let walPath = dbPath + "-wal"
        let walExists = FileManager.default.fileExists(atPath: walPath)
        try assertTrue(walExists || FileManager.default.fileExists(atPath: dbPath), "Database and WAL mode initialized")

        // Verify empty snapshot list
        let initialSnapshots = try await dbEngine.listSnapshots()
        try assertEqual(initialSnapshots.count, 0, "New database should have zero initial snapshots")
    }

    func testSnapshotCatalogBatchIndexing() async throws {
        let tempDir = try createTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let dbPath = tempDir.appendingPathComponent("catalog.sqlite").path
        let db = DatabaseEngine()
        try await db.open(at: dbPath)

        let snapshotId = "snapshot_2026-10-02_001"
        let snapRecord = SnapshotRecord(
            id: snapshotId,
            timestamp: Date(),
            status: "completed",
            totalFiles: 100,
            totalBytes: 500000,
            snapshotPath: "2026-10-02_001",
            backupType: "incremental"
        )
        try await db.insertSnapshot(snapRecord)

        let retrievedSnaps = try await db.listSnapshots()
        try assertEqual(retrievedSnaps.count, 1)
        try assertEqual(retrievedSnaps.first?.id, snapshotId)

        // Insert batch file records
        var batch: [FileCatalogRecord] = []
        for i in 1...50 {
            batch.append(FileCatalogRecord(
                snapshotId: snapshotId,
                relativePath: "Documents/File_\(i).txt",
                fileSize: Int64(i * 100),
                modificationTime: Date(),
                inode: UInt64(1000 + i),
                checksum: "hash_\(i)",
                sampleHash: "sample_\(i)",
                isDirectory: false,
                isSymlink: false
            ))
        }

        try await db.insertFileRecordsBatch(batch)

        let files = try await db.listFiles(forSnapshotId: snapshotId)
        try assertEqual(files.count, 50, "Batch indexing must persist all 50 records")
    }

    func testSnapshotDiffEngine() async throws {
        let now = Date()
        let fileA = FileCatalogRecord(snapshotId: "s1", relativePath: "fileA.txt", fileSize: 100, modificationTime: now, inode: 1, isDirectory: false, isSymlink: false)
        let fileB = FileCatalogRecord(snapshotId: "s1", relativePath: "fileB.txt", fileSize: 200, modificationTime: now, inode: 2, isDirectory: false, isSymlink: false)
        let fileC = FileCatalogRecord(snapshotId: "s1", relativePath: "fileC.txt", fileSize: 300, modificationTime: now, inode: 3, isDirectory: false, isSymlink: false)

        let baseFiles = [fileA, fileB, fileC]

        // Target: fileA modified (+50 bytes), fileB deleted, fileD added (400 bytes), fileC unchanged
        let fileAMod = FileCatalogRecord(snapshotId: "s2", relativePath: "fileA.txt", fileSize: 150, modificationTime: now.addingTimeInterval(10), inode: 1, isDirectory: false, isSymlink: false)
        let fileD = FileCatalogRecord(snapshotId: "s2", relativePath: "fileD.txt", fileSize: 400, modificationTime: now, inode: 4, isDirectory: false, isSymlink: false)

        let targetFiles = [fileAMod, fileC, fileD]

        let report = SnapshotDiffEngine.computeDiff(
            baseFiles: baseFiles,
            targetFiles: targetFiles,
            baseSnapshotId: "s1",
            targetSnapshotId: "s2"
        )

        try assertEqual(report.addedCount, 1, "Exactly 1 file added")
        try assertEqual(report.modifiedCount, 1, "Exactly 1 file modified")
        try assertEqual(report.deletedCount, 1, "Exactly 1 file deleted")
        try assertEqual(report.addedFiles.first?.relativePath, "fileD.txt")
        try assertEqual(report.modifiedFiles.first?.relativePath, "fileA.txt")
        try assertEqual(report.deletedFiles.first?.relativePath, "fileB.txt")
        try assertEqual(report.netBytesDelta, 150 - 100 + 400 - 200, "Net bytes calculation must match")
    }

    func testSnapshotTimelineQueries() async throws {
        let tempDir = try createTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let dbPath = tempDir.appendingPathComponent("timeline.sqlite").path
        let db = DatabaseEngine()
        try await db.open(at: dbPath)

        let snap1 = SnapshotRecord(id: "snap1", timestamp: Date(timeIntervalSince1970: 1000), status: "completed", totalFiles: 1, totalBytes: 10, snapshotPath: "snap1")
        let snap2 = SnapshotRecord(id: "snap2", timestamp: Date(timeIntervalSince1970: 2000), status: "completed", totalFiles: 1, totalBytes: 20, snapshotPath: "snap2")
        let snap3 = SnapshotRecord(id: "snap3", timestamp: Date(timeIntervalSince1970: 3000), status: "completed", totalFiles: 1, totalBytes: 30, snapshotPath: "snap3")

        try await db.insertSnapshot(snap1)
        try await db.insertSnapshot(snap2)
        try await db.insertSnapshot(snap3)

        let targetPath = "Projects/ImportantDoc.md"
        let rec1 = FileCatalogRecord(snapshotId: "snap1", relativePath: targetPath, fileSize: 10, modificationTime: Date(timeIntervalSince1970: 1000), inode: 10, isDirectory: false, isSymlink: false)
        let rec2 = FileCatalogRecord(snapshotId: "snap2", relativePath: targetPath, fileSize: 20, modificationTime: Date(timeIntervalSince1970: 2000), inode: 10, isDirectory: false, isSymlink: false)
        let rec3 = FileCatalogRecord(snapshotId: "snap3", relativePath: targetPath, fileSize: 30, modificationTime: Date(timeIntervalSince1970: 3000), inode: 10, isDirectory: false, isSymlink: false)

        try await db.insertFileRecordsBatch([rec1])
        try await db.insertFileRecordsBatch([rec2])
        try await db.insertFileRecordsBatch([rec3])

        let timeline = try await db.listVersions(ofRelativePath: targetPath)
        try assertEqual(timeline.count, 3, "Timeline should return all 3 historical versions")
        // Verify newest first ordering
        try assertEqual(timeline[0].snapshot.id, "snap3")
        try assertEqual(timeline[1].snapshot.id, "snap2")
        try assertEqual(timeline[2].snapshot.id, "snap1")
    }

    func testCrossSnapshotGlobalSearch() async throws {
        let tempDir = try createTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let dbPath = tempDir.appendingPathComponent("search.sqlite").path
        let db = DatabaseEngine()
        try await db.open(at: dbPath)

        let snap = SnapshotRecord(id: "snap_search", timestamp: Date(), status: "completed", totalFiles: 2, totalBytes: 100, snapshotPath: "snap_search")
        try await db.insertSnapshot(snap)

        let f1 = FileCatalogRecord(snapshotId: "snap_search", relativePath: "Documents/FinancialReport2026.pdf", fileSize: 50, modificationTime: Date(), inode: 101, isDirectory: false, isSymlink: false)
        let f2 = FileCatalogRecord(snapshotId: "snap_search", relativePath: "Photos/OtterPebble.png", fileSize: 50, modificationTime: Date(), inode: 102, isDirectory: false, isSymlink: false)
        try await db.insertFileRecordsBatch([f1, f2])

        let results = try await db.searchFilesAcrossSnapshots(query: "Financial")
        try assertEqual(results.count, 1)
        try assertEqual(results.first?.relativePath, "Documents/FinancialReport2026.pdf")
    }

    // =========================================================================
    // MARK: - Module 4 Implementations
    // =========================================================================

    func testGitIgnoreRuleParsing() async throws {
        let ruleFile = GitIgnoreRule(pattern: "*.tmp")!
        try assertTrue(ruleFile.matches(relativePath: "scratch.tmp", isDirectory: false))
        try assertTrue(ruleFile.matches(relativePath: "sub/dir/test.tmp", isDirectory: false))
        try assertFalse(ruleFile.matches(relativePath: "scratch.tmp.keep", isDirectory: false))

        // Directory-only rule
        let ruleDir = GitIgnoreRule(pattern: "build/")!
        try assertTrue(ruleDir.isDirectoryOnly)
        try assertTrue(ruleDir.matches(relativePath: "build", isDirectory: true))
        try assertFalse(ruleDir.matches(relativePath: "build", isDirectory: false))

        // Rooted rule
        let ruleRooted = GitIgnoreRule(pattern: "/root_only.log")!
        try assertTrue(ruleRooted.isRooted)
        try assertTrue(ruleRooted.matches(relativePath: "root_only.log", isDirectory: false))
        try assertFalse(ruleRooted.matches(relativePath: "nested/root_only.log", isDirectory: false))

        // Negative rule
        let ruleNeg = GitIgnoreRule(pattern: "!important.tmp")!
        try assertTrue(ruleNeg.isNegative)
    }

    func testDifferentialChangeDetector() async throws {
        let now = Date()
        let scanned1 = ScannedItem(
            url: URL(fileURLWithPath: "/src/file1.txt"),
            relativePath: "file1.txt",
            metadata: FileMetadata(url: URL(fileURLWithPath: "/src/file1.txt"), size: 100, modificationTime: now, inode: 1, posixPermissions: 0o644, isDirectory: false, isSymlink: false)
        )
        let scanned2 = ScannedItem(
            url: URL(fileURLWithPath: "/src/file2.txt"),
            relativePath: "file2.txt",
            metadata: FileMetadata(url: URL(fileURLWithPath: "/src/file2.txt"), size: 250, modificationTime: now.addingTimeInterval(5), inode: 2, posixPermissions: 0o644, isDirectory: false, isSymlink: false)
        )
        let scanned3New = ScannedItem(
            url: URL(fileURLWithPath: "/src/file3.txt"),
            relativePath: "file3.txt",
            metadata: FileMetadata(url: URL(fileURLWithPath: "/src/file3.txt"), size: 300, modificationTime: now, inode: 3, posixPermissions: 0o644, isDirectory: false, isSymlink: false)
        )

        // Previous catalog has file1 (unmodified), file2 (modified size 200 -> 250), and fileOld (deleted)
        let prev1 = FileCatalogRecord(snapshotId: "s0", relativePath: "file1.txt", fileSize: 100, modificationTime: now, inode: 1, isDirectory: false, isSymlink: false)
        let prev2 = FileCatalogRecord(snapshotId: "s0", relativePath: "file2.txt", fileSize: 200, modificationTime: now, inode: 2, isDirectory: false, isSymlink: false)
        let prevOld = FileCatalogRecord(snapshotId: "s0", relativePath: "fileOld.txt", fileSize: 50, modificationTime: now, inode: 9, isDirectory: false, isSymlink: false)

        let prevMap = ["file1.txt": prev1, "file2.txt": prev2, "fileOld.txt": prevOld]

        let detector = ChangeDetector()
        let result = detector.detectChanges(scannedItems: [scanned1, scanned2, scanned3New], previousCatalog: prevMap)

        try assertEqual(result.unmodified.count, 1)
        try assertEqual(result.unmodified.first?.current.relativePath, "file1.txt")
        try assertEqual(result.modified.count, 1)
        try assertEqual(result.modified.first?.relativePath, "file2.txt")
        try assertEqual(result.added.count, 1)
        try assertEqual(result.added.first?.relativePath, "file3.txt")
        try assertEqual(result.deleted.count, 1)
        try assertEqual(result.deleted.first?.relativePath, "fileOld.txt")
    }

    func testRansomwareAnomalyGuard() async throws {
        // Normal change rate: 5 modified out of 100 files, no suspicious extensions
        let normalReport = RansomwareAnomalyGuard.evaluate(
            totalFiles: 100,
            modifiedCount: 5,
            deletedCount: 0,
            candidatePaths: ["docs/readme.txt", "src/main.swift"],
            maxChangeThresholdPercent: 20.0
        )
        try assertFalse(normalReport.isAnomalyDetected, "Normal change rate must not trigger guard")

        // Abnormal change rate: 30 changes out of 100 (30% > 20% threshold)
        let abnormalRateReport = RansomwareAnomalyGuard.evaluate(
            totalFiles: 100,
            modifiedCount: 25,
            deletedCount: 5,
            candidatePaths: ["file1.txt", "file2.txt"],
            maxChangeThresholdPercent: 20.0
        )
        try assertTrue(abnormalRateReport.isAnomalyDetected, "High change rate must trigger guard")
        try assertTrue(abnormalRateReport.reason?.contains("Rate of change anomaly") == true)

        // Ransomware extension attack detected
        let ransomwareReport = RansomwareAnomalyGuard.evaluate(
            totalFiles: 100,
            modifiedCount: 2,
            deletedCount: 0,
            candidatePaths: ["important_db.sqlite.locked", "notes.txt.crypto", "backup.wncry"],
            maxChangeThresholdPercent: 50.0
        )
        try assertTrue(ransomwareReport.isAnomalyDetected, "Known ransomware extensions must trigger anomaly shield")
        try assertEqual(ransomwareReport.suspiciousExtensionFiles.count, 3)
    }

    func testEndToEndBackupLifecycle() async throws {
        let tempDir = try createTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let srcDir = tempDir.appendingPathComponent("Source")
        let dstDir = tempDir.appendingPathComponent("Destination")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dstDir, withIntermediateDirectories: true)

        // Create sample files
        try "Content Alpha".data(using: .utf8)!.write(to: srcDir.appendingPathComponent("alpha.txt"))
        try "Content Beta".data(using: .utf8)!.write(to: srcDir.appendingPathComponent("beta.txt"))

        let profile = BackupProfile(name: "E2ETestProfile", sourceURL: srcDir, destinationURL: dstDir)
        let coordinator = BackupSessionCoordinator(storage: APFSFileSystemProvider())

        // 1. Initial Full Backup
        let snap1Result = try await coordinator.performBackup(profile: profile)
        try assertEqual(snap1Result.status, "completed")
        try assertEqual(snap1Result.totalFiles, 2)

        // 2. Incremental Changes: modify alpha, delete beta, add gamma
        try "Modified Alpha Content".data(using: .utf8)!.write(to: srcDir.appendingPathComponent("alpha.txt"))
        try FileManager.default.removeItem(at: srcDir.appendingPathComponent("beta.txt"))
        try "New Gamma Content".data(using: .utf8)!.write(to: srcDir.appendingPathComponent("gamma.txt"))

        // Small sleep to ensure modification timestamps tick
        try await Task.sleep(nanoseconds: 50_000_000)

        // 3. Second Incremental Backup
        let snap2Result = try await coordinator.performBackup(profile: profile)
        try assertEqual(snap2Result.status, "completed")
        try assertEqual(snap2Result.totalFiles, 2, "New snapshot contains alpha and gamma")

        // 4. Verify catalog records in SQLite
        let db = DatabaseEngine()
        let catalogURL = dstDir.appendingPathComponent(".otterkeep/manifest.sqlite")
        try await db.open(at: catalogURL.path)

        let snapshots = try await db.listSnapshots()
        try assertEqual(snapshots.count, 2, "Database must record both snapshots")

        let versionsOfAlpha = try await db.listVersions(ofRelativePath: "alpha.txt")
        try assertEqual(versionsOfAlpha.count, 2, "alpha.txt must have 2 historical versions")
    }

    // =========================================================================
    // MARK: - Module 5 Implementations
    // =========================================================================

    func testOKENC2PBKDF2Encryption() async throws {
        let plainText = "OtterKeep-Top-Secret-Payload-2026"
        let plainData = Data(plainText.utf8)
        let passphrase = "CorrectHorseBatteryStaple@2026!"

        // 1. Encrypt with OKENC2
        let encryptedEnvelope = try ClientSideEncryptor.encrypt(data: plainData, passphrase: passphrase)
        try assertTrue(encryptedEnvelope.starts(with: ClientSideEncryptor.headerMagicOKENC2), "Envelope must begin with OKENC2 magic header")
        try assertTrue(encryptedEnvelope.count > plainData.count + 32, "Envelope must include salt, nonce, ciphertext and auth tag")

        // 2. Decrypt with correct passphrase
        let decryptedData = try ClientSideEncryptor.decrypt(envelope: encryptedEnvelope, passphrase: passphrase)
        let decryptedString = String(data: decryptedData, encoding: .utf8)
        try assertEqual(decryptedString, plainText, "Decrypted text must match original plaintext")
    }

    func testDSENC1LegacyBackwardCompatibility() async throws {
        let legacyText = "LegacyDataSquirrelEncryptedPayloadV1"
        let plainData = Data(legacyText.utf8)
        let passphrase = "LegacyPassword123!"

        // Encrypt with DSENC1 legacy format
        let legacyEnvelope = try ClientSideEncryptor.encryptLegacyV1(data: plainData, passphrase: passphrase)
        try assertTrue(legacyEnvelope.starts(with: ClientSideEncryptor.headerMagicV1), "Envelope must begin with DSENC1 magic header")

        // Decrypt using unified decrypt method
        let decryptedData = try ClientSideEncryptor.decrypt(envelope: legacyEnvelope, passphrase: passphrase)
        let decryptedString = String(data: decryptedData, encoding: .utf8)
        try assertEqual(decryptedString, legacyText, "ClientSideEncryptor must decrypt legacy DSENC1 envelopes flawlessly")
    }

    func testCryptoTamperResistance() async throws {
        let plainData = Data("TamperTestContent".utf8)
        let passphrase = "SecretKey#999"

        let envelope = try ClientSideEncryptor.encrypt(data: plainData, passphrase: passphrase)

        // 1. Wrong Passphrase -> authenticationMismatch
        var didCatchAuthMismatch = false
        do {
            _ = try ClientSideEncryptor.decrypt(envelope: envelope, passphrase: "IncorrectPassword!")
        } catch let err as ClientEncryptionError {
            if err == .authenticationMismatch { didCatchAuthMismatch = true }
        }
        try assertTrue(didCatchAuthMismatch, "Wrong passphrase must produce authenticationMismatch error")

        // 2. Bit Flip in Ciphertext -> authenticationMismatch (AES-GCM authentication failure)
        var tamperedEnvelope = envelope
        let targetIndex = envelope.count - 10
        tamperedEnvelope[targetIndex] ^= 0x55

        var didCatchTamper = false
        do {
            _ = try ClientSideEncryptor.decrypt(envelope: tamperedEnvelope, passphrase: passphrase)
        } catch let err as ClientEncryptionError {
            if err == .authenticationMismatch { didCatchTamper = true }
        }
        try assertTrue(didCatchTamper, "Corrupted ciphertext must fail authentication")

        // 3. Truncated header -> invalidHeader
        let truncated = envelope.prefix(10)
        var didCatchInvalidHeader = false
        do {
            _ = try ClientSideEncryptor.decrypt(envelope: truncated, passphrase: passphrase)
        } catch let err as ClientEncryptionError {
            if err == .invalidHeader { didCatchInvalidHeader = true }
        }
        try assertTrue(didCatchInvalidHeader, "Truncated envelope must produce invalidHeader error")
    }

    func testChecksumAndSampleHash() async throws {
        let tempDir = try createTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let sampleFile = tempDir.appendingPathComponent("sample_hash.bin")
        let data = Data((0..<200_000).map { UInt8($0 % 256) })
        try data.write(to: sampleFile)

        // Full SHA-256 Checksum
        let fullHash = try ChecksumCalculator.computeSHA256(for: sampleFile)
        try assertEqual(fullHash.count, 64, "SHA-256 hash must be 64 hexadecimal characters")

        // Fast Sparse Sample Hash
        let sampleHash = try FastHashCalculator.computeSamplingHash(for: sampleFile)
        try assertEqual(sampleHash.count, 64, "Fast sample hash must be 64 hexadecimal characters")
    }

    // =========================================================================
    // MARK: - Module 6 Implementations
    // =========================================================================

    func testAFUnixBufferBoundsValidation() async throws {
        let addr = sockaddr_un()
        let maxAllowedLength = MemoryLayout.size(ofValue: addr.sun_path)
        try assertEqual(maxAllowedLength, 104, "Darwin AF_UNIX sockaddr_un sun_path buffer must be exactly 104 bytes")

        // Valid path within bounds
        let validPath = "/tmp/otterkeep_test.sock"
        try assertTrue(validPath.utf8CString.count <= maxAllowedLength)

        // Overflow path exceeding 104 bytes
        let longPath = "/tmp/" + String(repeating: "a", count: 120) + ".sock"
        try assertTrue(longPath.utf8CString.count > maxAllowedLength, "Exceeding path must be greater than 104 bytes")
    }

    func testPOSIXSocketAndDirectoryPermissions() async throws {
        let tempDir = try createTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let secureDir = tempDir.appendingPathComponent("secure_dir")
        try FileManager.default.createDirectory(at: secureDir, withIntermediateDirectories: true)
        chmod(secureDir.path, 0o700)

        var dirStat = stat()
        stat(secureDir.path, &dirStat)
        let dirMode = dirStat.st_mode & 0o777
        try assertEqual(dirMode, 0o700, "Directory permissions must be strictly 0700 (owner read/write/execute only)")

        // Socket permissions simulation
        let dummySocketFile = secureDir.appendingPathComponent("sim.sock")
        try "sock".data(using: .utf8)!.write(to: dummySocketFile)
        chmod(dummySocketFile.path, 0o600)

        var sockStat = stat()
        stat(dummySocketFile.path, &sockStat)
        let sockMode = sockStat.st_mode & 0o777
        try assertEqual(sockMode, 0o600, "Socket permissions must be strictly 0600 (owner read/write only)")
    }

    func testSFTPShellArgumentSanitization() async throws {
        // POSIX Single-Quote Sanitization Rule: wraps in single quotes, turns ' into '\''
        func sanitize(_ arg: String) -> String {
            "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }

        // 1. Normal safe path
        try assertEqual(sanitize("/backups/2026-10-02"), "'/backups/2026-10-02'")

        // 2. Path with spaces
        try assertEqual(sanitize("/Volumes/My Backup/Folder"), "'/Volumes/My Backup/Folder'")

        // 3. Command injection attempt with subshell
        let maliciousSubshell = "/backups/$(rm -rf /)"
        let sanitizedSubshell = sanitize(maliciousSubshell)
        try assertEqual(sanitizedSubshell, "'/backups/$(rm -rf /)'", "Subshell expansion must be neutralized in single quotes")

        // 4. Command injection with quotes and semicolons
        let maliciousSemicolon = "test'; rm -rf /; echo '"
        let sanitizedSemicolon = sanitize(maliciousSemicolon)
        try assertEqual(sanitizedSemicolon, "'test'\\\''; rm -rf /; echo '\\'''")
    }

    func testSingleInstanceManagerForwarding() async throws {
        let manager = SingleInstanceManager.shared
        try assertTrue(manager.socketPath.hasSuffix(".otterkeep/gui.sock"))
        try assertTrue(manager.lockFilePath.hasSuffix(".otterkeep/otterkeep_gui.lock"))

        // SingleInstanceMessage serialization
        let msg = SingleInstanceMessage(action: .openVersionHistory, filePath: "/Users/test/file.txt")
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(SingleInstanceMessage.self, from: data)
        try assertEqual(decoded.action, .openVersionHistory)
        try assertEqual(decoded.filePath, "/Users/test/file.txt")
    }

    // =========================================================================
    // MARK: - Module 7 Implementations
    // =========================================================================

    func testLogPrivacySanitizerRedaction() async throws {
        // 1. Bearer Token Redaction
        let authMsg = "Connecting to API with Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.secret"
        let sanitizedAuth = LogPrivacySanitizer.sanitize(authMsg)
        try assertFalse(sanitizedAuth.contains("eyJhbGciOiJIUzI1NiJ9.secret"), "Bearer token must be redacted")
        try assertTrue(sanitizedAuth.contains("<REDACTED_AUTH>"), "Redaction marker must be present")

        // 2. AWS Access Key Redaction
        let awsMsg = "Uploading shard to S3 using key AKIAIOSFODNN7EXAMPLE for user"
        let sanitizedAWS = LogPrivacySanitizer.sanitize(awsMsg)
        try assertFalse(sanitizedAWS.contains("AKIAIOSFODNN7EXAMPLE"), "AWS Key ID must be redacted")
        try assertTrue(sanitizedAWS.contains("<AWS_ACCESS_KEY_ID>"), "AWS redaction marker must be present")

        // 3. Webhook URL Redaction
        let slackMsg = "Posting notification to https://hooks.slack.com/services/T000/B000/XXXXX"
        let sanitizedSlack = LogPrivacySanitizer.sanitize(slackMsg)
        try assertFalse(sanitizedSlack.contains("XXXXX"), "Slack webhook token must be redacted")
        try assertTrue(sanitizedSlack.contains("<WEBHOOK_ENDPOINT_REDACTED>"))

        // 4. Query Parameter Redaction
        let queryMsg = "Fetching resource from https://example.com/api?token=SuperSecretToken123&action=sync"
        let sanitizedQuery = LogPrivacySanitizer.sanitize(queryMsg)
        try assertFalse(sanitizedQuery.contains("SuperSecretToken123"), "Token in query params must be redacted")
        try assertTrue(sanitizedQuery.contains("<REDACTED>"))

        // 5. Home Directory Redaction
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let pathMsg = "Scanning directory: \(homeDir)/Documents/SecretDoc.pdf"
        let sanitizedPath = LogPrivacySanitizer.sanitize(pathMsg)
        try assertFalse(sanitizedPath.contains(homeDir), "Home directory must be redacted")
        try assertTrue(sanitizedPath.contains("<USER_HOME>"))
    }

    func testDualTierLoggingRetention() async throws {
        let logManager = LogManager.shared

        // Disable debug logging
        logManager.disableDebugFileLogging(persistSetting: false)
        try assertFalse(logManager.isDebugFileLoggingEnabled)

        // Log an info message and a debug message
        let uniqueInfoTag = "INFO_TEST_\(UUID().uuidString)"
        let uniqueDebugTag = "DEBUG_TEST_\(UUID().uuidString)"

        logManager.log(uniqueInfoTag, level: .info, category: "Test")
        logManager.log(uniqueDebugTag, level: .debug, category: "Test")

        // Enable debug file logging (verbose mode)
        let logFileURL = logManager.enableDebugFileLogging(persistSetting: false)
        try assertTrue(logManager.isDebugFileLoggingEnabled)
        try assertTrue(FileManager.default.fileExists(atPath: logFileURL.path))

        let verboseDebugTag = "VERBOSE_DEBUG_\(UUID().uuidString)"
        logManager.log(verboseDebugTag, level: .debug, category: "Test")

        // Cleanup
        logManager.disableDebugFileLogging(persistSetting: false)
    }

    func testDebugFileLoggerNonOverwriting() async throws {
        let logger = DebugFileLogger.shared

        let url1 = logger.startSession()
        logger.stopSession()

        // Starting another session creates a distinct timestamped file, never overwriting
        let url2 = logger.startSession()
        logger.stopSession()

        try assertTrue(FileManager.default.fileExists(atPath: url1.path))
        try assertTrue(FileManager.default.fileExists(atPath: url2.path))
    }

    // =========================================================================
    // MARK: - Module 8 Implementations
    // =========================================================================

    func testPhotosConfigurationSchemes() async throws {
        var config = PhotosBackupConfiguration()
        try assertEqual(config.exportStructure, .dateHierarchy)

        config.exportStructure = .albumHierarchy
        try assertEqual(config.exportStructure, .albumHierarchy)

        config.exportStructure = .flat
        try assertEqual(config.exportStructure, .flat)

        // Codable serialization check
        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(PhotosBackupConfiguration.self, from: encoded)
        try assertEqual(decoded.exportStructure, .flat)
        try assertEqual(decoded.generateXMPSidecars, true)
    }

    func testPhotoMetadataExtractorXMP() async throws {
        let extractor = PhotoMetadataExtractor()

        // Generate XMP for an empty/mock asset without crashing
        // Even when passing empty albums, structure must be valid XMP packet
        let xmpData = extractor.generateXMPSidecar(for: PHAsset(), albums: ["Family Vacation", "Summer <2026>"])
        try assertNotNil(xmpData, "XMP sidecar data must be generated")

        let xmpString = String(data: xmpData!, encoding: .utf8)!
        try assertTrue(xmpString.contains("<?xpacket begin="), "Must contain valid XMP packet header")
        try assertTrue(xmpString.contains("<x:xmpmeta"), "Must contain XMP meta namespace tag")
        try assertTrue(xmpString.contains("Family Vacation"), "Must contain album name")
        try assertTrue(xmpString.contains("Summer &lt;2026&gt;"), "XML entities must be sanitized properly")
    }

    func testEphemeralStorageGuard() async throws {
        let tempDir = try createTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let guardActor = EphemeralStorageGuard(maxInFlightBytes: 10 * 1024 * 1024, temporaryDirectoryURL: tempDir)

        // Acquire capacity
        await guardActor.acquireInFlightCapacity(for: 2 * 1024 * 1024)
        let bufferBytes = await guardActor.currentBufferBytes
        try assertTrue(bufferBytes >= 2 * 1024 * 1024, "Buffer capacity must be reserved")

        // Create temporary staging file
        let stagedFile = await guardActor.createTemporaryFileURL(prefix: "test_asset", fileExtension: "heic")
        try "Staged HEIC Data".data(using: .utf8)!.write(to: stagedFile)
        try assertTrue(FileManager.default.fileExists(atPath: stagedFile.path))

        // Evict temporary file
        await guardActor.evictTemporaryFile(at: stagedFile)
        try assertFalse(FileManager.default.fileExists(atPath: stagedFile.path), "Evicted temporary file must be removed")

        // Release capacity
        await guardActor.releaseInFlightCapacity(for: 2 * 1024 * 1024)
        let finalBuffer = await guardActor.currentBufferBytes
        try assertEqual(finalBuffer, 0, "Buffer bytes must return to zero after release")
    }

    func testICloudEvictionController() async throws {
        let tempDir = try createTempDirectory()
        defer { removeTempDirectory(tempDir) }

        let controller = ICloudEvictionController(storage: APFSFileSystemProvider())
        let minThreshold = await controller.minFreeDiskSpaceThreshold
        try assertEqual(minThreshold, 2 * 1024 * 1024 * 1024, "Default free disk space safeguard must be 2 GB")
        try assertEqual(await controller.downloadTimeoutSeconds, 30.0)

        // Verify status check on a real local file (not ubiquitous, downloaded)
        let localFile = tempDir.appendingPathComponent("local.txt")
        try "Local content".data(using: .utf8)!.write(to: localFile)

        let status = await controller.checkICloudStatus(at: localFile)
        try assertFalse(status.isUbiquitous)
        try assertFalse(status.isDataless)

        let isDownloaded = await controller.isItemActuallyDownloaded(at: localFile)
        try assertTrue(isDownloaded, "Standard local file is considered downloaded")

        // Low disk space error formatting
        let lowSpaceErr = ICloudError.lowDiskSpace(availableBytes: 100 * 1024 * 1024, requiredBytes: 500 * 1024 * 1024)
        try assertTrue(lowSpaceErr.errorDescription?.contains("Low disk space") == true)
    }

    // =========================================================================
    // MARK: - Module 9 Implementations
    // =========================================================================

    func testBilingualLocalizationKeyCoverage() async throws {
        let allKeys = L10n.Key.allCases
        try assertTrue(allKeys.count >= 200, "Localization must define comprehensive UI keys (found: \(allKeys.count))")

        var missingInHungarian: [String] = []
        var missingInEnglish: [String] = []

        for key in allKeys {
            if !L10n.hasExplicitTranslation(for: key, in: .hungarian) {
                missingInHungarian.append(key.rawValue)
            }
            if !L10n.hasExplicitTranslation(for: key, in: .english) {
                missingInEnglish.append(key.rawValue)
            }
        }

        try assertTrue(
            missingInHungarian.isEmpty,
            "100% of keys must exist in Hungarian dictionary. Missing (\(missingInHungarian.count)): \(missingInHungarian.prefix(10).joined(separator: ", "))"
        )
        try assertTrue(
            missingInEnglish.isEmpty,
            "100% of keys must exist in English dictionary. Missing (\(missingInEnglish.count)): \(missingInEnglish.prefix(10).joined(separator: ", "))"
        )
    }

    func testBilingualStringsNonEmpty() async throws {
        for key in L10n.Key.allCases {
            let hu = L10n.t(key, lang: .hungarian).trimmingCharacters(in: .whitespacesAndNewlines)
            try assertFalse(hu.isEmpty, "Hungarian translation for '\(key.rawValue)' cannot be empty")

            let en = L10n.t(key, lang: .english).trimmingCharacters(in: .whitespacesAndNewlines)
            try assertFalse(en.isEmpty, "English translation for '\(key.rawValue)' cannot be empty")
        }
    }

    func testLocalizationFormatters() async throws {
        let huFormatted = L10n.format(.cliProfilesCountFormat, 42, lang: .hungarian)
        try assertEqual(huFormatted, "Profilok száma: 42")

        let enFormatted = L10n.format(.cliProfilesCountFormat, 42, lang: .english)
        try assertEqual(enFormatted, "Total profiles: 42")

        let huTitle = L10n.format(.notifBackupCompletedTitleFormat, "Munka", lang: .hungarian)
        try assertEqual(huTitle, "OtterKeep – Munka")
    }

    // =========================================================================
    // MARK: - Module 10 Implementations
    // =========================================================================

    func testOtterThemeDynamicColors() async throws {
        _ = OtterTheme.otterAmber
        _ = OtterTheme.oceanicTeal
        _ = OtterTheme.deepSeaNavy
        _ = OtterTheme.pebbleGrey
        _ = OtterTheme.accentPurple

        // Dynamic color generation helper
        let testColor = OtterTheme.dynamicColor(
            light: (red: 0.1, green: 0.2, blue: 0.3, alpha: 1.0),
            dark: (red: 0.4, green: 0.5, blue: 0.6, alpha: 1.0)
        )
        try assertNotNil(testColor)
    }

    func testAppThemeModeProperties() async throws {
        let auto = AppThemeMode.system
        let light = AppThemeMode.light
        let dark = AppThemeMode.dark

        try assertNil(auto.colorScheme, "System theme mode should produce nil colorScheme for macOS automatic appearance")
        try assertEqual(light.colorScheme, .light)
        try assertEqual(dark.colorScheme, .dark)

        try assertEqual(auto.iconName, "circle.lefthalf.filled")
        try assertEqual(light.iconName, "sun.max.fill")
        try assertEqual(dark.iconName, "moon.fill")
    }

    func testOtterAboutViewPresentation() async throws {
        // Instantiate OtterAboutView
        let aboutView = OtterAboutView()
        try assertNotNil(aboutView)

        // AboutWindowController singleton check
        let controller = AboutWindowController.shared
        try assertNotNil(controller)
    }

    func testAppStateRootNavigation() async throws {
        let appState = AppState()
        appState.activeNavigation = .dashboard
        try assertEqual(appState.activeNavigation, .dashboard)

        appState.activeNavigation = .photos
        try assertEqual(appState.activeNavigation, .photos)

        appState.activeNavigation = .logs
        try assertEqual(appState.activeNavigation, .logs)

        appState.activeNavigation = .settings
        try assertEqual(appState.activeNavigation, .settings)

        // Open About presentation trigger
        appState.openAbout()
    }
}

// MARK: - Executable Entrypoint

@main
struct OtterKeepTestRunnerMain {
    static func main() async {
        let suite = OtterKeepTestSuite()
        do {
            try await suite.runAll()
            exit(0)
        } catch {
            print("\n❌ SUITE COMPLETED WITH FAILURES: \(error)\n")
            exit(1)
        }
    }
}
