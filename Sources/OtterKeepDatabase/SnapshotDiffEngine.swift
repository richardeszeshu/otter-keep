import Foundation
import SQLite3
import OtterKeepStorage

/// Type of change detected between two snapshots for a specific file path.
public enum DiffChangeType: String, Codable, Sendable, CaseIterable {
    /// File was newly created in the target snapshot.
    case added = "added"
    /// File was modified (content hash, modification time, or size changed).
    case modified = "modified"
    /// File was deleted in the target snapshot.
    case deleted = "deleted"
    /// File is identical in both snapshots.
    case unchanged = "unchanged"

    public var isDifference: Bool {
        self != .unchanged
    }
}

/// Represents a single file or directory difference between two snapshots.
public struct SnapshotDiffItem: Sendable, Identifiable, Equatable {
    public var id: String { relativePath }
    /// Relative path within the snapshot root.
    public let relativePath: String
    /// Classification of the change.
    public let changeType: DiffChangeType
    /// Catalog record in the base snapshot (nil if newly added).
    public let oldRecord: FileCatalogRecord?
    /// Catalog record in the target snapshot (nil if deleted).
    public let newRecord: FileCatalogRecord?
    /// Net size delta in bytes (positive for growth/addition, negative for shrinkage/deletion).
    public let sizeDelta: Int64

    public init(
        relativePath: String,
        changeType: DiffChangeType,
        oldRecord: FileCatalogRecord?,
        newRecord: FileCatalogRecord?,
        sizeDelta: Int64
    ) {
        self.relativePath = relativePath
        self.changeType = changeType
        self.oldRecord = oldRecord
        self.newRecord = newRecord
        self.sizeDelta = sizeDelta
    }

    /// Primary display file name (last path component).
    public var fileName: String {
        URL(fileURLWithPath: relativePath).lastPathComponent
    }

    /// Parent directory path (empty if at snapshot root).
    public var parentDirectory: String {
        let dir = URL(fileURLWithPath: relativePath).deletingLastPathComponent().path
        return (dir == "/" || dir == ".") ? "" : dir
    }

    /// Whether this item is a directory.
    public var isDirectory: Bool {
        newRecord?.isDirectory ?? oldRecord?.isDirectory ?? false
    }
}

/// Consolidated comparison report between two snapshots.
public struct SnapshotDiffReport: Sendable, Equatable {
    /// Base snapshot identifier (nil if comparing against an empty state / initial backup).
    public let baseSnapshotId: String?
    /// Target snapshot identifier.
    public let targetSnapshotId: String
    /// Base snapshot creation timestamp (nil if initial).
    public let baseTimestamp: Date?
    /// Target snapshot creation timestamp.
    public let targetTimestamp: Date
    /// List of all changed items (added, modified, deleted).
    public let items: [SnapshotDiffItem]

    /// Total count of newly added files and directories.
    public let addedCount: Int
    /// Total count of modified files.
    public let modifiedCount: Int
    /// Total count of deleted files and directories.
    public let deletedCount: Int

    /// Logical bytes added by new files.
    public let addedBytes: Int64
    /// Logical net bytes changed by modified files.
    public let modifiedBytes: Int64
    /// Logical bytes freed by deleted files.
    public let deletedBytes: Int64
    /// Overall net size change in bytes.
    public let netBytesDelta: Int64

    public init(
        baseSnapshotId: String?,
        targetSnapshotId: String,
        baseTimestamp: Date?,
        targetTimestamp: Date,
        items: [SnapshotDiffItem]
    ) {
        self.baseSnapshotId = baseSnapshotId
        self.targetSnapshotId = targetSnapshotId
        self.baseTimestamp = baseTimestamp
        self.targetTimestamp = targetTimestamp
        self.items = items

        var addCount = 0
        var modCount = 0
        var delCount = 0
        var addBytes: Int64 = 0
        var modBytes: Int64 = 0
        var delBytes: Int64 = 0
        var totalDelta: Int64 = 0

        for item in items {
            totalDelta += item.sizeDelta
            switch item.changeType {
            case .added:
                addCount += 1
                addBytes += max(0, item.sizeDelta)
            case .modified:
                modCount += 1
                modBytes += item.sizeDelta
            case .deleted:
                delCount += 1
                delBytes += abs(item.sizeDelta)
            case .unchanged:
                break
            }
        }

        self.addedCount = addCount
        self.modifiedCount = modCount
        self.deletedCount = delCount
        self.addedBytes = addBytes
        self.modifiedBytes = modBytes
        self.deletedBytes = delBytes
        self.netBytesDelta = totalDelta
    }

    /// Returns true if no changes exist between the two snapshots.
    public var isEmpty: Bool {
        items.isEmpty
    }

    /// Convenience accessors for categorized differences.
    public var addedFiles: [SnapshotDiffItem] {
        items.filter { $0.changeType == .added }
    }

    public var modifiedFiles: [SnapshotDiffItem] {
        items.filter { $0.changeType == .modified }
    }

    public var deletedFiles: [SnapshotDiffItem] {
        items.filter { $0.changeType == .deleted }
    }
}

/// Actor engine providing high-performance diff calculation between snapshot manifests.
public actor SnapshotDiffEngine {
    public static let shared = SnapshotDiffEngine()

    public init() {}

    /// Pure in-memory calculation of differences between two lists of file catalog records.
    public static func computeDiff(
        baseFiles: [FileCatalogRecord],
        targetFiles: [FileCatalogRecord],
        baseSnapshotId: String? = nil,
        targetSnapshotId: String = "target",
        baseTimestamp: Date? = nil,
        targetTimestamp: Date = Date()
    ) -> SnapshotDiffReport {
        var baseMap: [String: FileCatalogRecord] = [:]
        baseMap.reserveCapacity(baseFiles.count)
        for record in baseFiles {
            baseMap[record.relativePath] = record
        }

        var targetMap: [String: FileCatalogRecord] = [:]
        targetMap.reserveCapacity(targetFiles.count)
        for record in targetFiles {
            targetMap[record.relativePath] = record
        }

        var diffItems: [SnapshotDiffItem] = []

        // Evaluate target items (Added and Modified)
        for (path, targetRec) in targetMap {
            if let baseRec = baseMap[path] {
                // Check if changed
                let hasDifferentSize = baseRec.fileSize != targetRec.fileSize
                let hasDifferentHash = (targetRec.checksum != nil && baseRec.checksum != nil && targetRec.checksum != baseRec.checksum)
                let hasDifferentMtime = abs(targetRec.modificationTime.timeIntervalSince(baseRec.modificationTime)) > 0.001
                let hasDifferentSample = (targetRec.sampleHash != nil && baseRec.sampleHash != nil && targetRec.sampleHash != baseRec.sampleHash)

                let isModified = hasDifferentSize || hasDifferentHash || hasDifferentSample || (!targetRec.isDirectory && hasDifferentMtime)

                if isModified {
                    let delta = targetRec.fileSize - baseRec.fileSize
                    diffItems.append(SnapshotDiffItem(
                        relativePath: path,
                        changeType: .modified,
                        oldRecord: baseRec,
                        newRecord: targetRec,
                        sizeDelta: delta
                    ))
                }
            } else {
                // Added item
                diffItems.append(SnapshotDiffItem(
                    relativePath: path,
                    changeType: .added,
                    oldRecord: nil,
                    newRecord: targetRec,
                    sizeDelta: targetRec.fileSize
                ))
            }
        }

        // Evaluate deleted items (existed in base but not in target)
        for (path, baseRec) in baseMap {
            if targetMap[path] == nil {
                diffItems.append(SnapshotDiffItem(
                    relativePath: path,
                    changeType: .deleted,
                    oldRecord: baseRec,
                    newRecord: nil,
                    sizeDelta: -baseRec.fileSize
                ))
            }
        }

        diffItems.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }

        return SnapshotDiffReport(
            baseSnapshotId: baseSnapshotId,
            targetSnapshotId: targetSnapshotId,
            baseTimestamp: baseTimestamp,
            targetTimestamp: targetTimestamp,
            items: diffItems
        )
    }

    /// Computes the visual diff between two snapshots using the given database engine.
    /// If `baseSnapshotId` is nil, the engine automatically finds the snapshot immediately preceding `targetSnapshotId`.
    public func diff(
        database: DatabaseEngine,
        targetSnapshotId: String,
        baseSnapshotId: String? = nil
    ) async throws -> SnapshotDiffReport {
        // 1. Fetch target snapshot metadata
        let allSnapshots = try await database.listSnapshots()
        guard let targetSnapshot = allSnapshots.first(where: { $0.id == targetSnapshotId }) else {
            throw DatabaseError.stepFailed("listSnapshots", "Target snapshot '\(targetSnapshotId)' not found.")
        }

        // 2. Resolve base snapshot
        let resolvedBaseSnapshot: SnapshotRecord?
        if let explicitBase = baseSnapshotId {
            resolvedBaseSnapshot = allSnapshots.first(where: { $0.id == explicitBase })
        } else {
            // Find immediately preceding snapshot chronologically
            resolvedBaseSnapshot = allSnapshots
                .filter { $0.timestamp < targetSnapshot.timestamp }
                .sorted { $0.timestamp > $1.timestamp }
                .first
        }

        // 3. Fetch catalogs for both snapshots
        let targetCatalog = try await database.listFiles(forSnapshotId: targetSnapshotId)
        let baseCatalog: [FileCatalogRecord]
        if let base = resolvedBaseSnapshot {
            baseCatalog = try await database.listFiles(forSnapshotId: base.id)
        } else {
            baseCatalog = []
        }

        // 4. Delegate to pure diff engine
        return Self.computeDiff(
            baseFiles: baseCatalog,
            targetFiles: targetCatalog,
            baseSnapshotId: resolvedBaseSnapshot?.id,
            targetSnapshotId: targetSnapshot.id,
            baseTimestamp: resolvedBaseSnapshot?.timestamp,
            targetTimestamp: targetSnapshot.timestamp
        )
    }
}
