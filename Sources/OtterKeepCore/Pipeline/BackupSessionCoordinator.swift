import Foundation
import os
import AppKit
import OtterKeepStorage
import OtterKeepDatabase

/// Operational phases of the incremental backup workflow.
public enum BackupPhase: String, Sendable {
    /// Idle state awaiting backup initiation.
    case idle = "idle"
    /// Scanning source directory and evaluating exclusion rules.
    case scanning = "scanning"
    /// Running differential change detection against the previous snapshot.
    case analyzing = "analyzing"
    /// Copying new/modified files and creating APFS reflink clones.
    case copying = "copying"
    /// Committing snapshot metadata, immutability flags, and catalog index.
    case committing = "committing"
    /// Backup successfully completed.
    case completed = "completed"
    /// Backup failed with an unrecoverable error.
    case failed = "failed"

    /// Corresponding localization key.
    public var localizedKey: L10n.Key {
        switch self {
        case .idle: return .phaseIdle
        case .scanning: return .phaseScanning
        case .analyzing: return .phaseAnalyzing
        case .copying: return .phaseCopying
        case .committing: return .phaseFinalizing
        case .completed: return .phaseCompleted
        case .failed: return .phaseFailed
        }
    }

    /// Localized display description.
    public var localizedDescription: String {
        L10n.t(localizedKey)
    }
}

/// Execution mode for a backup operation.
public enum BackupMode: String, Codable, Sendable {
    /// Standard incremental backup comparing against previous catalog with APFS CoW deduplication.
    case incremental = "incremental"
    /// Forced full backup ignoring previous snapshots and freshly copying all files from source.
    case full = "full"

    /// Localized display title.
    public var localizedTitle: String {
        switch self {
        case .incremental: return L10n.t(.backupTypeIncremental)
        case .full: return L10n.t(.backupTypeFull)
        }
    }
}

/// Representation of an individual file error encountered during a backup operation.
public struct BackupErrorItem: Sendable, Equatable, Identifiable {
    /// Stable identifier for SwiftUI collections.
    public var id: String { relativePath + "_" + errorMessage }
    /// File URL that failed.
    public let url: URL
    /// Relative path of the failed item.
    public let relativePath: String
    /// Detailed error message.
    public let errorMessage: String
    /// Indicates whether the error was caused by missing permissions.
    public let isPermissionError: Bool

    /// Initializes a `BackupErrorItem`.
    public init(url: URL, relativePath: String, errorMessage: String, isPermissionError: Bool = false) {
        self.url = url
        self.relativePath = relativePath
        self.errorMessage = errorMessage
        self.isPermissionError = isPermissionError
    }
}

/// Comprehensive summary metrics recorded at the end of a backup session.
public struct BackupSessionSummary: Sendable, Equatable {
    /// Unique snapshot identifier.
    public let snapshotId: String
    /// Name of the profile that executed the backup.
    public let profileName: String
    /// Execution timestamp.
    public let timestamp: Date
    /// Total duration in seconds.
    public let durationSeconds: Double
    /// Total source files scanned.
    public let totalScannedFiles: Int
    /// Total source bytes scanned.
    public let totalScannedBytes: Int64
    /// Number of newly copied or modified files.
    public let copiedCount: Int
    /// Total byte size of transferred files.
    public let copiedBytes: Int64
    /// Number of files deduplicated via APFS Copy-on-Write (reflink).
    public let clonedCount: Int
    /// Total byte size of reflinked files.
    public let clonedBytes: Int64
    /// Total number of skipped items.
    public let skippedCount: Int
    /// Total number of encountered errors.
    public let errorCount: Int
    /// List of items skipped during scan.
    public let skippedItems: [SkippedItem]
    /// List of file errors encountered during copy.
    public let errorItems: [BackupErrorItem]
    /// Final completion status string.
    public let status: String
    /// Average data throughput in bytes per second.
    public let averageSpeedBytesPerSecond: Double
    /// Count of older snapshots pruned by retention rules.
    public let autoPrunedSnapshotsCount: Int

    /// Initializes a `BackupSessionSummary`.
    public init(
        snapshotId: String,
        profileName: String,
        timestamp: Date,
        durationSeconds: Double,
        totalScannedFiles: Int,
        totalScannedBytes: Int64,
        copiedCount: Int,
        copiedBytes: Int64,
        clonedCount: Int,
        clonedBytes: Int64,
        skippedCount: Int,
        errorCount: Int,
        skippedItems: [SkippedItem],
        errorItems: [BackupErrorItem],
        status: String,
        averageSpeedBytesPerSecond: Double,
        autoPrunedSnapshotsCount: Int = 0
    ) {
        self.snapshotId = snapshotId
        self.profileName = profileName
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.totalScannedFiles = totalScannedFiles
        self.totalScannedBytes = totalScannedBytes
        self.copiedCount = copiedCount
        self.copiedBytes = copiedBytes
        self.clonedCount = clonedCount
        self.clonedBytes = clonedBytes
        self.skippedCount = skippedCount
        self.errorCount = errorCount
        self.skippedItems = skippedItems
        self.errorItems = errorItems
        self.status = status
        self.averageSpeedBytesPerSecond = averageSpeedBytesPerSecond
        self.autoPrunedSnapshotsCount = autoPrunedSnapshotsCount
    }
}

/// Real-time progress state broadcasted during a live backup run.
public struct BackupProgressState: Sendable {
    /// Active operational phase.
    public var phase: BackupPhase
    /// Total number of files to process.
    public var totalFiles: Int
    /// Number of files processed so far.
    public var processedFiles: Int
    /// Total bytes requiring transfer.
    public var totalBytes: Int64
    /// Bytes transferred so far.
    public var processedBytes: Int64
    /// Current file path being processed.
    public var currentItem: String
    /// Current transfer speed in bytes per second.
    public var speedBytesPerSecond: Double

    /// Telemetry counters
    public var copiedCount: Int
    public var copiedBytes: Int64
    public var clonedCount: Int
    public var clonedBytes: Int64
    public var skippedCount: Int
    public var errorCount: Int
    public var skippedItems: [SkippedItem]
    public var errorItems: [BackupErrorItem]
    public var estimatedRemainingSeconds: TimeInterval?
    public var lastSummary: BackupSessionSummary?

    /// Initializes a `BackupProgressState`.
    public init(
        phase: BackupPhase = .idle,
        totalFiles: Int = 0,
        processedFiles: Int = 0,
        totalBytes: Int64 = 0,
        processedBytes: Int64 = 0,
        currentItem: String = "",
        speedBytesPerSecond: Double = 0,
        copiedCount: Int = 0,
        copiedBytes: Int64 = 0,
        clonedCount: Int = 0,
        clonedBytes: Int64 = 0,
        skippedCount: Int = 0,
        errorCount: Int = 0,
        skippedItems: [SkippedItem] = [],
        errorItems: [BackupErrorItem] = [],
        estimatedRemainingSeconds: TimeInterval? = nil,
        lastSummary: BackupSessionSummary? = nil
    ) {
        self.phase = phase
        self.totalFiles = totalFiles
        self.processedFiles = processedFiles
        self.totalBytes = totalBytes
        self.processedBytes = processedBytes
        self.currentItem = currentItem
        self.speedBytesPerSecond = speedBytesPerSecond
        self.copiedCount = copiedCount
        self.copiedBytes = copiedBytes
        self.clonedCount = clonedCount
        self.clonedBytes = clonedBytes
        self.skippedCount = skippedCount
        self.errorCount = errorCount
        self.skippedItems = skippedItems
        self.errorItems = errorItems
        self.estimatedRemainingSeconds = estimatedRemainingSeconds
        self.lastSummary = lastSummary
    }
}

/// Pre-backup simulation summary estimating disk space requirements without writing files.
public struct DryRunSummary: Sendable, Equatable {
    /// Total files scanned at source.
    public let totalScannedFiles: Int
    /// Total byte size of scanned source files.
    public let totalScannedBytes: Int64
    /// Count of newly added files.
    public let addedCount: Int
    /// Byte size of newly added files.
    public let addedBytes: Int64
    /// Count of modified files.
    public let modifiedCount: Int
    /// Byte size of modified files.
    public let modifiedBytes: Int64
    /// Count of deleted files.
    public let deletedCount: Int
    /// Count of unmodified files eligible for APFS reflink deduplication.
    public let unmodifiedCount: Int
    /// Estimated net additional disk storage required.
    public let estimatedNewBytes: Int64
    /// Number of skipped items.
    public let skippedCount: Int
    /// List of skipped items.
    public let skippedItems: [SkippedItem]
    /// List of relative paths for added items.
    public let addedPaths: [String]
    /// List of relative paths for modified items.
    public let modifiedPaths: [String]
    /// List of relative paths for deleted items.
    public let deletedPaths: [String]

    /// Initializes a `DryRunSummary`.
    public init(
        totalScannedFiles: Int,
        totalScannedBytes: Int64,
        addedCount: Int,
        addedBytes: Int64,
        modifiedCount: Int,
        modifiedBytes: Int64,
        deletedCount: Int,
        unmodifiedCount: Int,
        estimatedNewBytes: Int64,
        skippedCount: Int,
        skippedItems: [SkippedItem] = [],
        addedPaths: [String] = [],
        modifiedPaths: [String] = [],
        deletedPaths: [String] = []
    ) {
        self.totalScannedFiles = totalScannedFiles
        self.totalScannedBytes = totalScannedBytes
        self.addedCount = addedCount
        self.addedBytes = addedBytes
        self.modifiedCount = modifiedCount
        self.modifiedBytes = modifiedBytes
        self.deletedCount = deletedCount
        self.unmodifiedCount = unmodifiedCount
        self.estimatedNewBytes = estimatedNewBytes
        self.skippedCount = skippedCount
        self.skippedItems = skippedItems
        self.addedPaths = addedPaths
        self.modifiedPaths = modifiedPaths
        self.deletedPaths = deletedPaths
    }
}

/// Actor-isolated coordinator orchestrating the atomic, incremental APFS Copy-on-Write backup lifecycle.
public actor BackupSessionCoordinator {
    private let storage: FileSystemProvider
    private let database: DatabaseEngine
    private let icloudController: ICloudEvictionController
    private let retentionManager: RetentionManager
    private let logger = Logger(subsystem: "com.otterkeep", category: "BackupCoordinator")

    /// Summary of the most recently executed backup session.
    public private(set) var lastSessionSummary: BackupSessionSummary?

    /// Initializes a `BackupSessionCoordinator`.
    /// - Parameters:
    ///   - storage: Filesystem provider.
    ///   - database: Database engine.
    ///   - icloudController: iCloud eviction and download controller.
    ///   - retentionManager: Snapshot retention manager.
    public init(
        storage: FileSystemProvider = APFSFileSystemProvider(),
        database: DatabaseEngine = DatabaseEngine(),
        icloudController: ICloudEvictionController = ICloudEvictionController(),
        retentionManager: RetentionManager? = nil
    ) {
        self.storage = storage
        self.database = database
        self.icloudController = icloudController
        self.retentionManager = retentionManager ?? RetentionManager(storage: storage, database: database)
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmmss"
        df.timeZone = .current
        return df
    }()

    /// Performs a complete atomic incremental or forced full backup for the specified profile.
    /// - Parameters:
    ///   - profile: Target backup profile.
    ///   - mode: Backup execution mode (incremental or full).
    ///   - onProgress: Optional callback invoked periodically with live progress telemetry.
    /// - Returns: The newly created `SnapshotRecord`.
    public func performBackup(
        profile: BackupProfile,
        mode: BackupMode = .incremental,
        onProgress: (@Sendable (BackupProgressState) -> Void)? = nil
    ) async throws -> SnapshotRecord {
        let startTime = ContinuousClock.now
        let progressTracker = OSAllocatedUnfairLock(initialState: BackupProgressState(phase: .scanning))
        let reportProgress: @Sendable () -> Void = {
            let state = progressTracker.withLock { $0 }
            onProgress?(state)
        }
        reportProgress()

        let modeTag = mode == .full ? "[FORCED FULL BACKUP]" : "[INCREMENTAL]"
        logger.info("\(modeTag) Backup started for profile '\(profile.name)' (UUID: \(profile.id.uuidString)) Source: \(profile.sourceURL.path), Destination: \(profile.destinationURL.path)")
        LogManager.shared.log("\(modeTag) Backup started for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]. Source: '\(profile.sourceURL.path)', Destination: '\(profile.destinationURL.path)'", level: .info, category: "Backup")

        // Lock profile against concurrent operations across processes
        guard let lockToken = ProfileExecutionLock.shared.acquireLock(for: profile.id) else {
            let lockMsg = L10n.format(.errProfileAlreadyLocked, profile.name)
            logger.warning("\(lockMsg)")
            LogManager.shared.log(lockMsg, level: .warning, category: "Backup")
            NotificationDeliveryService.shared.notifyBackupFailed(profileName: profile.name, errorMessage: lockMsg)
            throw FileSystemError.permissionDenied(path: "\(profile.name) (Profile locked by another process)")
        }
        defer { lockToken.release() }

        let powerAssertion = PowerManagementAssertion()
        powerAssertion.begin(reason: "OtterKeep backup for profile '\(profile.name)'")
        defer { powerAssertion.end() }

        do {
            // Pre-backup hook execution
            if let preHookURL = await HookExecutionManager.shared.resolveHookScript(hookName: "pre-backup", profile: profile) {
                logger.info("Executing pre-backup hook script: \(preHookURL.path)")
                LogManager.shared.log("Executing pre-backup hook script: '\(preHookURL.path)'", level: .info, category: "Hook")
                let preEnv: [String: String] = [
                    "OTTERKEEP_PROFILE_ID": profile.id.uuidString,
                    "OTTERKEEP_PROFILE_NAME": profile.name,
                    "OTTERKEEP_PROFILE": profile.name,
                    "OTTERKEEP_SOURCE_PATH": profile.sourceURL.standardizedFileURL.path,
                    "OTTERKEEP_SOURCE": profile.sourceURL.standardizedFileURL.path,
                    "OTTERKEEP_DESTINATION_PATH": profile.destinationURL.standardizedFileURL.path,
                    "OTTERKEEP_DESTINATION": profile.destinationURL.standardizedFileURL.path,
                    "OTTERKEEP_BACKUP_MODE": mode.rawValue
                ]
                let result = try await HookExecutionManager.shared.executeHook(scriptURL: preHookURL, environment: preEnv)
                if !result.isSuccess {
                    let abortMsg = "Pre-backup hook failed with exit code \(result.exitCode). Backup aborted to preserve consistency."
                    logger.error("\(abortMsg) Output: \(result.standardError.isEmpty ? result.standardOutput : result.standardError)")
                    LogManager.shared.log(abortMsg, level: .error, category: "Hook")
                    throw FileSystemError.unknown(abortMsg)
                }
                LogManager.shared.log("Pre-backup hook completed successfully.", level: .info, category: "Hook")
            }

            // 0. Verify source directory accessibility
            let srcPath = profile.sourceURL.standardizedFileURL.path(percentEncoded: false)
            guard FileManager.default.fileExists(atPath: srcPath) else {
                let errMsg = "Source directory is not accessible: '\(profile.sourceURL.path)'"
                logger.error("\(errMsg)")
                LogManager.shared.log(errMsg, level: .error, category: "Backup")
                throw FileSystemError.itemNotFound(path: profile.sourceURL.path)
            }

            // 1. Prepare destination directory, capabilities, and SQLite database
            let destinationURL = profile.destinationURL.standardizedFileURL
            try storage.createDirectory(at: destinationURL)

        let eval = VolumeCapabilityEvaluator.evaluate(sourceURL: profile.sourceURL, destinationURL: destinationURL)
        let destinationCaps = try await storage.capabilities(at: destinationURL)
        logger.info("Destination volume capabilities: FS=\(destinationCaps.fsTypeName), APFSClone=\(destinationCaps.supportsAPFSClone), CoWMode=\(String(describing: eval.cowMode))")

        if eval.isSameVolume {
            let spofMsg = String(format: L10n.t(.spofWarningFormat), profile.destinationURL.path)
            logger.warning("\(spofMsg)")
            LogManager.shared.log(spofMsg, level: .warning, category: "Security")
        }

        let internalDir = destinationURL.appendingPathComponent(".otterkeep")
        try storage.createDirectory(at: internalDir)

        let dbPath = internalDir.appendingPathComponent("manifest.sqlite").standardizedFileURL.path(percentEncoded: false)
        try await database.open(at: dbPath)

        // 2. Clean up dangling temporary/staging directories from any interrupted runs
        try cleanupDanglingStagingDirectories(at: destinationURL)

        // 3. Find previous snapshot catalog if running in incremental mode
        var previousCatalog: [String: FileCatalogRecord] = [:]
        var previousSnapshotURL: URL?
        if mode == .incremental {
            let latestSnapshots = try await database.listSnapshots()
            let previousSnapshot = latestSnapshots.first(where: { $0.status == "completed" || $0.status == "completed_with_warnings" })
            if let prev = previousSnapshot {
                let files = try await database.listFiles(forSnapshotId: prev.id)
                for f in files {
                    previousCatalog[f.relativePath] = f
                }
                previousSnapshotURL = destinationURL.appendingPathComponent(prev.snapshotPath)
                logger.info("Previous snapshot found: \(prev.id) (\(files.count) entries)")
            }
        } else {
            logger.info("Forced FULL backup initiated for profile '\(profile.name)'. Previous snapshots will not be cloned.")
            LogManager.shared.log("Forced FULL backup initiated for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]. All source files will be copied freshly.", level: .info, category: "Backup")
        }

        // 4. Scan source directory (collecting items and TCC/permission skips)
        let scanner = FileTreeScanner(
            storage: storage,
            excludePatterns: profile.excludePatterns,
            enableIgnoreFiles: profile.enableIgnoreFiles,
            respectGitIgnore: profile.respectGitIgnore
        )
        let scanResult = try await scanner.scanDetailed(rootURL: profile.sourceURL)
        let scannedItems = scanResult.items
        var skippedItems: [SkippedItem] = scanResult.skippedItems
        var errorItems: [BackupErrorItem] = []

        logger.info("Scan completed: \(scannedItems.count) items found, \(skippedItems.count) skipped")

        let initialSkipped = skippedItems
        progressTracker.withLock { state in
            state.phase = .analyzing
            state.totalFiles = scannedItems.count
            state.skippedCount = initialSkipped.count
            state.skippedItems = initialSkipped
        }
        reportProgress()

        // 5. Differential change analysis
        let detector = ChangeDetector()
        let changes = detector.detectChanges(
            scannedItems: scannedItems,
            previousCatalog: previousCatalog,
            hashMode: profile.hashVerificationMode
        )

        logger.info("Differential: \(changes.unmodified.count) unmodified, \(changes.added.count) added, \(changes.modified.count) modified, \(changes.deleted.count) deleted")

        // 5a. Ransomware & Rate-of-Change Anomaly Guard evaluation
        if profile.enableRateOfChangeGuard {
            let anomalyReport = RansomwareAnomalyGuard.evaluate(
                scannedItems: scannedItems,
                changes: changes,
                profile: profile
            )
            if anomalyReport.isAnomalyDetected {
                let anomalyReason = anomalyReport.reason ?? "Ransomware signature or abnormal rate-of-change detected."
                logger.warning("Ransomware Anomaly Guard triggered for profile '\(profile.name)': \(anomalyReason)")
                LogManager.shared.log("Ransomware Anomaly Guard: \(anomalyReason)", level: .warning, category: "Security")

                if profile.abortOnAnomaly {
                    NotificationDeliveryService.shared.notifyRansomwareAlert(
                        profileName: profile.name,
                        reason: anomalyReason
                    )
                    await dispatchWebhookNotification(
                        profile: profile,
                        status: "ransomware_anomaly",
                        snapshotPath: "",
                        scannedFiles: scannedItems.count,
                        copiedFiles: 0,
                        copiedBytes: 0,
                        durationSeconds: 0,
                        errorMessage: anomalyReason
                    )
                    throw FileSystemError.unknown("Backup aborted by Ransomware & Rate-of-Change Guard: \(anomalyReason)")
                }
            }
        }

        // 5b. Pre-flight storage check (changed bytes + 1 GB safety buffer)
        let safetyBuffer: Int64 = 1024 * 1024 * 1024 // 1 GB safety margin
        let requiredBytes = changes.totalChangedBytes + safetyBuffer
        let targetCapacity = try storage.storageCapacity(at: destinationURL)
        if targetCapacity.availableBytes < requiredBytes {
            let errMsg = "Insufficient destination storage space. Required: \(requiredBytes / 1024 / 1024) MB (including 1 GB buffer), Available: \(targetCapacity.availableBytes / 1024 / 1024) MB"
            logger.error("\(errMsg)")
            LogManager.shared.log(errMsg, level: .error, category: "Backup")
            NotificationDeliveryService.shared.notifyLowDiskSpace(
                availableBytes: targetCapacity.availableBytes,
                requiredBytes: requiredBytes,
                destinationName: destinationURL.lastPathComponent
            )
            throw FileSystemError.notEnoughSpace(requiredBytes: requiredBytes, availableBytes: targetCapacity.availableBytes)
        }

        // 6. Create staging directory for atomic commit
        let snapshotDate = Date()
        var timestampStr = Self.dateFormatter.string(from: snapshotDate)
        var finalSnapshotDir = destinationURL.appendingPathComponent(timestampStr)
        var suffixIndex = 1
        while FileManager.default.fileExists(atPath: finalSnapshotDir.standardizedFileURL.path(percentEncoded: false)) {
            timestampStr = "\(Self.dateFormatter.string(from: snapshotDate))_\(suffixIndex)"
            finalSnapshotDir = destinationURL.appendingPathComponent(timestampStr)
            suffixIndex += 1
        }
        let snapshotId = "snapshot_\(timestampStr)"
        let stagingDir = destinationURL.appendingPathComponent(".in-progress_\(timestampStr)")
        let stagingRoot = stagingDir.appendingPathComponent("root")

        var isCommitted = false
        defer {
            if !isCommitted {
                try? storage.setImmutable(at: stagingDir, immutable: false)
                try? storage.removeItem(at: stagingDir)
            }
        }

        try storage.createDirectory(at: stagingRoot)

        progressTracker.withLock { state in
            state.phase = .copying
            state.totalFiles = scannedItems.count
            state.totalBytes = changes.totalChangedBytes
        }
        reportProgress()

        var catalogRecordsToSave: [FileCatalogRecord] = []
        var clonedCount = 0
        var clonedBytes: Int64 = 0
        var copiedCount = 0
        var copiedBytes: Int64 = 0

        // Pre-create directory skeleton in staging root
        for item in scannedItems where item.metadata.isDirectory {
            let dirURL = stagingRoot.appendingPathComponent(item.relativePath)
            try storage.createDirectory(at: dirURL)
        }

        // 7. Process unmodified files via concurrent APFS CoW cloning or hardlinks from previous snapshot
        if let prevURL = previousSnapshotURL {
            let prevRoot = prevURL.appendingPathComponent("root")

            for item in changes.unmodified where item.current.metadata.isDirectory {
                catalogRecordsToSave.append(FileCatalogRecord(
                    snapshotId: snapshotId,
                    relativePath: item.current.relativePath,
                    fileSize: item.current.metadata.size,
                    modificationTime: item.current.metadata.modificationTime,
                    inode: item.current.metadata.inode,
                    checksum: item.previous.checksum,
                    sampleHash: item.previous.sampleHash,
                    isDirectory: true,
                    isSymlink: item.current.metadata.isSymlink
                ))
            }

            let unmodifiedFiles = changes.unmodified.filter { !$0.current.metadata.isDirectory }
            let cloneConcurrency = min(8, max(4, ProcessInfo.processInfo.activeProcessorCount))

            try await withThrowingTaskGroup(of: (record: FileCatalogRecord, size: Int64, wasCloned: Bool).self) { group in
                var activeTasks = 0
                for item in unmodifiedFiles {
                    try Task.checkCancellation()

                    if activeTasks >= cloneConcurrency {
                        if let result = try await group.next() {
                            activeTasks -= 1
                            catalogRecordsToSave.append(result.record)
                            if result.wasCloned {
                                clonedCount += 1
                                clonedBytes += result.size
                            } else {
                                copiedCount += 1
                                copiedBytes += result.size
                            }
                            let currentClonedCount = clonedCount
                            let currentClonedBytes = clonedBytes
                            let shouldReport = progressTracker.withLock { state -> Bool in
                                state.processedFiles += 1
                                state.currentItem = result.record.relativePath
                                state.clonedCount = currentClonedCount
                                state.clonedBytes = currentClonedBytes
                                return state.processedFiles % 100 == 0
                            }
                            if shouldReport {
                                reportProgress()
                            }
                        }
                    }

                    let currentItem = item.current
                    let prevRecord = item.previous
                    let targetURL = stagingRoot.appendingPathComponent(currentItem.relativePath)
                    let sourceCloneURL = prevRoot.appendingPathComponent(currentItem.relativePath)
                    let localCapAPFS = destinationCaps.supportsAPFSClone
                    let localCapHardLink = destinationCaps.supportsHardLinks
                    let localStorage = self.storage
                    let localSnapshotId = snapshotId
                    let localIcloud = self.icloudController
                    let localStrategy = profile.icloudStrategy

                    group.addTask {
                        try Task.checkCancellation()
                        let parentDir = targetURL.deletingLastPathComponent()
                        try localStorage.createDirectory(at: parentDir)

                        var cloned = false
                        let performFallbackCopy = {
                            if currentItem.isDatalessICloud && localStrategy == .downloadAndEvict {
                                try await localIcloud.processUbiquitousItem(
                                    sourceURL: currentItem.url,
                                    destinationURL: targetURL,
                                    strategy: localStrategy,
                                    wasOriginallyDataless: true
                                )
                            } else {
                                try await localStorage.copyItemPreservingMetadata(at: currentItem.url, to: targetURL, progress: nil)
                            }
                        }

                        if localCapAPFS {
                            do {
                                try await localStorage.cloneItem(at: sourceCloneURL, to: targetURL)
                                cloned = true
                            } catch {
                                do {
                                    try await performFallbackCopy()
                                } catch {
                                    try? localStorage.removeItem(at: targetURL)
                                    throw error
                                }
                            }
                        } else if localCapHardLink {
                            do {
                                try await localStorage.createHardLink(at: sourceCloneURL, to: targetURL)
                                cloned = true
                            } catch {
                                do {
                                    try await performFallbackCopy()
                                } catch {
                                    try? localStorage.removeItem(at: targetURL)
                                    throw error
                                }
                            }
                        } else {
                            do {
                                try await performFallbackCopy()
                            } catch {
                                try? localStorage.removeItem(at: targetURL)
                                throw error
                            }
                        }

                        let record = FileCatalogRecord(
                            snapshotId: localSnapshotId,
                            relativePath: currentItem.relativePath,
                            fileSize: currentItem.metadata.size,
                            modificationTime: currentItem.metadata.modificationTime,
                            inode: currentItem.metadata.inode,
                            checksum: prevRecord.checksum,
                            sampleHash: prevRecord.sampleHash,
                            isDirectory: false,
                            isSymlink: currentItem.metadata.isSymlink
                        )
                        return (record, currentItem.metadata.size, cloned)
                    }
                    activeTasks += 1
                }

                while let result = try await group.next() {
                    catalogRecordsToSave.append(result.record)
                    if result.wasCloned {
                        clonedCount += 1
                        clonedBytes += result.size
                    } else {
                        copiedCount += 1
                        copiedBytes += result.size
                    }
                    let currentClonedCount = clonedCount
                    let currentClonedBytes = clonedBytes
                    let shouldReport = progressTracker.withLock { state -> Bool in
                        state.processedFiles += 1
                        state.currentItem = result.record.relativePath
                        state.clonedCount = currentClonedCount
                        state.clonedBytes = currentClonedBytes
                        return state.processedFiles % 100 == 0
                    }
                    if shouldReport {
                        reportProgress()
                    }
                }
            }
        }

        // 8. Copy added and modified files with concurrent transfer, iCloud deduplication & SHA-256 verification
        let itemsToCopy = changes.added + changes.modified

        // Pre-warm ubiquitous iCloud items in batch so background daemons pipeline transfers ahead of time
        if profile.icloudStrategy == .downloadAndEvict {
            let datalessURLs = itemsToCopy.filter { $0.isDatalessICloud }.map { $0.url }
            await icloudController.prewarmUbiquitousItems(urls: datalessURLs)
        }

        for item in itemsToCopy where item.metadata.isDirectory {
            catalogRecordsToSave.append(FileCatalogRecord(
                snapshotId: snapshotId,
                relativePath: item.relativePath,
                fileSize: item.metadata.size,
                modificationTime: item.metadata.modificationTime,
                inode: item.metadata.inode,
                checksum: nil,
                isDirectory: true,
                isSymlink: item.metadata.isSymlink
            ))
            progressTracker.withLock { state in
                state.processedFiles += 1
                state.currentItem = item.relativePath
            }
            reportProgress()
        }

        let filesToCopy = itemsToCopy.filter { !$0.metadata.isDirectory }
        let copyConcurrency = min(6, max(3, ProcessInfo.processInfo.activeProcessorCount))

        try await withThrowingTaskGroup(of: CopyWorkerResult.self) { group in
            var activeTasks = 0
            for item in filesToCopy {
                try Task.checkCancellation()

                if activeTasks >= copyConcurrency {
                    if let result = try await group.next() {
                        activeTasks -= 1
                        self.handleCopyWorkerResult(
                            result,
                            profile: profile,
                            progressTracker: progressTracker,
                            copiedCount: &copiedCount,
                            copiedBytes: &copiedBytes,
                            catalogRecordsToSave: &catalogRecordsToSave,
                            errorItems: &errorItems,
                            skippedItems: &skippedItems,
                            reportProgress: reportProgress
                        )
                    }
                }

                let currentItem = item
                let targetURL = stagingRoot.appendingPathComponent(currentItem.relativePath)
                let currentItemPath = currentItem.relativePath
                let localSnapshotId = snapshotId
                let localIcloud = self.icloudController
                let localStrategy = profile.icloudStrategy
                let localTracker = progressTracker
                let localStart = startTime
                let localStorage = self.storage

                group.addTask {
                    try Task.checkCancellation()
                    let parentDir = targetURL.deletingLastPathComponent()
                    try localStorage.createDirectory(at: parentDir)

                    do {
                        try await localIcloud.processUbiquitousItem(
                            sourceURL: currentItem.url,
                            destinationURL: targetURL,
                            strategy: localStrategy,
                            wasOriginallyDataless: currentItem.isDatalessICloud
                        ) { copiedChunk in
                            let elapsed = ContinuousClock.now - localStart
                            let elapsedSec = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                            localTracker.withLock { state in
                                let speed = elapsedSec > 0.05 ? Double(state.processedBytes + copiedChunk) / elapsedSec : 0
                                state.speedBytesPerSecond = speed
                                state.currentItem = currentItemPath
                                if speed > 1024 && state.totalBytes > state.processedBytes {
                                    state.estimatedRemainingSeconds = Double(state.totalBytes - state.processedBytes) / speed
                                }
                            }
                        }

                        // Compute SHA-256 cryptographic hash and sparse sample hash for data integrity & fast change detection
                        let checksum = try? ChecksumCalculator.computeSHA256(for: targetURL)
                        let sampleHash = try? FastHashCalculator.computeSamplingHash(for: targetURL)

                        let record = FileCatalogRecord(
                            snapshotId: localSnapshotId,
                            relativePath: currentItem.relativePath,
                            fileSize: currentItem.metadata.size,
                            modificationTime: currentItem.metadata.modificationTime,
                            inode: currentItem.metadata.inode,
                            checksum: checksum,
                            sampleHash: sampleHash,
                            isDirectory: false,
                            isSymlink: currentItem.metadata.isSymlink
                        )

                        return CopyWorkerResult(
                            item: currentItem,
                            record: record,
                            copiedBytes: currentItem.metadata.size,
                            errorItem: nil,
                            skippedItem: nil
                        )
                    } catch is CancellationError {
                        try? localStorage.removeItem(at: targetURL)
                        throw CancellationError()
                    } catch {
                        try? localStorage.removeItem(at: targetURL)
                        let isPerm = (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSFileReadNoPermissionError
                        let errItem = BackupErrorItem(
                            url: currentItem.url,
                            relativePath: currentItem.relativePath,
                            errorMessage: error.localizedDescription,
                            isPermissionError: isPerm
                        )
                        let skipItem = SkippedItem(
                            url: currentItem.url,
                            relativePath: currentItem.relativePath,
                            reason: error.localizedDescription,
                            isPermissionError: isPerm
                        )
                        return CopyWorkerResult(
                            item: currentItem,
                            record: nil,
                            copiedBytes: 0,
                            errorItem: errItem,
                            skippedItem: skipItem
                        )
                    }
                }
                activeTasks += 1
            }

            while let result = try await group.next() {
                self.handleCopyWorkerResult(
                    result,
                    profile: profile,
                    progressTracker: progressTracker,
                    copiedCount: &copiedCount,
                    copiedBytes: &copiedBytes,
                    catalogRecordsToSave: &catalogRecordsToSave,
                    errorItems: &errorItems,
                    skippedItems: &skippedItems,
                    reportProgress: reportProgress
                )
            }
        }

        // Reclaim local storage for ubiquitous packages, directories, and standalone files downloaded during backup
        if profile.icloudStrategy == .downloadAndEvict {
            var directoryURLsToEvict = Set<URL>()
            var fileURLsToEvict = Set<URL>()

            let allDatalessItems = scannedItems.filter { $0.isDatalessICloud }
            for item in allDatalessItems {
                if item.metadata.isDirectory {
                    directoryURLsToEvict.insert(item.url)
                } else {
                    fileURLsToEvict.insert(item.url)

                    // Check if any ancestor directory up to sourceURL is a ubiquitous package (e.g. .app, .photoslibrary)
                    var parent = item.url.deletingLastPathComponent()
                    let sourcePath = profile.sourceURL.standardizedFileURL.path
                    while parent.standardizedFileURL.path.hasPrefix(sourcePath) && parent.standardizedFileURL.path != sourcePath {
                        if let vals = try? parent.resourceValues(forKeys: [.isPackageKey, .isUbiquitousItemKey]),
                           vals.isPackage == true && vals.isUbiquitousItem == true {
                            directoryURLsToEvict.insert(parent)
                        }
                        parent = parent.deletingLastPathComponent()
                    }
                }
            }

            // 1. Evict any standalone files that were originally dataless and might still be downloaded on disk
            for fileURL in fileURLsToEvict {
                if await icloudController.isItemActuallyDownloaded(at: fileURL) {
                    logger.info("Post-backup reclaiming storage for dataless file: \(fileURL.lastPathComponent)")
                    await icloudController.evictUbiquitousItemWithRetry(at: fileURL)
                }
            }

            // 2. Sort deepest paths first so sub-packages evict before top-level packages
            let sortedDirs = directoryURLsToEvict.sorted { $0.path.count > $1.path.count }
            for dirURL in sortedDirs {
                await icloudController.evictUbiquitousItemWithRetry(at: dirURL)
            }
        }

        // 9. Write snapshot metadata manifest
        progressTracker.withLock { state in
            state.phase = .committing
        }
        reportProgress()

        let snapshotInfo: [String: Any] = [
            "id": snapshotId,
            "timestamp": snapshotDate.timeIntervalSince1970,
            "totalFiles": scannedItems.count,
            "totalBytes": scannedItems.reduce(0) { $0 + $1.metadata.size },
            "profileName": profile.name,
            "skippedCount": skippedItems.count,
            "errorCount": errorItems.count
        ]
        if let infoData = try? JSONSerialization.data(withJSONObject: snapshotInfo, options: [.prettyPrinted]) {
            try infoData.write(to: stagingDir.appendingPathComponent(".snapshot_info.json"))
        }

        // 10. Atomically move staging directory to final snapshot location
        try await storage.atomicMove(from: stagingDir, to: finalSnapshotDir)
        isCommitted = true

        // 11. Activate BSD immutability (UF_IMMUTABLE / WORM protection)
        do {
            try storage.setImmutable(at: finalSnapshotDir, immutable: true)
            logger.info("Immutability (UF_IMMUTABLE) flag activated for: \(finalSnapshotDir.lastPathComponent)")
        } catch {
            logger.warning("Notice: Immutability flag could not be set: \(error.localizedDescription)")
        }

        // 12. Atomically update 'Latest' symbolic link
        let latestLink = destinationURL.appendingPathComponent("Latest")
        let tempLink = destinationURL.appendingPathComponent(".latest_temp")
        try? FileManager.default.removeItem(at: tempLink)
        try FileManager.default.createSymbolicLink(at: tempLink, withDestinationURL: finalSnapshotDir)
        try await storage.atomicMove(from: tempLink, to: latestLink)

        // 13. Determine final status
        let snapshotStatus: String
        if !errorItems.isEmpty {
            snapshotStatus = "completed_with_errors"
        } else if !skippedItems.isEmpty {
            snapshotStatus = "completed_with_warnings"
        } else {
            snapshotStatus = "completed"
        }

        // 14. Persist database records
        let snapshotRecord = SnapshotRecord(
            id: snapshotId,
            timestamp: snapshotDate,
            status: snapshotStatus,
            totalFiles: Int64(catalogRecordsToSave.count),
            totalBytes: catalogRecordsToSave.reduce(0) { $0 + $1.fileSize },
            snapshotPath: timestampStr,
            backupType: mode.rawValue
        )
        try await database.insertSnapshot(snapshotRecord)
        try await database.insertFileRecordsBatch(catalogRecordsToSave)

        // 15. Automatic retention pruning (if enabled in profile)
        var autoPrunedCount = 0
        if profile.pruningPolicy.isAutoPruningEnabled {
            do {
                let retainCount = profile.pruningPolicy.maxSnapshotsToKeep ?? 5
                logger.info("Running automatic retention pruning for profile '\(profile.name)' (Threshold: \(retainCount))...")
                let deletedIds = try await retentionManager.applyRetentionPolicy(destinationURL: destinationURL, policy: profile.pruningPolicy)
                autoPrunedCount = deletedIds.count
                if !deletedIds.isEmpty {
                    LogManager.shared.log("Auto-pruning completed for profile '\(profile.name)': \(deletedIds.count) older snapshots pruned (Pruned IDs: [\(deletedIds.joined(separator: ", "))]). Retained: \(retainCount) recent snapshots.", level: .info, category: "Retention")
                } else {
                    LogManager.shared.log("Auto-pruning checked for profile '\(profile.name)': All snapshots within retention limit (\(retainCount)).", level: .debug, category: "Retention")
                }
            } catch {
                logger.error("Auto-pruning failed for profile '\(profile.name)': \(error.localizedDescription)")
                LogManager.shared.log("Auto-pruning failed for profile '\(profile.name)': \(error.localizedDescription)", level: .warning, category: "Retention")
            }
        }

        let duration = Double((ContinuousClock.now - startTime).components.seconds) + Double((ContinuousClock.now - startTime).components.attoseconds) / 1e18
        let avgSpeed = duration > 0.05 ? Double(copiedBytes) / duration : 0

        let sessionSummary = BackupSessionSummary(
            snapshotId: snapshotId,
            profileName: profile.name,
            timestamp: snapshotDate,
            durationSeconds: duration,
            totalScannedFiles: scannedItems.count,
            totalScannedBytes: scannedItems.reduce(0) { $0 + $1.metadata.size },
            copiedCount: copiedCount,
            copiedBytes: copiedBytes,
            clonedCount: clonedCount,
            clonedBytes: clonedBytes,
            skippedCount: skippedItems.count,
            errorCount: errorItems.count,
            skippedItems: skippedItems,
            errorItems: errorItems,
            status: snapshotStatus,
            averageSpeedBytesPerSecond: avgSpeed,
            autoPrunedSnapshotsCount: autoPrunedCount
        )
        self.lastSessionSummary = sessionSummary

        // Deliver macOS system notification
        NotificationDeliveryService.shared.notifyBackupCompleted(
            profileName: profile.name,
            status: snapshotStatus,
            copiedCount: copiedCount,
            durationSec: duration
        )

        let finalErrors = errorItems
        let finalSkipped = skippedItems
        let finalCopiedCount = copiedCount
        let finalCopiedBytes = copiedBytes
        let finalClonedCount = clonedCount
        let finalClonedBytes = clonedBytes
        progressTracker.withLock { state in
            state.phase = .completed
            state.processedFiles = scannedItems.count
            state.processedBytes = state.totalBytes
            state.copiedCount = finalCopiedCount
            state.copiedBytes = finalCopiedBytes
            state.clonedCount = finalClonedCount
            state.clonedBytes = finalClonedBytes
            state.skippedCount = finalSkipped.count
            state.errorCount = finalErrors.count
            state.skippedItems = finalSkipped
            state.errorItems = finalErrors
            state.lastSummary = sessionSummary
        }
        reportProgress()

        let speedMB = avgSpeed / (1024 * 1024)
        var errorDetails = ""
        if !errorItems.isEmpty {
            let topErrors = errorItems.prefix(3).map { "'\($0.relativePath)': \($0.errorMessage)" }.joined(separator: "; ")
            errorDetails = ", Error details: [\(topErrors)\(errorItems.count > 3 ? "; ..." : "")]"
        }

        let completionMessage = "Backup finished (\(snapshotStatus)) for profile '\(profile.name)' [UUID: \(profile.id.uuidString)] (\(mode.rawValue.uppercased())). Snapshot: \(snapshotId). Duration: \(String(format: "%.2f", duration))s, Speed: \(String(format: "%.2f", speedMB)) MB/s. Copied: \(copiedCount) files (\(copiedBytes) bytes), Cloned (APFS CoW): \(clonedCount) files (\(clonedBytes) bytes), Skipped: \(skippedItems.count) files, Errors: \(errorItems.count) files\(errorDetails). Auto-pruned: \(autoPrunedCount) snapshots."

        logger.info("\(completionMessage)")
        LogManager.shared.log(
            completionMessage,
            level: errorItems.isEmpty ? .info : .warning,
            category: "Backup"
        )
        // Post-backup hook execution (success / warnings / errors)
        await runPostBackupHook(
            profile: profile,
            mode: mode,
            status: snapshotStatus,
            snapshotPath: finalSnapshotDir.standardizedFileURL.path,
            scannedFiles: scannedItems.count,
            copiedFiles: copiedCount,
            copiedBytes: copiedBytes,
            durationSeconds: duration
        )

        // Webhook remote monitoring dispatch
        await dispatchWebhookNotification(
            profile: profile,
            status: snapshotStatus,
            snapshotPath: finalSnapshotDir.standardizedFileURL.path,
            scannedFiles: scannedItems.count,
            copiedFiles: copiedCount,
            copiedBytes: copiedBytes,
            durationSeconds: duration
        )

        // Automatic unmount/eject if enabled
        if profile.autoEjectOnCompletion && (snapshotStatus == "completed" || snapshotStatus == "completed_with_warnings") {
            logger.info("Auto-eject enabled for profile '\(profile.name)'. Ejecting destination device...")
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: profile.destinationURL)
                LogManager.shared.log("Destination volume safely unmounted and ejected for profile '\(profile.name)'.", level: .info, category: "Storage")
            } catch {
                LogManager.shared.log("Failed to safely unmount destination volume at '\(profile.destinationURL.path)': \(error.localizedDescription)", level: .warning, category: "Storage")
            }
        }

        return snapshotRecord
    } catch {
        let duration = Double((ContinuousClock.now - startTime).components.seconds) + Double((ContinuousClock.now - startTime).components.attoseconds) / 1e18
        await runPostBackupHook(
            profile: profile,
            mode: mode,
            status: "failed",
            snapshotPath: "",
            scannedFiles: 0,
            copiedFiles: 0,
            copiedBytes: 0,
            durationSeconds: duration
        )
        await dispatchWebhookNotification(
            profile: profile,
            status: "failed",
            snapshotPath: "",
            scannedFiles: 0,
            copiedFiles: 0,
            copiedBytes: 0,
            durationSeconds: duration,
            errorMessage: error.localizedDescription
        )
        throw error
    }
}


    /// Performs pre-backup dry-run analysis evaluating additions, modifications, and storage impact without writing files.
    /// - Parameters:
    ///   - profile: Target backup profile.
    ///   - mode: Backup execution mode (default: `.incremental`).
    /// - Returns: A `DryRunSummary` metric structure.
    public func performDryRun(profile: BackupProfile, mode: BackupMode = .incremental) async throws -> DryRunSummary {
        let modeTag = mode == .full ? "[FORCED FULL BACKUP]" : "[INCREMENTAL]"
        logger.info("Starting pre-backup analysis (Dry-Run \(modeTag)): '\(profile.name)' (Source: \(profile.sourceURL.path))")

        let destinationURL = profile.destinationURL.standardizedFileURL
        let internalDir = destinationURL.appendingPathComponent(".otterkeep")
        let dbPath = internalDir.appendingPathComponent("manifest.sqlite").standardizedFileURL.path(percentEncoded: false)

        var previousCatalog: [String: FileCatalogRecord] = [:]
        if mode == .incremental && FileManager.default.fileExists(atPath: dbPath) {
            try? await database.open(at: dbPath)
            if let latestSnapshots = try? await database.listSnapshots(),
               let previousSnapshot = latestSnapshots.first(where: { $0.status == "completed" || $0.status == "completed_with_warnings" }) {
                if let files = try? await database.listFiles(forSnapshotId: previousSnapshot.id) {
                    for f in files {
                        previousCatalog[f.relativePath] = f
                    }
                }
            }
        }

        // Scan source directory respecting exclusion rules
        let scanner = FileTreeScanner(
            storage: storage,
            excludePatterns: profile.excludePatterns,
            enableIgnoreFiles: profile.enableIgnoreFiles,
            respectGitIgnore: profile.respectGitIgnore
        )
        let scanResult = try await scanner.scanDetailed(rootURL: profile.sourceURL)
        let scannedItems = scanResult.items

        // Detect differential changes
        let detector = ChangeDetector()
        let changes = detector.detectChanges(
            scannedItems: scannedItems,
            previousCatalog: previousCatalog,
            hashMode: profile.hashVerificationMode
        )

        let addedBytes = changes.added.reduce(0) { $0 + $1.metadata.size }
        let modifiedBytes = changes.modified.reduce(0) { $0 + $1.metadata.size }
        let totalScannedBytes = scannedItems.reduce(0) { $0 + $1.metadata.size }

        logger.info("Dry-Run (\(mode.rawValue)) completed: \(changes.added.count) added, \(changes.modified.count) modified, \(changes.deleted.count) deleted, \(changes.unmodified.count) unmodified. Estimated net storage: \(changes.totalChangedBytes) bytes.")

        return DryRunSummary(
            totalScannedFiles: scannedItems.count,
            totalScannedBytes: totalScannedBytes,
            addedCount: changes.added.count,
            addedBytes: addedBytes,
            modifiedCount: changes.modified.count,
            modifiedBytes: modifiedBytes,
            deletedCount: changes.deleted.count,
            unmodifiedCount: changes.unmodified.count,
            estimatedNewBytes: changes.totalChangedBytes,
            skippedCount: scanResult.skippedItems.count,
            skippedItems: scanResult.skippedItems,
            addedPaths: changes.added.map { $0.relativePath },
            modifiedPaths: changes.modified.map { $0.relativePath },
            deletedPaths: changes.deleted.map { $0.relativePath }
        )
    }

    private func cleanupDanglingStagingDirectories(at destinationURL: URL) throws {
        let contents = (try? FileManager.default.contentsOfDirectory(at: destinationURL, includingPropertiesForKeys: nil)) ?? []
        for url in contents {
            let name = url.lastPathComponent
            if name.hasPrefix(".in-progress_") || name == ".latest_temp" || name.hasPrefix(".trash_") {
                logger.warning("Cleaning dangling temporary directory: \(name)")
                try? storage.setImmutable(at: url, immutable: false)
                try? storage.removeItem(at: url)
            }
        }
    }

    private struct CopyWorkerResult: Sendable {
        let item: ScannedItem
        let record: FileCatalogRecord?
        let copiedBytes: Int64
        let errorItem: BackupErrorItem?
        let skippedItem: SkippedItem?
    }

    private func handleCopyWorkerResult(
        _ result: CopyWorkerResult,
        profile: BackupProfile,
        progressTracker: OSAllocatedUnfairLock<BackupProgressState>,
        copiedCount: inout Int,
        copiedBytes: inout Int64,
        catalogRecordsToSave: inout [FileCatalogRecord],
        errorItems: inout [BackupErrorItem],
        skippedItems: inout [SkippedItem],
        reportProgress: () -> Void
    ) {
        if let record = result.record {
            catalogRecordsToSave.append(record)
            copiedCount += 1
            copiedBytes += result.copiedBytes

            let currentCopiedCount = copiedCount
            let currentCopiedBytes = copiedBytes
            let itemBytes = result.copiedBytes
            progressTracker.withLock { state in
                state.processedBytes += itemBytes
                state.processedFiles += 1
                state.copiedCount = currentCopiedCount
                state.copiedBytes = currentCopiedBytes
                state.currentItem = result.item.relativePath
            }
        } else if let err = result.errorItem, let skip = result.skippedItem {
            logger.warning("Failed to process '\(result.item.relativePath)': \(err.errorMessage)")
            let isPerm = err.isPermissionError
            let reasonTag = isPerm ? "[Permission Denied / TCC]" : "[Read/Copy Failed]"
            LogManager.shared.log("\(reasonTag) Failed to backup '\(result.item.relativePath)' in profile '\(profile.name)': \(err.errorMessage)", level: .warning, category: "Backup")

            errorItems.append(err)
            skippedItems.append(skip)

            let currentErrors = errorItems
            let currentSkipped = skippedItems
            progressTracker.withLock { state in
                state.processedFiles += 1
                state.currentItem = result.item.relativePath
                state.errorCount = currentErrors.count
                state.errorItems = currentErrors
                state.skippedCount = currentSkipped.count
                state.skippedItems = currentSkipped
            }
        }
        reportProgress()
    }

    private func runPostBackupHook(
        profile: BackupProfile,
        mode: BackupMode,
        status: String,
        snapshotPath: String,
        scannedFiles: Int,
        copiedFiles: Int,
        copiedBytes: Int64,
        durationSeconds: Double
    ) async {
        guard let postHookURL = await HookExecutionManager.shared.resolveHookScript(hookName: "post-backup", profile: profile) else {
            return
        }
        logger.info("Executing post-backup hook script: \(postHookURL.path)")
        LogManager.shared.log("Executing post-backup hook script: '\(postHookURL.path)'", level: .info, category: "Hook")
        let postEnv: [String: String] = [
            "OTTERKEEP_PROFILE_ID": profile.id.uuidString,
            "OTTERKEEP_PROFILE_NAME": profile.name,
            "OTTERKEEP_PROFILE": profile.name,
            "OTTERKEEP_SOURCE_PATH": profile.sourceURL.standardizedFileURL.path,
            "OTTERKEEP_SOURCE": profile.sourceURL.standardizedFileURL.path,
            "OTTERKEEP_DESTINATION_PATH": profile.destinationURL.standardizedFileURL.path,
            "OTTERKEEP_DESTINATION": profile.destinationURL.standardizedFileURL.path,
            "OTTERKEEP_BACKUP_MODE": mode.rawValue,
            "OTTERKEEP_STATUS": status,
            "OTTERKEEP_SNAPSHOT_PATH": snapshotPath,
            "OTTERKEEP_FILES_SCANNED": String(scannedFiles),
            "OTTERKEEP_FILES_COPIED": String(copiedFiles),
            "OTTERKEEP_BYTES_WRITTEN": String(copiedBytes),
            "OTTERKEEP_DURATION_SECONDS": String(format: "%.2f", durationSeconds)
        ]
        do {
            let result = try await HookExecutionManager.shared.executeHook(scriptURL: postHookURL, environment: postEnv)
            if result.isSuccess {
                LogManager.shared.log("Post-backup hook executed successfully (Exit code: 0).", level: .info, category: "Hook")
            } else {
                LogManager.shared.log("Post-backup hook exited with non-zero status \(result.exitCode). Stderr: \(result.standardError)", level: .warning, category: "Hook")
            }
        } catch {
            LogManager.shared.log("Post-backup hook execution error: \(error.localizedDescription)", level: .warning, category: "Hook")
        }
    }

    private func dispatchWebhookNotification(
        profile: BackupProfile,
        status: String,
        snapshotPath: String,
        scannedFiles: Int,
        copiedFiles: Int,
        copiedBytes: Int64,
        durationSeconds: Double,
        errorMessage: String? = nil
    ) async {
        guard profile.webhookConfig.isEnabled else { return }
        let payload = WebhookBackupPayload(
            profileId: profile.id.uuidString,
            profileName: profile.name,
            status: status,
            snapshotPath: snapshotPath,
            filesScanned: Int64(scannedFiles),
            filesCopied: Int64(copiedFiles),
            bytesWritten: copiedBytes,
            durationSeconds: durationSeconds,
            timestamp: Date(),
            errorMessage: errorMessage
        )
        do {
            try await WebhookDispatcher.shared.dispatch(config: profile.webhookConfig, payload: payload)
        } catch {
            LogManager.shared.log("Failed to dispatch webhook notification: \(error.localizedDescription)", level: .warning, category: "Webhook")
        }
    }
}

