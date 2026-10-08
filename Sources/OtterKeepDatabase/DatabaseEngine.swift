import Foundation
import SQLite3
import os
import OtterKeepStorage

/// Representation of a persistent backup snapshot manifest record stored in SQLite.
public struct SnapshotRecord: Sendable, Identifiable, Equatable {
    /// Unique snapshot identifier (e.g. "snapshot_2026-09-26_173000").
    public let id: String
    /// Snapshot creation timestamp.
    public let timestamp: Date
    /// Completion status ("completed", "completed_with_warnings", "completed_with_errors").
    public let status: String
    /// Total number of indexed files and directories in this snapshot.
    public let totalFiles: Int64
    /// Total logical byte size of all files in this snapshot.
    public let totalBytes: Int64
    /// Relative directory path on the backup destination disk (e.g. "2026-09-26_173000").
    public let snapshotPath: String
    /// Type of the backup ("incremental" or "full").
    public let backupType: String

    /// Initializes a new `SnapshotRecord`.
    /// - Parameters:
    ///   - id: Unique snapshot ID.
    ///   - timestamp: Creation timestamp.
    ///   - status: Completion status.
    ///   - totalFiles: Total indexed items count.
    ///   - totalBytes: Total byte size.
    ///   - snapshotPath: Relative snapshot directory name.
    ///   - backupType: Backup type ("incremental" or "full").
    public init(
        id: String,
        timestamp: Date,
        status: String,
        totalFiles: Int64,
        totalBytes: Int64,
        snapshotPath: String,
        backupType: String = "incremental"
    ) {
        self.id = id
        self.timestamp = timestamp
        self.status = status
        self.totalFiles = totalFiles
        self.totalBytes = totalBytes
        self.snapshotPath = snapshotPath
        self.backupType = backupType
    }
}

/// Representation of an indexed file or directory record in a specific snapshot catalog.
public struct FileCatalogRecord: Sendable, Identifiable, Equatable {
    /// Primary key in the database (0 for unpersisted records).
    public let id: Int64
    /// Associated snapshot identifier foreign key.
    public let snapshotId: String
    /// Relative path from the snapshot root folder (e.g. "Projects/App/main.swift").
    public let relativePath: String
    /// Logical file size in bytes (0 for directories).
    public let fileSize: Int64
    /// Last modification timestamp.
    public let modificationTime: Date
    /// Inode number on the filesystem.
    public let inode: UInt64
    /// Optional cryptographic SHA-256 hash (hex string).
    public let checksum: String?
    /// Optional fast sparse sample hash (head/mid/tail 64KB digest).
    public let sampleHash: String?
    /// True if this catalog entry is a directory.
    public let isDirectory: Bool
    /// True if this catalog entry is a symbolic link.
    public let isSymlink: Bool

    /// Initializes a new `FileCatalogRecord`.
    public init(
        id: Int64 = 0,
        snapshotId: String,
        relativePath: String,
        fileSize: Int64,
        modificationTime: Date,
        inode: UInt64,
        checksum: String? = nil,
        sampleHash: String? = nil,
        isDirectory: Bool,
        isSymlink: Bool
    ) {
        self.id = id
        self.snapshotId = snapshotId
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.modificationTime = modificationTime
        self.inode = inode
        self.checksum = checksum
        self.sampleHash = sampleHash
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
    }
}

/// Representation of a cross-snapshot global search hit in the catalog.
public struct GlobalSearchResult: Sendable, Identifiable, Equatable {
    public var id: String { "\(snapshotId)_\(relativePath)" }
    public let snapshotId: String
    public let snapshotTimestamp: Date
    public let snapshotPath: String
    public let relativePath: String
    public let fileSize: Int64
    public let modificationDate: Date
    public let sha256: String

    public var snapshotDate: Date { snapshotTimestamp }

    public var fileRecord: FileCatalogRecord {
        FileCatalogRecord(
            snapshotId: snapshotId,
            relativePath: relativePath,
            fileSize: fileSize,
            modificationTime: modificationDate,
            inode: 0,
            checksum: sha256.isEmpty ? nil : sha256,
            sampleHash: nil,
            isDirectory: false,
            isSymlink: false
        )
    }

    public init(
        snapshotId: String,
        snapshotTimestamp: Date,
        snapshotPath: String = "",
        relativePath: String,
        fileSize: Int64,
        modificationDate: Date,
        sha256: String
    ) {
        self.snapshotId = snapshotId
        self.snapshotTimestamp = snapshotTimestamp
        self.snapshotPath = snapshotPath
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.sha256 = sha256
    }
}

/// Representation of an indexed Photos item record in a Photos backup snapshot catalog.
public struct PhotosAssetRecord: Sendable, Identifiable, Equatable {
    /// Primary key in the database (0 for unpersisted records).
    public let id: Int64
    /// Associated snapshot identifier foreign key.
    public let snapshotId: String
    /// Unique Photos.app local identifier (e.g. "ED123456-7890-.../L0/001").
    public let localIdentifier: String
    /// Original file name (e.g. "IMG_1234.HEIC").
    public let originalFilename: String
    /// Relative path within the snapshot destination (e.g. "Originals/2026/09/IMG_1234.HEIC").
    public let relativePath: String
    /// Logical file size in bytes.
    public let fileSize: Int64
    /// Modification timestamp in Photos library.
    public let modificationTime: Date
    /// Optional SHA-256 checksum.
    public let sha256: String?
    /// Indicates whether this represents an adjusted/edited version.
    public let isEdited: Bool
    /// Indicates whether this asset is part of a Live Photo pair.
    public let isLivePhoto: Bool
    /// Media type ("image", "video", "audio").
    public let mediaType: String
    /// JSON serialized array of album names.
    public let albumsJson: String?

    /// Initializes a new `PhotosAssetRecord`.
    public init(
        id: Int64 = 0,
        snapshotId: String,
        localIdentifier: String,
        originalFilename: String,
        relativePath: String,
        fileSize: Int64,
        modificationTime: Date,
        sha256: String? = nil,
        isEdited: Bool = false,
        isLivePhoto: Bool = false,
        mediaType: String = "image",
        albumsJson: String? = nil
    ) {
        self.id = id
        self.snapshotId = snapshotId
        self.localIdentifier = localIdentifier
        self.originalFilename = originalFilename
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.modificationTime = modificationTime
        self.sha256 = sha256
        self.isEdited = isEdited
        self.isLivePhoto = isLivePhoto
        self.mediaType = mediaType
        self.albumsJson = albumsJson
    }
}

/// Representation of a background data integrity scrubbing audit record.
public struct ScrubAuditRecord: Sendable, Identifiable, Equatable {
    /// Primary key.
    public let id: Int64
    /// Timestamp when scrubbing completed.
    public let timestamp: Date
    /// Total snapshots inspected.
    public let checkedSnapshotsCount: Int
    /// Total files checksum-verified.
    public let checkedFilesCount: Int
    /// Count of corrupted files discovered (bit-rot).
    public let corruptedFilesCount: Int
    /// Overall audit status ("healthy", "corruption_detected", "failed").
    public let status: String
    /// JSON details of any corrupted items or audit log.
    public let detailsJson: String?

    public init(
        id: Int64 = 0,
        timestamp: Date,
        checkedSnapshotsCount: Int,
        checkedFilesCount: Int,
        corruptedFilesCount: Int,
        status: String,
        detailsJson: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.checkedSnapshotsCount = checkedSnapshotsCount
        self.checkedFilesCount = checkedFilesCount
        self.corruptedFilesCount = corruptedFilesCount
        self.status = status
        self.detailsJson = detailsJson
    }
}

/// Representation of a snapshot replication event / status stored in SQLite.
public struct ReplicationSnapshotRecord: Sendable, Identifiable, Equatable {
    public let id: Int64
    public let snapshotId: String
    public let destinationType: String
    public let destinationIdentifier: String
    public let status: String
    public let replicatedBytes: Int64
    public let totalBytes: Int64
    public let startedAt: Date
    public let completedAt: Date?
    public let errorMessage: String?

    public init(
        id: Int64 = 0,
        snapshotId: String,
        destinationType: String,
        destinationIdentifier: String,
        status: String = "pending",
        replicatedBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.snapshotId = snapshotId
        self.destinationType = destinationType
        self.destinationIdentifier = destinationIdentifier
        self.status = status
        self.replicatedBytes = replicatedBytes
        self.totalBytes = totalBytes
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
    }
}

/// Representation of an individual file's replication status.
public struct ReplicationFileRecord: Sendable, Identifiable, Equatable {
    public let id: Int64
    public let snapshotId: String
    public let destinationIdentifier: String
    public let relativePath: String
    public let remoteKey: String
    public let remoteETag: String?
    public let checksum: String?
    public let fileSize: Int64
    public let status: String

    public init(
        id: Int64 = 0,
        snapshotId: String,
        destinationIdentifier: String,
        relativePath: String,
        remoteKey: String,
        remoteETag: String? = nil,
        checksum: String? = nil,
        fileSize: Int64,
        status: String = "replicated"
    ) {
        self.id = id
        self.snapshotId = snapshotId
        self.destinationIdentifier = destinationIdentifier
        self.relativePath = relativePath
        self.remoteKey = remoteKey
        self.remoteETag = remoteETag
        self.checksum = checksum
        self.fileSize = fileSize
        self.status = status
    }
}


/// Structured errors encountered during SQLite catalog database operations.
public enum DatabaseError: Error, Sendable, LocalizedError {
    /// Failed to open or initialize the SQLite database connection.
    case openFailed(String)
    /// SQL statement execution failed.
    case executionFailed(String, String)
    /// SQL query compilation/preparation failed.
    case prepareFailed(String, String)
    /// SQL statement step iteration failed.
    case stepFailed(String, String)

    /// Human-readable localized error description.
    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "Database connection error: \(msg)"
        case .executionFailed(let query, let msg): return "SQL execution error '\(query)': \(msg)"
        case .prepareFailed(let query, let msg): return "SQL prepare error '\(query)': \(msg)"
        case .stepFailed(let query, let msg): return "SQL step error '\(query)': \(msg)"
        }
    }
}

/// SQLite transient destructor constant for memory safety when binding Swift strings.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thread-safe wrapper around a SQLite database handle.
final class SQLiteHandle: @unchecked Sendable {
    var pointer: OpaquePointer?
    init(pointer: OpaquePointer?) { self.pointer = pointer }
    deinit {
        if let ptr = pointer {
            sqlite3_close_v2(ptr)
        }
    }
}

/// High-performance, actor-isolated SQLite database engine managing snapshot metadata and file version history.
public actor DatabaseEngine {
    private let logger = Logger(subsystem: "com.otterkeep.desktop", category: "Database")
    private var handle: SQLiteHandle?
    private var db: OpaquePointer? { handle?.pointer }

    /// Initializes a new `DatabaseEngine` instance.
    public init() {}

    /// Safely closes the active SQLite database connection, checkpoints the WAL journal, and releases all locks and file descriptors.
    public func close() {
        guard let handle = self.handle, let db = handle.pointer else { return }
        _ = sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
        sqlite3_close_v2(db)
        handle.pointer = nil
        self.handle = nil
        logger.debug("Database connection closed and handles cleanly released.")
    }

    /// Whether the database currently has an active open connection.
    public var isOpen: Bool {
        db != nil
    }

    /// Opens the SQLite database at the specified path and initializes tables, pragmas, and indices.
    /// - Parameter path: Full filesystem path to the SQLite file.
    public func open(at path: String) throws {
        if let oldHandle = handle {
            if let ptr = oldHandle.pointer {
                _ = sqlite3_wal_checkpoint_v2(ptr, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
                sqlite3_close_v2(ptr)
                oldHandle.pointer = nil
            }
            handle = nil
        }

        var newPointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &newPointer, flags, nil) != SQLITE_OK {
            let msg = newPointer.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Failed to open SQLite"
            if let p = newPointer { sqlite3_close_v2(p) }
            throw DatabaseError.openFailed(msg)
        }
        self.handle = SQLiteHandle(pointer: newPointer)

        // Configure 10-second busy timeout to prevent immediate SQLITE_BUSY locking under multi-process contention
        sqlite3_busy_timeout(newPointer, 10000)
        try execute(query: "PRAGMA busy_timeout = 10000;")

        // Write-Ahead Logging (WAL) and performance tuning pragmas
        // If WAL mode fails (e.g. on external FAT/exFAT or network drives lacking POSIX shared memory),
        // gracefully fall back to TRUNCATE mode.
        do {
            try execute(query: "PRAGMA journal_mode = WAL;")
        } catch {
            logger.warning("WAL journal mode unavailable on filesystem, falling back to TRUNCATE: \(error.localizedDescription)")
            try? execute(query: "PRAGMA journal_mode = TRUNCATE;")
        }
        try execute(query: "PRAGMA synchronous = NORMAL;")
        try execute(query: "PRAGMA foreign_keys = ON;")

        try createSchema()
    }


    /// Executes a raw SQL query with error handling and query execution duration profiling.
    private func execute(query: String) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let startTime = CFAbsoluteTimeGetCurrent()
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, query, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg != nil ? String(cString: errMsg!) : "Unknown SQLite execution error"
            sqlite3_free(errMsg)
            throw DatabaseError.executionFailed(query, msg)
        }
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        if durationMs > 50.0 {
            logger.warning("Slow SQL query execution (\(String(format: "%.1f", durationMs)) ms): \(query)")
        }
    }

    /// Initializes database schema tables and query optimization indexes.
    private func createSchema() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS snapshots (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            status TEXT NOT NULL,
            total_files INTEGER NOT NULL,
            total_bytes INTEGER NOT NULL,
            snapshot_path TEXT NOT NULL,
            backup_type TEXT NOT NULL DEFAULT 'incremental'
        );

        CREATE TABLE IF NOT EXISTS file_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            snapshot_id TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            mtime REAL NOT NULL,
            inode INTEGER NOT NULL,
            checksum TEXT,
            is_directory INTEGER NOT NULL,
            is_symlink INTEGER NOT NULL,
            sample_hash TEXT,
            FOREIGN KEY (snapshot_id) REFERENCES snapshots(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_file_records_snapshot ON file_records(snapshot_id);
        CREATE INDEX IF NOT EXISTS idx_file_records_path ON file_records(relative_path);
        CREATE INDEX IF NOT EXISTS idx_snapshots_timestamp ON snapshots(timestamp DESC);

        CREATE TABLE IF NOT EXISTS photos_asset_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            snapshot_id TEXT NOT NULL,
            local_identifier TEXT NOT NULL,
            original_filename TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            mtime REAL NOT NULL,
            sha256 TEXT,
            is_edited INTEGER NOT NULL DEFAULT 0,
            is_live_photo INTEGER NOT NULL DEFAULT 0,
            media_type TEXT NOT NULL DEFAULT 'image',
            albums_json TEXT,
            FOREIGN KEY (snapshot_id) REFERENCES snapshots(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_photos_records_snapshot ON photos_asset_records(snapshot_id);
        CREATE INDEX IF NOT EXISTS idx_photos_records_local_id ON photos_asset_records(local_identifier);

        CREATE TABLE IF NOT EXISTS scrub_audit_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            checked_snapshots_count INTEGER NOT NULL,
            checked_files_count INTEGER NOT NULL,
            corrupted_files_count INTEGER NOT NULL,
            status TEXT NOT NULL,
            details_json TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_scrub_audit_timestamp ON scrub_audit_logs(timestamp DESC);

        CREATE TABLE IF NOT EXISTS replication_snapshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            snapshot_id TEXT NOT NULL,
            destination_type TEXT NOT NULL,
            destination_identifier TEXT NOT NULL,
            status TEXT NOT NULL,
            replicated_bytes INTEGER NOT NULL DEFAULT 0,
            total_bytes INTEGER NOT NULL DEFAULT 0,
            started_at REAL NOT NULL,
            completed_at REAL,
            error_message TEXT,
            FOREIGN KEY (snapshot_id) REFERENCES snapshots(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_rep_snapshots_id ON replication_snapshots(snapshot_id);
        CREATE INDEX IF NOT EXISTS idx_rep_snapshots_dest ON replication_snapshots(destination_identifier);

        CREATE TABLE IF NOT EXISTS replication_files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            snapshot_id TEXT NOT NULL,
            destination_identifier TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            remote_key TEXT NOT NULL,
            remote_etag TEXT,
            checksum TEXT,
            file_size INTEGER NOT NULL,
            status TEXT NOT NULL,
            FOREIGN KEY (snapshot_id) REFERENCES snapshots(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_rep_files_lookup ON replication_files(destination_identifier, relative_path);
        CREATE INDEX IF NOT EXISTS idx_rep_files_snapshot ON replication_files(snapshot_id);
        """
        try execute(query: sql)

        // Schema migrations for existing databases
        try? execute(query: "ALTER TABLE snapshots ADD COLUMN backup_type TEXT NOT NULL DEFAULT 'incremental';")
        try? execute(query: "ALTER TABLE file_records ADD COLUMN sample_hash TEXT;")
    }


    // MARK: - Safe Column Helper Methods

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: ptr)
    }

    private func columnOptionalText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: ptr)
    }

    // MARK: - Snapshot Operations

    /// Inserts or replaces a snapshot record in the database.
    /// - Parameter record: The snapshot record to persist.
    public func insertSnapshot(_ record: SnapshotRecord) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        INSERT OR REPLACE INTO snapshots (id, timestamp, status, total_files, total_bytes, snapshot_path, backup_type)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, record.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, record.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, record.status, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 4, record.totalFiles)
        sqlite3_bind_int64(stmt, 5, record.totalBytes)
        sqlite3_bind_text(stmt, 6, record.snapshotPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, record.backupType, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(query, String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Lists all snapshots ordered by creation timestamp in descending order.
    /// - Returns: Array of `SnapshotRecord` objects.
    public func listSnapshots() throws -> [SnapshotRecord] {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = "SELECT id, timestamp, status, total_files, total_bytes, snapshot_path, backup_type FROM snapshots ORDER BY timestamp DESC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var results: [SnapshotRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = columnText(stmt, 0)
            let ts = sqlite3_column_double(stmt, 1)
            let status = columnText(stmt, 2)
            let totalFiles = sqlite3_column_int64(stmt, 3)
            let totalBytes = sqlite3_column_int64(stmt, 4)
            let path = columnText(stmt, 5)
            var bType = columnText(stmt, 6)
            if bType.isEmpty { bType = "incremental" }

            results.append(SnapshotRecord(
                id: id,
                timestamp: Date(timeIntervalSince1970: ts),
                status: status,
                totalFiles: totalFiles,
                totalBytes: totalBytes,
                snapshotPath: path,
                backupType: bType
            ))
        }
        return results
    }

    /// Deletes a snapshot record by ID, automatically cascading deletion to associated file records.
    /// - Parameter id: Snapshot ID.
    public func deleteSnapshot(id: String) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = "DELETE FROM snapshots WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(query, String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - File Catalog Batch Insertion

    /// Inserts an array of file catalog records inside an atomic SQLite transaction.
    /// - Parameter records: Array of `FileCatalogRecord` entries.
    public func insertFileRecordsBatch(_ records: [FileCatalogRecord]) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        guard !records.isEmpty else { return }

        try execute(query: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            let query = """
            INSERT INTO file_records (snapshot_id, relative_path, file_size, mtime, inode, checksum, is_directory, is_symlink, sample_hash)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            for rec in records {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)

                sqlite3_bind_text(stmt, 1, rec.snapshotId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, rec.relativePath, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 3, rec.fileSize)
                sqlite3_bind_double(stmt, 4, rec.modificationTime.timeIntervalSince1970)
                sqlite3_bind_int64(stmt, 5, Int64(bitPattern: rec.inode))
                if let checksum = rec.checksum {
                    sqlite3_bind_text(stmt, 6, checksum, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 6)
                }
                sqlite3_bind_int(stmt, 7, rec.isDirectory ? 1 : 0)
                sqlite3_bind_int(stmt, 8, rec.isSymlink ? 1 : 0)
                if let sHash = rec.sampleHash {
                    sqlite3_bind_text(stmt, 9, sHash, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 9)
                }

                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw DatabaseError.stepFailed(query, String(cString: sqlite3_errmsg(db)))
                }
            }
            try execute(query: "COMMIT;")
        } catch {
            try? execute(query: "ROLLBACK;")
            throw error
        }
    }

    /// Lists all file catalog records associated with a snapshot ID.
    /// - Parameter snapshotId: The snapshot identifier.
    /// - Returns: Array of `FileCatalogRecord` entries sorted by relative path.
    public func listFiles(forSnapshotId snapshotId: String) throws -> [FileCatalogRecord] {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        SELECT id, snapshot_id, relative_path, file_size, mtime, inode, checksum, is_directory, is_symlink, sample_hash
        FROM file_records WHERE snapshot_id = ? ORDER BY relative_path ASC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, snapshotId, -1, SQLITE_TRANSIENT)

        var records: [FileCatalogRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let sId = columnText(stmt, 1)
            let path = columnText(stmt, 2)
            let size = sqlite3_column_int64(stmt, 3)
            let mtime = sqlite3_column_double(stmt, 4)
            let inode = UInt64(bitPattern: sqlite3_column_int64(stmt, 5))
            let checksumText = columnOptionalText(stmt, 6)
            let isDir = sqlite3_column_int(stmt, 7) == 1
            let isLnk = sqlite3_column_int(stmt, 8) == 1
            let sampleHashText = columnOptionalText(stmt, 9)

            records.append(FileCatalogRecord(
                id: id,
                snapshotId: sId,
                relativePath: path,
                fileSize: size,
                modificationTime: Date(timeIntervalSince1970: mtime),
                inode: inode,
                checksum: checksumText,
                sampleHash: sampleHashText,
                isDirectory: isDir,
                isSymlink: isLnk
            ))
        }
        return records
    }

    /// Finds all historical catalog records for a specific relative file path.
    /// - Parameter relativePath: The relative path to query.
    /// - Returns: Array of `FileCatalogRecord` entries in reverse chronological order.
    public func findFileVersions(relativePath: String) throws -> [FileCatalogRecord] {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        SELECT fr.id, fr.snapshot_id, fr.relative_path, fr.file_size, fr.mtime, fr.inode, fr.checksum, fr.is_directory, fr.is_symlink, fr.sample_hash
        FROM file_records fr
        JOIN snapshots s ON s.id = fr.snapshot_id
        WHERE fr.relative_path = ?
        ORDER BY s.timestamp DESC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, relativePath, -1, SQLITE_TRANSIENT)

        var records: [FileCatalogRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let sId = columnText(stmt, 1)
            let path = columnText(stmt, 2)
            let size = sqlite3_column_int64(stmt, 3)
            let mtime = sqlite3_column_double(stmt, 4)
            let inode = UInt64(bitPattern: sqlite3_column_int64(stmt, 5))
            let checksumText = columnOptionalText(stmt, 6)
            let isDir = sqlite3_column_int(stmt, 7) == 1
            let isLnk = sqlite3_column_int(stmt, 8) == 1
            let sampleHashText = columnOptionalText(stmt, 9)

            records.append(FileCatalogRecord(
                id: id,
                snapshotId: sId,
                relativePath: path,
                fileSize: size,
                modificationTime: Date(timeIntervalSince1970: mtime),
                inode: inode,
                checksum: checksumText,
                sampleHash: sampleHashText,
                isDirectory: isDir,
                isSymlink: isLnk
            ))
        }
        return records
    }

    /// Queries all historical versions of a relative path along with their corresponding snapshot manifests.
    /// - Parameter path: The relative file path.
    /// - Returns: Array of snapshot and file record tuples sorted from newest to oldest.
    public func listVersions(ofRelativePath path: String) throws -> [(snapshot: SnapshotRecord, file: FileCatalogRecord)] {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        SELECT
            s.id, s.timestamp, s.status, s.total_files, s.total_bytes, s.snapshot_path, s.backup_type,
            fr.id, fr.snapshot_id, fr.relative_path, fr.file_size, fr.mtime, fr.inode, fr.checksum, fr.is_directory, fr.is_symlink, fr.sample_hash
        FROM file_records fr
        JOIN snapshots s ON s.id = fr.snapshot_id
        WHERE fr.relative_path = ?
        ORDER BY s.timestamp DESC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)

        var results: [(snapshot: SnapshotRecord, file: FileCatalogRecord)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let snapId = columnText(stmt, 0)
            let snapTimestamp = sqlite3_column_double(stmt, 1)
            let snapStatus = columnText(stmt, 2)
            let snapTotalFiles = sqlite3_column_int64(stmt, 3)
            let snapTotalBytes = sqlite3_column_int64(stmt, 4)
            let snapPath = columnText(stmt, 5)
            var snapBackupType = columnText(stmt, 6)
            if snapBackupType.isEmpty { snapBackupType = "incremental" }

            let snapshot = SnapshotRecord(
                id: snapId,
                timestamp: Date(timeIntervalSince1970: snapTimestamp),
                status: snapStatus,
                totalFiles: snapTotalFiles,
                totalBytes: snapTotalBytes,
                snapshotPath: snapPath,
                backupType: snapBackupType
            )

            let fileId = sqlite3_column_int64(stmt, 7)
            let fileSnapId = columnText(stmt, 8)
            let filePath = columnText(stmt, 9)
            let fileSize = sqlite3_column_int64(stmt, 10)
            let fileMtime = sqlite3_column_double(stmt, 11)
            let fileInode = UInt64(bitPattern: sqlite3_column_int64(stmt, 12))
            let checksumText = columnOptionalText(stmt, 13)
            let isDir = sqlite3_column_int(stmt, 14) == 1
            let isLnk = sqlite3_column_int(stmt, 15) == 1
            let sampleHashText = columnOptionalText(stmt, 16)

            let fileRecord = FileCatalogRecord(
                id: fileId,
                snapshotId: fileSnapId,
                relativePath: filePath,
                fileSize: fileSize,
                modificationTime: Date(timeIntervalSince1970: fileMtime),
                inode: fileInode,
                checksum: checksumText,
                sampleHash: sampleHashText,
                isDirectory: isDir,
                isSymlink: isLnk
            )

            results.append((snapshot: snapshot, file: fileRecord))
        }
        return results
    }

    // MARK: - Data Scrubbing Audit Operations

    /// Inserts a new scrubbing audit log record into SQLite.
    /// - Parameter record: The scrub audit result to persist.
    public func insertScrubAudit(_ record: ScrubAuditRecord) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        INSERT INTO scrub_audit_logs (timestamp, checked_snapshots_count, checked_files_count, corrupted_files_count, status, details_json)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, record.timestamp.timeIntervalSince1970)
        sqlite3_bind_int64(stmt, 2, Int64(record.checkedSnapshotsCount))
        sqlite3_bind_int64(stmt, 3, Int64(record.checkedFilesCount))
        sqlite3_bind_int64(stmt, 4, Int64(record.corruptedFilesCount))
        sqlite3_bind_text(stmt, 5, record.status, -1, SQLITE_TRANSIENT)
        if let json = record.detailsJson {
            sqlite3_bind_text(stmt, 6, json, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(query, String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Lists past scrubbing audit records in reverse chronological order.
    /// - Parameter limit: Maximum entries to return.
    /// - Returns: Array of `ScrubAuditRecord` items.
    public func listScrubAudits(limit: Int = 50) throws -> [ScrubAuditRecord] {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        SELECT id, timestamp, checked_snapshots_count, checked_files_count, corrupted_files_count, status, details_json
        FROM scrub_audit_logs ORDER BY timestamp DESC LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(limit))

        var results: [ScrubAuditRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let ts = sqlite3_column_double(stmt, 1)
            let checkedSnaps = Int(sqlite3_column_int64(stmt, 2))
            let checkedFiles = Int(sqlite3_column_int64(stmt, 3))
            let corruptedFiles = Int(sqlite3_column_int64(stmt, 4))
            let status = columnText(stmt, 5)
            let details = columnOptionalText(stmt, 6)

            results.append(ScrubAuditRecord(
                id: id,
                timestamp: Date(timeIntervalSince1970: ts),
                checkedSnapshotsCount: checkedSnaps,
                checkedFilesCount: checkedFiles,
                corruptedFilesCount: corruptedFiles,
                status: status,
                detailsJson: details
            ))
        }
        return results
    }

    /// Searches distinct relative paths across all snapshots matching an optional substring query.
    /// - Parameters:
    ///   - query: Substring filter pattern (empty string matches all).
    ///   - limit: Maximum number of paths to return.
    /// - Returns: Array of distinct relative file paths.
    public func searchDistinctRelativePaths(matching query: String = "", limit: Int = 100) throws -> [String] {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let sql: String
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            sql = "SELECT DISTINCT relative_path FROM file_records ORDER BY relative_path ASC LIMIT ?;"
        } else {
            sql = "SELECT DISTINCT relative_path FROM file_records WHERE relative_path LIKE ? ORDER BY relative_path ASC LIMIT ?;"
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sql, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        if trimmed.isEmpty {
            sqlite3_bind_int(stmt, 1, Int32(limit))
        } else {
            let pattern = "%\(trimmed)%"
            sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(limit))
        }

        var paths: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let path = columnText(stmt, 0)
            paths.append(path)
        }
        return paths
    }

    /// Performs a high-performance cross-snapshot search across all indexed catalog records.
    /// - Parameters:
    ///   - query: Substring or filename pattern to search for.
    ///   - limit: Maximum number of search results to return (default: 100).
    /// - Returns: Array of `GlobalSearchResult` records.
    public func searchFilesAcrossSnapshots(
        query: String,
        limit: Int = 100
    ) throws -> [GlobalSearchResult] {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sql: String
        if trimmed.isEmpty {
            sql = """
            SELECT fr.snapshot_id, s.timestamp, s.snapshot_path, fr.relative_path, fr.file_size, fr.mtime, COALESCE(fr.checksum, '')
            FROM file_records fr
            JOIN snapshots s ON s.id = fr.snapshot_id
            WHERE fr.is_directory = 0
            ORDER BY s.timestamp DESC, fr.relative_path ASC
            LIMIT ?;
            """
        } else {
            sql = """
            SELECT fr.snapshot_id, s.timestamp, s.snapshot_path, fr.relative_path, fr.file_size, fr.mtime, COALESCE(fr.checksum, '')
            FROM file_records fr
            JOIN snapshots s ON s.id = fr.snapshot_id
            WHERE fr.is_directory = 0 AND fr.relative_path LIKE ?
            ORDER BY s.timestamp DESC, fr.relative_path ASC
            LIMIT ?;
            """
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(sql, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        if trimmed.isEmpty {
            sqlite3_bind_int(stmt, 1, Int32(limit))
        } else {
            let pattern = "%\(trimmed)%"
            sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(limit))
        }

        var results: [GlobalSearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let sId = columnText(stmt, 0)
            let ts = sqlite3_column_double(stmt, 1)
            let snapPath = columnText(stmt, 2)
            let path = columnText(stmt, 3)
            let size = sqlite3_column_int64(stmt, 4)
            let mtime = sqlite3_column_double(stmt, 5)
            let sha = columnText(stmt, 6)

            results.append(GlobalSearchResult(
                snapshotId: sId,
                snapshotTimestamp: Date(timeIntervalSince1970: ts),
                snapshotPath: snapPath,
                relativePath: path,
                fileSize: size,
                modificationDate: Date(timeIntervalSince1970: mtime),
                sha256: sha
            ))
        }
        return results
    }

    // MARK: - Photos Asset Batch Insertion & Queries

    /// Inserts an array of Photos asset records inside an atomic SQLite transaction.
    /// - Parameter records: Array of `PhotosAssetRecord` entries.
    public func insertPhotosAssetRecordsBatch(_ records: [PhotosAssetRecord]) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        guard !records.isEmpty else { return }

        try execute(query: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            let query = """
            INSERT INTO photos_asset_records (
                snapshot_id, local_identifier, original_filename, relative_path,
                file_size, mtime, sha256, is_edited, is_live_photo, media_type, albums_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            for rec in records {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)

                sqlite3_bind_text(stmt, 1, rec.snapshotId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, rec.localIdentifier, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, rec.originalFilename, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, rec.relativePath, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 5, rec.fileSize)
                sqlite3_bind_double(stmt, 6, rec.modificationTime.timeIntervalSince1970)
                if let sha = rec.sha256 {
                    sqlite3_bind_text(stmt, 7, sha, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 7)
                }
                sqlite3_bind_int(stmt, 8, rec.isEdited ? 1 : 0)
                sqlite3_bind_int(stmt, 9, rec.isLivePhoto ? 1 : 0)
                sqlite3_bind_text(stmt, 10, rec.mediaType, -1, SQLITE_TRANSIENT)
                if let albums = rec.albumsJson {
                    sqlite3_bind_text(stmt, 11, albums, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 11)
                }

                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw DatabaseError.stepFailed(query, String(cString: sqlite3_errmsg(db)))
                }
            }
            try execute(query: "COMMIT;")
        } catch {
            try? execute(query: "ROLLBACK;")
            throw error
        }
    }

    /// Fetches all Photos asset records for a specific snapshot identifier.
    /// - Parameter snapshotId: The snapshot ID.
    /// - Returns: Array of `PhotosAssetRecord`.
    public func fetchPhotosAssetRecords(for snapshotId: String) throws -> [PhotosAssetRecord] {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        SELECT id, snapshot_id, local_identifier, original_filename, relative_path,
               file_size, mtime, sha256, is_edited, is_live_photo, media_type, albums_json
        FROM photos_asset_records
        WHERE snapshot_id = ?
        ORDER BY relative_path ASC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, snapshotId, -1, SQLITE_TRANSIENT)

        var records: [PhotosAssetRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rec = PhotosAssetRecord(
                id: sqlite3_column_int64(stmt, 0),
                snapshotId: columnText(stmt, 1),
                localIdentifier: columnText(stmt, 2),
                originalFilename: columnText(stmt, 3),
                relativePath: columnText(stmt, 4),
                fileSize: sqlite3_column_int64(stmt, 5),
                modificationTime: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6)),
                sha256: columnOptionalText(stmt, 7),
                isEdited: sqlite3_column_int(stmt, 8) == 1,
                isLivePhoto: sqlite3_column_int(stmt, 9) == 1,
                mediaType: columnText(stmt, 10),
                albumsJson: columnOptionalText(stmt, 11)
            )
            records.append(rec)
        }
        return records
    }

    /// Lists all snapshots (alias for listSnapshots).
    public func fetchSnapshots() throws -> [SnapshotRecord] {
        try listSnapshots()
    }

    /// Fetches the most recent snapshot record if available.
    public func fetchLatestSnapshot() throws -> SnapshotRecord? {
        try listSnapshots().first
    }

    /// Fetches the most recent Photos asset records across the latest snapshot.
    /// - Returns: Dictionary mapping localIdentifier to `PhotosAssetRecord`.
    public func fetchLatestPhotosAssetIndex() throws -> [String: PhotosAssetRecord] {
        guard db != nil else { throw DatabaseError.openFailed("Database is not open") }
        guard let latestSnap = try fetchLatestSnapshot() else { return [:] }

        let records = try fetchPhotosAssetRecords(for: latestSnap.id)
        var dict: [String: PhotosAssetRecord] = [:]
        for r in records {
            dict[r.localIdentifier] = r
        }
        return dict
    }

    // MARK: - 3-2-1 Replication Operations

    /// Records or updates a snapshot replication status record.
    public func recordReplicationSnapshot(_ record: ReplicationSnapshotRecord) throws -> Int64 {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        INSERT INTO replication_snapshots (snapshot_id, destination_type, destination_identifier, status, replicated_bytes, total_bytes, started_at, completed_at, error_message)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, record.snapshotId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, record.destinationType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, record.destinationIdentifier, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, record.status, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 5, record.replicatedBytes)
        sqlite3_bind_int64(stmt, 6, record.totalBytes)
        sqlite3_bind_double(stmt, 7, record.startedAt.timeIntervalSince1970)
        if let completedAt = record.completedAt {
            sqlite3_bind_double(stmt, 8, completedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 8)
        }
        if let errMsg = record.errorMessage {
            sqlite3_bind_text(stmt, 9, errMsg, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 9)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        return sqlite3_last_insert_rowid(db)
    }

    /// Updates status and metrics for an existing snapshot replication run.
    public func updateReplicationSnapshot(
        snapshotId: String,
        destinationIdentifier: String,
        status: String,
        replicatedBytes: Int64,
        completedAt: Date? = nil,
        errorMessage: String? = nil
    ) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        UPDATE replication_snapshots
        SET status = ?, replicated_bytes = ?, completed_at = ?, error_message = ?
        WHERE snapshot_id = ? AND destination_identifier = ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, status, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, replicatedBytes)
        if let completedAt = completedAt {
            sqlite3_bind_double(stmt, 3, completedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        if let errMsg = errorMessage {
            sqlite3_bind_text(stmt, 4, errMsg, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_text(stmt, 5, snapshotId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, destinationIdentifier, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(query, String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Fetches all replication records for a specific snapshot.
    public func fetchReplicationSnapshots(for snapshotId: String) throws -> [ReplicationSnapshotRecord] {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        SELECT id, snapshot_id, destination_type, destination_identifier, status, replicated_bytes, total_bytes, started_at, completed_at, error_message
        FROM replication_snapshots
        WHERE snapshot_id = ?
        ORDER BY started_at DESC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, snapshotId, -1, SQLITE_TRANSIENT)

        var records: [ReplicationSnapshotRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let completedAtTime = sqlite3_column_type(stmt, 8) != SQLITE_NULL ? sqlite3_column_double(stmt, 8) : nil
            let rec = ReplicationSnapshotRecord(
                id: sqlite3_column_int64(stmt, 0),
                snapshotId: columnText(stmt, 1),
                destinationType: columnText(stmt, 2),
                destinationIdentifier: columnText(stmt, 3),
                status: columnText(stmt, 4),
                replicatedBytes: sqlite3_column_int64(stmt, 5),
                totalBytes: sqlite3_column_int64(stmt, 6),
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)),
                completedAt: completedAtTime != nil ? Date(timeIntervalSince1970: completedAtTime!) : nil,
                errorMessage: columnOptionalText(stmt, 9)
            )
            records.append(rec)
        }
        return records
    }

    /// Records an individual replicated file record.
    public func recordReplicationFile(_ record: ReplicationFileRecord) throws {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query = """
        INSERT INTO replication_files (snapshot_id, destination_identifier, relative_path, remote_key, remote_etag, checksum, file_size, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, record.snapshotId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, record.destinationIdentifier, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, record.relativePath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, record.remoteKey, -1, SQLITE_TRANSIENT)
        if let etag = record.remoteETag {
            sqlite3_bind_text(stmt, 5, etag, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        if let chk = record.checksum {
            sqlite3_bind_text(stmt, 6, chk, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        sqlite3_bind_int64(stmt, 7, record.fileSize)
        sqlite3_bind_text(stmt, 8, record.status, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(query, String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Checks whether a file with matching relative path, checksum, and size is already synced to a remote destination.
    public func isReplicationFileSynced(
        destinationIdentifier: String,
        relativePath: String,
        checksum: String?,
        fileSize: Int64
    ) throws -> (isSynced: Bool, remoteKey: String?, remoteETag: String?) {
        guard let db = db else { throw DatabaseError.openFailed("Database is not open") }
        let query: String
        if let chk = checksum, !chk.isEmpty {
            query = """
            SELECT remote_key, remote_etag
            FROM replication_files
            WHERE destination_identifier = ? AND relative_path = ? AND checksum = ? AND file_size = ? AND status = 'replicated'
            ORDER BY id DESC LIMIT 1;
            """
        } else {
            query = """
            SELECT remote_key, remote_etag
            FROM replication_files
            WHERE destination_identifier = ? AND relative_path = ? AND file_size = ? AND status = 'replicated'
            ORDER BY id DESC LIMIT 1;
            """
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(query, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, destinationIdentifier, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, relativePath, -1, SQLITE_TRANSIENT)
        if let chk = checksum, !chk.isEmpty {
            sqlite3_bind_text(stmt, 3, chk, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 4, fileSize)
        } else {
            sqlite3_bind_int64(stmt, 3, fileSize)
        }

        if sqlite3_step(stmt) == SQLITE_ROW {
            let key = columnText(stmt, 0)
            let etag = columnOptionalText(stmt, 1)
            return (true, key, etag)
        }
        return (false, nil, nil)
    }
}

