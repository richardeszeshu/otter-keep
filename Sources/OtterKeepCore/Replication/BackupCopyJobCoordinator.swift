import Foundation
import os
import OtterKeepStorage
import OtterKeepDatabase

/// Summary metrics of a completed 3-2-1 replication copy job run.
public struct ReplicationJobSummary: Sendable, Equatable {
    public let snapshotId: String
    public let profileId: UUID
    public let totalDestinations: Int
    public let successfulDestinations: Int
    public let replicatedFiles: Int
    public let replicatedBytes: Int64
    public let skippedFiles: Int
    public let durationSeconds: Double
    public let status: String

    public init(
        snapshotId: String,
        profileId: UUID,
        totalDestinations: Int,
        successfulDestinations: Int,
        replicatedFiles: Int,
        replicatedBytes: Int64,
        skippedFiles: Int,
        durationSeconds: Double,
        status: String
    ) {
        self.snapshotId = snapshotId
        self.profileId = profileId
        self.totalDestinations = totalDestinations
        self.successfulDestinations = successfulDestinations
        self.replicatedFiles = replicatedFiles
        self.replicatedBytes = replicatedBytes
        self.skippedFiles = skippedFiles
        self.durationSeconds = durationSeconds
        self.status = status
    }
}

/// Real-time progress state broadcasted during a live 3-2-1 backup copy job.
public struct ReplicationProgressState: Sendable {
    public var isRunning: Bool
    public var currentDestinationName: String
    public var totalFiles: Int
    public var processedFiles: Int
    public var totalBytes: Int64
    public var replicatedBytes: Int64
    public var currentFile: String
    public var speedBytesPerSecond: Double
    public var statusMessage: String

    public init(
        isRunning: Bool = false,
        currentDestinationName: String = "",
        totalFiles: Int = 0,
        processedFiles: Int = 0,
        totalBytes: Int64 = 0,
        replicatedBytes: Int64 = 0,
        currentFile: String = "",
        speedBytesPerSecond: Double = 0,
        statusMessage: String = ""
    ) {
        self.isRunning = isRunning
        self.currentDestinationName = currentDestinationName
        self.totalFiles = totalFiles
        self.processedFiles = processedFiles
        self.totalBytes = totalBytes
        self.replicatedBytes = replicatedBytes
        self.currentFile = currentFile
        self.speedBytesPerSecond = speedBytesPerSecond
        self.statusMessage = statusMessage
    }
}

/// Internal outcome metrics for a single destination sync execution.
private struct DestinationSyncResult: Sendable {
    let replicatedFiles: Int
    let replicatedBytes: Int64
    let skippedFiles: Int
    let isSuccess: Bool
}

/// Actor orchestrating the secondary replication pipeline (3-2-1 Backup Copy Job) to S3 Cloud and NAS storage.
public actor BackupCopyJobCoordinator {
    private let storage: FileSystemProvider
    private let database: DatabaseEngine
    private let logger = Logger(subsystem: "com.otterkeep", category: "Replication")

    public typealias ProgressHandler = @Sendable (ReplicationProgressState) -> Void
    private var onProgress: ProgressHandler?

    public init(storage: FileSystemProvider, database: DatabaseEngine) {
        self.storage = storage
        self.database = database
    }

    /// Sets the progress update callback.
    public func setProgressHandler(_ handler: @escaping ProgressHandler) {
        self.onProgress = handler
    }

    /// Executes the 3-2-1 replication copy job for a given profile and snapshot.
    /// - Parameters:
    ///   - profile: The backup profile.
    ///   - targetSnapshotId: Optional snapshot ID (if nil, uses latest completed snapshot).
    /// - Returns: Summary of replication results.
    public func executeReplication(
        profile: BackupProfile,
        targetSnapshotId: String? = nil
    ) async throws -> ReplicationJobSummary {
        let startTime = Date()
        let destinations = profile.copyJobConfig.destinations.filter { $0.isEnabled }

        guard profile.copyJobConfig.isEnabled, !destinations.isEmpty else {
            logger.info("3-2-1 Replication copy job is not enabled or has no active destinations.")
            return ReplicationJobSummary(
                snapshotId: targetSnapshotId ?? "",
                profileId: profile.id,
                totalDestinations: 0,
                successfulDestinations: 0,
                replicatedFiles: 0,
                replicatedBytes: 0,
                skippedFiles: 0,
                durationSeconds: 0,
                status: "skipped_no_destinations"
            )
        }

        // 1. Verify Network Policy (including Wi-Fi SSID rules and metered connection guard)
        let unmeteredOnly = profile.copyJobConfig.networkPolicy == .unmeteredOnly || profile.copyJobConfig.pauseOnMeteredNetwork
        let eval = NetworkReachability.shared.evaluatePolicy(
            allowedSSIDs: profile.copyJobConfig.allowedWiFiSSIDs,
            disallowedSSIDs: profile.copyJobConfig.disallowedWiFiSSIDs,
            pauseOnMetered: unmeteredOnly
        )
        if !eval.isPermitted {
            let msg = eval.reason ?? "Network policy constraint not satisfied."
            logger.warning("\(msg)")
            LogManager.shared.log("Replication postponed for profile [\(profile.id)]: \(msg)", level: .warning, category: "Replication")
            throw NSError(domain: "OtterKeep.Replication", code: 4001, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        // 2. Resolve target snapshot
        let snapshot: SnapshotRecord
        if let id = targetSnapshotId {
            let snaps = try await database.listSnapshots()
            guard let found = snaps.first(where: { $0.id == id }) else {
                throw NSError(domain: "OtterKeep.Replication", code: 4004, userInfo: [NSLocalizedDescriptionKey: "Snapshot not found: \(id)"])
            }
            snapshot = found
        } else {
            guard let latest = try await database.fetchLatestSnapshot() else {
                throw NSError(domain: "OtterKeep.Replication", code: 4004, userInfo: [NSLocalizedDescriptionKey: "No snapshots available for replication"])
            }
            snapshot = latest
        }

        let snapshotRoot = profile.destinationURL.appendingPathComponent(snapshot.snapshotPath).appendingPathComponent("root")
        let fileRecords = try await database.listFiles(forSnapshotId: snapshot.id)
        let filesToSync = fileRecords.filter { !$0.isDirectory }

        var totalReplicatedFiles = 0
        var totalReplicatedBytes: Int64 = 0
        var totalSkippedFiles = 0
        var successfulDests = 0

        let throttler = BandwidthThrottler(maxBytesPerSecond: profile.copyJobConfig.maxBandwidthBytesPerSec)

        for dest in destinations {
            try Task.checkCancellation()

            var state = ReplicationProgressState(
                isRunning: true,
                currentDestinationName: dest.name,
                totalFiles: filesToSync.count,
                processedFiles: 0,
                totalBytes: snapshot.totalBytes,
                replicatedBytes: 0,
                statusMessage: "Starting replication to \(dest.name)..."
            )
            onProgress?(state)

            let result: DestinationSyncResult
            switch dest.type {
            case .s3(let s3Config):
                result = try await replicateS3(
                    dest: dest,
                    s3Config: s3Config,
                    snapshot: snapshot,
                    snapshotRoot: snapshotRoot,
                    filesToSync: filesToSync,
                    profile: profile,
                    throttler: throttler,
                    state: &state
                )
            case .smb(let smbConfig):
                result = try await replicateSMB(
                    dest: dest,
                    smbConfig: smbConfig,
                    snapshot: snapshot,
                    snapshotRoot: snapshotRoot,
                    filesToSync: filesToSync,
                    profile: profile,
                    throttler: throttler,
                    state: &state
                )
            case .webdav(let webdavConfig):
                result = try await replicateWebDAV(
                    dest: dest,
                    webdavConfig: webdavConfig,
                    snapshot: snapshot,
                    snapshotRoot: snapshotRoot,
                    filesToSync: filesToSync,
                    profile: profile,
                    throttler: throttler,
                    state: &state
                )
            case .sftp(let sftpConfig):
                result = try await replicateSFTP(
                    dest: dest,
                    sftpConfig: sftpConfig,
                    snapshot: snapshot,
                    snapshotRoot: snapshotRoot,
                    filesToSync: filesToSync,
                    profile: profile,
                    throttler: throttler,
                    state: &state
                )
            }

            totalReplicatedFiles += result.replicatedFiles
            totalReplicatedBytes += result.replicatedBytes
            totalSkippedFiles += result.skippedFiles
            if result.isSuccess {
                successfulDests += 1
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        let summary = ReplicationJobSummary(
            snapshotId: snapshot.id,
            profileId: profile.id,
            totalDestinations: destinations.count,
            successfulDestinations: successfulDests,
            replicatedFiles: totalReplicatedFiles,
            replicatedBytes: totalReplicatedBytes,
            skippedFiles: totalSkippedFiles,
            durationSeconds: duration,
            status: successfulDests == destinations.count ? "completed" : "completed_with_errors"
        )

        onProgress?(ReplicationProgressState(
            isRunning: false,
            currentDestinationName: "",
            totalFiles: filesToSync.count,
            processedFiles: filesToSync.count,
            totalBytes: snapshot.totalBytes,
            replicatedBytes: totalReplicatedBytes,
            statusMessage: "3-2-1 Replication finished."
        ))

        LogManager.shared.log("3-2-1 Replication Copy Job finished for profile [\(profile.id)]: \(successfulDests)/\(destinations.count) destinations synced (\(totalReplicatedFiles) files, \(totalReplicatedBytes / 1024 / 1024) MB) in \(String(format: "%.2f", duration))s", level: .info, category: "Replication")

        return summary
    }

    // MARK: - Private Protocol-Specific Replicators

    private func replicateS3(
        dest: RemoteDestination,
        s3Config: S3Configuration,
        snapshot: SnapshotRecord,
        snapshotRoot: URL,
        filesToSync: [FileCatalogRecord],
        profile: BackupProfile,
        throttler: BandwidthThrottler,
        state: inout ReplicationProgressState
    ) async throws -> DestinationSyncResult {
        let destId = "s3://\(s3Config.bucket)/\(s3Config.pathPrefix)"
        _ = try await database.recordReplicationSnapshot(ReplicationSnapshotRecord(
            snapshotId: snapshot.id,
            destinationType: "s3",
            destinationIdentifier: destId,
            status: "in_progress",
            replicatedBytes: 0,
            totalBytes: snapshot.totalBytes,
            startedAt: Date()
        ))

        do {
            let s3Provider = RemoteStorageFactory.makeS3Provider(for: dest, config: s3Config)
            let passphrase = RemoteStorageFactory.resolveEncryptionPassphrase(for: dest, profileId: profile.id)

            var destReplicatedFiles = 0
            var destReplicatedBytes: Int64 = 0
            var destSkippedFiles = 0

            if dest.archivePackagingEnabled || profile.copyJobConfig.archivePackagingEnabled {
                state.statusMessage = "Packaging snapshot into compressed archive..."
                let format = ArchivePackagingEngine.shared.defaultFormat
                state.currentFile = "\(snapshot.id).\(format.fileExtension)"
                onProgress?(state)

                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("OtterKeep_Arch_\(UUID().uuidString)")
                let archiveURL = tempDir.appendingPathComponent("\(snapshot.id).\(format.fileExtension)")
                defer { try? FileManager.default.removeItem(at: tempDir) }

                try await ArchivePackagingEngine.shared.createArchive(
                    sourceDirectory: snapshotRoot,
                    destinationArchiveURL: archiveURL,
                    compressionLevel: dest.archiveCompressionLevel
                )

                let rawData = try Data(contentsOf: archiveURL)
                let payload: Data
                let objectKey: String
                if dest.isClientEncryptionEnabled {
                    payload = try ClientSideEncryptor.encrypt(data: rawData, passphrase: passphrase)
                    objectKey = "\(snapshot.id)/\(archiveURL.lastPathComponent).enc"
                } else {
                    payload = rawData
                    objectKey = "\(snapshot.id)/\(archiveURL.lastPathComponent)"
                }

                await throttler.throttle(byteCount: Int64(payload.count))

                let etag: String
                if payload.count > 8 * 1024 * 1024 {
                    let uploadId = try await s3Provider.initiateMultipartUpload(key: objectKey)
                    var parts: [(partNumber: Int, etag: String)] = []
                    let chunkSize = 5 * 1024 * 1024
                    var offset = 0
                    var partNumber = 1

                    while offset < payload.count {
                        try Task.checkCancellation()
                        let length = min(chunkSize, payload.count - offset)
                        let chunkData = payload.subdata(in: offset..<(offset + length))
                        await throttler.throttle(byteCount: Int64(chunkData.count))
                        let partETag = try await s3Provider.uploadPart(key: objectKey, uploadId: uploadId, partNumber: partNumber, data: chunkData)
                        parts.append((partNumber: partNumber, etag: partETag))
                        offset += length
                        partNumber += 1
                    }
                    try await s3Provider.completeMultipartUpload(key: objectKey, uploadId: uploadId, parts: parts)
                    etag = parts.first?.etag ?? ""
                } else {
                    etag = try await s3Provider.putObject(key: objectKey, data: payload)
                }

                try await database.recordReplicationFile(ReplicationFileRecord(
                    snapshotId: snapshot.id,
                    destinationIdentifier: destId,
                    relativePath: archiveURL.lastPathComponent,
                    remoteKey: objectKey,
                    remoteETag: etag,
                    checksum: try? ChecksumCalculator.computeSHA256(for: archiveURL),
                    fileSize: Int64(payload.count),
                    status: "replicated"
                ))

                destReplicatedFiles = 1
                destReplicatedBytes = Int64(payload.count)
                state.processedFiles = filesToSync.count
                state.replicatedBytes = destReplicatedBytes
                onProgress?(state)
            } else {
                for file in filesToSync {
                    try Task.checkCancellation()

                    state.currentFile = file.relativePath
                    onProgress?(state)

                    let (alreadySynced, existingKey, existingETag) = try await database.isReplicationFileSynced(
                        destinationIdentifier: destId,
                        relativePath: file.relativePath,
                        checksum: file.checksum,
                        fileSize: file.fileSize
                    )

                    if alreadySynced, let key = existingKey {
                        destSkippedFiles += 1
                        try await database.recordReplicationFile(ReplicationFileRecord(
                            snapshotId: snapshot.id,
                            destinationIdentifier: destId,
                            relativePath: file.relativePath,
                            remoteKey: key,
                            remoteETag: existingETag,
                            checksum: file.checksum,
                            fileSize: file.fileSize,
                            status: "reused"
                        ))
                        state.processedFiles += 1
                        onProgress?(state)
                        continue
                    }

                    let localFileURL = snapshotRoot.appendingPathComponent(file.relativePath)
                    guard FileManager.default.fileExists(atPath: localFileURL.path(percentEncoded: false)) else {
                        continue
                    }

                    let rawData = try Data(contentsOf: localFileURL)
                    let payload: Data
                    let objectKey: String
                    if dest.isClientEncryptionEnabled {
                        payload = try ClientSideEncryptor.encrypt(data: rawData, passphrase: passphrase)
                        objectKey = "\(snapshot.id)/\(file.relativePath).enc"
                    } else {
                        payload = rawData
                        objectKey = "\(snapshot.id)/\(file.relativePath)"
                    }

                    await throttler.throttle(byteCount: Int64(payload.count))

                    let etag: String
                    if payload.count > 8 * 1024 * 1024 {
                        let uploadId = try await s3Provider.initiateMultipartUpload(key: objectKey)
                        var parts: [(partNumber: Int, etag: String)] = []
                        let chunkSize = 5 * 1024 * 1024
                        var offset = 0
                        var partNumber = 1

                        while offset < payload.count {
                            try Task.checkCancellation()
                            let length = min(chunkSize, payload.count - offset)
                            let chunkData = payload.subdata(in: offset..<(offset + length))
                            await throttler.throttle(byteCount: Int64(chunkData.count))
                            let partETag = try await s3Provider.uploadPart(key: objectKey, uploadId: uploadId, partNumber: partNumber, data: chunkData)
                            parts.append((partNumber: partNumber, etag: partETag))
                            offset += length
                            partNumber += 1
                        }
                        try await s3Provider.completeMultipartUpload(key: objectKey, uploadId: uploadId, parts: parts)
                        etag = parts.first?.etag ?? ""
                    } else {
                        etag = try await s3Provider.putObject(key: objectKey, data: payload)
                    }

                    try await database.recordReplicationFile(ReplicationFileRecord(
                        snapshotId: snapshot.id,
                        destinationIdentifier: destId,
                        relativePath: file.relativePath,
                        remoteKey: objectKey,
                        remoteETag: etag,
                        checksum: file.checksum,
                        fileSize: file.fileSize,
                        status: "replicated"
                    ))

                    destReplicatedFiles += 1
                    destReplicatedBytes += file.fileSize
                    state.processedFiles += 1
                    state.replicatedBytes += file.fileSize
                    onProgress?(state)
                }
            }

            try await database.updateReplicationSnapshot(
                snapshotId: snapshot.id,
                destinationIdentifier: destId,
                status: "completed",
                replicatedBytes: destReplicatedBytes,
                completedAt: Date()
            )

            logger.info("Successfully replicated snapshot \(snapshot.id) to S3: \(destReplicatedFiles) files, \(destReplicatedBytes) bytes")
            return DestinationSyncResult(
                replicatedFiles: destReplicatedFiles,
                replicatedBytes: destReplicatedBytes,
                skippedFiles: destSkippedFiles,
                isSuccess: true
            )
        } catch {
            let errMsg = error.localizedDescription
            logger.error("Failed to replicate snapshot to S3: \(errMsg)")
            try? await database.updateReplicationSnapshot(
                snapshotId: snapshot.id,
                destinationIdentifier: destId,
                status: "failed",
                replicatedBytes: 0,
                completedAt: Date(),
                errorMessage: errMsg
            )
            return DestinationSyncResult(
                replicatedFiles: 0,
                replicatedBytes: 0,
                skippedFiles: 0,
                isSuccess: false
            )
        }
    }

    private func replicateSMB(
        dest: RemoteDestination,
        smbConfig: NetworkShareConfiguration,
        snapshot: SnapshotRecord,
        snapshotRoot: URL,
        filesToSync: [FileCatalogRecord],
        profile: BackupProfile,
        throttler: BandwidthThrottler,
        state: inout ReplicationProgressState
    ) async throws -> DestinationSyncResult {
        let destId = smbConfig.shareURL
        _ = try await database.recordReplicationSnapshot(ReplicationSnapshotRecord(
            snapshotId: snapshot.id,
            destinationType: "smb",
            destinationIdentifier: destId,
            status: "in_progress",
            replicatedBytes: 0,
            totalBytes: snapshot.totalBytes,
            startedAt: Date()
        ))

        do {
            let (mountPoint, resolvedSubpath) = try await RemoteStorageFactory.mountNetworkShare(for: dest, config: smbConfig)
            let targetDir = mountPoint.appendingPathComponent(resolvedSubpath).appendingPathComponent(snapshot.snapshotPath)
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

            var destReplicatedFiles = 0
            var destReplicatedBytes: Int64 = 0
            var destSkippedFiles = 0

            for file in filesToSync {
                try Task.checkCancellation()
                let srcURL = snapshotRoot.appendingPathComponent(file.relativePath)
                let dstURL = targetDir.appendingPathComponent("root").appendingPathComponent(file.relativePath)
                try FileManager.default.createDirectory(at: dstURL.deletingLastPathComponent(), withIntermediateDirectories: true)

                if !FileManager.default.fileExists(atPath: dstURL.path(percentEncoded: false)) {
                    try FileManager.default.copyItem(at: srcURL, to: dstURL)
                    destReplicatedFiles += 1
                    destReplicatedBytes += file.fileSize
                } else {
                    destSkippedFiles += 1
                }

                state.processedFiles += 1
                state.replicatedBytes += file.fileSize
                onProgress?(state)
            }

            try await database.updateReplicationSnapshot(
                snapshotId: snapshot.id,
                destinationIdentifier: destId,
                status: "completed",
                replicatedBytes: destReplicatedBytes,
                completedAt: Date()
            )

            logger.info("Successfully replicated snapshot \(snapshot.id) to SMB NAS")
            return DestinationSyncResult(
                replicatedFiles: destReplicatedFiles,
                replicatedBytes: destReplicatedBytes,
                skippedFiles: destSkippedFiles,
                isSuccess: true
            )
        } catch {
            let errMsg = error.localizedDescription
            logger.error("Failed to replicate snapshot to SMB: \(errMsg)")
            try? await database.updateReplicationSnapshot(
                snapshotId: snapshot.id,
                destinationIdentifier: destId,
                status: "failed",
                replicatedBytes: 0,
                completedAt: Date(),
                errorMessage: errMsg
            )
            return DestinationSyncResult(
                replicatedFiles: 0,
                replicatedBytes: 0,
                skippedFiles: 0,
                isSuccess: false
            )
        }
    }

    private func replicateWebDAV(
        dest: RemoteDestination,
        webdavConfig: WebDAVConfiguration,
        snapshot: SnapshotRecord,
        snapshotRoot: URL,
        filesToSync: [FileCatalogRecord],
        profile: BackupProfile,
        throttler: BandwidthThrottler,
        state: inout ReplicationProgressState
    ) async throws -> DestinationSyncResult {
        let destId = webdavConfig.serverURL + webdavConfig.destinationPath
        _ = try await database.recordReplicationSnapshot(ReplicationSnapshotRecord(
            snapshotId: snapshot.id,
            destinationType: "webdav",
            destinationIdentifier: destId,
            status: "in_progress",
            replicatedBytes: 0,
            totalBytes: snapshot.totalBytes,
            startedAt: Date()
        ))

        do {
            let webdavProvider = RemoteStorageFactory.makeWebDAVProvider(for: dest, config: webdavConfig)
            let passphrase = RemoteStorageFactory.resolveEncryptionPassphrase(for: dest, profileId: profile.id)

            var destReplicatedFiles = 0
            var destReplicatedBytes: Int64 = 0
            let destSkippedFiles = 0

            if dest.archivePackagingEnabled || profile.copyJobConfig.archivePackagingEnabled {
                let format = ArchivePackagingEngine.shared.defaultFormat
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("OtterKeep_WebDAV_\(UUID().uuidString)")
                let archiveURL = tempDir.appendingPathComponent("\(snapshot.id).\(format.fileExtension)")
                defer { try? FileManager.default.removeItem(at: tempDir) }

                try await ArchivePackagingEngine.shared.createArchive(
                    sourceDirectory: snapshotRoot,
                    destinationArchiveURL: archiveURL,
                    compressionLevel: dest.archiveCompressionLevel
                )

                let rawArchiveData = try Data(contentsOf: archiveURL)
                let payload: Data
                let remoteFilename: String
                if dest.isClientEncryptionEnabled {
                    payload = try ClientSideEncryptor.encrypt(data: rawArchiveData, passphrase: passphrase)
                    remoteFilename = "\(archiveURL.lastPathComponent).enc"
                } else {
                    payload = rawArchiveData
                    remoteFilename = archiveURL.lastPathComponent
                }

                try await webdavProvider.uploadFile(path: remoteFilename, data: payload)

                destReplicatedFiles = 1
                destReplicatedBytes = Int64(payload.count)
            } else {
                for file in filesToSync {
                    try Task.checkCancellation()
                    let localFileURL = snapshotRoot.appendingPathComponent(file.relativePath)
                    guard FileManager.default.fileExists(atPath: localFileURL.path(percentEncoded: false)) else { continue }
                    let rawData = try Data(contentsOf: localFileURL)
                    let payload: Data
                    let remotePath: String
                    if dest.isClientEncryptionEnabled {
                        payload = try ClientSideEncryptor.encrypt(data: rawData, passphrase: passphrase)
                        remotePath = "\(snapshot.id)/\(file.relativePath).enc"
                    } else {
                        payload = rawData
                        remotePath = "\(snapshot.id)/\(file.relativePath)"
                    }
                    await throttler.throttle(byteCount: Int64(payload.count))
                    try await webdavProvider.uploadFile(path: remotePath, data: payload)
                    destReplicatedFiles += 1
                    destReplicatedBytes += file.fileSize
                    state.processedFiles += 1
                    state.replicatedBytes += file.fileSize
                    onProgress?(state)
                }
            }

            try await database.updateReplicationSnapshot(
                snapshotId: snapshot.id,
                destinationIdentifier: destId,
                status: "completed",
                replicatedBytes: destReplicatedBytes,
                completedAt: Date()
            )

            logger.info("Successfully replicated snapshot \(snapshot.id) to WebDAV: \(destReplicatedFiles) files, \(destReplicatedBytes) bytes")
            return DestinationSyncResult(
                replicatedFiles: destReplicatedFiles,
                replicatedBytes: destReplicatedBytes,
                skippedFiles: destSkippedFiles,
                isSuccess: true
            )
        } catch {
            let errMsg = error.localizedDescription
            logger.error("Failed to replicate snapshot to WebDAV: \(errMsg)")
            try? await database.updateReplicationSnapshot(
                snapshotId: snapshot.id,
                destinationIdentifier: destId,
                status: "failed",
                replicatedBytes: 0,
                completedAt: Date(),
                errorMessage: errMsg
            )
            return DestinationSyncResult(
                replicatedFiles: 0,
                replicatedBytes: 0,
                skippedFiles: 0,
                isSuccess: false
            )
        }
    }

    private func replicateSFTP(
        dest: RemoteDestination,
        sftpConfig: SFTPConfiguration,
        snapshot: SnapshotRecord,
        snapshotRoot: URL,
        filesToSync: [FileCatalogRecord],
        profile: BackupProfile,
        throttler: BandwidthThrottler,
        state: inout ReplicationProgressState
    ) async throws -> DestinationSyncResult {
        let destId = "\(sftpConfig.host):\(sftpConfig.remotePath)"
        _ = try await database.recordReplicationSnapshot(ReplicationSnapshotRecord(
            snapshotId: snapshot.id,
            destinationType: "sftp",
            destinationIdentifier: destId,
            status: "in_progress",
            replicatedBytes: 0,
            totalBytes: snapshot.totalBytes,
            startedAt: Date()
        ))

        do {
            let sftpProvider = RemoteStorageFactory.makeSFTPProvider(for: dest, config: sftpConfig)
            let passphrase = RemoteStorageFactory.resolveEncryptionPassphrase(for: dest, profileId: profile.id)

            var destReplicatedFiles = 0
            var destReplicatedBytes: Int64 = 0
            let destSkippedFiles = 0

            if dest.archivePackagingEnabled || profile.copyJobConfig.archivePackagingEnabled {
                let format = ArchivePackagingEngine.shared.defaultFormat
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("OtterKeep_SFTP_\(UUID().uuidString)")
                let archiveURL = tempDir.appendingPathComponent("\(snapshot.id).\(format.fileExtension)")
                defer { try? FileManager.default.removeItem(at: tempDir) }

                try await ArchivePackagingEngine.shared.createArchive(
                    sourceDirectory: snapshotRoot,
                    destinationArchiveURL: archiveURL,
                    compressionLevel: dest.archiveCompressionLevel
                )

                let uploadURL: URL
                if dest.isClientEncryptionEnabled {
                    let rawArchiveData = try Data(contentsOf: archiveURL)
                    let payload = try ClientSideEncryptor.encrypt(data: rawArchiveData, passphrase: passphrase)
                    let encURL = tempDir.appendingPathComponent("\(archiveURL.lastPathComponent).enc")
                    try payload.write(to: encURL)
                    uploadURL = encURL
                } else {
                    uploadURL = archiveURL
                }

                try await sftpProvider.uploadFile(localURL: uploadURL, remotePath: uploadURL.lastPathComponent)

                let fileSize = (try? FileManager.default.attributesOfItem(atPath: uploadURL.path)[.size] as? Int64) ?? 0
                destReplicatedFiles = 1
                destReplicatedBytes = fileSize
            } else {
                for file in filesToSync {
                    try Task.checkCancellation()
                    let localFileURL = snapshotRoot.appendingPathComponent(file.relativePath)
                    guard FileManager.default.fileExists(atPath: localFileURL.path(percentEncoded: false)) else { continue }
                    try await sftpProvider.uploadFile(localURL: localFileURL, remotePath: "\(snapshot.id)/\(file.relativePath)")
                    destReplicatedFiles += 1
                    destReplicatedBytes += file.fileSize
                    state.processedFiles += 1
                    state.replicatedBytes += file.fileSize
                    onProgress?(state)
                }
            }

            try await database.updateReplicationSnapshot(
                snapshotId: snapshot.id,
                destinationIdentifier: destId,
                status: "completed",
                replicatedBytes: destReplicatedBytes,
                completedAt: Date()
            )

            logger.info("Successfully replicated snapshot \(snapshot.id) to SFTP: \(destReplicatedFiles) files, \(destReplicatedBytes) bytes")
            return DestinationSyncResult(
                replicatedFiles: destReplicatedFiles,
                replicatedBytes: destReplicatedBytes,
                skippedFiles: destSkippedFiles,
                isSuccess: true
            )
        } catch {
            let errMsg = error.localizedDescription
            logger.error("Failed to replicate snapshot to SFTP: \(errMsg)")
            try? await database.updateReplicationSnapshot(
                snapshotId: snapshot.id,
                destinationIdentifier: destId,
                status: "failed",
                replicatedBytes: 0,
                completedAt: Date(),
                errorMessage: errMsg
            )
            return DestinationSyncResult(
                replicatedFiles: 0,
                replicatedBytes: 0,
                skippedFiles: 0,
                isSuccess: false
            )
        }
    }
}
