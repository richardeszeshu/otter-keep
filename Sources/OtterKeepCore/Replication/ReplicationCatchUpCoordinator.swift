import Foundation
import os
import OtterKeepStorage
import OtterKeepDatabase

/// Background catch-up manager synchronizing missing snapshots to offline secondary destinations once connectivity is restored.
public actor ReplicationCatchUpCoordinator {
    private let database: DatabaseEngine
    private let storage: FileSystemProvider
    private let logger = Logger(subsystem: "com.otterkeep", category: "CatchUpCoordinator")

    public init(database: DatabaseEngine, storage: FileSystemProvider = DefaultFileSystemProvider()) {
        self.database = database
        self.storage = storage
    }

    /// Enqueues pending replication tasks for destinations that were offline or unreachable during the backup run.
    public func enqueuePendingReplication(
        profileId: UUID,
        snapshotId: String,
        destination: RemoteDestination,
        errorMessage: String? = nil
    ) async throws {
        let destTypeStr: String
        switch destination.type {
        case .s3: destTypeStr = "s3"
        case .backblazeB2: destTypeStr = "b2"
        case .smb: destTypeStr = "smb"
        case .webdav: destTypeStr = "webdav"
        case .sftp: destTypeStr = "sftp"
        }

        let record = PendingReplicationRecord(
            profileId: profileId,
            snapshotId: snapshotId,
            destinationId: destination.id,
            destinationType: destTypeStr,
            status: "pending",
            errorMessage: errorMessage
        )
        try await database.insertPendingReplication(record)
        logger.info("Enqueued pending catch-up replication for destination '\(destination.name)' [Snapshot: \(snapshotId)]")
    }

    /// Inspects and processes pending replications for a profile whose destinations may have reconnected.
    /// - Parameters:
    ///   - profile: The active backup profile.
    /// - Returns: Count of successfully caught-up snapshot replications.
    @discardableResult
    public func processPendingReplications(profile: BackupProfile) async -> Int {
        guard profile.copyJobConfig.isEnabled else { return 0 }

        let pendingJobs: [PendingReplicationRecord]
        do {
            pendingJobs = try await database.listPendingReplications(status: "pending", profileId: profile.id)
        } catch {
            logger.error("Failed to query pending replications for profile '\(profile.name)': \(error.localizedDescription)")
            return 0
        }

        guard !pendingJobs.isEmpty else { return 0 }
        logger.info("Found \(pendingJobs.count) pending replication tasks for profile '\(profile.name)'. Checking destination availability...")

        var successCount = 0
        let coordinator = BackupCopyJobCoordinator(storage: storage, database: database)

        for job in pendingJobs {
            guard let dest = profile.copyJobConfig.destinations.first(where: { $0.id == job.destinationId && $0.isEnabled }) else {
                // Destination no longer exists or is disabled, clean up queue
                try? await database.deletePendingReplication(id: job.id)
                continue
            }

            // Verify if snapshot still exists locally
            let localSnapshots = (try? await database.listSnapshots()) ?? []
            guard localSnapshots.contains(where: { $0.id == job.snapshotId }) else {
                logger.warning("Snapshot '\(job.snapshotId)' no longer exists locally; dropping pending catch-up task.")
                try? await database.deletePendingReplication(id: job.id)
                continue
            }

            do {
                try await database.updatePendingReplicationStatus(id: job.id, status: "in_progress")
                logger.info("Executing background catch-up replication for snapshot '\(job.snapshotId)' to '\(dest.name)'...")

                let summary = try await coordinator.executeReplication(profile: profile, targetSnapshotId: job.snapshotId)
                if summary.successfulDestinations > 0 {
                    try await database.updatePendingReplicationStatus(id: job.id, status: "completed")
                    successCount += 1
                    logger.info("Background catch-up replication succeeded for snapshot '\(job.snapshotId)' to '\(dest.name)'.")
                } else {
                    try await database.updatePendingReplicationStatus(
                        id: job.id,
                        status: "pending",
                        errorMessage: "Replication incomplete",
                        incrementRetry: true
                    )
                }
            } catch {
                logger.warning("Catch-up replication attempt failed for snapshot '\(job.snapshotId)' to '\(dest.name)': \(error.localizedDescription)")
                try? await database.updatePendingReplicationStatus(
                    id: job.id,
                    status: "pending",
                    errorMessage: error.localizedDescription,
                    incrementRetry: true
                )
            }
        }

        return successCount
    }
}
