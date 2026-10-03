import Foundation
import Photos
import OtterKeepDatabase

/// Media folder directory organization strategy in the backup destination.
public enum PhotosExportStructure: String, Codable, Sendable, CaseIterable {
    /// Date-based year and month hierarchy (e.g. Originals/2026/09/IMG_0001.HEIC).
    case dateHierarchy = "dateHierarchy"
    /// User and smart album hierarchy (e.g. Originals/Albums/Vacation/IMG_0001.HEIC).
    case albumHierarchy = "albumHierarchy"
    /// Flat directory containing assets with unique UUID suffixes (e.g. Originals/IMG_0001_UUID.HEIC).
    case flat = "flat"

    /// Localized display title.
    public var localizedTitle: String {
        switch self {
        case .dateHierarchy:
            return L10n.t(.photosStructureDateHierarchy)
        case .albumHierarchy:
            return L10n.t(.photosStructureAlbumHierarchy)
        case .flat:
            return L10n.t(.photosStructureFlat)
        }
    }
}

/// Photos backup profile and rule configuration settings.
public struct PhotosBackupConfiguration: Identifiable, Codable, Sendable, Equatable {
    /// Unique profile identifier.
    public let id: UUID
    /// Profile display name.
    public var name: String
    /// Indicates whether Apple Photos backup is enabled.
    public var isEnabled: Bool
    /// Directory layout scheme on disk.
    public var exportStructure: PhotosExportStructure
    /// True to export both original master and edited versions.
    public var includeEditedVersions: Bool
    /// True to back up the .mov video component for Live Photos.
    public var includeLivePhotoVideos: Bool
    /// True to back up both RAW and JPEG components of paired shots.
    public var includeRawPairs: Bool
    /// True to generate standard XMP sidecar files for EXIF/IPTC/GPS metadata.
    public var generateXMPSidecars: Bool
    /// True to include assets from the Hidden album.
    public var includeHiddenAlbum: Bool
    /// Maximum concurrent asset download workers.
    public var maxConcurrentDownloads: Int
    /// Maximum in-flight local cache buffer in bytes before flushing.
    public var maxInFlightCacheBytes: Int64
    /// Target backup destination directory URL.
    public var destinationURL: URL
    /// Automatic background backup schedule.
    public var schedule: BackupSchedule
    /// Snapshot retention and pruning policy.
    public var pruningPolicy: PruningPolicy

    /// Initializes a new `PhotosBackupConfiguration`.
    public init(
        id: UUID = UUID(),
        name: String = "Apple Photos Backup",
        isEnabled: Bool = true,
        exportStructure: PhotosExportStructure = .dateHierarchy,
        includeEditedVersions: Bool = true,
        includeLivePhotoVideos: Bool = true,
        includeRawPairs: Bool = true,
        generateXMPSidecars: Bool = true,
        includeHiddenAlbum: Bool = false,
        maxConcurrentDownloads: Int = 4,
        maxInFlightCacheBytes: Int64 = 512 * 1024 * 1024,
        destinationURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Backups/PhotosBackup"),
        schedule: BackupSchedule = BackupSchedule(isEnabled: false, frequency: .daily, hour: 20, minute: 0),
        pruningPolicy: PruningPolicy = PruningPolicy(isAutoPruningEnabled: true, maxSnapshotsToKeep: 10, keepDailyDays: 30)
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.exportStructure = exportStructure
        self.includeEditedVersions = includeEditedVersions
        self.includeLivePhotoVideos = includeLivePhotoVideos
        self.includeRawPairs = includeRawPairs
        self.generateXMPSidecars = generateXMPSidecars
        self.includeHiddenAlbum = includeHiddenAlbum
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.maxInFlightCacheBytes = maxInFlightCacheBytes
        self.destinationURL = destinationURL
        self.schedule = schedule
        self.pruningPolicy = pruningPolicy
    }
}

/// Metadata representation of an individual discovered photo or video asset for delta analysis.
public struct ScannedPhotoAssetItem: Sendable, Identifiable, Equatable {
    public var id: String { localIdentifier }
    /// Apple Photos local persistent identifier.
    public let localIdentifier: String
    /// Original file name on disk or in the camera roll.
    public let originalFilename: String
    /// Asset capture timestamp.
    public let creationDate: Date?
    /// Last modification timestamp.
    public let modificationDate: Date
    /// Media type identifier ("image", "video", "audio").
    public let mediaType: String
    /// Pixel width of the image or video frame.
    public let pixelWidth: Int
    /// Pixel height of the image or video frame.
    public let pixelHeight: Int
    /// Playback duration in seconds (for videos/audio).
    public let duration: TimeInterval
    /// True if marked as a favorite.
    public let isFavorite: Bool
    /// True if located in the Hidden album.
    public let isHidden: Bool
    /// True if the asset is an Apple Live Photo.
    public let isLivePhoto: Bool
    /// True if adjustments or filters have been applied.
    public let hasAdjustments: Bool
    /// List of album names containing this asset.
    public let albums: [String]
    /// Estimated byte size of the asset.
    public let estimatedSizeBytes: Int64

    /// Initializes a new `ScannedPhotoAssetItem`.
    public init(
        localIdentifier: String,
        originalFilename: String,
        creationDate: Date?,
        modificationDate: Date,
        mediaType: String,
        pixelWidth: Int,
        pixelHeight: Int,
        duration: TimeInterval,
        isFavorite: Bool,
        isHidden: Bool,
        isLivePhoto: Bool,
        hasAdjustments: Bool,
        albums: [String],
        estimatedSizeBytes: Int64
    ) {
        self.localIdentifier = localIdentifier
        self.originalFilename = originalFilename
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.mediaType = mediaType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.isFavorite = isFavorite
        self.isHidden = isHidden
        self.isLivePhoto = isLivePhoto
        self.hasAdjustments = hasAdjustments
        self.albums = albums
        self.estimatedSizeBytes = estimatedSizeBytes
    }
}

/// Scheduled action for an individual media item in the Photos backup pipeline.
public enum PhotoAssetAction: Sendable {
    /// Item exists in the previous snapshot and is unchanged: perform zero-byte APFS reflink clone.
    case cloneReflink(previousRecord: PhotosAssetRecord, relativePath: String)
    /// New or modified item: fetch/download from Photos or iCloud and write to destination.
    case downloadAndExport(item: ScannedPhotoAssetItem, relativePath: String)
}

/// Live telemetry progress state for an ongoing Photos backup operation.
public struct PhotosBackupProgressState: Sendable, Equatable {
    public var isRunning: Bool = false
    public var phaseDescription: String = ""
    public var totalAssetsCount: Int = 0
    public var processedAssetsCount: Int = 0
    public var downloadedBytes: Int64 = 0
    public var clonedBytes: Int64 = 0
    public var currentAssetFilename: String = ""
    public var currentSpeedBytesPerSecond: Double = 0
    public var inFlightBufferBytes: Int64 = 0
    public var errorCount: Int = 0

    public var progressFraction: Double {
        guard totalAssetsCount > 0 else { return 0 }
        return min(1.0, max(0.0, Double(processedAssetsCount) / Double(totalAssetsCount)))
    }

    public init() {}
}

/// Final summary telemetry metrics reported after a Photos backup session concludes.
public struct PhotosSessionSummary: Sendable, Equatable {
    public let snapshotId: String
    public let timestamp: Date
    public let durationSeconds: Double
    public let totalAssetsScanned: Int
    public let newDownloadedCount: Int
    public let newDownloadedBytes: Int64
    public let reflinkClonedCount: Int
    public let reflinkClonedBytes: Int64
    public let errorCount: Int
    public let status: String

    public init(
        snapshotId: String,
        timestamp: Date,
        durationSeconds: Double,
        totalAssetsScanned: Int,
        newDownloadedCount: Int,
        newDownloadedBytes: Int64,
        reflinkClonedCount: Int,
        reflinkClonedBytes: Int64,
        errorCount: Int,
        status: String
    ) {
        self.snapshotId = snapshotId
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.totalAssetsScanned = totalAssetsScanned
        self.newDownloadedCount = newDownloadedCount
        self.newDownloadedBytes = newDownloadedBytes
        self.reflinkClonedCount = reflinkClonedCount
        self.reflinkClonedBytes = reflinkClonedBytes
        self.errorCount = errorCount
        self.status = status
    }
}
