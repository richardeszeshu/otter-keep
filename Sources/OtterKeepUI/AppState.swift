import SwiftUI
import AppKit
import Observation
import Photos
import UniformTypeIdentifiers
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

/// Primary navigation sections within the modern sidebar.
public enum NavigationSection: Hashable, Sendable {
    /// A specific backup profile selected in the sidebar.
    case profile(UUID)
    /// Unified Apple Photos workspace.
    case photos
    /// Diagnostic system logs.
    case logs
    /// Preferences and system configuration.
    case settings

    // Backward-compatible cases:
    case dashboard
    case restoreExplorer
    case profileRules
    case maintenance
    case photosBackup
    case photosSnapshots
}

/// Tabs within the unified Profile Workspace.
public enum ProfileWorkspaceTab: String, CaseIterable, Identifiable, Sendable {
    case overview = "overview"
    case timeMachine = "timeMachine"
    case rulesAndMaintenance = "rulesAndMaintenance"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .overview: return L10n.t(.tabOverview)
        case .timeMachine: return L10n.t(.tabTimeMachine)
        case .rulesAndMaintenance: return L10n.t(.tabRulesAndMaintenance)
        }
    }

    public var iconName: String {
        switch self {
        case .overview: return "gauge.with.needle"
        case .timeMachine: return "clock.arrow.circlepath"
        case .rulesAndMaintenance: return "slider.horizontal.3"
        }
    }
}

/// Tabs within the unified Photos Workspace.
public enum PhotosWorkspaceTab: String, CaseIterable, Identifiable, Sendable {
    case syncAndBackup = "syncAndBackup"
    case snapshots = "snapshots"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .syncAndBackup: return L10n.t(.tabPhotosSync)
        case .snapshots: return L10n.t(.tabPhotosSnapshots)
        }
    }

    public var iconName: String {
        switch self {
        case .syncAndBackup: return "photo.badge.arrow.down"
        case .snapshots: return "photo.stack"
        }
    }
}

/// Browsing mode selection for the restore explorer.
public enum RestoreBrowseMode: String, CaseIterable, Identifiable, Sendable {
    /// Browse files by individual snapshot directory tree.
    case snapshot = "snapshot"
    /// Search files across all snapshots with complete version history.
    case globalSearch = "globalSearch"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .snapshot: return L10n.t(.restoreSnapshotMode)
        case .globalSearch: return L10n.t(.searchAcrossSnapshotsMode)
        }
    }
}


/// Modal feedback payload presenting Ottie mascot illustrations and actionable guidance.
public struct OperationFeedback: Identifiable, Sendable {
    public enum FeedbackType: Sendable {
        case success
        case failure
    }

    public let id: UUID
    public let type: FeedbackType
    public let title: String
    public let message: String
    public let detailedReason: String?
    public let profileName: String?
    public let summary: BackupSessionSummary?
    public let restoreSummary: RestoreSessionSummary?

    public init(
        id: UUID = UUID(),
        type: FeedbackType,
        title: String,
        message: String,
        detailedReason: String? = nil,
        profileName: String? = nil,
        summary: BackupSessionSummary? = nil,
        restoreSummary: RestoreSessionSummary? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.message = message
        self.detailedReason = detailedReason
        self.profileName = profileName
        self.summary = summary
        self.restoreSummary = restoreSummary
    }
}

/// Central `@Observable` view-model orchestrating application state, profile switching, background backup execution, and restore operations on the `@MainActor`.
@MainActor
@Observable
public final class AppState: Sendable {
    /// List of all configured backup profiles.
    public var profiles: [BackupProfile] = []
    /// Currently selected backup profile ID.
    public var selectedProfileId: UUID?
    /// Active navigation section in the split view sidebar.
    public var activeNavigation: NavigationSection = .dashboard

    /// Currently active tab within the selected Profile workspace.
    public var activeProfileTab: ProfileWorkspaceTab = .overview
    /// Currently active tab within the Apple Photos workspace.
    public var activePhotosTab: PhotosWorkspaceTab = .syncAndBackup

    // MARK: - Per-Profile Parallel Backup Operations State (1.3.1)
    /// Active background backup tasks keyed by profile UUID.
    private var activeBackupTasks: [UUID: Task<Void, Never>] = [:]

    /// Live telemetry progress states keyed by profile UUID.
    public private(set) var profileProgressStates: [UUID: BackupProgressState] = [:]

    /// Last session summaries keyed by profile UUID.
    public private(set) var profileLastSummaries: [UUID: BackupSessionSummary] = [:]

    /// Indicates whether a backup operation is currently executing for any profile.
    public var isBackupRunning: Bool {
        !activeBackupTasks.isEmpty
    }

    /// Checks if a specific profile is currently backing up.
    public func isBackupRunning(for profileId: UUID) -> Bool {
        activeBackupTasks[profileId] != nil
    }

    /// Retrieves the live progress state for a specific profile (or idle if not running).
    public func progressState(for profileId: UUID) -> BackupProgressState {
        profileProgressStates[profileId] ?? BackupProgressState(phase: .idle)
    }

    /// Backward-compatible progress state resolving to the currently selected profile (or first active).
    public var progressState: BackupProgressState {
        get {
            if let selectedId = selectedProfileId, let state = profileProgressStates[selectedId] {
                return state
            }
            if let firstActive = profileProgressStates.values.first(where: { $0.phase != .idle }) {
                return firstActive
            }
            return BackupProgressState(phase: .idle)
        }
        set {
            if let selectedId = selectedProfileId {
                profileProgressStates[selectedId] = newValue
            }
        }
    }

    // MARK: - Testing State Helpers
    /// Simulates or sets running state for testing profile lockout and multi-profile parallelism.
    public func setBackupRunningForTesting(profileId: UUID, running: Bool) {
        if running {
            activeBackupTasks[profileId] = Task { try? await Task.sleep(nanoseconds: 10_000_000_000) }
            profileProgressStates[profileId] = BackupProgressState(phase: .copying)
        } else {
            activeBackupTasks[profileId]?.cancel()
            activeBackupTasks.removeValue(forKey: profileId)
            profileProgressStates.removeValue(forKey: profileId)
        }
    }

    /// Sets simulated system dark mode state for theme switcher testing.
    public func setSystemDarkModeForTesting(_ isDark: Bool) {
        self.isSystemDarkMode = isDark
    }

    // MARK: - Modal Operation Feedback State (1.3.1)
    public var activeFeedback: OperationFeedback? = nil
    public var showFeedbackModal: Bool = false

    // MARK: - 3-2-1 Replication State
    public var isReplicationRunning: Bool = false
    public var replicationProgressState: ReplicationProgressState = ReplicationProgressState()
    public var lastReplicationSummary: ReplicationJobSummary?

    // MARK: - Remote Destination Editor Sheet State
    public var showRemoteDestinationEditorSheet: Bool = false
    public var destinationEditorTargetId: UUID? = nil
    public var destinationEditorName: String = ""
    public var destinationEditorTypeIndex: Int = 0 // 0: S3, 1: SMB, 2: WebDAV, 3: SFTP, 4: Backblaze B2
    public var destinationEditorS3Endpoint: String = "https://s3.amazonaws.com"
    public var destinationEditorS3Bucket: String = ""
    public var destinationEditorS3Region: String = "eu-central-1"
    public var destinationEditorS3AccessKeyId: String = ""
    public var destinationEditorS3SecretAccessKey: String = ""
    public var destinationEditorS3PathPrefix: String = "otterkeep"
    public var destinationEditorS3ForcePathStyle: Bool = true
    public var destinationEditorSmbShareURL: String = "smb://nas.local/backups"
    public var destinationEditorSmbMountPath: String = "/Volumes/backups"
    public var destinationEditorSmbUsername: String = ""
    public var destinationEditorSmbPassword: String = ""
    public var destinationEditorWebDAVURL: String = "https://nas.local:5006"
    public var destinationEditorWebDAVPath: String = "/backups"
    public var destinationEditorWebDAVUsername: String = ""
    public var destinationEditorWebDAVPassword: String = ""
    public var destinationEditorSFTPHost: String = "nas.local"
    public var destinationEditorSFTPPort: Int = 22
    public var destinationEditorSFTPUsername: String = ""
    public var destinationEditorSFTPPasswordOrKey: String = ""
    public var destinationEditorSFTPAuthModeIndex: Int = 0
    public var destinationEditorSFTPPath: String = "/var/backups/otterkeep"
    public var destinationEditorB2KeyId: String = ""
    public var destinationEditorB2AppKey: String = ""
    public var destinationEditorB2BucketName: String = ""
    public var destinationEditorB2Region: String = "us-west-004"
    public var destinationEditorB2CustomEndpoint: String = ""
    public var destinationEditorB2PathPrefix: String = "otterkeep"
    public var destinationEditorArchivePackagingEnabled: Bool = false
    public var destinationEditorArchiveCompressionLevel: Int = 3
    public var destinationEditorIsClientEncryptionEnabled: Bool = true
    public var destinationEditorIsEnabled: Bool = true
    public var destinationEditorIsTesting: Bool = false
    public var destinationEditorTestSuccessMessage: String? = nil
    public var destinationEditorTestErrorMessage: String? = nil

    // MARK: - Software Updates State
    public var isCheckingForSoftwareUpdates: Bool = false
    public var softwareUpdateStatusMessage: String? = nil
    public var softwareUpdateAvailableInfo: SoftwareUpdateInfo? = nil

    // MARK: - Photos Backup State
    public var photosConfig: PhotosBackupConfiguration
    public var isPhotosBackupRunning: Bool = false
    public var photosProgressState: PhotosBackupProgressState = PhotosBackupProgressState()
    public var lastPhotosSessionSummary: PhotosSessionSummary?
    public var photosAuthorizationStatus: PHAuthorizationStatus = .notDetermined
    public var loadedPhotosSnapshotId: String? = nil
    public var photosSnapshots: [SnapshotRecord] = []
    public var selectedPhotosSnapshotId: String?
    public var photosAssets: [PhotosAssetRecord] = []
    public var selectedPhotosAsset: PhotosAssetRecord?
    public var photosLibraryTotalCount: Int = 0
    public var isScanningPhotosLibrary: Bool = false

    // MARK: - Pre-backup Simulation (Dry-Run)
    public var isDryRunRunning: Bool = false
    public var dryRunSummary: DryRunSummary?
    public var showDryRunModal: Bool = false
    public var dryRunSelectedCategory: String = "all"

    // MARK: - Backup Inspector Modal
    public var lastSessionSummary: BackupSessionSummary?
    public var showInspectorModal: Bool = false
    public var inspectorSelectedTab: String = "summary"
    public var inspectorSearchQuery: String = ""

    // MARK: - Profile Management Dialogs
    public var showNewProfileSheet: Bool = false
    public var newProfileName: String = ""
    public var newProfileSourceURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
    public var newProfileDestinationURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("OtterKeep_Backups")
    public var newProfileIsDestinationCustomized: Bool = false
    public var newProfileExcludePatterns: [String] = ["*.tmp", ".DS_Store", "node_modules", "DerivedData"]
    public var newProfileEnableIgnoreFiles: Bool = true
    public var newProfileRespectGitIgnore: Bool = false
    public var newProfileBackupOnVolumeMount: Bool = false
    public var newProfileAutoEjectOnCompletion: Bool = false
    public var selectedPresetTag: String? = nil

    public var showRenameProfileSheet: Bool = false
    public var renameProfileName: String = ""

    // MARK: - Cross-Snapshot Global Search State
    public var globalSearchQuery: String = ""
    public var globalSearchResults: [GlobalSearchResult] = []
    public var selectedGlobalSearchResult: GlobalSearchResult? = nil
    public var isGlobalSearching: Bool = false

    public func resetNewProfileDraft() {
        newProfileName = ""
        newProfileSourceURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        newProfileDestinationURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("OtterKeep_Backups")
        newProfileIsDestinationCustomized = false
        newProfileExcludePatterns = ["*.tmp", ".DS_Store", "node_modules", "DerivedData"]
        newProfileEnableIgnoreFiles = true
        newProfileRespectGitIgnore = false
        newProfileBackupOnVolumeMount = false
        newProfileAutoEjectOnCompletion = false
        selectedPresetTag = nil
    }

    public func applyDeveloperPreset() {
        selectedPresetTag = "developer"
        newProfileName = "Development"
        let devURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Development")
        let projURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects")
        if FileManager.default.fileExists(atPath: devURL.path) {
            newProfileSourceURL = devURL
        } else if FileManager.default.fileExists(atPath: projURL.path) {
            newProfileSourceURL = projURL
        } else {
            newProfileSourceURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Projects")
        }
        updateNewProfileName("Development")
        newProfileExcludePatterns = ["node_modules", ".build", "target", ".venv", "Pods", "DerivedData", ".gradle", "vendor", "*.pyc"]
        newProfileEnableIgnoreFiles = true
        newProfileRespectGitIgnore = true
    }

    public func applyDocumentsPreset() {
        selectedPresetTag = "documents"
        newProfileName = "Documents"
        newProfileSourceURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        updateNewProfileName("Documents")
        newProfileExcludePatterns = ["*.tmp", "~*", "*.crdownload"]
        newProfileEnableIgnoreFiles = true
        newProfileRespectGitIgnore = false
    }

    public func applyCreativePreset() {
        selectedPresetTag = "creative"
        newProfileName = "Photos & Media"
        newProfileSourceURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        updateNewProfileName("Photos & Media")
        newProfileExcludePatterns = ["*.tmp"]
        newProfileEnableIgnoreFiles = true
        newProfileRespectGitIgnore = false
    }

    public func updateNewProfileName(_ newName: String) {
        newProfileName = newName
        if !newProfileIsDestinationCustomized {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = trimmed.isEmpty ? "" : "_\(trimmed.replacingOccurrences(of: " ", with: "_"))"
            newProfileDestinationURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("OtterKeep_Backups\(suffix)")
        }
    }

    // MARK: - Snapshot Browsing & File Tree
    public var loadedProfileId: UUID? = nil
    public var loadedSnapshotId: String? = nil
    public var snapshots: [SnapshotRecord] = []
    public var selectedSnapshotId: String?
    public var snapshotFiles: [FileCatalogRecord] = []
    public var snapshotTreeNodes: [FileTreeNode] = []
    public var selectedTreeNode: FileTreeNode?
    public var selectedFile: FileCatalogRecord?

    // MARK: - File Timeline & Tree Structure
    public var restoreBrowseMode: RestoreBrowseMode = .snapshot
    public var timelineSearchQuery: String = ""
    public var timelinePaths: [String] = []
    public var timelineTreeNodes: [FileTreeNode] = []
    public var selectedTimelinePath: String?
    public var selectedPathVersions: [(snapshot: SnapshotRecord, file: FileCatalogRecord)] = []
    public var selectedTimelineVersion: (snapshot: SnapshotRecord, file: FileCatalogRecord)?
    public var versionToRestore: (snapshot: SnapshotRecord, file: FileCatalogRecord)?

    // MARK: - Snapshot Diff & What Changed State
    public var selectedDiffTargetSnapshotId: String?
    public var selectedDiffBaseSnapshotId: String?
    public var snapshotDiffReport: SnapshotDiffReport?
    public var isLoadingDiff: Bool = false
    public var diffFilterType: DiffChangeType? = nil
    public var diffSearchQuery: String = ""
    public var showDiffSheet: Bool = false

    // MARK: - Side-by-Side Snapshot File Diff (1.5.0)
    public var showSideBySideDiffModal: Bool = false
    public var activeSideBySideDiffItem: SnapshotDiffItem? = nil
    public var activeSideBySideDiffComparison: FileComparisonResult? = nil
    public var isLoadingSideBySideDiff: Bool = false

    // MARK: - Data Integrity Scrubber State (1.5.0)
    public var isDataScrubInProgress: Bool = false
    public var scrubProgress: ScrubRunProgress? = nil

    // MARK: - Storage Capacity Forecast & Quota Alerts
    public var storageForecastReport: StorageForecastReport?
    public var isLoadingForecast: Bool = false
    public var webhookTestingStatus: (isTesting: Bool, message: String?, isSuccess: Bool) = (false, nil, false)

    // MARK: - Wi-Fi Filter Input State
    public var newAllowedWiFiSSID: String = ""
    public var newDisallowedWiFiSSID: String = ""


    // MARK: - Direct File Version History & Finder In-Place Restore

    public var showFileVersionHistoryModal: Bool = false
    public var activeVersionHistoryFile: URL? = nil
    public var activeVersionHistoryProfile: BackupProfile? = nil
    public var activeVersionHistoryRecords: [(snapshot: SnapshotRecord, file: FileCatalogRecord)] = []
    public var isLoadingFileVersions: Bool = false
    public var selectedFileVersionHistoryRecord: (snapshot: SnapshotRecord, file: FileCatalogRecord)? = nil
    public var versionForInPlaceRestore: (snapshot: SnapshotRecord, file: FileCatalogRecord)? = nil
    public var showConfirmInPlaceRestore: Bool = false
    public var inPlaceRestoreCollisionChoice: CollisionResolution = .overwrite

    // MARK: - Volume & CoW Capability Evaluation
    public var volumeEvaluation: VolumeEvaluationResult?

    // MARK: - Quick Look
    public var quickLookURL: URL?

    public var logEntries: [LogEntry] = []
    public var alertMessage: String?
    public var showAlert: Bool = false

    // MARK: - UI Interaction State
    public var newExcludePattern: String = ""
    public var searchFilter: String = ""
    public var showRestoreDialog: Bool = false
    public var showRestoreSnapshotDialog: Bool = false
    public var snapshotToRestoreEntirely: SnapshotRecord? = nil
    public var isSnapshotRestoreInProgress: Bool = false
    public var snapshotRestoreProgress: RestoreProgressState? = nil
    public var collisionChoice: CollisionResolution = .keepBoth
    public var maxSnapshotsToKeep: Int = 5
    public var showConfirmPrune: Bool = false
    public var showConfirmRebuild: Bool = false
    public var showConfirmFullBackup: Bool = false
    public var selectedLogLevel: LogEntry.LogLevel? = nil
    public var logFilterQuery: String = ""

    // MARK: - Language, Theme & Settings State
    public private(set) var isSystemDarkMode: Bool = false

    /// Computes the active SwiftUI color scheme, dynamically synchronizing system mode with the OS interface style.
    public var effectiveColorScheme: ColorScheme {
        switch currentTheme {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return isSystemDarkMode ? .dark : .light
        }
    }

    /// Evaluates the true operating system appearance setting.
    public func updateSystemDarkMode() {
        let isDark: Bool
        if let match = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            isDark = (match == .darkAqua)
        } else if let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") {
            isDark = (style.caseInsensitiveCompare("Dark") == .orderedSame)
        } else {
            isDark = false
        }
        self.isSystemDarkMode = isDark
    }

    public var currentTheme: AppThemeMode = LocalizationManager.shared.currentTheme {
        didSet {
            LocalizationManager.shared.currentTheme = currentTheme
            applyThemeAppearance(currentTheme)
        }
    }

    /// Synchronizes the global macOS application appearance with the selected theme mode.
    public func applyThemeAppearance(_ theme: AppThemeMode) {
        updateSystemDarkMode()
        let targetAppearance: NSAppearance?
        switch theme {
        case .system:
            targetAppearance = nil
        case .light:
            targetAppearance = NSAppearance(named: .aqua)
        case .dark:
            targetAppearance = NSAppearance(named: .darkAqua)
        }

        NSApplication.shared.appearance = targetAppearance
        for window in NSApplication.shared.windows {
            window.appearance = targetAppearance
        }
    }

    public var currentLanguage: AppLanguage = LocalizationManager.shared.currentLanguage {
        didSet {
            LocalizationManager.shared.currentLanguage = currentLanguage
            let targetName = L10n.t(.defaultProfileName, lang: currentLanguage)
            let otherName = currentLanguage == .hungarian ? "Default profile" : "Alapértelmezett profil"
            if let defaultProf = profiles.first(where: { $0.name == otherName }) {
                renameProfile(id: defaultProf.id, newName: targetName)
            }
        }
    }

    public var launchAtLoginEnabled: Bool = LaunchAtLoginManager.shared.isEnabled {
        didSet {
            LaunchAtLoginManager.shared.isEnabled = launchAtLoginEnabled
        }
    }

    public var startMinimized: Bool = LocalizationManager.shared.startMinimized {
        didSet {
            LocalizationManager.shared.startMinimized = startMinimized
        }
    }

    public var isFinderIntegrationEnabled: Bool = FinderIntegrationStore.shared.isEnabled {
        didSet {
            FinderIntegrationStore.shared.setEnabled(isFinderIntegrationEnabled)
            if isFinderIntegrationEnabled {
                refreshFinderPermissionStatus()
            }
        }
    }

    public var isDebugFileLoggingEnabled: Bool = LogManager.shared.isDebugFileLoggingEnabled {
        didSet {
            if isDebugFileLoggingEnabled {
                self.currentDebugLogFileURL = LogManager.shared.enableDebugFileLogging(persistSetting: true)
            } else {
                LogManager.shared.disableDebugFileLogging(persistSetting: true)
                self.currentDebugLogFileURL = nil
            }
        }
    }

    public var currentDebugLogFileURL: URL? = LogManager.shared.currentDebugLogFileURL

    public var finderPermissionStatus: FinderPermissionStatus?
    public var isCheckingFinderPermissions: Bool = false

    /// Re-evaluates macOS permissions and extension state for the Finder integration.
    public func refreshFinderPermissionStatus() {
        self.finderPermissionStatus = FinderPermissionManager.shared.evaluateStatus(for: profiles)
    }

    private let storage: FileSystemProvider
    private let database: DatabaseEngine
    private let coordinator: BackupSessionCoordinator
    private let retentionManager: RetentionManager
    private let restoreEngine: RestoreEngine
    private let photosCoordinator: PhotosBackupCoordinator

    public init() {
        let storage = APFSFileSystemProvider()
        let database = DatabaseEngine()
        let retentionManager = RetentionManager(storage: storage, database: database)
        self.storage = storage
        self.database = database
        self.retentionManager = retentionManager
        self.coordinator = BackupSessionCoordinator(storage: storage, database: database, retentionManager: retentionManager)
        self.restoreEngine = RestoreEngine(storage: storage, database: database)
        self.photosCoordinator = PhotosBackupCoordinator(storage: storage, dbEngine: database)

        // Load persistent profiles from ~/.otterkeep/profiles.json
        let loadedProfiles = ProfileStore.shared.loadProfiles()
        self.profiles = loadedProfiles
        if let firstId = loadedProfiles.first?.id {
            self.selectedProfileId = firstId
            self.activeNavigation = .profile(firstId)
        } else {
            self.activeNavigation = .photos
        }

        // Load Photos backup configuration
        self.photosConfig = PhotosProfileStore.shared.loadConfiguration()

        // Rename default profile if required by the effective language
        let currentEffective = LocalizationManager.shared.effectiveLanguage
        let expectedDefault = L10n.t(.defaultProfileName, lang: currentEffective)
        let oppositeDefault = currentEffective == .english ? "Alapértelmezett profil" : "Default profile"
        if let defaultProf = loadedProfiles.first(where: { $0.name == oppositeDefault }) {
            renameProfile(id: defaultProf.id, newName: expectedDefault)
        }

        refreshVolumeEvaluation()
        refreshLogs()
        checkPhotosAuthorization()
        refreshPhotosLibraryStats()
        loadPhotosSnapshots()
        applyThemeAppearance(self.currentTheme)

        // Observe macOS system theme changes (Auto mode live switching)
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.updateSystemDarkMode()
                if self.currentTheme == .system {
                    self.applyThemeAppearance(.system)
                }
            }
        }

        startScheduler()
    }

    public var selectedProfile: BackupProfile? {
        get {
            profiles.first(where: { $0.id == selectedProfileId })
        }
        set {
            if let newValue = newValue, let index = profiles.firstIndex(where: { $0.id == newValue.id }) {
                profiles[index] = newValue
                saveProfiles()
                refreshVolumeEvaluation()
            }
        }
    }

    public func selectProfile(id: UUID) {
        selectedProfileId = id
        activeNavigation = .profile(id)
        refreshVolumeEvaluation()
        loadSnapshots()
    }

    public func saveProfiles() {
        try? ProfileStore.shared.saveProfiles(profiles)
    }

    public func refreshVolumeEvaluation() {
        guard let profile = selectedProfile else {
            self.volumeEvaluation = nil
            return
        }
        self.volumeEvaluation = VolumeCapabilityEvaluator.evaluate(
            sourceURL: profile.sourceURL,
            destinationURL: profile.destinationURL
        )
    }

    /// Queries total, free, and available storage capacities on the currently selected destination volume.
    public func destinationStorageCapacity() -> StorageCapacity? {
        guard let destURL = selectedProfile?.destinationURL else { return nil }
        return try? storage.storageCapacity(at: destURL)
    }

    /// Calculates the sum of all stored snapshot catalog sizes for the selected profile.
    public func totalBackupSize() -> Int64 {
        snapshots.reduce(0) { $0 + $1.totalBytes }
    }

    // MARK: - Scheduler Management

    private func startScheduler() {
        BackupScheduler.shared.start(
            triggerHandler: { [weak self] profile, isCatchUp in
                Task { @MainActor in
                    guard let self = self else { return }
                    if isCatchUp {
                        LogManager.shared.log("Running catch-up backup for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]", level: .info, category: "Scheduler")
                    } else {
                        LogManager.shared.log("Running scheduled backup for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]", level: .info, category: "Scheduler")
                    }
                    self.startBackup(for: profile)
                }
            },
            photosTriggerHandler: { [weak self] config, isCatchUp in
                Task { @MainActor in
                    guard let self = self else { return }
                    if isCatchUp {
                        LogManager.shared.log("Running catch-up Photos backup", level: .info, category: "Scheduler")
                    } else {
                        LogManager.shared.log("Running scheduled Photos backup", level: .info, category: "Scheduler")
                    }
                    self.startPhotosBackup()
                }
            }
        )

        Task {
            await BackupScheduler.shared.checkAndRunCatchUpBackups()
        }
    }

    public func updateSchedule(
        isEnabled: Bool,
        frequency: ScheduleFrequency,
        hour: Int,
        minute: Int,
        weekday: Int,
        intervalMinutes: Int,
        catchUp: Bool
    ) {
        guard var profile = selectedProfile, !isBackupRunning(for: profile.id) else { return }
        profile.schedule.isEnabled = isEnabled
        profile.schedule.frequency = frequency
        profile.schedule.hour = hour
        profile.schedule.minute = minute
        profile.schedule.weekday = weekday
        profile.schedule.intervalMinutes = intervalMinutes
        profile.schedule.catchUpIfMissed = catchUp
        self.selectedProfile = profile
        saveProfiles()
        LogManager.shared.log("Schedule updated for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: Enabled=\(isEnabled), Frequency=\(frequency.rawValue), Time=\(String(format: "%02d:%02d", hour, minute)), Interval=\(intervalMinutes)m, CatchUp=\(catchUp)", level: .info, category: "Scheduler")
        refreshLogs()
    }

    public func nextScheduledRunDescription(for profile: BackupProfile) -> String {
        guard profile.schedule.isEnabled else {
            return L10n.t(.scheduleNotScheduled)
        }
        let refDate = profile.schedule.lastRunDate ?? Date()
        let nextDate = BackupScheduler.shared.calculateNextRunDate(for: profile.schedule, referenceDate: refDate)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: nextDate)
    }

    public var nextScheduledRunDescription: String {
        guard let profile = selectedProfile else {
            return L10n.t(.scheduleNotScheduled)
        }
        return nextScheduledRunDescription(for: profile)
    }

    // MARK: - Auto-Pruning Policy Configuration

    public func updateAutoPruning(isEnabled: Bool, maxKeep: Int) {
        guard var profile = selectedProfile, !isBackupRunning(for: profile.id) else { return }
        profile.pruningPolicy.isAutoPruningEnabled = isEnabled
        profile.pruningPolicy.maxSnapshotsToKeep = maxKeep
        self.selectedProfile = profile
        self.maxSnapshotsToKeep = maxKeep
        saveProfiles()
        LogManager.shared.log("Auto-pruning policy updated for profile '\(profile.name)': Enabled=\(isEnabled), Retain=\(maxKeep)", level: .info, category: "Retention")
        refreshLogs()
    }

    // MARK: - Folder Validation & Selection Helpers

    public func validateFolderPair(sourceURL: URL, destinationURL: URL) -> Bool {
        let stdSource = sourceURL.standardizedFileURL.path
        let stdDest = destinationURL.standardizedFileURL.path
        if stdSource == stdDest { return false }
        if stdDest.hasPrefix(stdSource + "/") { return false }
        return true
    }

    @MainActor
    public func selectSourceDirectory() {
        guard let profile = selectedProfile, !isBackupRunning(for: profile.id) else { return }
        pickDirectory(
            title: L10n.t(.selectSourceFolder),
            prompt: L10n.t(.selectFolderConfirm),
            initialURL: profile.sourceURL,
            canCreateDirectories: false
        ) { [weak self] url in
            self?.updateSourceURL(url)
        }
    }

    @MainActor
    public func selectDestinationDirectory() {
        guard let profile = selectedProfile, !isBackupRunning(for: profile.id) else { return }
        pickDirectory(
            title: L10n.t(.selectDestinationFolder),
            prompt: L10n.t(.selectFolderConfirm),
            initialURL: profile.destinationURL,
            canCreateDirectories: true
        ) { [weak self] url in
            self?.updateDestinationURL(url)
        }
    }

    @MainActor
    public func pickDirectory(
        title: String? = nil,
        prompt: String? = nil,
        initialURL: URL? = nil,
        canCreateDirectories: Bool = true,
        completion: @escaping (URL) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = canCreateDirectories
        panel.allowsMultipleSelection = false
        if let title = title {
            panel.title = title
            panel.message = title
        }
        if let prompt = prompt {
            panel.prompt = prompt
        }
        if let initial = initialURL {
            panel.directoryURL = initial
        }

        if let keyWindow = NSApp.keyWindow {
            let targetWindow = keyWindow.attachedSheet ?? keyWindow
            panel.beginSheetModal(for: targetWindow) { response in
                if response == .OK, let url = panel.url {
                    completion(url)
                }
            }
        } else {
            if panel.runModal() == .OK, let url = panel.url {
                completion(url)
            }
        }
    }

    // MARK: - Source, Destination & Exclusions Persistence

    public func updateSourceURL(_ url: URL) {
        guard var profile = selectedProfile, !isBackupRunning(for: profile.id) else { return }
        guard validateFolderPair(sourceURL: url, destinationURL: profile.destinationURL) else {
            showError(L10n.t(.invalidFolderSelectionMessage))
            return
        }
        profile.sourceURL = url
        self.selectedProfile = profile
        saveProfiles()
        refreshVolumeEvaluation()
        LogManager.shared.log("Source directory updated for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: '\(url.path)'", level: .info, category: "Profile")
        refreshLogs()
    }

    public func updateDestinationURL(_ url: URL) {
        guard var profile = selectedProfile, !isBackupRunning(for: profile.id) else { return }
        guard validateFolderPair(sourceURL: profile.sourceURL, destinationURL: url) else {
            showError(L10n.t(.invalidFolderSelectionMessage))
            return
        }
        profile.destinationURL = url
        self.selectedProfile = profile
        saveProfiles()
        refreshVolumeEvaluation()
        loadSnapshots()
        LogManager.shared.log("Destination directory updated for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: '\(url.path)'", level: .info, category: "Profile")
        refreshLogs()
    }

    public func addExcludePattern(_ pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var profile = selectedProfile, !isBackupRunning(for: profile.id) else { return }
        if !profile.excludePatterns.contains(trimmed) {
            profile.excludePatterns.append(trimmed)
            self.selectedProfile = profile
            saveProfiles()
            LogManager.shared.log("Exclusion pattern added for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: '\(trimmed)'", level: .info, category: "Profile")
            refreshLogs()
        }
    }

    public func removeExcludePattern(_ pattern: String) {
        guard var profile = selectedProfile, !isBackupRunning(for: profile.id) else { return }
        profile.excludePatterns.removeAll(where: { $0 == pattern })
        self.selectedProfile = profile
        saveProfiles()
        LogManager.shared.log("Exclusion pattern removed for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: '\(pattern)'", level: .info, category: "Profile")
        refreshLogs()
    }

    // MARK: - Profile Operations

    public func createProfile(
        name: String,
        sourceURL: URL? = nil,
        destinationURL: URL? = nil,
        excludePatterns: [String]? = nil,
        enableIgnoreFiles: Bool = true,
        respectGitIgnore: Bool = false,
        backupOnVolumeMount: Bool = false,
        autoEjectOnCompletion: Bool = false
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let defaultSource = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        let defaultDest = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("OtterKeep_Backups_\(trimmed.replacingOccurrences(of: " ", with: "_"))")

        let effectiveSource = sourceURL ?? defaultSource
        let effectiveDest = destinationURL ?? defaultDest

        guard validateFolderPair(sourceURL: effectiveSource, destinationURL: effectiveDest) else {
            showError(L10n.t(.invalidFolderSelectionMessage))
            return
        }

        let newProfile = BackupProfile(
            name: trimmed,
            sourceURL: effectiveSource,
            destinationURL: effectiveDest,
            excludePatterns: excludePatterns ?? ["*.tmp", ".DS_Store", "node_modules", "DerivedData"],
            enableIgnoreFiles: enableIgnoreFiles,
            respectGitIgnore: respectGitIgnore,
            backupOnVolumeMount: backupOnVolumeMount,
            autoEjectOnCompletion: autoEjectOnCompletion
        )
        profiles.append(newProfile)
        selectedProfileId = newProfile.id
        saveProfiles()
        refreshVolumeEvaluation()
        loadSnapshots()
        LogManager.shared.log("New profile created: '\(trimmed)' [UUID: \(newProfile.id.uuidString)] (Source: '\(newProfile.sourceURL.path)', Dest: '\(newProfile.destinationURL.path)')", level: .info, category: "Profile")
        refreshLogs()
    }

    public func createProfileFromDraft() {
        let trimmed = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        createProfile(
            name: trimmed,
            sourceURL: newProfileSourceURL,
            destinationURL: newProfileDestinationURL,
            excludePatterns: newProfileExcludePatterns,
            enableIgnoreFiles: newProfileEnableIgnoreFiles,
            respectGitIgnore: newProfileRespectGitIgnore,
            backupOnVolumeMount: newProfileBackupOnVolumeMount,
            autoEjectOnCompletion: newProfileAutoEjectOnCompletion
        )
    }

    public func renameProfile(id: UUID, newName: String) {
        guard !isBackupRunning(for: id) else {
            LogManager.shared.log("Cannot rename profile while backup is actively running [UUID: \(id.uuidString)]", level: .warning, category: "Profile")
            return
        }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].name = trimmed
        saveProfiles()
        LogManager.shared.log("Profile renamed to: '\(trimmed)' [UUID: \(id.uuidString)]", level: .info, category: "Profile")
        refreshLogs()
    }

    public func deleteProfile(id: UUID) {
        guard !isBackupRunning(for: id) else {
            LogManager.shared.log("Cannot delete profile while backup is actively running [UUID: \(id.uuidString)]", level: .warning, category: "Profile")
            return
        }
        guard profiles.count > 1, let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        let removedProfile = profiles[idx]
        let removedName = removedProfile.name
        profiles.remove(at: idx)
        if selectedProfileId == id {
            selectedProfileId = profiles.first?.id
        }

        // Clean up Keychain credentials associated with the deleted profile
        KeychainManager.deletePassphrase(for: id)
        KeychainManager.deleteSecret(for: id.uuidString)
        KeychainManager.deleteSecret(for: "s3_\(id.uuidString)")
        KeychainManager.deleteSecret(for: "smb_\(id.uuidString)")
        KeychainManager.deleteSecret(for: "webdav_\(id.uuidString)")
        KeychainManager.deleteSecret(for: "sftp_\(id.uuidString)")
        KeychainManager.deleteSecret(for: "webhook_\(id.uuidString)")
        for dest in removedProfile.copyJobConfig.destinations {
            KeychainManager.deleteSecret(for: dest.id.uuidString)
            KeychainManager.deleteSecret(for: "s3_\(dest.id.uuidString)")
            KeychainManager.deleteSecret(for: "smb_\(dest.id.uuidString)")
            KeychainManager.deleteSecret(for: "webdav_\(dest.id.uuidString)")
            KeychainManager.deleteSecret(for: "sftp_\(dest.id.uuidString)")
        }

        saveProfiles()
        refreshVolumeEvaluation()
        loadSnapshots()
        LogManager.shared.log("Profile deleted: '\(removedName)' [UUID: \(id.uuidString)]", level: .info, category: "Profile")
        refreshLogs()
    }

    /// Opens the native macOS Sequoia About (Névjegy) panel.
    public func openAbout() {
        AboutWindowController.shared.show()
    }

    // MARK: - 3-2-1 Compliance & Replication Controls

    public enum Rule321Compliance: Sendable {
        case compliant(description: String)
        case partial(description: String)
        case localOnly(description: String)

        public var badgeText: String {
            switch self {
            case .compliant: return L10n.t(.rule321StatusCompliant)
            case .partial: return L10n.t(.rule321StatusPartial)
            case .localOnly: return L10n.t(.rule321StatusLocalOnly)
            }
        }

        public var color: Color {
            switch self {
            case .compliant: return OtterTheme.oceanicTeal
            case .partial: return OtterTheme.statusWarning
            case .localOnly: return OtterTheme.otterAmber
            }
        }
    }

    public var rule321Compliance: Rule321Compliance {
        guard let profile = selectedProfile else {
            return .localOnly(description: L10n.t(.rule321StatusLocalOnly))
        }

        let enabledDestinations = profile.copyJobConfig.destinations.filter { $0.isEnabled }
        if profile.copyJobConfig.isEnabled && !enabledDestinations.isEmpty {
            let names = enabledDestinations.map { $0.name }.joined(separator: ", ")
            return .compliant(description: "\(L10n.t(.rule321StatusCompliant)): \(names)")
        } else {
            return .partial(description: L10n.t(.rule321StatusPartial))
        }
    }

    public func startReplication(for profile: BackupProfile? = nil) {
        guard let prof = profile ?? selectedProfile else { return }
        guard !isReplicationRunning else { return }

        isReplicationRunning = true
        replicationProgressState = ReplicationProgressState(
            isRunning: true,
            statusMessage: "Starting 3-2-1 replication..."
        )
        let localStorage = self.storage
        let localDatabase = self.database

        Task { [weak self] in
            guard let self = self else { return }
            let copyCoordinator = BackupCopyJobCoordinator(storage: localStorage, database: localDatabase)
            await copyCoordinator.setProgressHandler { [weak self] state in
                Task { @MainActor in
                    self?.replicationProgressState = state
                }
            }

            do {
                let summary = try await copyCoordinator.executeReplication(profile: prof)
                await MainActor.run {
                    self.lastReplicationSummary = summary
                    self.isReplicationRunning = false
                    self.refreshLogs()
                }
            } catch {
                await MainActor.run {
                    self.isReplicationRunning = false
                    self.showError("3-2-1 Replication Error: \(error.localizedDescription)")
                    self.refreshLogs()
                }
            }
        }
    }

    public func openDestinationEditor(destination: RemoteDestination?) {
        destinationEditorTestSuccessMessage = nil
        destinationEditorTestErrorMessage = nil
        destinationEditorIsTesting = false
        if let dest = destination {
            destinationEditorTargetId = dest.id
            destinationEditorName = dest.name
            destinationEditorIsClientEncryptionEnabled = dest.isClientEncryptionEnabled
            destinationEditorIsEnabled = dest.isEnabled
            destinationEditorArchivePackagingEnabled = dest.archivePackagingEnabled
            destinationEditorArchiveCompressionLevel = dest.archiveCompressionLevel
            switch dest.type {
            case .s3(let cfg):
                destinationEditorTypeIndex = 0
                destinationEditorS3Endpoint = cfg.endpoint
                destinationEditorS3Bucket = cfg.bucket
                destinationEditorS3Region = cfg.region
                destinationEditorS3AccessKeyId = cfg.accessKeyId
                destinationEditorS3PathPrefix = cfg.pathPrefix
                destinationEditorS3ForcePathStyle = cfg.forcePathStyle
                destinationEditorS3SecretAccessKey = KeychainManager.getSecret(for: dest.keychainAccount) ?? ""
            case .smb(let cfg):
                destinationEditorTypeIndex = 1
                destinationEditorSmbShareURL = cfg.shareURL
                destinationEditorSmbMountPath = cfg.subfolder
                destinationEditorSmbUsername = cfg.username
                destinationEditorSmbPassword = KeychainManager.getSecret(for: dest.keychainAccount) ?? ""
            case .webdav(let cfg):
                destinationEditorTypeIndex = 2
                destinationEditorWebDAVURL = cfg.serverURL
                destinationEditorWebDAVPath = cfg.destinationPath
                destinationEditorWebDAVUsername = cfg.username
                destinationEditorWebDAVPassword = KeychainManager.getSecret(for: dest.keychainAccount) ?? ""
            case .sftp(let cfg):
                destinationEditorTypeIndex = 3
                destinationEditorSFTPHost = cfg.host
                destinationEditorSFTPPort = cfg.port
                destinationEditorSFTPUsername = cfg.username
                destinationEditorSFTPPath = cfg.remotePath
                let sec = KeychainManager.getSecret(for: dest.keychainAccount) ?? ""
                destinationEditorSFTPPasswordOrKey = sec
                destinationEditorSFTPAuthModeIndex = (sec.hasPrefix("/") || sec.hasPrefix("~")) ? 1 : 0
            case .backblazeB2(let cfg):
                destinationEditorTypeIndex = 4
                destinationEditorB2KeyId = cfg.keyId
                destinationEditorB2BucketName = cfg.bucketName
                destinationEditorB2Region = cfg.region
                destinationEditorB2CustomEndpoint = cfg.customEndpoint ?? ""
                destinationEditorB2PathPrefix = cfg.pathPrefix
                destinationEditorB2AppKey = KeychainManager.getSecret(for: dest.keychainAccount) ?? ""
            }
        } else {
            destinationEditorTargetId = nil
            destinationEditorName = L10n.t(.remoteS3Title)
            destinationEditorTypeIndex = 0
            destinationEditorS3Endpoint = "https://s3.amazonaws.com"
            destinationEditorS3Bucket = ""
            destinationEditorS3Region = "eu-central-1"
            destinationEditorS3AccessKeyId = ""
            destinationEditorS3SecretAccessKey = ""
            destinationEditorS3PathPrefix = "otterkeep"
            destinationEditorS3ForcePathStyle = true
            destinationEditorSmbShareURL = "smb://nas.local/backups"
            destinationEditorSmbMountPath = ""
            destinationEditorSmbUsername = ""
            destinationEditorSmbPassword = ""
            destinationEditorWebDAVURL = "https://nas.local:5006"
            destinationEditorWebDAVPath = "/backups"
            destinationEditorWebDAVUsername = ""
            destinationEditorWebDAVPassword = ""
            destinationEditorSFTPHost = "nas.local"
            destinationEditorSFTPPort = 22
            destinationEditorSFTPUsername = ""
            destinationEditorSFTPPasswordOrKey = ""
            destinationEditorSFTPAuthModeIndex = 0
            destinationEditorSFTPPath = "/var/backups/otterkeep"
            destinationEditorArchivePackagingEnabled = false
            destinationEditorArchiveCompressionLevel = 3
            destinationEditorIsClientEncryptionEnabled = true
            destinationEditorIsEnabled = true
        }
        showRemoteDestinationEditorSheet = true
    }

    public func saveDestinationEditor() {
        guard var profile = selectedProfile else { return }
        let destId = destinationEditorTargetId ?? UUID()
        let finalType: RemoteDestinationType

        let account: String
        if destinationEditorTypeIndex == 0 {
            let s3Config = S3Configuration(
                endpoint: destinationEditorS3Endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                bucket: destinationEditorS3Bucket.trimmingCharacters(in: .whitespacesAndNewlines),
                region: destinationEditorS3Region.trimmingCharacters(in: .whitespacesAndNewlines),
                accessKeyId: destinationEditorS3AccessKeyId.trimmingCharacters(in: .whitespacesAndNewlines),
                pathPrefix: destinationEditorS3PathPrefix.trimmingCharacters(in: .whitespacesAndNewlines),
                forcePathStyle: destinationEditorS3ForcePathStyle
            )
            finalType = .s3(s3Config)

            account = "s3_\(destId.uuidString)"
            if !destinationEditorS3SecretAccessKey.isEmpty {
                try? KeychainManager.saveSecret(destinationEditorS3SecretAccessKey, for: account)
            }
        } else if destinationEditorTypeIndex == 1 {
            let smbConfig = NetworkShareConfiguration(
                shareURL: destinationEditorSmbShareURL.trimmingCharacters(in: .whitespacesAndNewlines),
                username: destinationEditorSmbUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                subfolder: destinationEditorSmbMountPath.trimmingCharacters(in: .whitespacesAndNewlines),
                useSparsebundle: false
            )
            finalType = .smb(smbConfig)

            account = "smb_\(destId.uuidString)"
            if !destinationEditorSmbPassword.isEmpty {
                try? KeychainManager.saveSecret(destinationEditorSmbPassword, for: account)
            }
        } else if destinationEditorTypeIndex == 2 {
            let urlString = destinationEditorWebDAVURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let webdavConfig = WebDAVConfiguration(
                serverURL: urlString,
                destinationPath: destinationEditorWebDAVPath.trimmingCharacters(in: .whitespacesAndNewlines),
                username: destinationEditorWebDAVUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                useSSL: urlString.lowercased().hasPrefix("https")
            )
            finalType = .webdav(webdavConfig)

            account = "webdav_\(destId.uuidString)"
            if !destinationEditorWebDAVPassword.isEmpty {
                try? KeychainManager.saveSecret(destinationEditorWebDAVPassword, for: account)
            }
        } else if destinationEditorTypeIndex == 3 {
            let auth: SFTPAuthMethod
            let secret = destinationEditorSFTPPasswordOrKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if secret.hasPrefix("/") || secret.hasPrefix("~") || FileManager.default.fileExists(atPath: secret) {
                auth = .privateKey(keyPath: secret)
            } else {
                auth = .password
            }
            let sftpConfig = SFTPConfiguration(
                host: destinationEditorSFTPHost.trimmingCharacters(in: .whitespacesAndNewlines),
                port: destinationEditorSFTPPort,
                username: destinationEditorSFTPUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                remotePath: destinationEditorSFTPPath.trimmingCharacters(in: .whitespacesAndNewlines),
                authMethod: auth
            )
            finalType = .sftp(sftpConfig)

            account = "sftp_\(destId.uuidString)"
            if !destinationEditorSFTPPasswordOrKey.isEmpty {
                try? KeychainManager.saveSecret(destinationEditorSFTPPasswordOrKey, for: account)
            }
        } else {
            let b2Config = B2Configuration(
                keyId: destinationEditorB2KeyId.trimmingCharacters(in: .whitespacesAndNewlines),
                bucketName: destinationEditorB2BucketName.trimmingCharacters(in: .whitespacesAndNewlines),
                region: destinationEditorB2Region.trimmingCharacters(in: .whitespacesAndNewlines),
                customEndpoint: destinationEditorB2CustomEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : destinationEditorB2CustomEndpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                pathPrefix: destinationEditorB2PathPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            finalType = .backblazeB2(b2Config)

            account = "b2_\(destId.uuidString)"
            if !destinationEditorB2AppKey.isEmpty {
                try? KeychainManager.saveSecret(destinationEditorB2AppKey, for: account)
            }
        }

        let updatedDestination = RemoteDestination(
            id: destId,
            name: destinationEditorName.trimmingCharacters(in: .whitespacesAndNewlines),
            type: finalType,
            isClientEncryptionEnabled: destinationEditorIsClientEncryptionEnabled,
            keychainAccount: account,
            isEnabled: destinationEditorIsEnabled,
            archivePackagingEnabled: destinationEditorArchivePackagingEnabled,
            archiveCompressionLevel: destinationEditorArchiveCompressionLevel
        )

        if let idx = profile.copyJobConfig.destinations.firstIndex(where: { $0.id == destId }) {
            profile.copyJobConfig.destinations[idx] = updatedDestination
        } else {
            profile.copyJobConfig.destinations.append(updatedDestination)
        }

        selectedProfile = profile
        if let pIdx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[pIdx] = profile
        }
        saveProfiles()
        showRemoteDestinationEditorSheet = false
    }

    public func deleteDestinationEditor(destinationId: UUID) {
        guard var profile = selectedProfile else { return }
        profile.copyJobConfig.destinations.removeAll(where: { $0.id == destinationId })
        KeychainManager.deleteSecret(for: "s3_\(destinationId.uuidString)")
        KeychainManager.deleteSecret(for: "smb_\(destinationId.uuidString)")
        KeychainManager.deleteSecret(for: "webdav_\(destinationId.uuidString)")
        KeychainManager.deleteSecret(for: "sftp_\(destinationId.uuidString)")
        KeychainManager.deleteSecret(for: "b2_\(destinationId.uuidString)")
        selectedProfile = profile
        if let pIdx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[pIdx] = profile
        }
        saveProfiles()
        showRemoteDestinationEditorSheet = false
    }

    public func testDestinationEditorConnection() {
        destinationEditorIsTesting = true
        destinationEditorTestSuccessMessage = nil
        destinationEditorTestErrorMessage = nil

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if self.destinationEditorTypeIndex == 0 {
                let config = S3Configuration(
                    endpoint: self.destinationEditorS3Endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                    bucket: self.destinationEditorS3Bucket.trimmingCharacters(in: .whitespacesAndNewlines),
                    region: self.destinationEditorS3Region.trimmingCharacters(in: .whitespacesAndNewlines),
                    accessKeyId: self.destinationEditorS3AccessKeyId.trimmingCharacters(in: .whitespacesAndNewlines),
                    pathPrefix: self.destinationEditorS3PathPrefix.trimmingCharacters(in: .whitespacesAndNewlines),
                    forcePathStyle: self.destinationEditorS3ForcePathStyle
                )
                let provider = S3StorageProvider(config: config, secretAccessKey: self.destinationEditorS3SecretAccessKey)
                do {
                    _ = try await provider.testConnection()
                    self.destinationEditorTestSuccessMessage = L10n.format(.testConnectionSuccessS3Format, config.bucket)
                } catch {
                    self.destinationEditorTestErrorMessage = L10n.format(.s3ConnectionErrorFormat, error.localizedDescription)
                }
            } else if self.destinationEditorTypeIndex == 1 {
                let shareTrimmed = self.destinationEditorSmbShareURL.trimmingCharacters(in: .whitespacesAndNewlines)
                do {
                    let components = try NetworkShareMounter.parseShareURL(shareTrimmed)
                    guard !components.host.isEmpty else {
                        self.destinationEditorTestErrorMessage = L10n.t(.testConnectionMissingSMBHost)
                        self.destinationEditorIsTesting = false
                        return
                    }

                    if !NetworkReachability.shared.isConnected {
                        self.destinationEditorTestErrorMessage = L10n.t(.testConnectionNoNetwork)
                        self.destinationEditorIsTesting = false
                        return
                    }

                    let portReachable = NetworkShareMounter.testTCPPort(host: components.host, port: 445, timeoutSeconds: 3.0)
                    if portReachable {
                        self.destinationEditorTestSuccessMessage = L10n.format(.testConnectionSuccessSMBFormat, components.host)
                    } else {
                        self.destinationEditorTestErrorMessage = "A NAS szerver ('\(components.host)') nem érhető el a 445-ös (SMB) porton."
                    }
                } catch {
                    self.destinationEditorTestErrorMessage = error.localizedDescription
                }
            } else if self.destinationEditorTypeIndex == 2 {
                let urlString = self.destinationEditorWebDAVURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let base = URL(string: urlString), base.scheme != nil else {
                    self.destinationEditorTestErrorMessage = "Érvénytelen WebDAV URL cím."
                    self.destinationEditorIsTesting = false
                    return
                }
                let config = WebDAVConfiguration(
                    serverURL: urlString,
                    destinationPath: self.destinationEditorWebDAVPath.trimmingCharacters(in: .whitespacesAndNewlines),
                    username: self.destinationEditorWebDAVUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                    useSSL: urlString.lowercased().hasPrefix("https")
                )
                let provider = WebDAVStorageProvider(config: config, password: self.destinationEditorWebDAVPassword)
                do {
                    _ = try await provider.testConnection()
                    self.destinationEditorTestSuccessMessage = L10n.format(.testConnectionSuccessWebDAVFormat, urlString)
                } catch {
                    self.destinationEditorTestErrorMessage = error.localizedDescription
                }
            } else if self.destinationEditorTypeIndex == 3 {
                let host = self.destinationEditorSFTPHost.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !host.isEmpty else {
                    self.destinationEditorTestErrorMessage = "A megadott SFTP szerver cím érvénytelen."
                    self.destinationEditorIsTesting = false
                    return
                }
                let secret = self.destinationEditorSFTPPasswordOrKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let auth: SFTPAuthMethod
                if secret.hasPrefix("/") || secret.hasPrefix("~") || FileManager.default.fileExists(atPath: secret) {
                    auth = .privateKey(keyPath: secret)
                } else {
                    auth = .password
                }
                let config = SFTPConfiguration(
                    host: host,
                    port: self.destinationEditorSFTPPort,
                    username: self.destinationEditorSFTPUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                    remotePath: self.destinationEditorSFTPPath.trimmingCharacters(in: .whitespacesAndNewlines),
                    authMethod: auth
                )
                let provider = SFTPStorageProvider(config: config)
                do {
                    _ = try await provider.testConnection()
                    self.destinationEditorTestSuccessMessage = L10n.format(.testConnectionSuccessSFTPFormat, host)
                } catch {
                    self.destinationEditorTestErrorMessage = error.localizedDescription
                }
            } else {
                let config = B2Configuration(
                    keyId: self.destinationEditorB2KeyId.trimmingCharacters(in: .whitespacesAndNewlines),
                    bucketName: self.destinationEditorB2BucketName.trimmingCharacters(in: .whitespacesAndNewlines),
                    region: self.destinationEditorB2Region.trimmingCharacters(in: .whitespacesAndNewlines),
                    customEndpoint: self.destinationEditorB2CustomEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self.destinationEditorB2CustomEndpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                    pathPrefix: self.destinationEditorB2PathPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                let provider = B2StorageProvider(config: config, applicationKey: self.destinationEditorB2AppKey)
                do {
                    _ = try await provider.testConnection()
                    self.destinationEditorTestSuccessMessage = L10n.format(.testConnectionSuccessS3Format, config.bucketName)
                } catch {
                    self.destinationEditorTestErrorMessage = L10n.format(.s3ConnectionErrorFormat, error.localizedDescription)
                }
            }
            self.destinationEditorIsTesting = false
        }
    }

    // MARK: - Software Updates Management

    public var automaticallyChecksForUpdates: Bool {
        get {
            if UserDefaults.standard.object(forKey: "OtterKeep.AutoCheckForUpdates") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "OtterKeep.AutoCheckForUpdates")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "OtterKeep.AutoCheckForUpdates")
        }
    }

    public func checkForSoftwareUpdates(silent: Bool = false) {
        guard !isCheckingForSoftwareUpdates else { return }
        isCheckingForSoftwareUpdates = true
        if !silent {
            softwareUpdateStatusMessage = L10n.t(.settingsUpdateStatusChecking)
        }
        softwareUpdateAvailableInfo = nil

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let status = await SoftwareUpdateCoordinator.shared.checkForUpdates()
            switch status {
            case .updateAvailable(let info):
                self.softwareUpdateAvailableInfo = info
                self.softwareUpdateStatusMessage = L10n.format(.settingsUpdateStatusAvailableFormat, info.version)
                if silent {
                    NotificationDeliveryService.shared.notifySoftwareUpdateAvailable(version: info.version)
                }
            case .upToDate:
                if !silent {
                    self.softwareUpdateStatusMessage = L10n.t(.settingsUpdateStatusUpToDate)
                }
            case .failed(let err):
                if !silent {
                    self.softwareUpdateStatusMessage = L10n.format(.settingsUpdateStatusFailedFormat, err)
                }
            case .checking, .idle:
                break
            }
            self.isCheckingForSoftwareUpdates = false
        }
    }

    // MARK: - Backup Operations & Analysis

    /// Parallel executes backups across all configured profiles.
    public func startBackupAll(mode: BackupMode = .incremental) {
        let profilesToRun = self.profiles
        guard !profilesToRun.isEmpty else { return }

        LogManager.shared.log("Parallel batch backup requested for all \(profilesToRun.count) profile(s).", level: .info, category: "UI")
        refreshLogs()

        for profile in profilesToRun {
            if !isBackupRunning(for: profile.id) {
                startBackup(for: profile, mode: mode)
            }
        }
    }

    public func startBackup(for profileToBackup: BackupProfile? = nil, mode: BackupMode = .incremental) {
        guard let profile = profileToBackup ?? selectedProfile else { return }
        guard !isBackupRunning(for: profile.id) else {
            LogManager.shared.log("Backup already in progress for profile '\(profile.name)' [UUID: \(profile.id.uuidString)] - skipping duplicate launch.", level: .warning, category: "UI")
            return
        }

        profileProgressStates[profile.id] = BackupProgressState(phase: .scanning)
        let modeTag = mode == .full ? " (FORCED FULL)" : " (Incremental)"
        LogManager.shared.log("Backup initiated for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]\(modeTag)", level: .info, category: "UI")
        refreshLogs()

        // Create dedicated, isolated session coordinator and SQLite database to support zero-contention parallel backups
        let sessionDb = DatabaseEngine()
        let sessionRetention = RetentionManager(storage: self.storage, database: sessionDb)
        let sessionCoordinator = BackupSessionCoordinator(
            storage: self.storage,
            database: sessionDb,
            retentionManager: sessionRetention
        )

        let task = Task { [weak self] in
            guard let self = self else { return }
            do {
                _ = try await sessionCoordinator.performBackup(profile: profile, mode: mode) { [weak self] progress in
                    Task { @MainActor in
                        self?.profileProgressStates[profile.id] = progress
                    }
                }
                let coordinatorSummary = await sessionCoordinator.lastSessionSummary
                let finalSummary = coordinatorSummary ?? self.profileProgressStates[profile.id]?.lastSummary
                if let summary = finalSummary {
                    self.profileLastSummaries[profile.id] = summary
                }
                if self.selectedProfileId == profile.id {
                    self.lastSessionSummary = finalSummary
                }

                self.activeBackupTasks.removeValue(forKey: profile.id)
                self.profileProgressStates[profile.id] = BackupProgressState(phase: .idle)

                if let idx = self.profiles.firstIndex(where: { $0.id == profile.id }) {
                    self.profiles[idx].schedule.lastRunDate = Date()
                    self.saveProfiles()
                }

                LogManager.shared.log("Backup completed successfully for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]\(modeTag)", level: .info, category: "UI")
                self.refreshLogs()
                self.loadSnapshots()

                // Trigger Operation Feedback Modal
                self.activeFeedback = OperationFeedback(
                    type: .success,
                    title: L10n.t(.feedbackSuccessTitle),
                    message: L10n.format(.feedbackSuccessMessage, profile.name),
                    profileName: profile.name,
                    summary: finalSummary
                )
                self.showFeedbackModal = true

                // Trigger 3-2-1 Replication from UI AppState to provide live telemetry
                if profile.copyJobConfig.isEnabled && profile.copyJobConfig.trigger == .onPrimarySuccess {
                    self.startReplication(for: profile)
                }
            } catch is CancellationError {
                self.activeBackupTasks.removeValue(forKey: profile.id)
                self.profileProgressStates[profile.id] = BackupProgressState(phase: .idle)
                LogManager.shared.log("Backup cancelled by user for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]", level: .info, category: "UI")
                self.refreshLogs()
            } catch {
                self.activeBackupTasks.removeValue(forKey: profile.id)
                self.profileProgressStates[profile.id] = BackupProgressState(phase: .failed)
                NotificationDeliveryService.shared.notifyBackupFailed(profileName: profile.name, errorMessage: error.localizedDescription)
                LogManager.shared.log("Backup failed for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: \(error.localizedDescription)", level: .error, category: "UI")
                self.refreshLogs()

                let analyzed = Self.analyzeBackupError(error, destinationURL: profile.destinationURL, sourceURL: profile.sourceURL)
                self.activeFeedback = OperationFeedback(
                    type: .failure,
                    title: analyzed.title,
                    message: analyzed.message,
                    detailedReason: analyzed.detailedReason,
                    profileName: profile.name
                )
                self.showFeedbackModal = true
            }
        }

        activeBackupTasks[profile.id] = task
    }

    @MainActor
    public func cancelBackup(for profileId: UUID? = nil) {
        let targetId = profileId ?? selectedProfileId
        if let id = targetId, let task = activeBackupTasks[id] {
            let profileName = profiles.first(where: { $0.id == id })?.name ?? id.uuidString
            LogManager.shared.log("Cancelling backup upon user request for profile '\(profileName)'...", level: .info, category: "UI")
            task.cancel()
            activeBackupTasks.removeValue(forKey: id)
            profileProgressStates[id] = BackupProgressState(phase: .idle)
            refreshLogs()
        } else if targetId == nil {
            LogManager.shared.log("Cancelling all running backups upon user request...", level: .info, category: "UI")
            for (id, task) in activeBackupTasks {
                task.cancel()
                profileProgressStates[id] = BackupProgressState(phase: .idle)
            }
            activeBackupTasks.removeAll()
            refreshLogs()
        }
    }

    /// Analyzes backup failure errors to produce precise, non-misleading user guidance.
    public static func analyzeBackupError(_ error: Error, destinationURL: URL?, sourceURL: URL?) -> (title: String, message: String, detailedReason: String) {
        let errorDesc = error.localizedDescription

        // 1. External drive disconnected or destination directory vanished
        if let dest = destinationURL, !FileManager.default.fileExists(atPath: dest.path) {
            return (
                title: L10n.t(.feedbackExternalDriveMissingTitle),
                message: L10n.format(.feedbackExternalDriveMissingMessage, dest.lastPathComponent),
                detailedReason: L10n.t(.feedbackExternalDriveMissingAdvice)
            )
        }

        // 2. Source folder missing or renamed
        if let src = sourceURL, !FileManager.default.fileExists(atPath: src.path) {
            return (
                title: L10n.t(.feedbackSourceFolderMissingTitle),
                message: L10n.format(.feedbackSourceFolderMissingMessage, src.lastPathComponent),
                detailedReason: L10n.t(.feedbackSourceFolderMissingAdvice)
            )
        }

        // 3. Insufficient disk space
        if errorDesc.localizedCaseInsensitiveContains("space") ||
           errorDesc.localizedCaseInsensitiveContains("No space left") ||
           (error as NSError).code == 28 {
            return (
                title: L10n.t(.feedbackDiskFullTitle),
                message: L10n.t(.feedbackDiskFullMessage),
                detailedReason: L10n.t(.feedbackDiskFullAdvice)
            )
        }

        // 4. macOS Full Disk Access or filesystem permission denied
        if errorDesc.localizedCaseInsensitiveContains("permission") ||
           errorDesc.localizedCaseInsensitiveContains("Permission denied") ||
           (error as NSError).code == 13 {
            return (
                title: L10n.t(.feedbackPermissionDeniedTitle),
                message: L10n.t(.feedbackPermissionDeniedMessage),
                detailedReason: L10n.t(.feedbackPermissionDeniedAdvice)
            )
        }

        // 5. General failure with calm, reassuring advice
        return (
            title: L10n.t(.feedbackGeneralErrorTitle),
            message: errorDesc,
            detailedReason: L10n.t(.feedbackGeneralErrorAdvice)
        )
    }

    public func performDryRun(mode: BackupMode = .incremental) {
        guard let profile = selectedProfile, !isBackupRunning(for: profile.id), !isDryRunRunning else { return }

        isDryRunRunning = true
        let modeTag = mode == .full ? " (FULL)" : " (Incremental)"
        LogManager.shared.log("Pre-backup analysis (Dry-Run\(modeTag)) started for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]", level: .info, category: "UI")
        refreshLogs()

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let summary = try await self.coordinator.performDryRun(profile: profile, mode: mode)
                Task { @MainActor in
                    self.isDryRunRunning = false
                    self.dryRunSummary = summary
                    self.showDryRunModal = true
                    LogManager.shared.log("Dry-Run completed for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: Added: \(summary.addedCount) files (\(summary.addedBytes) bytes), Modified: \(summary.modifiedCount) files (\(summary.modifiedBytes) bytes), Deleted: \(summary.deletedCount) files, Unmodified (CoW): \(summary.unmodifiedCount) files, Estimated new storage: \(summary.estimatedNewBytes) bytes.", level: .info, category: "UI")
                    self.refreshLogs()
                }
            } catch {
                Task { @MainActor in
                    self.isDryRunRunning = false
                    LogManager.shared.log("Dry-Run analysis failed for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: \(error.localizedDescription)", level: .error, category: "UI")
                    self.refreshLogs()
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Snapshot & File Tree Loading

    @MainActor
    public func loadSnapshots(force: Bool = false) {
        guard let profile = selectedProfile else {
            self.snapshots = []
            self.snapshotFiles = []
            self.snapshotTreeNodes = []
            self.timelinePaths = []
            self.timelineTreeNodes = []
            self.selectedPathVersions = []
            self.loadedProfileId = nil
            self.loadedSnapshotId = nil
            return
        }
        let dbPath = profile.destinationURL.appendingPathComponent(".otterkeep/manifest.sqlite").path(percentEncoded: false)

        let profileChanged = self.loadedProfileId != profile.id
        if profileChanged {
            self.loadedProfileId = profile.id
            self.loadedSnapshotId = nil
        }

        Task {
            do {
                try await database.open(at: dbPath)
                let list = try await database.listSnapshots()
                Task { @MainActor in
                    let snapshotsChanged = profileChanged || (self.snapshots.map(\.id) != list.map(\.id))
                    if snapshotsChanged || self.snapshots.isEmpty {
                        self.snapshots = list
                    }
                    if self.selectedSnapshotId == nil || !list.contains(where: { $0.id == self.selectedSnapshotId }) {
                        self.selectedSnapshotId = list.first?.id
                    }

                    // Only reload file tree if forced, snapshots list changed, tree is empty, or selected snapshot doesn't match loaded snapshot
                    if force || snapshotsChanged || self.snapshotTreeNodes.isEmpty || self.loadedSnapshotId != self.selectedSnapshotId {
                        self.loadFilesForSelectedSnapshot(force: force)
                        self.searchTimelinePaths(query: self.timelineSearchQuery, force: force)
                    }
                }
            } catch {
                Task { @MainActor in
                    self.snapshots = []
                    self.snapshotFiles = []
                    self.snapshotTreeNodes = []
                    self.timelinePaths = []
                    self.timelineTreeNodes = []
                    self.selectedPathVersions = []
                    self.loadedSnapshotId = nil
                }
            }
        }
    }

    @MainActor
    public func loadFilesForSelectedSnapshot(force: Bool = false) {
        guard let snapshotId = selectedSnapshotId else {
            self.snapshotFiles = []
            self.snapshotTreeNodes = []
            self.loadedSnapshotId = nil
            return
        }

        if !force && self.loadedSnapshotId == snapshotId && !self.snapshotTreeNodes.isEmpty {
            return
        }

        Task {
            do {
                let files = try await database.listFiles(forSnapshotId: snapshotId)
                let tree = FileTreeBuilder.buildTree(from: files)
                Task { @MainActor in
                    self.loadedSnapshotId = snapshotId
                    self.snapshotFiles = files
                    self.snapshotTreeNodes = tree
                    let previousSelectedPath = self.selectedFile?.relativePath
                    if let previousSelectedPath = previousSelectedPath,
                       let matching = files.first(where: { $0.relativePath == previousSelectedPath }) {
                        self.selectedFile = matching
                    } else if self.selectedFile == nil || !files.contains(where: { $0.id == self.selectedFile?.id }) {
                        self.selectedFile = files.first
                    }
                }
            } catch {
                Task { @MainActor in
                    self.snapshotFiles = []
                    self.snapshotTreeNodes = []
                    self.loadedSnapshotId = nil
                }
            }
        }
    }

    // MARK: - File Timeline Tree & Search

    @MainActor
    public func searchTimelinePaths(query: String, force: Bool = false) {
        if !force && self.timelineSearchQuery == query && !self.timelineTreeNodes.isEmpty {
            return
        }
        self.timelineSearchQuery = query
        Task {
            do {
                let paths = try await database.searchDistinctRelativePaths(matching: query)
                let tree = FileTreeBuilder.buildTree(from: paths)
                Task { @MainActor in
                    self.timelinePaths = paths
                    self.timelineTreeNodes = tree
                    if self.selectedTimelinePath == nil || !paths.contains(where: { $0 == self.selectedTimelinePath }) {
                        self.selectedTimelinePath = paths.first
                    }
                    if let path = self.selectedTimelinePath {
                        self.loadTimelineVersions(for: path)
                    } else {
                        self.selectedPathVersions = []
                        self.selectedTimelineVersion = nil
                    }
                }
            } catch {
                Task { @MainActor in
                    self.timelinePaths = []
                    self.timelineTreeNodes = []
                    self.selectedPathVersions = []
                    self.selectedTimelineVersion = nil
                }
            }
        }
    }

    @MainActor
    public func loadTimelineVersions(for relativePath: String) {
        self.selectedTimelinePath = relativePath
        Task {
            do {
                let versions = try await database.listVersions(ofRelativePath: relativePath)
                Task { @MainActor in
                    self.selectedPathVersions = versions
                    self.selectedTimelineVersion = versions.first
                }
            } catch {
                Task { @MainActor in
                    self.selectedPathVersions = []
                    self.selectedTimelineVersion = nil
                }
            }
        }
    }

    // MARK: - Cross-Snapshot Global Search

    @MainActor
    public func searchGlobalSnapshots(query: String) {
        self.globalSearchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.globalSearchResults = []
            self.selectedGlobalSearchResult = nil
            self.isGlobalSearching = false
            return
        }

        self.isGlobalSearching = true
        Task {
            do {
                let results = try await database.searchFilesAcrossSnapshots(query: trimmed, limit: 200)
                Task { @MainActor in
                    guard self.globalSearchQuery == query else { return }
                    self.globalSearchResults = results
                    self.selectedGlobalSearchResult = results.first
                    self.isGlobalSearching = false
                    self.updateQuickLookForCurrentSelection()
                }
            } catch {
                Task { @MainActor in
                    guard self.globalSearchQuery == query else { return }
                    self.globalSearchResults = []
                    self.selectedGlobalSearchResult = nil
                    self.isGlobalSearching = false
                }
            }
        }
    }

    @MainActor
    public func revealGlobalSearchResultInSnapshot(_ result: GlobalSearchResult) {
        self.restoreBrowseMode = .snapshot
        self.selectedSnapshotId = result.snapshotId
        self.loadFilesForSelectedSnapshot(force: true)
        self.selectedFile = result.fileRecord
        self.updateQuickLookForCurrentSelection()
    }

    @MainActor
    public func restoreGlobalSearchResult(
        _ result: GlobalSearchResult,
        to targetDirectory: URL,
        collision: CollisionResolution = .keepBoth
    ) {
        let fakeSnapshot = SnapshotRecord(
            id: result.snapshotId,
            timestamp: result.snapshotTimestamp,
            status: "completed",
            totalFiles: 0,
            totalBytes: 0,
            snapshotPath: result.snapshotPath,
            backupType: "incremental"
        )
        restoreVersion(snapshot: fakeSnapshot, file: result.fileRecord, to: targetDirectory, collision: collision)
    }

    // MARK: - Snapshot Diff Operations

    @MainActor
    public func loadSnapshotDiff(targetId: String? = nil, baseId: String? = nil) {
        guard let profile = selectedProfile else { return }
        let target = targetId ?? selectedSnapshotId ?? snapshots.first?.id
        guard let effectiveTarget = target else {
            self.snapshotDiffReport = nil
            return
        }

        self.selectedDiffTargetSnapshotId = effectiveTarget
        self.selectedDiffBaseSnapshotId = baseId
        self.isLoadingDiff = true

        Task {
            do {
                let dbPath = profile.destinationURL.appendingPathComponent(".otterkeep/manifest.sqlite").path
                try await self.database.open(at: dbPath)
                let report = try await SnapshotDiffEngine.shared.diff(
                    database: self.database,
                    targetSnapshotId: effectiveTarget,
                    baseSnapshotId: baseId
                )
                Task { @MainActor in
                    self.snapshotDiffReport = report
                    self.isLoadingDiff = false
                }
            } catch {
                Task { @MainActor in
                    self.snapshotDiffReport = nil
                    self.isLoadingDiff = false
                    LogManager.shared.log("Failed to compute snapshot diff: \(error.localizedDescription)", level: .warning, category: "Diff")
                }
            }
        }
    }

    @MainActor
    public func openSideBySideDiff(for item: SnapshotDiffItem) {
        guard let profile = selectedProfile else { return }
        self.activeSideBySideDiffItem = item
        self.showSideBySideDiffModal = true
        self.isLoadingSideBySideDiff = true
        self.activeSideBySideDiffComparison = nil

        let targetSnapId = selectedDiffTargetSnapshotId ?? snapshots.first?.id
        let baseSnapId = selectedDiffBaseSnapshotId ?? (snapshots.count > 1 ? snapshots[1].id : nil)

        guard let tId = targetSnapId, let bId = baseSnapId,
              let snapTarget = snapshots.first(where: { $0.id == tId }),
              let snapBase = snapshots.first(where: { $0.id == bId }) else {
            self.isLoadingSideBySideDiff = false
            return
        }

        let urlA = profile.destinationURL.appendingPathComponent(snapBase.snapshotPath).appendingPathComponent("root").appendingPathComponent(item.relativePath)
        let urlB = profile.destinationURL.appendingPathComponent(snapTarget.snapshotPath).appendingPathComponent("root").appendingPathComponent(item.relativePath)

        Task {
            let result = try? TextDiffEngine().diffFiles(leftURL: urlA, rightURL: urlB, relativePath: item.relativePath)
            Task { @MainActor in
                self.activeSideBySideDiffComparison = result
                self.isLoadingSideBySideDiff = false
            }
        }
    }

    @MainActor
    public func openSideBySideDiff(forGlobalSearchResult result: GlobalSearchResult) {
        guard let profile = selectedProfile else { return }

        let diffItem = SnapshotDiffItem(
            relativePath: result.relativePath,
            changeType: .modified,
            oldRecord: nil,
            newRecord: result.fileRecord,
            sizeDelta: 0
        )
        self.activeSideBySideDiffItem = diffItem
        self.showSideBySideDiffModal = true
        self.isLoadingSideBySideDiff = true
        self.activeSideBySideDiffComparison = nil

        Task {
            do {
                let dbPath = profile.destinationURL.appendingPathComponent(".otterkeep/manifest.sqlite").path
                try await self.database.open(at: dbPath)
                let versions = try await self.database.listVersions(ofRelativePath: result.relativePath)

                let targetSnap: SnapshotRecord
                let baseSnap: SnapshotRecord?

                if let idx = versions.firstIndex(where: { $0.snapshot.id == result.snapshotId }) {
                    targetSnap = versions[idx].snapshot
                    // The preceding historical version is idx + 1 (older)
                    if idx + 1 < versions.count {
                        baseSnap = versions[idx + 1].snapshot
                    } else if idx - 1 >= 0 {
                        // If it's the oldest snapshot, compare with the newer one
                        baseSnap = versions[idx - 1].snapshot
                    } else {
                        baseSnap = nil
                    }
                } else {
                    targetSnap = self.snapshots.first(where: { $0.id == result.snapshotId }) ?? SnapshotRecord(
                        id: result.snapshotId,
                        timestamp: result.snapshotTimestamp,
                        status: "completed",
                        totalFiles: 0,
                        totalBytes: result.fileSize,
                        snapshotPath: result.snapshotPath
                    )
                    baseSnap = versions.first(where: { $0.snapshot.id != result.snapshotId })?.snapshot
                }

                let urlTarget = profile.destinationURL
                    .appendingPathComponent(targetSnap.snapshotPath)
                    .appendingPathComponent("root")
                    .appendingPathComponent(result.relativePath)

                let urlBase: URL?
                if let base = baseSnap {
                    urlBase = profile.destinationURL
                        .appendingPathComponent(base.snapshotPath)
                        .appendingPathComponent("root")
                        .appendingPathComponent(result.relativePath)
                } else {
                    urlBase = nil
                }

                let comparison = try TextDiffEngine().diffFiles(
                    leftURL: urlBase,
                    rightURL: urlTarget,
                    relativePath: result.relativePath
                )

                Task { @MainActor in
                    self.activeSideBySideDiffComparison = comparison
                    self.isLoadingSideBySideDiff = false
                }
            } catch {
                Task { @MainActor in
                    self.isLoadingSideBySideDiff = false
                }
            }
        }
    }

    @MainActor
    public func openSideBySideDiff(forFileRecord record: FileCatalogRecord, inSnapshotId snapshotId: String) {
        guard selectedProfile != nil else { return }
        let snap = snapshots.first(where: { $0.id == snapshotId })
        let hit = GlobalSearchResult(
            snapshotId: snapshotId,
            snapshotTimestamp: snap?.timestamp ?? record.modificationTime,
            snapshotPath: snap?.snapshotPath ?? snapshotId,
            relativePath: record.relativePath,
            fileSize: record.fileSize,
            modificationDate: record.modificationTime,
            sha256: record.checksum ?? ""
        )
        openSideBySideDiff(forGlobalSearchResult: hit)
    }

    // MARK: - Data Integrity Scrubber Operations (1.5.0)

    @MainActor
    public func performManualScrub(profile: BackupProfile? = nil) {
        guard !isDataScrubInProgress else { return }

        let targetProfile = profile ?? selectedProfile
        guard let prof = targetProfile else { return }

        isDataScrubInProgress = true
        scrubProgress = ScrubRunProgress()
        LogManager.shared.log("Starting manual data integrity scrub for profile '\(prof.name)'", level: .info, category: "Integrity")
        refreshLogs()

        Task.detached(priority: .background) {
            let scrubber = DataScrubberEngine()
            do {
                let audit = try await scrubber.performScrub(
                    backupRootURL: prof.destinationURL,
                    limitSnapshots: nil,
                    throttleSleepMs: 0
                ) { progress in
                    Task { @MainActor in
                        self.scrubProgress = progress
                    }
                }

                await MainActor.run {
                    self.isDataScrubInProgress = false
                    self.scrubProgress = nil
                    self.refreshLogs()

                    if audit.corruptedFilesCount == 0 {
                        self.activeFeedback = OperationFeedback(
                            type: .success,
                            title: L10n.t(.scrubSuccessTitle),
                            message: L10n.format(.scrubSuccessMessage, prof.name, Int64(audit.checkedSnapshotsCount), Int64(audit.checkedFilesCount)),
                            profileName: prof.name
                        )
                    } else {
                        self.activeFeedback = OperationFeedback(
                            type: .failure,
                            title: L10n.t(.scrubCorruptedTitle),
                            message: L10n.format(.scrubCorruptedMessage, prof.name, Int64(audit.corruptedFilesCount)),
                            detailedReason: audit.detailsJson,
                            profileName: prof.name
                        )
                    }
                    self.showFeedbackModal = true
                }
            } catch {
                await MainActor.run {
                    self.isDataScrubInProgress = false
                    self.scrubProgress = nil
                    self.refreshLogs()
                    self.activeFeedback = OperationFeedback(
                        type: .failure,
                        title: L10n.t(.scrubberCorruptedAlertTitle),
                        message: error.localizedDescription,
                        detailedReason: error.localizedDescription,
                        profileName: prof.name
                    )
                    self.showFeedbackModal = true
                }
            }
        }
    }

    // MARK: - Storage Forecast Operations

    @MainActor
    public func refreshStorageForecast() {
        guard let profile = selectedProfile else {
            self.storageForecastReport = nil
            return
        }
        self.isLoadingForecast = true
        Task {
            do {
                let dbPath = profile.destinationURL.appendingPathComponent(".otterkeep/manifest.sqlite").path
                try await self.database.open(at: dbPath)
                let forecast = try await StorageForecastEngine.shared.evaluateForecast(
                    profile: profile,
                    database: self.database
                )
                Task { @MainActor in
                    self.storageForecastReport = forecast
                    self.isLoadingForecast = false
                }
            } catch {
                Task { @MainActor in
                    self.storageForecastReport = nil
                    self.isLoadingForecast = false
                }
            }
        }
    }

    // MARK: - Webhook Testing

    @MainActor
    public func testWebhook(config: WebhookConfiguration) {
        self.webhookTestingStatus = (true, nil, false)
        Task {
            do {
                _ = try await WebhookDispatcher.shared.sendTestWebhook(config: config)
                Task { @MainActor in
                    self.webhookTestingStatus = (false, L10n.t(.webhookTestSuccess), true)
                }
            } catch {
                Task { @MainActor in
                    self.webhookTestingStatus = (false, L10n.format(.webhookTestFailedFormat, error.localizedDescription), false)
                }
            }
        }
    }

    // MARK: - Restore Operations


    @MainActor
    public func restoreVersion(
        snapshot: SnapshotRecord,
        file: FileCatalogRecord,
        to targetDirectory: URL,
        collision: CollisionResolution = .keepBoth
    ) {
        guard let profile = selectedProfile else { return }

        Task {
            do {
                let dest = try await restoreEngine.restore(
                    snapshotPath: snapshot.snapshotPath,
                    backupRootURL: profile.destinationURL,
                    relativePath: file.relativePath,
                    targetDirectoryURL: targetDirectory,
                    collisionResolution: collision
                )
                Task { @MainActor in
                    LogManager.shared.log("File restored successfully: '\(dest.path)' from snapshot '\(snapshot.id)' (Collision mode: \(collision))", level: .info, category: "Restore")
                    self.refreshLogs()
                    NotificationDeliveryService.shared.notifyRestoreCompleted(fileName: dest.lastPathComponent, profileName: profile.name)
                    self.showSuccess(L10n.format(.restoreSuccessMessage, dest.path))
                }
            } catch {
                Task { @MainActor in
                    LogManager.shared.log("Restore failed for target '\(targetDirectory.path)' [File: \(file.relativePath)]: \(error.localizedDescription)", level: .error, category: "Restore")
                    self.refreshLogs()
                    NotificationDeliveryService.shared.notifyRestoreFailed(fileName: file.relativePath, errorMessage: error.localizedDescription)
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    /// Restores the entire contents of a snapshot to a target directory.
    @MainActor
    public func restoreEntireSnapshot(
        snapshot: SnapshotRecord,
        to targetDirectory: URL,
        collision: CollisionResolution = .keepBoth
    ) {
        guard let profile = selectedProfile else { return }

        self.isSnapshotRestoreInProgress = true
        self.snapshotRestoreProgress = RestoreProgressState(
            phase: .preparing,
            totalFiles: Int(snapshot.totalFiles),
            processedFiles: 0,
            totalBytes: snapshot.totalBytes,
            processedBytes: 0,
            currentItem: ""
        )

        Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await restoreEngine.restoreSnapshot(
                    snapshotPath: snapshot.snapshotPath,
                    backupRootURL: profile.destinationURL,
                    targetDirectoryURL: targetDirectory,
                    collisionResolution: collision,
                    progress: { [weak self] progressState in
                        Task { @MainActor in
                            self?.snapshotRestoreProgress = progressState
                        }
                    }
                )

                Task { @MainActor in
                    self.isSnapshotRestoreInProgress = false
                    self.snapshotRestoreProgress = nil
                    LogManager.shared.log("Entire snapshot '\(snapshot.id)' restored successfully to '\(targetDirectory.path)' (\(summary.restoredFiles) files, \(summary.restoredBytes) bytes, \(String(format: "%.2f", summary.durationSeconds))s)", level: .info, category: "Restore")
                    self.refreshLogs()
                    NotificationDeliveryService.shared.notifyRestoreCompleted(fileName: snapshot.snapshotPath, profileName: profile.name)

                    // Trigger Operation Feedback Modal with Ottie mascot
                    self.activeFeedback = OperationFeedback(
                        type: .success,
                        title: L10n.t(.feedbackRestoreSuccessTitle),
                        message: L10n.format(.feedbackRestoreSuccessMessage, snapshot.snapshotPath, Int64(summary.restoredFiles)),
                        profileName: profile.name,
                        restoreSummary: summary
                    )
                    self.showFeedbackModal = true
                }
            } catch {
                Task { @MainActor in
                    self.isSnapshotRestoreInProgress = false
                    self.snapshotRestoreProgress = nil
                    LogManager.shared.log("Entire snapshot restore failed for '\(snapshot.id)': \(error.localizedDescription)", level: .error, category: "Restore")
                    self.refreshLogs()
                    NotificationDeliveryService.shared.notifyRestoreFailed(fileName: snapshot.snapshotPath, errorMessage: error.localizedDescription)

                    // Trigger Operation Feedback Modal with Ottie reassurance
                    self.activeFeedback = OperationFeedback(
                        type: .failure,
                        title: L10n.t(.feedbackRestoreFailedTitle),
                        message: L10n.format(.feedbackRestoreFailedMessage, error.localizedDescription),
                        detailedReason: error.localizedDescription,
                        profileName: profile.name
                    )
                    self.showFeedbackModal = true
                }
            }
        }
    }

    // MARK: - Direct File Version History & Finder In-Place Restore

    @MainActor
    public func openVersionHistory(for fileURL: URL) {
        let stdURL = fileURL.standardizedFileURL
        let fullPath = stdURL.path(percentEncoded: false)

        // Prevent duplicate presentation if modal is already open for this exact file
        if showFileVersionHistoryModal && activeVersionHistoryFile == stdURL {
            return
        }

        // Find which profile contains this file within its sourceURL (checking both active and persistent profiles)
        guard let matchingProfile = profiles.first(where: { $0.containsPath(fullPath) }) ?? ProfileStore.shared.loadProfiles().first(where: { $0.containsPath(fullPath) }) else {
            LogManager.shared.log("Requested version history for file not covered by any profile: '\(fullPath)'", level: .warning, category: "FinderSync")
            refreshLogs()
            showError(L10n.t(.fileNotUnderAnyProfile))
            return
        }

        guard let relPath = matchingProfile.relativePath(for: fullPath), !relPath.isEmpty else {
            LogManager.shared.log("Selected path is the root source directory: '\(fullPath)'", level: .info, category: "FinderSync")
            return
        }

        self.activeVersionHistoryFile = stdURL
        self.activeVersionHistoryProfile = matchingProfile
        self.isLoadingFileVersions = true
        self.activeVersionHistoryRecords = []
        self.selectedFileVersionHistoryRecord = nil
        self.showFileVersionHistoryModal = true

        let dbPath = matchingProfile.destinationURL.appendingPathComponent(".otterkeep").appendingPathComponent("manifest.sqlite").path(percentEncoded: false)

        Task {
            do {
                try await database.open(at: dbPath)
                let versions = try await database.listVersions(ofRelativePath: relPath)
                // Race condition safeguard: ensure active file hasn't changed while awaiting database
                guard self.activeVersionHistoryFile == stdURL else { return }
                self.activeVersionHistoryRecords = versions
                self.selectedFileVersionHistoryRecord = versions.first
                self.isLoadingFileVersions = false
                LogManager.shared.log("Loaded \(versions.count) historical versions for '\(relPath)' from profile '\(matchingProfile.name)'", level: .info, category: "FinderSync")
                self.refreshLogs()
            } catch {
                guard self.activeVersionHistoryFile == stdURL else { return }
                self.isLoadingFileVersions = false
                self.activeVersionHistoryRecords = []
                self.selectedFileVersionHistoryRecord = nil
                LogManager.shared.log("Failed to load versions for '\(relPath)': \(error.localizedDescription)", level: .error, category: "FinderSync")
                self.refreshLogs()
            }
        }
    }

    @MainActor
    public func restoreFileInPlace(
        version: (snapshot: SnapshotRecord, file: FileCatalogRecord),
        collision: CollisionResolution = .overwrite
    ) {
        guard let targetURL = activeVersionHistoryFile,
              let profile = activeVersionHistoryProfile else { return }

        Task {
            do {
                let finalURL = try await restoreEngine.restoreToFile(
                    snapshotPath: version.snapshot.snapshotPath,
                    backupRootURL: profile.destinationURL,
                    relativePath: version.file.relativePath,
                    destinationFileURL: targetURL,
                    collisionResolution: collision
                )

                let finalPath = finalURL.path(percentEncoded: false)
                LogManager.shared.log("In-place file restoration completed: '\(finalPath)' from snapshot '\(version.snapshot.id)' (Collision: \(collision))", level: .info, category: "Restore")
                NotificationDeliveryService.shared.notifyRestoreCompleted(
                    fileName: targetURL.lastPathComponent,
                    profileName: profile.name
                )
                self.refreshLogs()
                self.showFileVersionHistoryModal = false
                self.showSuccess(L10n.format(.restoreSuccessMessage, finalPath))
            } catch {
                let targetPath = targetURL.path(percentEncoded: false)
                LogManager.shared.log("In-place file restoration failed for '\(targetPath)': \(error.localizedDescription)", level: .error, category: "Restore")
                NotificationDeliveryService.shared.notifyRestoreFailed(
                    fileName: targetURL.lastPathComponent,
                    errorMessage: error.localizedDescription
                )
                self.refreshLogs()
                self.showError(error.localizedDescription)
            }
        }
    }

    @MainActor
    public func urlForVersionHistoryRecord(_ record: (snapshot: SnapshotRecord, file: FileCatalogRecord)) -> URL? {
        guard let profile = activeVersionHistoryProfile else { return nil }
        return profile.destinationURL
            .appendingPathComponent(record.snapshot.snapshotPath)
            .appendingPathComponent("root")
            .appendingPathComponent(record.file.relativePath)
    }

    @MainActor
    public func toggleQuickLook() {
        guard let url = currentSelectedFileURL() else {
            quickLookURL = nil
            QuickLookCoordinator.shared.closeQuickLook()
            return
        }
        self.quickLookURL = url
        QuickLookCoordinator.shared.toggleQuickLook(for: url)
    }

    @MainActor
    public func updateQuickLookForCurrentSelection() {
        let url = currentSelectedFileURL()
        self.quickLookURL = url
        if QuickLookCoordinator.shared.isVisible {
            QuickLookCoordinator.shared.updateSelection(url: url)
        }
    }

    @MainActor
    public func loadTimeline(for path: String) {
        loadTimelineVersions(for: path)
    }

    @MainActor
    public func currentSelectedFileURL() -> URL? {
        guard let profile = selectedProfile else { return nil }
        let candidateURL: URL?
        if restoreBrowseMode == .snapshot {
            guard let snapId = selectedSnapshotId,
                  let snap = snapshots.first(where: { $0.id == snapId }),
                  let file = selectedFile else { return nil }
            candidateURL = profile.destinationURL
                .appendingPathComponent(snap.snapshotPath)
                .appendingPathComponent("root")
                .appendingPathComponent(file.relativePath)
        } else {
            guard let result = selectedGlobalSearchResult else { return nil }
            candidateURL = profile.destinationURL
                .appendingPathComponent(result.snapshotPath)
                .appendingPathComponent("root")
                .appendingPathComponent(result.fileRecord.relativePath)
        }

        guard let url = candidateURL else { return nil }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir) {
            return url
        }
        return url
    }

    // MARK: - Maintenance & Housekeeping

    @MainActor
    public func pruneOldSnapshots(maxKeep: Int) {
        guard let profile = selectedProfile else { return }

        Task {
            do {
                let policy = PruningPolicy(isAutoPruningEnabled: profile.pruningPolicy.isAutoPruningEnabled, maxSnapshotsToKeep: maxKeep, keepDailyDays: 30)
                let deletedIds = try await retentionManager.applyRetentionPolicy(destinationURL: profile.destinationURL, policy: policy)

                Task { @MainActor in
                    LogManager.shared.log("Retention pruning completed for profile '\(profile.name)': \(deletedIds.count) snapshots pruned. Pruned IDs: [\(deletedIds.joined(separator: ", "))]", level: .info, category: "Retention")
                    self.refreshLogs()
                    self.loadSnapshots()
                    self.showSuccess(L10n.format(.maintenancePruneSuccessMessage, deletedIds.count))
                }
            } catch {
                Task { @MainActor in
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    public func disasterRebuildCatalog() {
        guard let profile = selectedProfile else { return }

        Task {
            do {
                let count = try await restoreEngine.rebuildCatalog(at: profile.destinationURL)
                Task { @MainActor in
                    LogManager.shared.log("Disaster recovery catalog rebuilt for profile '\(profile.name)': \(count) snapshots indexed from target disk", level: .info, category: "Rebuild")
                    self.refreshLogs()
                    self.loadSnapshots()
                    self.showSuccess(L10n.format(.maintenanceRebuildSuccessMessage, count))
                }
            } catch {
                Task { @MainActor in
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Diagnostics

    @MainActor
    public func refreshLogs() {
        self.logEntries = LogManager.shared.getEntries().reversed()
        self.currentDebugLogFileURL = LogManager.shared.currentDebugLogFileURL
        self.isDebugFileLoggingEnabled = LogManager.shared.isDebugFileLoggingEnabled
    }

    @MainActor
    public func exportLogs(to destinationURL: URL) {
        do {
            let logText = LogManager.shared.exportLogsAsPlainText()
            try logText.data(using: .utf8)?.write(to: destinationURL)
            showSuccess(L10n.format(.logExportSuccess, destinationURL.lastPathComponent))
        } catch {
            showError(L10n.format(.logExportError, error.localizedDescription))
        }
    }

    @MainActor
    public func clearLogs() {
        LogManager.shared.clear()
        refreshLogs()
    }

    @MainActor
    public func copyDebugLogPath() {
        if let path = currentDebugLogFileURL?.path(percentEncoded: false) ?? LogManager.shared.currentDebugLogFileURL?.path(percentEncoded: false) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
            showSuccess(L10n.t(.settingsDebugCopySuccess))
        }
    }

    // MARK: - Helpers

    @MainActor
    public func showError(_ message: String) {
        self.alertMessage = message
        self.showAlert = true
    }

    @MainActor
    public func showSuccess(_ message: String) {
        self.alertMessage = message
        self.showAlert = true
    }

    // MARK: - Photos Backup Operations

    @MainActor
    public func checkPhotosAuthorization() {
        self.photosAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    @MainActor
    public func requestPhotosAuthorization() {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            Task { @MainActor in
                self.photosAuthorizationStatus = status
                if status == .authorized || status == .limited {
                    self.refreshPhotosLibraryStats()
                }
            }
        }
    }

    @MainActor
    public func refreshPhotosLibraryStats() {
        guard photosAuthorizationStatus == .authorized || photosAuthorizationStatus == .limited else { return }
        self.isScanningPhotosLibrary = true
        Task.detached {
            let fetchOptions = PHFetchOptions()
            fetchOptions.includeHiddenAssets = false
            let count = PHAsset.fetchAssets(with: fetchOptions).count
            Task { @MainActor in
                self.photosLibraryTotalCount = count
                self.isScanningPhotosLibrary = false
            }
        }
    }

    @MainActor
    public func savePhotosConfig() {
        try? PhotosProfileStore.shared.saveConfiguration(self.photosConfig)
    }

    @MainActor
    public func startPhotosBackup() {
        guard !isPhotosBackupRunning else { return }
        self.isPhotosBackupRunning = true
        self.photosProgressState = PhotosBackupProgressState()
        self.photosProgressState.isRunning = true

        savePhotosConfig()

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let summary = try await self.photosCoordinator.executeBackup(configuration: self.photosConfig) { [weak self] progress in
                    Task { @MainActor in
                        self?.photosProgressState = progress
                    }
                }

                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isPhotosBackupRunning = false
                    self.lastPhotosSessionSummary = summary
                    self.photosConfig.schedule.lastRunDate = Date()
                    self.savePhotosConfig()
                    NotificationDeliveryService.shared.notifyPhotosBackupCompleted(
                        copiedCount: summary.newDownloadedCount + summary.reflinkClonedCount,
                        durationSec: summary.durationSeconds
                    )
                    LogManager.shared.log("Photos backup finished successfully: \(summary.newDownloadedCount) downloaded, \(summary.reflinkClonedCount) cloned", level: .info, category: "Photos")
                    self.refreshLogs()
                    self.loadPhotosSnapshots()
                }
            } catch {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isPhotosBackupRunning = false
                    self.photosProgressState.isRunning = false
                    NotificationDeliveryService.shared.notifyPhotosBackupFailed(
                        errorMessage: error.localizedDescription
                    )
                    LogManager.shared.log("Photos backup error: \(error.localizedDescription)", level: .error, category: "Photos")
                    self.refreshLogs()
                    self.showError("Photos backup error: \(error.localizedDescription)")
                }
            }
        }
    }

    @MainActor
    public func cancelPhotosBackup() {
        Task {
            await photosCoordinator.cancel()
            Task { @MainActor in
                self.isPhotosBackupRunning = false
                self.photosProgressState.isRunning = false
            }
        }
    }

    private func photosDatabasePath(for destURL: URL) -> String? {
        let unifiedPath = destURL.appendingPathComponent(".otterkeep/manifest.sqlite").path(percentEncoded: false)
        if FileManager.default.fileExists(atPath: unifiedPath) {
            return unifiedPath
        }
        let legacyPath = destURL.appendingPathComponent(".otterkeep_catalog.sqlite").path(percentEncoded: false)
        if FileManager.default.fileExists(atPath: legacyPath) {
            return legacyPath
        }
        return nil
    }

    @MainActor
    public func loadPhotosSnapshots(force: Bool = false) {
        let destURL = photosConfig.destinationURL
        guard let dbPath = photosDatabasePath(for: destURL) else {
            self.photosSnapshots = []
            self.loadedPhotosSnapshotId = nil
            return
        }

        Task {
            do {
                try await database.open(at: dbPath)
                let snaps = try await database.fetchSnapshots()
                Task { @MainActor in
                    let snapsChanged = self.photosSnapshots.map(\.id) != snaps.map(\.id)
                    if snapsChanged || self.photosSnapshots.isEmpty {
                        self.photosSnapshots = snaps
                    }
                    if self.selectedPhotosSnapshotId == nil || !snaps.contains(where: { $0.id == self.selectedPhotosSnapshotId }) {
                        self.selectedPhotosSnapshotId = snaps.first?.id
                    }
                    if let selId = self.selectedPhotosSnapshotId {
                        if force || snapsChanged || self.photosAssets.isEmpty || self.loadedPhotosSnapshotId != selId {
                            self.loadPhotosAssets(for: selId, force: force)
                        }
                    }
                }
            } catch {
                Task { @MainActor in
                    self.photosSnapshots = []
                    self.loadedPhotosSnapshotId = nil
                }
            }
        }
    }

    @MainActor
    public func selectPhotosSnapshot(id: String) {
        self.selectedPhotosSnapshotId = id
        loadPhotosAssets(for: id, force: true)
    }

    @MainActor
    public func loadPhotosAssets(for snapshotId: String, force: Bool = false) {
        if !force && self.loadedPhotosSnapshotId == snapshotId && !self.photosAssets.isEmpty {
            return
        }
        let destURL = photosConfig.destinationURL
        guard let dbPath = photosDatabasePath(for: destURL) else { return }

        Task {
            do {
                try await database.open(at: dbPath)
                let assets = try await database.fetchPhotosAssetRecords(for: snapshotId)
                Task { @MainActor in
                    self.loadedPhotosSnapshotId = snapshotId
                    self.photosAssets = assets
                    let prevLocalId = self.selectedPhotosAsset?.localIdentifier
                    if let prevLocalId = prevLocalId,
                       let matching = assets.first(where: { $0.localIdentifier == prevLocalId }) {
                        self.selectedPhotosAsset = matching
                    } else if self.selectedPhotosAsset == nil || !assets.contains(where: { $0.id == self.selectedPhotosAsset?.id }) {
                        self.selectedPhotosAsset = assets.first
                    }
                }
            } catch {
                Task { @MainActor in
                    self.photosAssets = []
                    self.loadedPhotosSnapshotId = nil
                }
            }
        }
    }

    @MainActor
    public func revealPhotosAssetInFinder(_ asset: PhotosAssetRecord) {
        let fileURL = photosConfig.destinationURL.appendingPathComponent(asset.relativePath)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([photosConfig.destinationURL])
        }
    }

    // MARK: - Configuration Export & Import

    /// Programmatically exports all profiles, settings, and photos configuration to a specified URL.
    @MainActor
    public func exportConfiguration(to url: URL) throws {
        try ProfileStore.shared.exportConfiguration(
            to: url,
            profiles: self.profiles,
            settings: LocalizationManager.shared.settings,
            photosConfig: self.photosConfig
        )
        LogManager.shared.log("Configuration exported successfully to: '\(url.path)'", level: .info, category: "Config")
        refreshLogs()
    }

    /// Programmatically imports configuration archive from a specified URL.
    @MainActor
    public func importConfiguration(from url: URL) throws {
        let archive = try ProfileStore.shared.importConfiguration(from: url)
        self.profiles = archive.profiles
        if let firstId = archive.profiles.first?.id {
            self.selectedProfileId = firstId
            self.activeNavigation = .profile(firstId)
        }
        self.currentTheme = archive.settings.themeMode
        self.currentLanguage = archive.settings.language
        self.launchAtLoginEnabled = archive.settings.launchAtLogin
        self.startMinimized = archive.settings.startMinimized
        self.isDebugFileLoggingEnabled = archive.settings.debugFileLoggingEnabled
        self.isFinderIntegrationEnabled = archive.settings.finderIntegrationEnabled
        if let photos = archive.photosConfig {
            self.photosConfig = photos
        }
        refreshVolumeEvaluation()
        loadSnapshots(force: true)
        loadPhotosSnapshots(force: true)
        LogManager.shared.log("Configuration imported successfully from: '\(url.path)' (\(archive.profiles.count) profile(s))", level: .info, category: "Config")
        refreshLogs()
    }

    /// Interactive NSSavePanel prompt for exporting configuration to JSON.
    @MainActor
    public func exportConfiguration() {
        let panel = NSSavePanel()
        panel.title = L10n.t(.exportConfigTitle)
        panel.prompt = L10n.t(.save)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        panel.nameFieldStringValue = "OtterKeep-Config-\(dateStr).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        let targetWindow = NSApp.keyWindow?.attachedSheet ?? NSApp.keyWindow ?? NSApp.mainWindow

        let runExport: (URL) -> Void = { [weak self] url in
            guard let self = self else { return }
            do {
                try self.exportConfiguration(to: url)
                self.showSuccess(L10n.t(.exportConfigSuccessMessage))
            } catch {
                self.showError(L10n.format(.exportConfigErrorMessage, error.localizedDescription))
            }
        }

        if let window = targetWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url {
                    runExport(url)
                }
            }
        } else {
            if panel.runModal() == .OK, let url = panel.url {
                runExport(url)
            }
        }
    }

    /// Interactive NSOpenPanel prompt for importing configuration from JSON.
    @MainActor
    public func importConfiguration() {
        let panel = NSOpenPanel()
        panel.title = L10n.t(.importConfigTitle)
        panel.prompt = L10n.t(.confirm)
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        let targetWindow = NSApp.keyWindow?.attachedSheet ?? NSApp.keyWindow ?? NSApp.mainWindow

        let runImport: (URL) -> Void = { [weak self] url in
            guard let self = self else { return }
            do {
                try self.importConfiguration(from: url)
                self.showSuccess(L10n.t(.importConfigSuccessMessage))
            } catch {
                self.showError(L10n.format(.importConfigErrorMessage, error.localizedDescription))
            }
        }

        if let window = targetWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url {
                    runImport(url)
                }
            }
        } else {
            if panel.runModal() == .OK, let url = panel.url {
                runImport(url)
            }
        }
    }
}
