import Foundation

/// Supported user interface application languages.
public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    /// Follows the operating system's preferred language settings.
    case system = "system"
    /// Hungarian language.
    case hungarian = "hu"
    /// English language.
    case english = "en"

    /// Localized display name for language selection menus.
    public var displayName: String {
        switch self {
        case .system:
            let osIsHu = Locale.preferredLanguages.first?.hasPrefix("hu") ?? false
            return osIsHu ? "Rendszer nyelve (Magyar)" : "System Default (English)"
        case .hungarian:
            return "Magyar (Hungarian)"
        case .english:
            return "English"
        }
    }
}

/// Persistent user settings configuration.
public struct AppSettings: Codable, Sendable, Equatable {
    /// Selected interface language.
    public var language: AppLanguage
    /// Whether the application is configured to launch automatically at login.
    public var launchAtLogin: Bool
    /// Whether the application should start minimized with only the menu bar icon visible.
    public var startMinimized: Bool
    /// Whether debug diagnostic file logging (.log) is enabled.
    public var debugFileLoggingEnabled: Bool
    /// Whether Finder context menu integration is enabled.
    public var finderIntegrationEnabled: Bool
    /// Selected application theme appearance mode.
    public var themeMode: AppThemeMode

    /// Initializes an `AppSettings` record.
    /// - Parameters:
    ///   - language: Selected language (default: `.system`).
    ///   - launchAtLogin: Whether Launch at Login is enabled (default: `false`).
    ///   - startMinimized: Whether the app starts minimized to menu bar (default: `false`).
    ///   - debugFileLoggingEnabled: Whether debug file logging is enabled (default: `false`).
    ///   - finderIntegrationEnabled: Whether Finder integration is enabled (default: `true`).
    ///   - themeMode: Selected appearance theme (default: `.system`).
    public init(
        language: AppLanguage = .system,
        launchAtLogin: Bool = false,
        startMinimized: Bool = false,
        debugFileLoggingEnabled: Bool = false,
        finderIntegrationEnabled: Bool = true,
        themeMode: AppThemeMode = .system
    ) {
        self.language = language
        self.launchAtLogin = launchAtLogin
        self.startMinimized = startMinimized
        self.debugFileLoggingEnabled = debugFileLoggingEnabled
        self.finderIntegrationEnabled = finderIntegrationEnabled
        self.themeMode = themeMode
    }

    enum CodingKeys: String, CodingKey {
        case language
        case launchAtLogin
        case startMinimized
        case debugFileLoggingEnabled
        case finderIntegrationEnabled
        case themeMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.startMinimized = try container.decodeIfPresent(Bool.self, forKey: .startMinimized) ?? false
        self.debugFileLoggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .debugFileLoggingEnabled) ?? false
        self.finderIntegrationEnabled = try container.decodeIfPresent(Bool.self, forKey: .finderIntegrationEnabled) ?? true
        self.themeMode = try container.decodeIfPresent(AppThemeMode.self, forKey: .themeMode) ?? .system
    }
}

/// Thread-safe manager handling user preferences and language selection persisted in `~/.otterkeep/settings.json`.
public final class LocalizationManager: @unchecked Sendable {
    /// Shared singleton instance.
    public static let shared = LocalizationManager()

    private let lock = NSLock()
    private let fileManager = FileManager.default

    /// Real user home directory URL resolved via POSIX getpwuid to avoid sandbox redirection discrepancies.
    public var realUserHome: URL {
        if let pw = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
        }
        return fileManager.homeDirectoryForCurrentUser
    }

    /// URL to the `settings.json` file.
    public var settingsFileURL: URL {
        realUserHome.appendingPathComponent(".otterkeep/settings.json")
    }

    /// Sandboxed container settings JSON path.
    public var containerSettingsFileURL: URL {
        realUserHome.appendingPathComponent("Library/Containers/com.otterkeep.OtterKeepApp.FinderSync/Data/.otterkeep/settings.json")
    }

    private var currentSettings: AppSettings

    private init() {
        let home: URL
        if let pw = getpwuid(getuid()) {
            home = URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
        }

        var loaded: AppSettings?
        let candidateURLs = [
            home.appendingPathComponent(".otterkeep/settings.json"),
            home.appendingPathComponent("Library/Containers/com.otterkeep.OtterKeepApp.FinderSync/Data/.otterkeep/settings.json"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".otterkeep/settings.json")
        ]

        for url in candidateURLs {
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
                loaded = decoded
                break
            }
        }
        self.currentSettings = loaded ?? AppSettings()
    }

    /// Gets or sets current application settings thread-safely.
    public var settings: AppSettings {
        get {
            lock.lock()
            defer { lock.unlock() }
            return currentSettings
        }
        set {
            lock.lock()
            currentSettings = newValue
            saveSettingsUnlocked()
            lock.unlock()
        }
    }

    /// Gets or sets the configured application language.
    public var currentLanguage: AppLanguage {
        get { settings.language }
        set {
            lock.lock()
            currentSettings.language = newValue
            saveSettingsUnlocked()
            lock.unlock()
        }
    }

    /// Gets or sets the configured application theme appearance mode.
    public var currentTheme: AppThemeMode {
        get { settings.themeMode }
        set {
            lock.lock()
            currentSettings.themeMode = newValue
            saveSettingsUnlocked()
            lock.unlock()
        }
    }

    /// Gets or sets whether the application starts minimized with only the menu bar icon visible.
    public var startMinimized: Bool {
        get { settings.startMinimized }
        set {
            lock.lock()
            currentSettings.startMinimized = newValue
            saveSettingsUnlocked()
            lock.unlock()
        }
    }

    /// Resolves the effective active language, resolving `.system` to either `.hungarian` or `.english`.
    public var effectiveLanguage: AppLanguage {
        let lang = currentLanguage
        if lang != .system { return lang }
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        return preferred.hasPrefix("hu") ? .hungarian : .english
    }

    private func saveSettingsUnlocked() {
        let dir = settingsFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(currentSettings) {
            try? data.write(to: settingsFileURL, options: .atomic)

            let containerDir = containerSettingsFileURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: containerDir.path) {
                try? fileManager.createDirectory(at: containerDir, withIntermediateDirectories: true)
            }
            try? data.write(to: containerSettingsFileURL, options: .atomic)
        }
    }
}

/// Type-safe, extensible localization system providing compile-time verified string resources.
public enum L10n {
    /// Retrieves the localized string for a given key on the active or specified language.
    /// - Parameters:
    ///   - key: Localization key.
    ///   - lang: Optional explicit language override.
    /// - Returns: Localized text.
    public static func t(_ key: Key, lang: AppLanguage? = nil) -> String {
        let activeLang = lang ?? LocalizationManager.shared.effectiveLanguage
        if let translation = translations[activeLang]?[key] {
            return translation
        }
        // Fallback: English -> Raw key
        return translations[.english]?[key] ?? key.rawValue
    }

    /// Checks whether an explicit translation entry exists for the given key in the specified language.
    public static func hasExplicitTranslation(for key: Key, in lang: AppLanguage) -> Bool {
        guard let langDict = translations[lang] else { return false }
        return langDict[key] != nil
    }

    /// Formats a localized string template with variadic format arguments.
    /// - Parameters:
    ///   - key: Localization key.
    ///   - args: Format arguments.
    ///   - lang: Optional explicit language override.
    /// - Returns: Formatted localized text.
    public static func format(_ key: Key, _ args: CVarArg..., lang: AppLanguage? = nil) -> String {
        let formatString = t(key, lang: lang)
        return String(format: formatString, locale: Locale.current, arguments: args)
    }

    /// Enumeration of all localized UI and CLI string keys.
    public enum Key: String, Sendable, CaseIterable {
        // MARK: - Navigation
        case navDashboard
        case navProfileRules
        case navPhotosBackup
        case navPhotosSnapshots
        case navRestore
        case navMaintenance
        case navLogs
        case navSettings

        // MARK: - General Actions & Common
        case cancel
        case create
        case save
        case delete
        case confirm
        case details
        case searchPlaceholder
        case okDone
        case unitCountFormat
        case filesCountUnit

        // MARK: - Profiles
        case defaultProfileName
        case profilesMenuTitle
        case activeProfileLabel
        case newProfileButton
        case renameProfileButton
        case deleteProfileButton
        case newProfileSheetTitle
        case newProfileSheetPrompt
        case renameProfileSheetTitle
        case renameProfileSheetPrompt
        case deleteProfileConfirmTitle
        case deleteProfileConfirmMessage
        case selectSourceFolder
        case selectDestinationFolder
        case selectFolderConfirm
        case browseButton
        case newProfileSourceDesc
        case newProfileDestinationDesc
        case newProfileNamePlaceholder
        case invalidFolderSelectionTitle
        case invalidFolderSelectionMessage

        // MARK: - Dashboard
        case dashboardHeroSubtitle
        case startBackupButton
        case backupRunningButton
        case stopBackupButton
        case backupStopping
        case backupCancelled
        case dryRunButton
        case analyzingProgress
        case sourceFolderTitle
        case destinationFolderTitle
        case changeFolderButton
        case revealInFinderButton
        case excludeRulesTitle
        case addRulePlaceholder
        case addRuleButton
        case commonRulesTitle
        case activeRulesCount
        case backupFoldersTitle
        case icloudStrategyTitle
        case lastBackupSuccess
        case lastBackupWarning
        case processedFilesSummary
        case spofBannerTitle
        case spofBannerDesc

        // MARK: - Telemetry & Progress
        case telemetryCopied
        case telemetryCloned
        case telemetrySkipped
        case telemetryErrors
        case telemetrySpeed
        case telemetryRemaining
        case phaseIdle
        case phaseScanning
        case phaseAnalyzing
        case phaseCopying
        case phaseFinalizing
        case phaseCompleted
        case phaseFailed

        // MARK: - CoW Capabilities & Badges
        case cowBadgeIntraVolume
        case cowBadgeSnapshotTarget
        case cowBadgeNonAPFS
        case cowBadgeExFAT
        case cowBadgeNTFS
        case cowBadgeNTFSReadOnly
        case cowDescIntraVolume
        case cowDescSnapshotTarget
        case cowDescNonAPFS
        case cowDescExFAT
        case cowDescNTFS
        case cowDescNTFSReadOnly
        case errNTFSTargetReadOnly
        case errDestinationReadOnly




        // MARK: - Scheduling
        case scheduleCardTitle
        case scheduleCardSubtitle
        case scheduleEnableToggle
        case scheduleFrequencyLabel
        case scheduleHourly
        case scheduleDaily
        case scheduleWeekly
        case scheduleInterval
        case scheduleIntervalMinutes
        case scheduleIntervalLabel
        case scheduleHourLabel
        case scheduleDayLabel
        case scheduleCatchUpToggle
        case scheduleCatchUpDesc
        case scheduleNextRunLabel
        case scheduleNotScheduled
        case scheduleEveryDayAt
        case scheduleEveryWeekOn
        case scheduleHourlyDesc
        case monday
        case tuesday
        case wednesday
        case thursday
        case friday
        case saturday
        case sunday

        // MARK: - Pruning / Auto-Pruning
        case autoPruningToggleTitle
        case autoPruningToggleDesc
        case autoPruningRetainCountLabel
        case autoPruningRetainFormat

        // MARK: - Settings View
        case settingsTitle
        case settingsSubtitle
        case settingsAppearanceSection
        case settingsAppearanceDesc
        case themeAuto
        case themeLight
        case themeDark
        case settingsLanguageSection
        case settingsLanguageDesc
        case settingsStartupSection
        case settingsLaunchAtLoginToggle
        case settingsLaunchAtLoginDesc
        case settingsStartMinimizedToggle
        case settingsStartMinimizedDesc
        case settingsStorageSection
        case settingsProfilesPathLabel
        case settingsLogsPathLabel
        case settingsOpenFolder
        case settingsAboutSection
        case settingsVersionLabel
        case settingsEngineDesc
        case settingsProfilesSection
        case settingsProfilesSectionDesc
        case settingsCopyUUID
        case settingsUUIDCopied
        case settingsActiveBadge
        case settingsDebugLoggingTitle
        case settingsDebugLoggingDesc
        case settingsDebugLoggingToggle
        case settingsDebugLoggingActive
        case settingsDebugLoggingInactive
        case settingsDebugLoggingPathLabel
        case settingsDebugLoggingPrivacyNotice
        case settingsDebugOpenLogsFolder
        case settingsDebugCopyPath
        case settingsDebugCopySuccess
        case cliDebugActiveNotice
        case cliDebugSavedNotice
        case cliLogsPathLabel
        case cliNoLogsFound
        case cliDebugLoggingEnabled
        case cliDebugLoggingDisabled

        // MARK: - Menubar
        case menuBarStatusIdle
        case menuBarStatusRunning
        case menuBarTriggerBackup
        case menuBarBackupAll
        case menuBarBackupProfile
        case menuBarProfilesTitle
        case menuBarStorageGlance
        case menuBarQuickTheme
        case menuBarOpenLogs
        case menuBarOpenSettings
        case menuBarOpenApp
        case menuBarQuit
        case menuBarNextRun
        case menuBarLastRun

        // MARK: - Inspector Modal
        case inspectorTitle
        case inspectorSubtitle
        case inspectorTabSummary
        case inspectorTabSkipped
        case inspectorTabErrors
        case inspectorCloseButton
        case inspectorOpenLogsButton
        case inspectorOperationalParams
        case inspectorDuration
        case inspectorAverageSpeed
        case inspectorTotalScanned
        case inspectorInProgressNotice
        case inspectorDataIntegrityTitle
        case inspectorDataIntegrityDesc
        case inspectorNoErrorsNotice
        case inspectorPermissionWarningTitle
        case inspectorPermissionWarningDesc
        case inspectorFullDiskAccessButton

        // MARK: - Restore & Tree Explorer
        case restoreExplorerTitle
        case restoreExplorerSubtitle
        case restoreSnapshotMode
        case restoreTimelineMode
        case previewSpaceButton
        case snapshotsCountTitle
        case noSnapshotsAvailable
        case noSnapshotsAvailableDesc
        case snapshotFilesCount
        case noMatchingFilesInSnapshot
        case noMatchingFilesInSnapshotDesc
        case selectedFileLabel
        case selectFileToRestorePrompt
        case searchFileTitle
        case searchFilePlaceholder
        case searchTreePlaceholder
        case noMatchingFilesFound
        case noMatchingFilesFoundDesc
        case versionsCountLabel
        case timelineSelectPrompt
        case fileSizeLabel
        case modificationDateLabel
        case sha256IntegrityLabel
        case restoreThisVersionButton
        case restoreSheetTitle
        case restoreItemLabel
        case sourceSnapshotLabel
        case collisionResolutionLabel
        case collisionKeepBoth
        case collisionOverwrite
        case collisionSkip
        case restoreToFolderButton
        case restoreSuccessMessage
        case restoreChoosePrompt
        case restoreRootFolder
        case restoreItemsCountFormat

        // MARK: - Timeline State Badges
        case timelineInitialVersion
        case timelineInitialCreated
        case timelineModifiedContent
        case timelineModifiedMeta
        case timelineUnmodifiedCoW

        // MARK: - Maintenance & Flattening
        case maintenanceTitle
        case maintenanceSubtitle
        case maintenanceTotalSnapshots
        case maintenanceTotalBackupSize
        case maintenanceConsolidationTitle
        case maintenanceConsolidationDesc
        case maintenanceKeepSnapshotsLabel
        case maintenancePruneButton
        case maintenancePruneConfirmTitle
        case maintenancePruneConfirmMessage
        case maintenancePruneConfirmAction
        case maintenancePruneSuccessMessage
        case maintenanceRecoveryTitle
        case maintenanceRecoveryDesc
        case maintenanceRebuildButton
        case maintenanceRebuildConfirmTitle
        case maintenanceRebuildConfirmMessage
        case maintenanceRebuildConfirmAction
        case maintenanceRebuildSuccessMessage

        // MARK: - Dry Run Modal
        case dryRunTitle
        case dryRunEstimatedStorage
        case dryRunCoWGrowth
        case dryRunTabAll
        case dryRunTabAdded
        case dryRunTabModified
        case dryRunTabDeleted
        case dryRunNoChangesInTab

        // MARK: - Diagnostic Logs
        case logsTitle
        case logsSubtitle
        case exportLogsButton
        case logAllLevels
        case logSearchPlaceholder
        case logEmptyTitle
        case logEmptyDesc
        case logExportSuccess
        case logExportError

        // MARK: - iCloud Strategies
        case icloudStrategyDownloadAndEvict
        case icloudStrategyDownloadAndEvictDesc
        case icloudStrategyMetadataOnly
        case icloudStrategyMetadataOnlyDesc

        // MARK: - Hash & Full Backup
        case hashModeMetadataOnly
        case hashModeSmartHash
        case hashModeThoroughSampling
        case backupTypeIncremental
        case backupTypeFull
        case startFullBackupButton
        case confirmFullBackupTitle
        case confirmFullBackupMessage
        case confirmFullBackupAction
        case cliCmdBackupFull

        // MARK: - Photos Backup
        case photosStructureDateHierarchy
        case photosStructureAlbumHierarchy
        case photosStructureFlat
        case photosBackupHeroTitle
        case photosBackupHeroSubtitle
        case photosStatusAuthorized
        case photosStatusNotAuthorized
        case photosStatusLimited
        case photosRequestPermissionButton
        case photosCardLibraryStatus
        case photosCardLibraryTotal
        case photosCardLibraryICloud
        case photosCardLibraryLocal
        case photosCardSettings
        case photosExportStructureLabel
        case photosIncludeEditedToggle
        case photosIncludeEditedDesc
        case photosIncludeLivePhotoVideosToggle
        case photosIncludeLivePhotoVideosDesc
        case photosGenerateXMPToggle
        case photosGenerateXMPDesc
        case photosStartBackupButton
        case photosBackupRunningButton
        case photosBufferStatus
        case photosSavedByReflink
        case photosRestorationTitle
        case photosRestorationSubtitle

        // MARK: - Refinements & Global UI
        case sidebarSectionFolders
        case sidebarSectionPhotos
        case sidebarSectionSystem
        case sidebarStatusReady
        case sidebarStatusRunning
        case noProfileSelectedTitle
        case noProfileSelectedDesc
        case rulesProfileSubtitleFormat
        case rulesConfigOnDashboardNotice
        case commonRulesLabel
        case noActiveRulesNotice
        case scheduleAndRetentionHeader
        case photosAuthRequiredDesc
        case photosBackupCardTitle
        case photosBackupCardSubtitle
        case photosConfigCardTitle
        case photosDownloadedClonedFormat
        case quickStatsSnapshotsTitle
        case quickStatsNextRunTitle
        case quickStatsActiveRulesTitle
        case quickStatsExcludeRulesCountFormat
        case sessionSummaryStatsFormat
        case interval15m
        case interval30m
        case interval1h
        case interval2h
        case interval4h
        case interval8h

        // MARK: - CLI Specifics
        case cliDescription
        case cliUsage
        case cliCommandsHeader
        case cliCmdBackup
        case cliCmdBackupProfile
        case cliCmdBackupDryRun
        case cliCmdStatus
        case cliCmdProfileList
        case cliCmdProfileCreate
        case cliCmdProfileName
        case cliCmdProfileSource
        case cliCmdProfileDest
        case cliCmdSnapshotsList
        case cliCmdRestore
        case cliCmdRestoreProfile
        case cliCmdRestoreSnapshot
        case cliCmdRestoreFile
        case cliCmdRestoreTarget
        case cliCmdLogs
        case cliCmdLogsLimit
        case cliCmdScheduleCheck
        case cliExamplesHeader
        case cliUnknownCommand
        case cliNoProfiles
        case cliProfileNotFound
        case cliMissingParams
        case cliProfileCreated
        case cliProfileDeleted
        case cliProfileSaveError
        case cliProfileDeleteError
        case cliLastProfileError
        case cliUnknownSubcommand
        case cliDryRunStarting
        case cliDryRunFinished
        case cliDryRunError
        case cliBackupStarting
        case cliBackupFinished
        case cliBackupError
        case cliSystemStatus
        case cliProfilesCountFormat
        case cliLastRunFormat
        case cliNeverRun
        case cliScheduleCheckStarting
        case cliScheduleCheckDone
        case cliDiskWaitNotice

        // MARK: - Finder Integration & In-Place Version History
        case finderContextMenuBrowseVersions
        case fileVersionsHistoryTitle
        case fileVersionsHistorySubtitle
        case confirmRestoreTitle
        case confirmRestoreMessage
        case confirmRestoreButton
        case confirmRestoreKeepBoth
        case confirmRestoreOverwrite
        case noVersionsFoundForFile
        case fileNotUnderAnyProfile
        case finderExtensionSettingsTitle
        case finderExtensionSettingsDesc
        case finderExtensionToggle
        case finderExtensionActive
        case finderExtensionDisabled
        case finderExtensionToggleDesc
        case finderExtensionMonitoredFolders
        case finderExtensionEnableHint
        case finderExtensionPermissionCheck
        case finderExtensionNotEnabledSystem
        case finderExtensionInaccessibleFolders
        case finderExtensionOpenSettings
        case finderExtensionOpenFDA
        case finderExtensionRestartFinder
        case finderExtensionAllPermissionsGranted
        case refreshStatus
        case cliCmdFileHistory
        case cliCmdFileHistoryPath
        case cliCmdFileHistoryGui

        // MARK: - Modern UI Columns & Settings Additions
        case columnDate
        case columnSize
        case columnType
        case settingsPhotosConfigTitle
        case remainingSecondsFormat

        // MARK: - Safety & System Notifications
        case spofWarningFormat
        case notifBackupCompletedTitleFormat
        case notifBackupCompletedSuccessFormat
        case notifBackupCompletedWarningFormat
        case notifBackupFailedTitleFormat
        case notifBackupFailedBodyFormat
        case notifStaleBackupTitleFormat
        case notifStaleBackupBodyFormat
        case notifBitRotTitle
        case notifBitRotBodyFormat
        // MARK: - 3-2-1 Rule, Remote Destinations & Backup Copy Job
        case copyJobTriggerOnPrimary
        case copyJobTriggerScheduled
        case copyJobTriggerManual
        case copyJobPolicyUnmetered
        case copyJobPolicyAny
        case remoteDestinationsTitle
        case remoteS3Title
        case remoteSMBTitle
        case rule321StatusCompliant
        case rule321StatusPartial
        case rule321StatusLocalOnly
        case smartThrottlingTitle
        case smartThrottlingDesc
        case rule321Title
        case rule321Desc
        case rule321BadgeLocal
        case rule321BadgeRemote
        case rule321BadgeCloud
        case copyJobMasterToggleTitle
        case copyJobMasterToggleDesc
        case copyJobTriggerLabel
        case copyJobNetworkPolicyLabel
        case copyJobThrottlingUnlimited
        case copyJobThrottlingGentle
        case copyJobThrottlingRecommended
        case copyJobThrottlingFast
        case copyJobThrottlingHigh
        case addRemoteDestinationButton
        case noRemoteDestinationsNotice
        case addRemoteDestinationPrompt
        case editRemoteDestination
        case deleteRemoteDestination
        case remoteDestEditorAddTitle
        case remoteDestEditorEditTitle
        case remoteDestEditorSubtitle
        case remoteDestEditorNameLabel
        case remoteDestEditorNamePlaceholder
        case remoteDestEditorTypeLabel
        case remoteDestEditorTypeS3
        case remoteDestEditorTypeSMB
        case remoteDestEditorS3SettingsTitle
        case remoteDestEditorPresetsLabel
        case remoteDestEditorEndpointLabel
        case remoteDestEditorEndpointPlaceholder
        case remoteDestEditorBucketLabel
        case remoteDestEditorBucketPlaceholder
        case remoteDestEditorRegionLabel
        case remoteDestEditorRegionPlaceholder
        case remoteDestEditorPrefixLabel
        case remoteDestEditorPrefixPlaceholder
        case remoteDestEditorAccessKeyLabel
        case remoteDestEditorAccessKeyPlaceholder
        case remoteDestEditorSecretKeyLabel
        case remoteDestEditorSecretKeyPlaceholder
        case remoteDestEditorForcePathStyle
        case remoteDestEditorSMBSettingsTitle
        case remoteDestEditorSMBShareLabel
        case remoteDestEditorSMBSharePlaceholder
        case remoteDestEditorSMBSubfolderLabel
        case remoteDestEditorSMBSubfolderPlaceholder
        case remoteDestEditorSMBUsernameLabel
        case remoteDestEditorSMBUsernamePlaceholder
        case remoteDestEditorSMBPasswordLabel
        case remoteDestEditorSMBPasswordPlaceholder
        case remoteDestEditorEncryptionTitle
        case remoteDestEditorEncryptionDesc
        case remoteDestEditorEnabledToggle
        case remoteDestEditorTestButton
        case remoteDestEditorTesting
        case remoteDestEditorAddButton
        case runReplicationButton
        case replicatingProgress
        case testConnectionSuccessS3Format
        case testConnectionSuccessSMBFormat
        case testConnectionNoNetwork
        case testConnectionInvalidSMBURL
        case testConnectionMissingSMBHost
        case s3ConnectionErrorFormat

        // MARK: - Notifications & Modern UI
        case notifMissedBackupTitle
        case notifMissedBackupBodyFormat
        case notifPhotosCompletedTitle
        case notifPhotosCompletedBodyFormat
        case notifPhotosFailedTitle
        case notifRestoreCompletedTitle
        case notifRestoreCompletedBodyFormat
        case notifRestoreFailedTitle
        case clearLogsButton

        // MARK: - Modern UI & Unified Workspace Tabs
        case tabOverview
        case tabTimeMachine
        case tabRulesAndMaintenance
        case tabPhotosSync
        case tabPhotosSnapshots
        case pipelineSourceLabel
        case pipelineEngineLabel
        case pipelineTargetLabel
        case storageBackupsLabel
        case storageOtherLabel
        case storageFreeLabel
        case statusReady
        case statusRunning
        case statusIdle
        case quickBackupAction
        case quickDryRunAction

        // MARK: - Error Handling & Actionable Guidance
        case errProfileAlreadyLocked
        case errPermissionDeniedTitle
        case errPermissionDeniedMessage
        case errPermissionDeniedRemediation
        case errNotEnoughSpaceTitle
        case errNotEnoughSpaceMessage
        case errNotEnoughSpaceRemediation
        case errItemNotFoundTitle
        case errItemNotFoundMessage
        case errItemNotFoundRemediation
        case errCloneFailedTitle
        case errCloneFailedRemediation
        case errDatabaseTitle
        case errDatabaseRemediation
        case errGenericTitle
        case errDestinationUnreachable

        // MARK: - Units & UI Labels
        case itemCountUnit
        case assetsCountUnit
        case snapshotsCountUnit
        case itemCountUnitFormat
        case assetsCountUnitFormat
        case uuidLabel
        case apfsCowBadge

        // MARK: - Enhanced System Notifications
        case notifLowDiskSpaceTitle
        case notifLowDiskSpaceBodyFormat
        case notifTCCPermissionTitle
        case notifTCCPermissionBodyFormat
        case notifDestinationDisconnectedTitle
        case notifDestinationDisconnectedBodyFormat
        case notifPruningCompletedTitle
        case notifPruningCompletedBodyFormat

        // MARK: - CLI Subcommands & Options
        case cliCmdPhotos
        case cliCmdPrune
        case cliCmdDaemon
        case cliCmdDoctor
        case cliOptDebug
        case cliOptVersion
        case cliOptLang
        case cliOptHelp
        case cliCmdLogsPath
        case cliCmdLogsList
        case cliCmdLogsEnable
        case cliCmdLogsDisable
        case cliCmdScrubDesc

        // MARK: - v1.5.0 Sprint Keys
        case notifVolumeMountTriggerTitle
        case notifVolumeMountTriggerBodyFormat
        case presetDeveloper
        case presetDeveloperDesc
        case presetDocuments
        case presetDocumentsDesc
        case presetCreative
        case presetCreativeDesc
        case enableIgnoreFilesTitle
        case enableIgnoreFilesDesc
        case respectGitIgnoreTitle
        case respectGitIgnoreDesc
        case backupOnVolumeMountTitle
        case backupOnVolumeMountDesc
        case autoEjectOnCompletionTitle
        case autoEjectOnCompletionDesc
        case searchAllSnapshots
        case searchAllSnapshotsTitle
        case searchAllSnapshotsDesc
        case searchAllSnapshotsEmpty
        case searchAcrossSnapshotsMode
        case permissionStatusTitle
        case permissionFDAGranted
        case permissionFDAMissing
        case permissionFinderActive
        case permissionFinderInactive
        case permissionOpenSettings
        case profilePresetsSection
        case enableIgnoreFilesToggle
        case respectGitIgnoreToggle
        case backupOnVolumeMountToggle
        case autoEjectOnCompletionToggle
        case driveAutomationHeader

        // MARK: - v1.6.0 Sprint Keys
        // Snapshot Diff
        case restoreDiffMode
        case diffCompareWithLabel
        case diffTargetSnapshotLabel
        case diffBaseSnapshotLabel
        case diffPreviousSnapshot
        case diffInitialSnapshot
        case diffTabAll
        case diffTabAdded
        case diffTabModified
        case diffTabDeleted
        case diffNoChanges
        case diffNetChange
        case diffCompareAction

        // Wi-Fi & Hotspot
        case wifiSectionTitle
        case wifiSectionDesc
        case wifiPauseOnMeteredToggle
        case wifiPauseOnMeteredDesc
        case wifiAllowedSSIDsLabel
        case wifiDisallowedSSIDsLabel
        case wifiAddCurrentButton
        case wifiNoActiveNetwork
        case wifiAllNetworksAllowed

        // Webhook Remote Monitoring
        case webhookSectionTitle
        case webhookSectionDesc
        case webhookMasterToggle
        case webhookServiceTypeLabel
        case webhookUrlLabel
        case webhookUrlPlaceholder
        case webhookTokenLabel
        case webhookTokenPlaceholder
        case webhookTargetLabel
        case webhookTargetPlaceholder
        case webhookNotifyOnSuccess
        case webhookNotifyOnWarning
        case webhookNotifyOnFailure
        case webhookTestButton
        case webhookTestSuccess
        case webhookTestFailedFormat

        // Storage Forecast & Quota
        case forecastSectionTitle
        case forecastSectionDesc
        case forecastDailyGrowthLabel
        case forecastDaysRemainingFormat
        case forecastSufficientSpace
        case forecastDiskFullNow
        case forecastFullDatePrefix
        case forecastQuotaWarningLabel
        case forecastQuotaAlertToggle
        case forecastQuotaExceededBanner
        case unitDay
        case wifiAllowedPlaceholder
        case wifiDisallowedPlaceholder
        case copyRelativePathAction
        case copySnapshotIdAction

        // MARK: - v1.7.0: Ransomware & Rate-of-Change Guard
        case ransomwareSectionTitle
        case ransomwareSectionDesc
        case ransomwareGuardToggle
        case ransomwareMaxChangePercentLabel
        case ransomwareMaxDeletedCountLabel
        case ransomwareDetectExtensionsToggle
        case ransomwareAbortToggle
        case ransomwareThresholdPercentFormat
        case ransomwareThresholdCountFormat
        case notifRansomwareAlertTitle
        case notifRansomwareAlertBodyFormat

        // MARK: - v1.7.0: Archive Packaging
        case archivePackagingSectionTitle
        case archivePackagingToggle
        case archivePackagingToggleDesc
        case archiveCompressionLevelLabel
        case archiveCompressionLevelFormat
        case archiveFormatZstd
        case archiveFormatGzip

        // MARK: - v1.7.0: Software Updates
        case settingsUpdatesSection
        case settingsUpdatesDesc
        case settingsAutoUpdateToggle
        case settingsCheckForUpdatesButton
        case settingsCurrentVersionFormat
        case settingsUpdateStatusChecking
        case settingsUpdateStatusUpToDate
        case settingsUpdateStatusAvailableFormat
        case settingsUpdateStatusFailedFormat
        case notifUpdateAvailableTitle
        case notifUpdateAvailableBodyFormat

        // MARK: - v1.7.0: WebDAV & SFTP Storage Providers
        case remoteDestEditorTypeWebDAV
        case remoteDestEditorTypeSFTP
        case remoteDestEditorWebDAVSettingsTitle
        case remoteDestEditorWebDAVURLLabel
        case remoteDestEditorWebDAVURLPlaceholder
        case remoteDestEditorWebDAVPathLabel
        case remoteDestEditorWebDAVPathPlaceholder
        case remoteDestEditorWebDAVUsernameLabel
        case remoteDestEditorWebDAVUsernamePlaceholder
        case remoteDestEditorWebDAVPasswordLabel
        case remoteDestEditorWebDAVPasswordPlaceholder
        case remoteDestEditorSFTPSettingsTitle
        case remoteDestEditorSFTPHostLabel
        case remoteDestEditorSFTPHostPlaceholder
        case remoteDestEditorSFTPPortLabel
        case remoteDestEditorSFTPUsernameLabel
        case remoteDestEditorSFTPUsernamePlaceholder
        case remoteDestEditorSFTPPasswordLabel
        case remoteDestEditorSFTPPasswordPlaceholder
        case remoteDestEditorSFTPPathLabel
        case remoteDestEditorSFTPPathPlaceholder
        case testConnectionSuccessWebDAVFormat
        case testConnectionSuccessSFTPFormat
        case testConnectionFailedFormat
        case remoteDestEditorSFTPAuthMethodLabel
        case remoteDestEditorSFTPAuthPassword
        case remoteDestEditorSFTPAuthKey
        case remoteDestEditorSFTPBrowseKeyButton
        case remoteDestEditorSFTPSelectKeyTitle
        case settingsDownloadInBrowser

        // MARK: - About Window & Brand Lore (v1.0.0 Production Release)
        case aboutWindowTitle
        case aboutTagline
        case aboutLoreTitle
        case aboutLoreStory
        case aboutReleaseHighlightsTitle
        case aboutHighlight1
        case aboutHighlight2
        case aboutHighlight3
        case aboutHighlight4
        case aboutHighlight5
        case aboutVersionInfoFormat
        case aboutCopyright
        case aboutArchitectureTag
        case aboutLinksTitle
        case aboutWebsiteButton
        case aboutDocumentationButton
        case aboutReleaseNotesButton
        case aboutCloseButton

        // MARK: - Modern UI Tooltips & Feature Badges
        case tooltipStartBackup
        case tooltipDryRun
        case tooltipStopBackup
        case tooltipApfsCow
        case tooltip321Rule
        case tooltipRansomwareShield
        case tooltipICloudEviction
        case tooltipStorageForecast
        case tooltipVolumeMount
        case tooltipAutoEject
        case tooltipFinderSync
        case tooltipWebhookAlerts
        case tooltipZstdPackaging
        case tooltipQuickLook

        // MARK: - Actionable Guidance & Permission Errors
        case errFDAInstructionTitle
        case errFDAInstructionDesc
        case errDiskFullRemediationDesc
        case errRemoteUnreachableRemediationDesc
        case errPhotosNotAuthorizedTitle
        case errPhotosNotAuthorizedDesc

        // MARK: - Menu Bar Commands & Configuration Archive
        case menuFile
        case menuBackupActions
        case menuView
        case menuWindow
        case menuHelp
        case menuCheckForUpdates
        case menuPreferences
        case menuNewProfile
        case menuRenameProfile
        case menuExportConfig
        case menuImportConfig
        case menuCloseWindow
        case menuRunBackupSelected
        case menuRunAllBackups
        case menuRunPhotosBackup
        case menuDryRunBackup
        case menuCancelBackup
        case menuBackupInspector
        case menuViewOverview
        case menuViewTimeMachine
        case menuViewRulesMaintenance
        case menuViewPhotos
        case menuViewLogs
        case menuToggleTheme
        case menuRefreshData
        case menuMainWindow
        case menuDocumentation
        case menuReleaseNotes
        case menuRevealLogs
        case menuReportIssue
        case exportConfigTitle
        case exportConfigSuccessMessage
        case exportConfigErrorMessage
        case importConfigTitle
        case importConfigSuccessMessage
        case importConfigErrorMessage
        case importConfigInvalidFile
        case importConfigConfirmTitle
        case importConfigConfirmMessage

        // MARK: - Operation Feedback & Profile Lockout (1.3.1)
        case feedbackSuccessTitle
        case feedbackSuccessMessage
        case feedbackViewDetails
        case feedbackViewLogs
        case feedbackExternalDriveMissingTitle
        case feedbackExternalDriveMissingMessage
        case feedbackExternalDriveMissingAdvice
        case feedbackSourceFolderMissingTitle
        case feedbackSourceFolderMissingMessage
        case feedbackSourceFolderMissingAdvice
        case feedbackDiskFullTitle
        case feedbackDiskFullMessage
        case feedbackDiskFullAdvice
        case feedbackPermissionDeniedTitle
        case feedbackPermissionDeniedMessage
        case feedbackPermissionDeniedAdvice
        case feedbackGeneralErrorTitle
        case feedbackGeneralErrorAdvice
        case profileLockedBannerTitle
        case profileLockedBannerMessage

        // MARK: - Restore & Maintenance (1.4.0)
        case restoredSuffixFormat
    }


    // MARK: - Translation Dictionaries

    private static let translations: [AppLanguage: [Key: String]] = [
        .hungarian: hungarianStrings,
        .english: englishStrings
    ]

    private static let hungarianStrings: [Key: String] = [
        .navDashboard: "Áttekintés & Mentés",
        .navProfileRules: "Szabályok & Ütemezés",
        .navPhotosBackup: "Fotótár & Mentés",
        .navPhotosSnapshots: "Fotó-Pillanatképek",
        .navRestore: "Időgép & Visszaállítás",
        .navMaintenance: "Tárhely-Karbantartás",
        .navLogs: "Rendszernapló",
        .navSettings: "Beállítások",

        .cancel: "Mégse",
        .create: "Létrehozás",
        .save: "Mentés",
        .delete: "Törlés",
        .confirm: "Megerősítés",
        .details: "Részletek...",
        .searchPlaceholder: "Keresés...",
        .okDone: "Rendben",
        .unitCountFormat: "%d db",
        .filesCountUnit: "fájl",

        .defaultProfileName: "Alapértelmezett profil",
        .profilesMenuTitle: "Mentési Profilok",
        .activeProfileLabel: "Aktív profil",
        .newProfileButton: "Új Mentési Profil...",
        .renameProfileButton: "Profil Átnevezése...",
        .deleteProfileButton: "Profil Törlése...",
        .newProfileSheetTitle: "Új Mentési Profil Létrehozása",
        .newProfileSheetPrompt: "Adj meg egy nevet az új mentési profilnak:",
        .renameProfileSheetTitle: "Profil Átnevezése",
        .renameProfileSheetPrompt: "Profil új neve:",
        .deleteProfileConfirmTitle: "Biztosan törlöd a profilt?",
        .deleteProfileConfirmMessage: "A profil konfigurációja törlődik. A korábban elkészült mentések a lemezen sértetlenek maradnak.",
        .selectSourceFolder: "Forrás Mappa Kiválasztása",
        .selectDestinationFolder: "Cél Mappa Kiválasztása",
        .selectFolderConfirm: "Kiválasztás",
        .browseButton: "Tallózás...",
        .newProfileSourceDesc: "Válaszd ki a mappát, amelynek tartalmát menteni szeretnéd.",
        .newProfileDestinationDesc: "Válaszd ki a célmappát vagy külső kötetet a mentések tárolására.",
        .newProfileNamePlaceholder: "pl. Fontos Dokumentumok",
        .invalidFolderSelectionTitle: "Érvénytelen mappaválasztás",
        .invalidFolderSelectionMessage: "A forrás és cél mappa nem lehet azonos, és a cél nem lehet a forrás mappán belül.",

        .dashboardHeroSubtitle: "APFS Copy-on-Write inkrementális mentés zéró redundanciával és kriptográfiai védelemmel.",
        .startBackupButton: "Mentés Indítása Most",
        .backupRunningButton: "Mentés Folyamatban...",
        .stopBackupButton: "Mentés Leállítása",
        .backupStopping: "Leállítás folyamatban...",
        .backupCancelled: "Biztonsági mentés megszakítva",
        .dryRunButton: "Előzetes Változáselemzés (Dry-Run)",
        .analyzingProgress: "Elemzés...",
        .sourceFolderTitle: "Forrás Mappa (Mit mentünk)",
        .destinationFolderTitle: "Cél Mappa (Hova mentünk)",
        .changeFolderButton: "Módosítás...",
        .revealInFinderButton: "Megnyitás a Finderben",
        .excludeRulesTitle: "Kizárási Szabályok (Fájlok / Mappák)",
        .addRulePlaceholder: "Új minta, pl. *.log vagy node_modules",
        .addRuleButton: "Hozzáadás",
        .commonRulesTitle: "Gyakori kizárási javaslatok:",
        .activeRulesCount: "aktív szabály",
        .backupFoldersTitle: "Mentési Mappák",
        .icloudStrategyTitle: "iCloud Stratégia:",
        .lastBackupSuccess: "Legutóbbi mentés sikeresen befejeződött",
        .lastBackupWarning: "Legutóbbi mentés figyelmeztetésekkel zárult",
        .processedFilesSummary: "fájl feldolgozva",
        .spofBannerTitle: "Egyetlen Hibapont (SPOF) Észlelve",
        .spofBannerDesc: "A mentési cél és a forrás azonos fizikai meghajtón található. Meghajtóhiba esetén az adatok és a mentések egyszerre vesznek el. Csatlakoztass külső lemezt a 3-2-1 szabály szerint!",

        .telemetryCopied: "Új / Módosult",
        .telemetryCloned: "APFS Reflink",
        .telemetrySkipped: "Kihagyva",
        .telemetryErrors: "Hibák",
        .telemetrySpeed: "Sebesség",
        .telemetryRemaining: "Hátralévő idő",
        .phaseIdle: "Készenlétben",
        .phaseScanning: "Fájlrendszer pásztázása...",
        .phaseAnalyzing: "Változások elemzése...",
        .phaseCopying: "Másolás és klónozás...",
        .phaseFinalizing: "Snapshot lezárása...",
        .phaseCompleted: "Sikeresen befejezve",
        .phaseFailed: "Sikertelen",

        .cowBadgeIntraVolume: "APFS Helyi CoW",
        .cowBadgeSnapshotTarget: "APFS Snapshot CoW",
        .cowBadgeNonAPFS: "Standard Mentés (Nem APFS)",
        .cowBadgeExFAT: "exFAT (Fallback Stream)",
        .cowBadgeNTFS: "NTFS (Illesztőprogram-alapú)",
        .cowBadgeNTFSReadOnly: "NTFS (Írásvédett)",
        .cowDescIntraVolume: "Zéró másolású helyi pillanatfelvétel azonnali APFS reflink klónozással.",
        .cowDescSnapshotTarget: "Inkrementális mentés a céllemezen APFS CoW blokk-deduplikációval.",
        .cowDescNonAPFS: "Hagyományos másolási mód (a céllemez nem támogatja az APFS blokkszintű klónozást).",
        .cowDescExFAT: "exFAT kötet: Nem támogat blokkszintű CoW klónozást és hardlinkeket; fizikai adatfolyam-másolással működik.",
        .cowDescNTFS: "NTFS kötet: Illesztőprogram-támogatással működő írható tároló.",
        .cowDescNTFSReadOnly: "A macOS natív NTFS illesztője írásvédett. Csak forrásként használható mentéshez.",
        .errNTFSTargetReadOnly: "A kiválasztott célkötet NTFS fájlrendszerű és írásvédett. A macOS gyári NTFS illesztője nem támogatja az írást. Kérjük válasszon APFS vagy exFAT meghajtót, vagy használjon írható NTFS illesztőprogramot.",
        .errDestinationReadOnly: "A kiválasztott célkötet írásvédett. Kérjük válasszon írható célmeghajtót.",



        .scheduleCardTitle: "Automatikus Ütemezés & Időzítés",
        .scheduleCardSubtitle: "Állítsd be, hogy a OtterKeep mikor hajtson végre automatikus háttérmentést ehhez a profilhoz.",
        .scheduleEnableToggle: "Automatikus mentési ütemezés bekapcsolása",
        .scheduleFrequencyLabel: "Gyakoriság:",
        .scheduleHourly: "Óránként",
        .scheduleDaily: "Naponta adott időben",
        .scheduleWeekly: "Hetente adott napon",
        .scheduleInterval: "Egyéni időközönként",
        .scheduleIntervalMinutes: "percenként",
        .scheduleIntervalLabel: "Időköz:",
        .scheduleHourLabel: "Időpont:",
        .scheduleDayLabel: "Hét napja:",
        .scheduleCatchUpToggle: "Elmaradt mentések pótlása (Catch-up)",
        .scheduleCatchUpDesc: "Ha a Mac aludt vagy a meghajtó nem volt csatlakoztatva, azonnal pótolja a mentést.",
        .scheduleNextRunLabel: "Következő esedékes mentés:",
        .scheduleNotScheduled: "Nincs bekapcsolva automatikus mentés",
        .scheduleEveryDayAt: "Minden nap ekkor:",
        .scheduleEveryWeekOn: "Minden héten ezen a napon:",
        .scheduleHourlyDesc: "Minden órában automatikusan lefut a háttérben.",
        .monday: "Hétfő",
        .tuesday: "Kedd",
        .wednesday: "Szerda",
        .thursday: "Csütörtök",
        .friday: "Péntek",
        .saturday: "Szombat",
        .sunday: "Vasárnap",

        .autoPruningToggleTitle: "Automatikus Flattesítés (Pruning) mentés után",
        .autoPruningToggleDesc: "Ha be van kapcsolva, a sikeres mentés után azonnal törli a legrégebbi felesleges snapshotokat a megadott darabszám felett.",
        .autoPruningRetainCountLabel: "Megtartandó legfrissebb mentések száma:",
        .autoPruningRetainFormat: "%d db mentés megőrzése",

        .settingsTitle: "Beállítások",
        .settingsSubtitle: "Nyelv, megjelenés, rendszerindítás, profilok és perzisztens tárolási preferenciák.",
        .settingsAppearanceSection: "Megjelenés és téma",
        .settingsAppearanceDesc: "Válassz az operációs rendszert követő automata, a klasszikus világos vagy a sötét téma közül.",
        .themeAuto: "Automata",
        .themeLight: "Világos",
        .themeDark: "Sötét",
        .settingsLanguageSection: "Nyelv és Régió",
        .settingsLanguageDesc: "Válaszd ki az alkalmazás felületi nyelvét. Alapértelmezésben követi az operációs rendszert.",
        .settingsStartupSection: "Rendszerrel Együtt Indulás",
        .settingsLaunchAtLoginToggle: "Automatikus indítás bejelentkezéskor",
        .settingsLaunchAtLoginDesc: "A OtterKeep automatikusan elindul a háttérben a macOS indításakor, biztosítva az ütemezett mentéseket és a Menubar jelenlétet.",
        .settingsStartMinimizedToggle: "Indítás a háttérben (csak menübar ikon)",
        .settingsStartMinimizedDesc: "Indításkor a főablak rejtve marad, a OtterKeep közvetlenül a menüsorból érhető el.",
        .settingsStorageSection: "Perzisztens Fájlok és Tárhely",
        .settingsProfilesPathLabel: "Profilok konfigurációs fájlja:",
        .settingsLogsPathLabel: "Megőrzött rendszernapló fájl:",
        .settingsOpenFolder: "Mappa megnyitása",
        .settingsAboutSection: "Az OtterKeep-ről",
        .settingsVersionLabel: "Verzió: 1.1.0 (Golden Gate UI Release)",
        .settingsEngineDesc: "Natív APFS Copy-on-Write alapú inkrementális biztonsági mentőrendszer Apple Silicon és Intel architektúrára.",
        .settingsProfilesSection: "Mentési Profilok és Azonosítók (UUID)",
        .settingsProfilesSectionDesc: "A OtterKeep által kezelt mentési profilok listája és azok egyedi UUID azonosítói.",
        .settingsCopyUUID: "Másolás",
        .settingsUUIDCopied: "Kimásolva!",
        .settingsActiveBadge: "Aktív",
        .settingsDebugLoggingTitle: "Debug Naplózás & Hibakeresés",
        .settingsDebugLoggingDesc: "Részletes diagnosztikai naplózás ember által olvasható .log fájlba hibaelhárításhoz.",
        .settingsDebugLoggingToggle: "Részletes debug naplózás fájlba (.log)",
        .settingsDebugLoggingActive: "Naplózás Aktív",
        .settingsDebugLoggingInactive: "Inaktív",
        .settingsDebugLoggingPathLabel: "Aktuális debug naplófájl:",
        .settingsDebugLoggingPrivacyNotice: "🔒 Adatvédelmi garancia: A naplófájl automatikusan anonimizálja a felhasználói neveket, privát elérési utakat és érzékeny adatokat.",
        .settingsDebugOpenLogsFolder: "Összes log mappa megnyitása",
        .settingsDebugCopyPath: "Útvonal másolása",
        .settingsDebugCopySuccess: "Útvonal kimásolva!",
        .cliDebugActiveNotice: "🦦 OtterKeep: Debug naplózás aktív.\n📄 Naplófájl: %@\n🔒 Adatvédelem: A felhasználónevek és elérési utak anonimizálva vannak.",
        .cliDebugSavedNotice: "✅ Debug napló elmentve: %@",
        .cliLogsPathLabel: "Aktuális/legfrissebb debug naplófájl elérési útja: %@",
        .cliNoLogsFound: "Nem található még létrehozott .log fájl a logs mappában.",
        .cliDebugLoggingEnabled: "✅ Debug fájlba naplózás sikeresen bekapcsolva.",
        .cliDebugLoggingDisabled: "ℹ️ Debug fájlba naplózás sikeresen kikapcsolva.",

        .menuBarStatusIdle: "OtterKeep: Készenlétben",
        .menuBarStatusRunning: "OtterKeep: Mentés folyamatban...",
        .menuBarTriggerBackup: "Mentés Indítása Most",
        .menuBarBackupAll: "Összes profil mentése",
        .menuBarBackupProfile: "Mentés indítása",
        .menuBarProfilesTitle: "Mentési Profilok",
        .menuBarStorageGlance: "Céllemez szabad tárhely",
        .menuBarQuickTheme: "Téma váltása",
        .menuBarOpenLogs: "Rendszernaplók",
        .menuBarOpenSettings: "Beállítások",
        .menuBarOpenApp: "Főablak Megnyitása",
        .menuBarQuit: "Kilépés",
        .menuBarNextRun: "Következő mentés:",
        .menuBarLastRun: "Utolsó mentés:",

        .inspectorTitle: "Mentési Művelet Részletei",
        .inspectorSubtitle: "Teljes átláthatóság a mentett, kihagyott és hibás állományokról.",
        .inspectorTabSummary: "Áttekintés & Statisztika",
        .inspectorTabSkipped: "Kihagyott Elemek",
        .inspectorTabErrors: "Hibák & Diagnosztika",
        .inspectorCloseButton: "Rendben / Bezárás",
        .inspectorOpenLogsButton: "Részletes Rendszernapló (Logs)",
        .inspectorOperationalParams: "Műveleti Paraméterek",
        .inspectorDuration: "Futási Idő",
        .inspectorAverageSpeed: "Átlagos Írási Sebesség",
        .inspectorTotalScanned: "Összes Ellenőrzött Forrás",
        .inspectorInProgressNotice: "A mentés még folyamatban van...",
        .inspectorDataIntegrityTitle: "Adatintegritás & Változhatatlansági Védelem",
        .inspectorDataIntegrityDesc: "A generált snapshot atomi módon lezárva. Új fájlok kriptográfiai SHA-256 hash ellenőrzéssel rögzítve a manifest katalógusban.",
        .inspectorNoErrorsNotice: "A mentési folyamat során egyetlen fájl olvasása vagy átvitele sem hiúsult meg.",
        .inspectorPermissionWarningTitle: "Figyelem: Néhány fájl nem volt másolható",
        .inspectorPermissionWarningDesc: "Amennyiben macOS jogosultsági (TCC / Operation not permitted) hibát látsz, nyisd meg a Rendszerbeállítások -> Adatvédelem és biztonság -> Teljes lemezelérés menüt, és adj engedélyt a OtterKeep-nek.",
        .inspectorFullDiskAccessButton: "Teljes Lemezelérés Beállítások Megnyitása...",

        .restoreExplorerTitle: "Visszaállítás és Időgép",
        .restoreExplorerSubtitle: "Fastruktúra szerinti böngészés, keresés és visszaállítás.",
        .restoreSnapshotMode: "Snapshotok (Fastruktúra)",
        .restoreTimelineMode: "Fájl-idővonal (Timeline)",
        .previewSpaceButton: "Előnézet (Space)",
        .snapshotsCountTitle: "Snapshotok",
        .noSnapshotsAvailable: "Nincsenek Elérhető Snapshotok",
        .noSnapshotsAvailableDesc: "Futtass egy mentést a kezdőlapon a pillanatképek létrehozásához.",
        .snapshotFilesCount: "fájl",
        .noMatchingFilesInSnapshot: "Nincs Találat",
        .noMatchingFilesInSnapshotDesc: "Nincs a szűrésnek megfelelő fájl a kiválasztott mentésben.",
        .selectedFileLabel: "Kiválasztva:",
        .selectFileToRestorePrompt: "Válassz ki egy fájlt a visszaállításhoz vagy nyomj Space-t az előnézethez",
        .searchFileTitle: "Fájl Keresése / Fastruktúra",
        .searchFilePlaceholder: "Keresés a mentett fájlok között (név vagy útvonal)...",
        .searchTreePlaceholder: "Szűrés a könyvtárfában (fájlnév)...",
        .noMatchingFilesFound: "Nincs Találat",
        .noMatchingFilesFoundDesc: "Nem található a feltételnek megfelelő mentett fájl.",
        .versionsCountLabel: "verzió a mentésekben",
        .timelineSelectPrompt: "A bal oldali fastruktúrában válassz ki egy fájlt a teljes verziótörténet és idővonal megjelenítéséhez.",
        .fileSizeLabel: "Méret",
        .modificationDateLabel: "Módosítás Dátuma",
        .sha256IntegrityLabel: "SHA-256 Integritás",
        .restoreThisVersionButton: "Visszaállítás ebből a verzióból...",
        .restoreSheetTitle: "Fájl Visszaállítása",
        .restoreItemLabel: "Visszaállítandó elem:",
        .sourceSnapshotLabel: "Forrás snapshot:",
        .collisionResolutionLabel: "Névütközés Kezelése:",
        .collisionKeepBoth: "Mindkét fájl megtartása (új néven)",
        .collisionOverwrite: "Meglévő fájl felülírása",
        .collisionSkip: "Átugrás (ha már létezik)",
        .restoreToFolderButton: "Visszaállítás Mappába...",
        .restoreSuccessMessage: "Fájl sikeresen visszaállítva ide:\n%@",
        .restoreChoosePrompt: "Visszaállítás Ide",
        .restoreRootFolder: "Gyökérkönyvtár",
        .restoreItemsCountFormat: "%d elem",

        .timelineInitialVersion: "Kezdeti verzió",
        .timelineInitialCreated: "Létrehozva (Kezdeti verzió)",
        .timelineModifiedContent: "Módosult tartalom",
        .timelineModifiedMeta: "Módosult (Méret/Dátum)",
        .timelineUnmodifiedCoW: "Változatlan (CoW deduplikáció)",

        .maintenanceTitle: "Tárhely-Karbantartás és Flattesítés",
        .maintenanceSubtitle: "Inkrementális snapshotok konszolidációja és katalógus helyreállítása.",
        .maintenanceTotalSnapshots: "Snapshotok Száma",
        .maintenanceTotalBackupSize: "Összes Mentett Adat",
        .maintenanceConsolidationTitle: "Snapshot Pruning / Kézi Flattesítés",
        .maintenanceConsolidationDesc: "A régebbi mentések törlésével az APFS Copy-on-Write blokk-referenciái azonnal felszabadítják a nem használt adatblokkokat, míg a későbbi mentések fájljai sértetlenek maradnak.",
        .maintenanceKeepSnapshotsLabel: "Megtartandó legfrissebb mentések száma:",
        .maintenancePruneButton: "Régi Snapshotok Flattesítése és Törlése...",
        .maintenancePruneConfirmTitle: "Biztosan flattesíted a mentéseket?",
        .maintenancePruneConfirmMessage: "A megadott legfrissebb mentéseken kívül az összes korábbi snapshot és a fel nem használt adatblokkok véglegesen törlődnek.",
        .maintenancePruneConfirmAction: "Igen, régebbi snapshotok törlése",
        .maintenancePruneSuccessMessage: "A flattesítés sikeresen befejeződött! Törölt snapshotok: %d db",
        .maintenanceRecoveryTitle: "Katasztrófa Utáni Katalógus Helyreállítás",
        .maintenanceRecoveryDesc: "Amennyiben a belső metaadat-bázis (.otterkeep/manifest.sqlite) megsérülne vagy elveszne, ez a funkció közvetlenül végigpásztázza a célmeghajtón található raw snapshot könyvtárakat és veszteségmentesen újraépíti a teljes katalógust és fájlindexet.",
        .maintenanceRebuildButton: "Katalógus Újraépítése a Raw Lemezről...",
        .maintenanceRebuildConfirmTitle: "Újraépíted a katalógust?",
        .maintenanceRebuildConfirmMessage: "A folyamat átvizsgálja a mentési könyvtárat és frissíti a helyi SQLite indexet.",
        .maintenanceRebuildConfirmAction: "Újraépítés Indítása",
        .maintenanceRebuildSuccessMessage: "A katalógus újraépítése sikeres! %d snapshot regisztrálva a lemezről.",

        .dryRunTitle: "Mentés Előtti Elemzés (Dry-Run)",
        .dryRunEstimatedStorage: "Becsült Új Tárhelyigény",
        .dryRunCoWGrowth: "CoW deduplikált nettó bővülés",
        .dryRunTabAll: "Összes",
        .dryRunTabAdded: "Új",
        .dryRunTabModified: "Módosult",
        .dryRunTabDeleted: "Törölt",
        .dryRunNoChangesInTab: "Ebben a kategóriában nincsenek azonosított változások.",

        .logsTitle: "Diagnosztikai Rendszernapló",
        .logsSubtitle: "Valós idejű és futások között megőrzött rendszeresemények.",
        .exportLogsButton: "Napló Exportálása...",
        .logAllLevels: "Mindegyik Szint",
        .logSearchPlaceholder: "Keresés üzenetekben...",
        .logEmptyTitle: "Nincs Naplóbejegyzés",
        .logEmptyDesc: "Nincsenek a szűrőknek megfelelő logesemények.",
        .logExportSuccess: "Logok sikeresen exportálva ide:\n%@",
        .logExportError: "Log exportálási hiba: %@",

        .icloudStrategyDownloadAndEvict: "Letöltés és Evikció (Teljes, helytakarékos)",
        .icloudStrategyDownloadAndEvictDesc: "Letölti a felhőfájlokat a mentéshez, majd azonnal törli a helyi gyorsítótárat a helytakarékosságért.",
        .icloudStrategyMetadataOnly: "Csak Metaadatok (Sávszélesség-kímélő)",
        .icloudStrategyMetadataOnlyDesc: "Helyőrző fájlokat és metaadatokat ment el anélkül, hogy letöltené a teljes fájltartalmat.",

        .hashModeMetadataOnly: "Csak Metaadatok (mtime + méret)",
        .hashModeSmartHash: "Okos Hash (mtime eltérésnél hash ellenőrzés)",
        .hashModeThoroughSampling: "Mély Hash (Mintavételes ellenőrzés)",
        .backupTypeIncremental: "Inkrementális",
        .backupTypeFull: "Teljes Mentés",
        .startFullBackupButton: "Teljes Mentés Indítása...",
        .confirmFullBackupTitle: "Teljes Mentés (Full Backup) Indítása",
        .confirmFullBackupMessage: "A teljes mentés a korábbi snapshotoktól függetlenül minden fájlt újra beolvas és átmásol a forrásból, új hash ellenőrzést generálva. Ez több időt és lemezterületet igényelhet. Folytatja?",
        .confirmFullBackupAction: "Teljes Mentés Indítása",
        .cliCmdBackupFull: "Teljes mentés kényszerítése korábbi snapshotok CoW klónozása nélkül",

        // Photos Backup
        .photosStructureDateHierarchy: "Év / Hónap struktúra (YYYY/MM)",
        .photosStructureAlbumHierarchy: "Albumok szerinti struktúra",
        .photosStructureFlat: "Lapos könyvtár",
        .photosBackupHeroTitle: "Apple Fotók Archívum",
        .photosBackupHeroSubtitle: "Tárhelytakarékos, streaming mentés iCloud letöltéssel és APFS CoW deduplikációval",
        .photosStatusAuthorized: "Fotók könyvtár elérése engedélyezve",
        .photosStatusNotAuthorized: "Fotók könyvtár hozzáférés szükséges",
        .photosStatusLimited: "Korlátozott Fotók hozzáférés",
        .photosRequestPermissionButton: "Engedély kérése a macOS-től",
        .photosCardLibraryStatus: "Fotók Könyvtár Állapot",
        .photosCardLibraryTotal: "Összes Média Elem",
        .photosCardLibraryICloud: "iCloudban tárolt (On-Demand)",
        .photosCardLibraryLocal: "Helyi SSD-n elérhető",
        .photosCardSettings: "Photos Mentési Beállítások",
        .photosExportStructureLabel: "Mappastruktúra formátum",
        .photosIncludeEditedToggle: "Szerkesztett verziók mentése",
        .photosIncludeEditedDesc: "Az eredeti nyers mesterfájlok mellett a szűrőzött/módosított képeket is elmenti az Adjusted mappába",
        .photosIncludeLivePhotoVideosToggle: "Live Photo videó komponensek mentése",
        .photosIncludeLivePhotoVideosDesc: "A mozgó .mov komponensek párhuzamos mentése a .heic képek mellé",
        .photosGenerateXMPToggle: "Szabványos XMP Sidecar metaadatok",
        .photosGenerateXMPDesc: "EXIF, GPS, címkék és album-tagságok exportálása szabványos .xmp fájlokba",
        .photosStartBackupButton: "Fotók Mentése Most",
        .photosBackupRunningButton: "Fotók Mentése Folyamatban...",
        .photosBufferStatus: "In-Flight Puffer Terhelés",
        .photosSavedByReflink: "APFS Deduplikációval Megtakarítva",
        .photosRestorationTitle: "Fotók Visszaállítási Böngésző",
        .photosRestorationSubtitle: "Médiaelemek megtekintése QuickLook előnézettel és exportálása",

        .sidebarSectionFolders: "Mappamentés",
        .sidebarSectionPhotos: "Apple Fotótár",
        .sidebarSectionSystem: "Rendszer",
        .sidebarStatusReady: "APFS Készenlét",
        .sidebarStatusRunning: "Mentés folyamatban...",
        .noProfileSelectedTitle: "Nincs kiválasztott profil",
        .noProfileSelectedDesc: "Válassz ki vagy hozz létre egy mappamentési profilt az oldalsáv alján.",
        .rulesProfileSubtitleFormat: "Beállítások, kizárások és ütemezés a(z) „%@” profilhoz.",
        .rulesConfigOnDashboardNotice: "Mappák konfigurálása: Áttekintés & Mentés",
        .commonRulesLabel: "Gyakori minták:",
        .noActiveRulesNotice: "Nincsenek aktív kizárási szabályok ehhez a profilhoz.",
        .scheduleAndRetentionHeader: "Ütemezés és Megőrzési Házirend",
        .photosAuthRequiredDesc: "A OtterKeep számára engedélyezni kell a Fotók könyvtár elérését a mentés végrehajtásához.",
        .photosBackupCardTitle: "Fotótár Biztonsági Mentése",
        .photosBackupCardSubtitle: "Inkrementális szinkronizáció és export az Apple Fotók adatbázisból.",
        .photosConfigCardTitle: "Célkönyvtár és Export Beállítások",
        .photosDownloadedClonedFormat: "Letöltve: %@ | Klónozva: %@",
        .quickStatsSnapshotsTitle: "Mentett Pillanatképek",
        .quickStatsNextRunTitle: "Következő Mentés",
        .quickStatsActiveRulesTitle: "Aktív Kizárási Szabályok",
        .quickStatsExcludeRulesCountFormat: "%d minta",
        .sessionSummaryStatsFormat: "%d fájl feldolgozva • %d másolva • %d klónozva • %.1fs",
        .interval15m: "15 perc",
        .interval30m: "30 perc",
        .interval1h: "1 óra (60p)",
        .interval2h: "2 óra (120p)",
        .interval4h: "4 óra (240p)",
        .interval8h: "8 óra (480p)",

        .cliDescription: "🦦  OtterKeep CLI v1.0 – Natív APFS Mentő és Helyreállító Eszköz",
        .cliUsage: "Használat: otterkeep <parancs> [opciók]",
        .cliCommandsHeader: "Parancsok:",
        .cliCmdBackup: "Biztonsági mentés vagy előzetes elemzés indítása",
        .cliCmdBackupProfile: "Mentési profil kiválasztása (név vagy UUID)",
        .cliCmdBackupDryRun: "Csak előzetes változáselemzés lemezmódosítás nélkül",
        .cliCmdStatus: "Aktuális rendszerállapot, profilok és mentési metrikák",
        .cliCmdProfileList: "Mentési profilok kilistázása",
        .cliCmdProfileCreate: "Új profil létrehozása",
        .cliCmdProfileName: "Profil neve",
        .cliCmdProfileSource: "Forráskönyvtár elérési útja",
        .cliCmdProfileDest: "Célkönyvtár (Backup root) elérési útja",
        .cliCmdSnapshotsList: "Snapshotok kilistázása",
        .cliCmdRestore: "Fájl vagy könyvtár visszaállítása",
        .cliCmdRestoreProfile: "Mentési profil kiválasztása",
        .cliCmdRestoreSnapshot: "Snapshot azonosító",
        .cliCmdRestoreFile: "Visszaállítandó fájl relatív elérési útja a rootból",
        .cliCmdRestoreTarget: "Célkönyvtár, ahova visszaállítunk",
        .cliCmdLogs: "Megőrzött rendszernaplók megtekintése",
        .cliCmdLogsLimit: "Megjelenítendő bejegyzések száma (alapértelmezett: 25)",
        .cliCmdScheduleCheck: "Ütemezett és elmaradt (Catch-up) mentések ellenőrzése",
        .cliExamplesHeader: "Példák:",
        .cliUnknownCommand: "❌ Ismeretlen parancs: '%@'. Használd a 'otterkeep --help' parancsot.",
        .cliNoProfiles: "❌ Nincsenek beállított mentési profilok.",
        .cliProfileNotFound: "❌ Nem található mentési profil: '%@'",
        .cliMissingParams: "❌ Hiányzó paraméterek.",
        .cliProfileCreated: "✅ Profil sikeresen létrehozva: %@",
        .cliProfileDeleted: "✅ Profil sikeresen törölve: %@",
        .cliProfileSaveError: "❌ Hiba a profil mentésekor: %@",
        .cliProfileDeleteError: "❌ Hiba a profil törlésekor: %@",
        .cliLastProfileError: "❌ Az utolsó profilt nem lehet törölni.",
        .cliUnknownSubcommand: "❌ Ismeretlen alparancs: '%@'.",
        .cliDryRunStarting: "🔍 Előzetes változáselemzés (Dry-Run) indítása...",
        .cliDryRunFinished: "✅ Dry-Run Elemzés Befejeződött:",
        .cliDryRunError: "❌ Dry-Run hiba: %@",
        .cliBackupStarting: "🚀 Biztonsági mentés indítása...",
        .cliBackupFinished: "✅ Mentés sikeresen befejeződött!",
        .cliBackupError: "❌ Mentési hiba: %@",
        .cliSystemStatus: "🦦  OtterKeep Rendszerállapot",
        .cliProfilesCountFormat: "Profilok száma: %d",
        .cliLastRunFormat: "    Utolsó futás: %@",
        .cliNeverRun: "    Utolsó futás: Még nem futott",
        .cliScheduleCheckStarting: "⏰ Ütemezések és elmaradt mentések ellenőrzése...",
        .cliScheduleCheckDone: "✅ Ütemezési ellenőrzés kész.",
        .cliDiskWaitNotice: "⏳ Céllemez csatlakoztatására várakozás...",

        .finderContextMenuBrowseVersions: "OtterKeep: Előző verziók böngészése...",
        .fileVersionsHistoryTitle: "Fájl korábbi verziói",
        .fileVersionsHistorySubtitle: "Elérhető pillanatképek a kijelölt fájlhoz",
        .confirmRestoreTitle: "Fájl visszaállításának megerősítése",
        .confirmRestoreMessage: "Biztosan visszaállítja a(z) '%@' időpontban készült verziót ide: '%@'? A célhelyen lévő fájl felülírásra kerül.",
        .confirmRestoreButton: "Visszaállítás megerősítése",
        .confirmRestoreKeepBoth: "Mindkettő megtartása",
        .confirmRestoreOverwrite: "Felülírás",
        .noVersionsFoundForFile: "Nem található korábbi mentett verzió ehhez a fájlhoz az adatbázisban.",
        .fileNotUnderAnyProfile: "A kijelölt fájl nem található egyetlen beállított mentési profil forráskönyvtárában sem.",
        .finderExtensionSettingsTitle: "Finder Integráció",
        .finderExtensionSettingsDesc: "Jobb klikkes helyi menü a profilok forráskönyvtáraiban a fájlok verzióinak közvetlen böngészéséhez és helyben történő visszaállításához.",
        .finderExtensionToggle: "Finder integráció engedélyezése",
        .finderExtensionActive: "Aktív",
        .finderExtensionDisabled: "Kikapcsolva",
        .finderExtensionToggleDesc: "Megjeleníti az 'Előző verziók böngészése...' menüpontot a Finderben az összes mentési profil forráskönyvtárán.",
        .finderExtensionMonitoredFolders: "Figyelt forráskönyvtárak:",
        .finderExtensionEnableHint: "Engedélyezd a OtterKeep Finder bővítményt a Rendszerbeállítások > Bővítmények menüpontban.",
        .finderExtensionPermissionCheck: "Jogosultságok és kiterjesztés ellenőrzése",
        .finderExtensionNotEnabledSystem: "A Finder kiterjesztés nincs engedélyezve a macOS Rendszerbeállításokban. Kérjük, engedélyezd a használatához.",
        .finderExtensionInaccessibleFolders: "A következő forráskönyvtárakhoz nincs elegendő hozzáférési jog (Full Disk Access szükséges lehet):",
        .finderExtensionOpenSettings: "Bővítmények beállításai",
        .finderExtensionOpenFDA: "Teljes lemezelérés megnyitása",
        .finderExtensionRestartFinder: "Finder újraindítása",
        .finderExtensionAllPermissionsGranted: "Minden szükséges rendszerjogosultság és a Finder kiterjesztés is aktív.",
        .refreshStatus: "Állapot frissítése",
        .cliCmdFileHistory: "Fájl verziótörténetének megjelenítése",
        .cliCmdFileHistoryPath: "Fájl útvonala",
        .cliCmdFileHistoryGui: "Verziótörténet ablak megnyitása a grafikus felületen",

        .columnDate: "Dátum",
        .columnSize: "Méret",
        .columnType: "Típus",
        .settingsPhotosConfigTitle: "Apple Fotótár Konfiguráció",
        .remainingSecondsFormat: "~%.0fs hátra",

        .spofWarningFormat: "⚠️ [SPOF FIGYELMEZTETÉS] A mentési cél és a forrás azonos fizikai köteten található ('%@'). Hardverhiba esetén a forrás és a mentés egyszerre megsemmisülhet! A 3-2-1 szabály szerint csatlakoztasson független külső lemezt.",
        .notifBackupCompletedTitleFormat: "OtterKeep – %@",
        .notifBackupCompletedSuccessFormat: "Mentés sikeresen befejeződött: %d fájl másolva (%.1f mp).",
        .notifBackupCompletedWarningFormat: "Mentés figyelmeztetésekkel fejeződött be (%@). Kattintson a részletekért.",
        .notifBackupFailedTitleFormat: "⚠️ OtterKeep Mentési Hiba – %@",
        .notifBackupFailedBodyFormat: "A mentés sikertelen: %@",
        .notifStaleBackupTitleFormat: "⏰ Mentési Lemez Szükséges – %@",
        .notifStaleBackupBodyFormat: "A(z) '%@' meghajtó már %d napja nem volt csatlakoztatva! Kérjük csatlakoztassa a friss mentés elkészítéséhez.",
        .notifBitRotTitle: "🚨 Adatromlás (Bit-rot) Észlelve!",
        .notifBitRotBodyFormat: "A OtterKeep Scrubbing ellenőrzés %d sérült fájlt talált a(z) '%@' tárolón. Ellenőrizze a meghajtót azonnal!",
        .copyJobTriggerOnPrimary: "Elsődleges mentés után azonnal",
        .copyJobTriggerScheduled: "Időzített replikáció",
        .copyJobTriggerManual: "Kézi indítás",
        .copyJobPolicyUnmetered: "Csak korlátlan hálózaton (Wi-Fi / LAN)",
        .copyJobPolicyAny: "Bármely elérhető internetkapcsolaton",
        .remoteDestinationsTitle: "Távoli Célpontok (NAS / Felhő)",
        .remoteS3Title: "S3-Kompatibilis Felhő (AWS / Backblaze / R2)",
        .remoteSMBTitle: "NAS Hálózati Megosztás (SMB / NFS)",
        .rule321StatusCompliant: "3-2-1 Megfelelő (Helyi + Off-site Felhő/NAS)",
        .rule321StatusPartial: "Részleges 3-2-1 (Csak helyi másolat aktív)",
        .rule321StatusLocalOnly: "1 Példány (Nincs másolat)",
        .smartThrottlingTitle: "Intelligens Sávszélesség-korlátozás",
        .smartThrottlingDesc: "Korlátozza a másolási sebességet a hálózat védelmében.",
        .rule321Title: "3-2-1 Mentési Szabály",
        .rule321Desc: "3 példány az adatokból, 2 különböző adathordozón, 1 távoli (off-site) helyszínen.",
        .rule321BadgeLocal: "1. Helyi APFS",
        .rule321BadgeRemote: "2. NAS Tároló",
        .rule321BadgeCloud: "3. Off-site S3",

        .copyJobMasterToggleTitle: "3-2-1 Backup Copy Job (Másodlagos Replikáció) Engedélyezése",
        .copyJobMasterToggleDesc: "A helyi APFS mentés után a háttérben automatikusan másolatot készít a távoli S3 felhőbe vagy NAS-ra.",
        .copyJobTriggerLabel: "Másolás indítása:",
        .copyJobNetworkPolicyLabel: "Hálózati szabályzat:",
        .copyJobThrottlingUnlimited: "Korlátlan sebesség",
        .copyJobThrottlingGentle: "2 MB/s (Kímélő)",
        .copyJobThrottlingRecommended: "5 MB/s (Ajánlott)",
        .copyJobThrottlingFast: "10 MB/s",
        .copyJobThrottlingHigh: "25 MB/s",
        .addRemoteDestinationButton: "Új Célpont Hozzáadása...",
        .noRemoteDestinationsNotice: "Nincs konfigurált távoli mentési célpont.",
        .addRemoteDestinationPrompt: "S3 vagy NAS célpont hozzáadása",
        .editRemoteDestination: "Célpont szerkesztése",
        .deleteRemoteDestination: "Célpont eltávolítása",
        .remoteDestEditorAddTitle: "Új Távoli Célpont Hozzáadása",
        .remoteDestEditorEditTitle: "Távoli Célpont Módosítása",
        .remoteDestEditorSubtitle: "3-2-1 szabály: Off-site felhő (S3/B2/R2) vagy helyi hálózati NAS (SMB)",
        .remoteDestEditorNameLabel: "Célpont megnevezése:",
        .remoteDestEditorNamePlaceholder: "pl. AWS S3 Offsite vagy Synology NAS",
        .remoteDestEditorTypeLabel: "Típus:",
        .remoteDestEditorTypeS3: "S3 Felhőtárhely (AWS, B2, R2, MinIO)",
        .remoteDestEditorTypeSMB: "SMB / NAS Megosztás (Samba, Synology)",
        .remoteDestEditorS3SettingsTitle: "S3 Felhőtárhely Beállítások",
        .remoteDestEditorPresetsLabel: "Gyors sablonok:",
        .remoteDestEditorEndpointLabel: "Endpoint URL:",
        .remoteDestEditorEndpointPlaceholder: "https://s3.eu-central-1.amazonaws.com",
        .remoteDestEditorBucketLabel: "Bucket (Vödör) név:",
        .remoteDestEditorBucketPlaceholder: "pl. otterkeep-offsite",
        .remoteDestEditorRegionLabel: "Régió:",
        .remoteDestEditorRegionPlaceholder: "pl. eu-central-1 vagy auto",
        .remoteDestEditorPrefixLabel: "Könyvtár előtag (Prefix - Opcionális):",
        .remoteDestEditorPrefixPlaceholder: "pl. backups/macbook",
        .remoteDestEditorAccessKeyLabel: "Access Key ID:",
        .remoteDestEditorAccessKeyPlaceholder: "AKIAIOSFODNN7EXAMPLE",
        .remoteDestEditorSecretKeyLabel: "Secret Access Key:",
        .remoteDestEditorSecretKeyPlaceholder: "macOS Keychainben védve",
        .remoteDestEditorForcePathStyle: "Path-Style címzés kényszerítése (MinIO / S3 proxykhoz)",
        .remoteDestEditorSMBSettingsTitle: "SMB / NAS Hálózati Megosztás Beállítások",
        .remoteDestEditorSMBShareLabel: "Megosztás URL (Share URL):",
        .remoteDestEditorSMBSharePlaceholder: "smb://synology.local/backups",
        .remoteDestEditorSMBSubfolderLabel: "Megosztáson belüli mappa (Opcionális):",
        .remoteDestEditorSMBSubfolderPlaceholder: "pl. OtterKeep_Backups vagy üres",
        .remoteDestEditorSMBUsernameLabel: "Felhasználónév (Opcionális):",
        .remoteDestEditorSMBUsernamePlaceholder: "backup_user",
        .remoteDestEditorSMBPasswordLabel: "Jelszó:",
        .remoteDestEditorSMBPasswordPlaceholder: "macOS Keychainben védve",
        .remoteDestEditorEncryptionTitle: "Zero-Knowledge AES-256-GCM Titkosítás",
        .remoteDestEditorEncryptionDesc: "A fájlok feltöltés előtt titkosításra kerülnek a profil kulcsával. A felhőszolgáltató nem láthatja a fájlok tartalmát.",
        .remoteDestEditorEnabledToggle: "Célpont bekapcsolása (másolás engedélyezve)",
        .remoteDestEditorTestButton: "Kapcsolat Tesztelése",
        .remoteDestEditorTesting: "Tesztelés...",
        .remoteDestEditorAddButton: "Hozzáadás",
        .runReplicationButton: "Replikáció futtatása",
        .replicatingProgress: "Szinkronizálás...",
        .testConnectionSuccessS3Format: "Sikeres kapcsolat! A(z) '%@' vödör elérhető és az S3 hitelesítés érvényes.",
        .testConnectionSuccessSMBFormat: "SMB szerver beállítások érvényesek (%@). A csatolás replikációkor automatikusan lefut.",
        .testConnectionNoNetwork: "Nincs aktív hálózati kapcsolat.",
        .testConnectionInvalidSMBURL: "Érvénytelen SMB URL (formátum: smb://szerver/megosztas).",
        .testConnectionMissingSMBHost: "Hiányzó NAS szerver host az SMB URL-ben.",
        .s3ConnectionErrorFormat: "S3 Kapcsolódási hiba: %@",

        .notifMissedBackupTitle: "⏰ Kimaradt Mentés Pótlása",
        .notifMissedBackupBodyFormat: "A(z) '%@' profil ütemezett futása kimaradt, az automatikus pótló mentés elindult.",
        .notifPhotosCompletedTitle: "📸 Fotótár Mentése Befejeződött",
        .notifPhotosCompletedBodyFormat: "%d új médiaelem sikeresen archiválva (%.1f mp).",
        .notifPhotosFailedTitle: "⚠️ Fotótár Mentési Hiba",
        .notifRestoreCompletedTitle: "✅ Fájl Sikeresen Visszaállítva",
        .notifRestoreCompletedBodyFormat: "A(z) '%@' fájl sikeresen visszaállításra került a(z) '%@' profilból.",
        .notifRestoreFailedTitle: "⚠️ Visszaállítási Hiba",
        .clearLogsButton: "Napló Ürítése",

        .tabOverview: "Áttekintés",
        .tabTimeMachine: "Time Machine",
        .tabRulesAndMaintenance: "Szabályok & Karbantartás",
        .tabPhotosSync: "Mentés & Állapot",
        .tabPhotosSnapshots: "Fotó-Verziók",
        .pipelineSourceLabel: "Forrásmappa",
        .pipelineEngineLabel: "Darwin APFS CoW Motor",
        .pipelineTargetLabel: "Célkötet",
        .storageBackupsLabel: "Biztonsági mentések",
        .storageOtherLabel: "Egyéb adatok",
        .storageFreeLabel: "Szabad tárhely",
        .statusReady: "Készenlétben",
        .statusRunning: "Mentés folyamatban...",
        .statusIdle: "Inaktív",
        .quickBackupAction: "Mentés indítása",
        .quickDryRunAction: "Próbafutás (Dry-Run)",

        .errProfileAlreadyLocked: "A(z) '%@' profil mentése már folyamatban van egy másik folyamat által.",
        .errPermissionDeniedTitle: "Hozzáférési jogosultság megtagadva",
        .errPermissionDeniedMessage: "A rendszer megtagadta a hozzáférést a következőhöz: %@",
        .errPermissionDeniedRemediation: "Kérjük, adjon Teljes Lemezhozzáférést a OtterKeep számára a Rendszerbeállítások > Adatvédelem és biztonság menüpontban.",
        .errNotEnoughSpaceTitle: "Nincs elegendő szabad tárhely",
        .errNotEnoughSpaceMessage: "Legalább %@ szabad hely szükséges a céllemezen, de csak %@ érhető el.",
        .errNotEnoughSpaceRemediation: "Szabadítson fel helyet a céllemezen vagy válasszon másik mentési meghajtót.",
        .errItemNotFoundTitle: "A megadott elem nem található",
        .errItemNotFoundMessage: "A megadott útvonal nem érhető el: %@",
        .errItemNotFoundRemediation: "Ellenőrizze, hogy a forrásmappa vagy külső meghajtó csatlakoztatva van-e.",
        .errCloneFailedTitle: "APFS CoW klónozási hiba",
        .errCloneFailedRemediation: "A céllemez nem támogatja az APFS CoW klónozást, vagy I/O hiba történt.",
        .errDatabaseTitle: "Katalógus adatbázis hiba",
        .errDatabaseRemediation: "Futtassa a 'Katalógus újraépítése' funkciót a Helyreállítás lapon.",
        .errGenericTitle: "Váratlan hiba történt",
        .errDestinationUnreachable: "A célkönyvtár jelenleg nem érhető el vagy le van csatlakoztatva.",

        .itemCountUnit: "db",
        .assetsCountUnit: "elem",
        .snapshotsCountUnit: "db pillanatkép",
        .itemCountUnitFormat: "%d db",
        .assetsCountUnitFormat: "%d elem",
        .uuidLabel: "UUID:",
        .apfsCowBadge: "APFS CoW",

        .notifLowDiskSpaceTitle: "Kritikusan alacsony tárhely",
        .notifLowDiskSpaceBodyFormat: "A(z) '%@' lemezen csak %@ szabad hely maradt (szükséges: %@).",
        .notifTCCPermissionTitle: "Teljes Lemezhozzáférés szükséges",
        .notifTCCPermissionBodyFormat: "A mentés megszakadt, mert hiányzik a jogosultság ehhez: %@",
        .notifDestinationDisconnectedTitle: "Céllemez leválasztva",
        .notifDestinationDisconnectedBodyFormat: "A(z) '%@' meghajtó lekapcsolódott a(z) '%@' profil mentése közben.",
        .notifPruningCompletedTitle: "Retenciós takarítás befejezve",
        .notifPruningCompletedBodyFormat: "%d elavult pillanatkép törölve a(z) '%@' profilból.",

        .cliCmdPhotos: "Apple Photos könyvtár mentése, állapota és pillanatképei",
        .cliCmdPrune: "Pillanatképek szabály szerinti vagy egyéni takarítása",
        .cliCmdDaemon: "Háttérben futó LaunchAgent kezelése (install, uninstall, status, check)",
        .cliCmdDoctor: "Rendszerdiagnosztika és jogosultságok vizsgálata (Full Disk Access, APFS)",
        .cliOptDebug: "Részletes diagnosztikai naplózás timestampelt .log fájlba",
        .cliOptVersion: "Aktuális szoftververzió megjelenítése",
        .cliOptLang: "Megjelenítési nyelv beállítása (hu | en)",
        .cliOptHelp: "Parancssori súgó megjelenítése",
        .cliCmdLogsPath: "Aktív vagy legutóbbi .log fájl útvonalának kiírása",
        .cliCmdLogsList: "Minden elérhető időbélyeges .log fájl listázása",
        .cliCmdLogsEnable: "Állandó részletes fájlnaplózás bekapcsolása",
        .cliCmdLogsDisable: "Állandó részletes fájlnaplózás kikapcsolása",
        .cliCmdScrubDesc: "Kriptográfiai pillanatkép integritásvizsgálat és bit-rot keresés",

        // MARK: - v1.5.0 Sprint
        .notifVolumeMountTriggerTitle: "Külső meghajtó észlelve",
        .notifVolumeMountTriggerBodyFormat: "%@ csatlakoztatva. Biztonsági mentés indul a(z) '%@' profilhoz...",
        .presetDeveloper: "Fejlesztői",
        .presetDeveloperDesc: "node_modules, .build, Pods és Gitignore szűréssel",
        .presetDocuments: "Dokumentumok",
        .presetDocumentsDesc: "Személyes fájlok, irodai dokumentumok",
        .presetCreative: "Fotók & Média",
        .presetCreativeDesc: "Képtárak és média mappák SmartHash ellenőrzéssel",
        .enableIgnoreFilesTitle: ".otterkeepignore és mappajelölők tiszteletben tartása",
        .enableIgnoreFilesDesc: "Mappák és fájlok kizárása .nobackup, CACHEDIR.TAG vagy ignore szabályok alapján",
        .respectGitIgnoreTitle: ".gitignore szabályok automatikus alkalmazása",
        .respectGitIgnoreDesc: "Git tárolókban lévő .gitignore fájlok feldolgozása és érvényesítése",
        .backupOnVolumeMountTitle: "Automatikus mentés csatlakoztatáskor",
        .backupOnVolumeMountDesc: "Mentés automatikus indítása, amikor a mentési célkötet megjelenik",
        .autoEjectOnCompletionTitle: "Automatikus leválasztás mentés után",
        .autoEjectOnCompletionDesc: "A célmeghajtó biztonságos leválasztása a mentés és WORM védelem befejeztével",
        .searchAllSnapshots: "Keresés a teljes mentési előzményben...",
        .searchAllSnapshotsTitle: "Globális Keresés az Idővonalon",
        .searchAllSnapshotsDesc: "Fájlverziók gyors keresése az összes mentett pillanatképen keresztül",
        .searchAllSnapshotsEmpty: "Nincs találat a mentési katalógusban",
        .searchAcrossSnapshotsMode: "Keresés az idővonalon",
        .permissionStatusTitle: "Rendszerengedélyek Állapota",
        .permissionFDAGranted: "Full Disk Access (FDA): Jóváhagyva",
        .permissionFDAMissing: "Full Disk Access (FDA): Hiányzik",
        .permissionFinderActive: "Finder Bővítmény: Aktív",
        .permissionFinderInactive: "Finder Bővítmény: Inaktív",
        .permissionOpenSettings: "Rendszerbeállítások Megnyitása",
        .profilePresetsSection: "Ajánlott sablonok",
        .enableIgnoreFilesToggle: ".otterkeepignore és mappajelölők tiszteletben tartása",
        .respectGitIgnoreToggle: ".gitignore szabályok automatikus alkalmazása",
        .backupOnVolumeMountToggle: "Automatikus mentés csatlakoztatáskor",
        .autoEjectOnCompletionToggle: "Automatikus leválasztás mentés után",
        .driveAutomationHeader: "Külső meghajtó vezérlés",

        // v1.6.0 Sprint
        .restoreDiffMode: "Változásnapló",
        .diffCompareWithLabel: "Összehasonlítás ezzel:",
        .diffTargetSnapshotLabel: "Cél pillanatkép:",
        .diffBaseSnapshotLabel: "Bázis pillanatkép:",
        .diffPreviousSnapshot: "Közvetlenül megelőző verzió",
        .diffInitialSnapshot: "Kezdeti állapot (üres)",
        .diffTabAll: "Összes változás",
        .diffTabAdded: "Hozzáadva",
        .diffTabModified: "Módosult",
        .diffTabDeleted: "Törölve",
        .diffNoChanges: "Nincs eltérés a két pillanatkép között.",
        .diffNetChange: "Nettó változás:",
        .diffCompareAction: "Mi változott?",

        .wifiSectionTitle: "Wi-Fi Hálózat & Hotspot Szűrés",
        .wifiSectionDesc: "Replikáció és hálózati mentés korlátozása adott Wi-Fi hálózatokra, mobil hotspot védelem.",
        .wifiPauseOnMeteredToggle: "Szüneteltetés mobil hotspoton & Alacsony adatforgalom módban",
        .wifiPauseOnMeteredDesc: "Megakadályozza a drága mobilnetes adatkeret elhasználását iPhone Personal Hotspot használatakor.",
        .wifiAllowedSSIDsLabel: "Engedélyezett Wi-Fi hálózatok (SSID):",
        .wifiDisallowedSSIDsLabel: "Tiltott Wi-Fi hálózatok (SSID):",
        .wifiAddCurrentButton: "Jelenlegi Wi-Fi hozzáadása",
        .wifiNoActiveNetwork: "Nincs aktív Wi-Fi kapcsolat",
        .wifiAllNetworksAllowed: "Bármely nem tiltott Wi-Fi engedélyezve",

        .webhookSectionTitle: "Webhook Távfelügyelet (Slack, Discord, Pushover)",
        .webhookSectionDesc: "Értesítések küldése csevegőcsatornákra vagy mobil eszközre a mentési folyamat végén.",
        .webhookMasterToggle: "Webhook értesítések engedélyezése",
        .webhookServiceTypeLabel: "Szolgáltató típusa:",
        .webhookUrlLabel: "Webhook URL:",
        .webhookUrlPlaceholder: "https://hooks.slack.com/... vagy Discord / egyedi URL",
        .webhookTokenLabel: "Hitelesítési token (API Token):",
        .webhookTokenPlaceholder: "Pushover Token vagy Bearer token",
        .webhookTargetLabel: "Célzott felhasználó / csatorna:",
        .webhookTargetPlaceholder: "Pushover User Key vagy csatorna",
        .webhookNotifyOnSuccess: "Értesítés sikeres mentéskor",
        .webhookNotifyOnWarning: "Értesítés figyelmeztetéskor",
        .webhookNotifyOnFailure: "Értesítés mentési hiba esetén",
        .webhookTestButton: "Teszt Webhook Küldése",
        .webhookTestSuccess: "Teszt webhook sikeresen elküldve!",
        .webhookTestFailedFormat: "Webhook hiba: %@",

        .forecastSectionTitle: "Tárhely-előrejelzés & Kvóta",
        .forecastSectionDesc: "Növekedési ütem elemzése és megelőző kapacitás-riasztás a célmeghajtón.",
        .forecastDailyGrowthLabel: "Napi átlagos növekedés:",
        .forecastDaysRemainingFormat: "kb. %d nap elegendő tárhely",
        .forecastSufficientSpace: "Bőséges szabad tárhely (stabil)",
        .forecastDiskFullNow: "A célmeghajtó megtelt!",
        .forecastFullDatePrefix: "Becsült betelés dátuma:",
        .forecastQuotaWarningLabel: "Figyelmeztetési küszöbérték:",
        .forecastQuotaAlertToggle: "Alacsony tárhely és kvóta riasztások",
        .forecastQuotaExceededBanner: "Figyelem: A célmeghajtó szabad helye a beállított küszöbérték alá esett!",
        .unitDay: "nap",
        .wifiAllowedPlaceholder: "Pl. Otthoni_WiFi, Iroda_5G",
        .wifiDisallowedPlaceholder: "Pl. Mobil_Hotspot, Kavezo_WiFi",
        .copyRelativePathAction: "Relatív útvonal másolása",
        .copySnapshotIdAction: "Pillanatkép azonosító másolása",

        // MARK: - v1.7.0: Ransomware & Rate-of-Change Guard
        .ransomwareSectionTitle: "Zsarolóvírus & Tömeges Változás Őr",
        .ransomwareSectionDesc: "Proaktív anomália-észlelés zsarolóvírusos titkosítások és véletlen tömeges fájltörlések megelőzésére a mentés rögzítése előtt.",
        .ransomwareGuardToggle: "Anomália-védelem aktív",
        .ransomwareMaxChangePercentLabel: "Maximális változási arány (%):",
        .ransomwareMaxDeletedCountLabel: "Maximális törölt fájlszám:",
        .ransomwareDetectExtensionsToggle: "Gyanús zsarolóvírus kiterjesztések szűrése (.locked, .crypto stb.)",
        .ransomwareAbortToggle: "Mentés azonnali megszakítása anomália esetén",
        .ransomwareThresholdPercentFormat: "%.0f%% küszöbérték",
        .ransomwareThresholdCountFormat: "%d db fájl",
        .notifRansomwareAlertTitle: "⚠️ Zsarolóvírus / Anomália Észlelve!",
        .notifRansomwareAlertBodyFormat: "A(z) '%@' profil mentése leállítva: %@",

        // MARK: - v1.7.0: Archive Packaging
        .archivePackagingSectionTitle: "Tömörített Csomagolás (Tar.Zstandard / Tar.Gzip)",
        .archivePackagingToggle: "Pillanatképek csomagolása egyetlen tömörített archívumba",
        .archivePackagingToggleDesc: "Több tízezer kis fájl helyett egyetlen .tar.zst vagy .tar.gz tömörített archívumot tölt fel a felhőbe, minimalizálva az S3 API költségeket.",
        .archiveCompressionLevelLabel: "Tömörítési szint:",
        .archiveCompressionLevelFormat: "%d. szint",
        .archiveFormatZstd: "Tar.Zstandard (.tar.zst)",
        .archiveFormatGzip: "Tar.Gzip (.tar.gz)",

        // MARK: - v1.7.0: Software Updates
        .settingsUpdatesSection: "Szoftverfrissítések",
        .settingsUpdatesDesc: "Keresse a legújabb hibajavításokat és új funkciókat automatikusan vagy manuálisan.",
        .settingsAutoUpdateToggle: "Frissítések automatikus keresése a háttérben",
        .settingsCheckForUpdatesButton: "Frissítések keresése most",
        .settingsCurrentVersionFormat: "OtterKeep v%@ (Build %@)",
        .settingsUpdateStatusChecking: "Frissítések keresése...",
        .settingsUpdateStatusUpToDate: "Az OtterKeep naprakész. A legfrissebb verziót használja.",
        .settingsUpdateStatusAvailableFormat: "Új verzió érhető el: v%@!",
        .settingsUpdateStatusFailedFormat: "Nem sikerült ellenőrizni a frissítéseket: %@",
        .notifUpdateAvailableTitle: "Új OtterKeep frissítés érhető el",
        .notifUpdateAvailableBodyFormat: "Az OtterKeep v%@ elérhető. Kattintson a megtekintéshez vagy letöltéshez.",

        // MARK: - v1.7.0: WebDAV & SFTP Storage Providers
        .remoteDestEditorTypeWebDAV: "WebDAV",
        .remoteDestEditorTypeSFTP: "SFTP",
        .remoteDestEditorWebDAVSettingsTitle: "WebDAV Kapcsolat Beállításai",
        .remoteDestEditorWebDAVURLLabel: "WebDAV Kiszolgáló URL:",
        .remoteDestEditorWebDAVURLPlaceholder: "https://nas.local:5006 vagy https://cloud.pelda.hu",
        .remoteDestEditorWebDAVPathLabel: "Célmappa útvonala:",
        .remoteDestEditorWebDAVPathPlaceholder: "/remote.php/dav/files/felhasznalo/OtterKeep",
        .remoteDestEditorWebDAVUsernameLabel: "Felhasználónév:",
        .remoteDestEditorWebDAVUsernamePlaceholder: "WebDAV felhasználónév",
        .remoteDestEditorWebDAVPasswordLabel: "Jelszó vagy Alkalmazás-jelszó:",
        .remoteDestEditorWebDAVPasswordPlaceholder: "Titkos jelszó",
        .remoteDestEditorSFTPSettingsTitle: "SFTP (SSH) Kapcsolat Beállításai",
        .remoteDestEditorSFTPHostLabel: "Kiszolgáló (Host vagy IP):",
        .remoteDestEditorSFTPHostPlaceholder: "nas.local vagy 192.168.1.100",
        .remoteDestEditorSFTPPortLabel: "Port:",
        .remoteDestEditorSFTPUsernameLabel: "SSH Felhasználónév:",
        .remoteDestEditorSFTPUsernamePlaceholder: "root vagy backup_user",
        .remoteDestEditorSFTPPasswordLabel: "Jelszó / SSH Kulcs útvonal:",
        .remoteDestEditorSFTPPasswordPlaceholder: "Jelszó vagy ~/.ssh/id_ed25519",
        .remoteDestEditorSFTPPathLabel: "Távoli mappa útvonala:",
        .remoteDestEditorSFTPPathPlaceholder: "/var/backups/otterkeep",
        .testConnectionSuccessWebDAVFormat: "Sikeres WebDAV kapcsolat: '%@' elérhető!",
        .testConnectionSuccessSFTPFormat: "Sikeres SFTP kapcsolat: '%@' elérhető a 22-es porton!",
        .testConnectionFailedFormat: "Kapcsolódási hiba: %@",
        .remoteDestEditorSFTPAuthMethodLabel: "Hitelesítés módja:",
        .remoteDestEditorSFTPAuthPassword: "Jelszó",
        .remoteDestEditorSFTPAuthKey: "SSH Kulcsfájl",
        .remoteDestEditorSFTPBrowseKeyButton: "Tallózás...",
        .remoteDestEditorSFTPSelectKeyTitle: "Válassz SSH privát kulcs fájlt",
        .settingsDownloadInBrowser: "Megnyitás böngészőben",

        // MARK: - About Window & Brand Lore (v1.0.0 Production Release)
        .aboutWindowTitle: "Az OtterKeep névjegye",
        .aboutTagline: "Őrizd a legfontosabb kincseidet biztos kezekben.",
        .aboutLoreTitle: "A vidrák kedvenc kavicsának legendája",
        .aboutLoreStory: "A tengeri vidráknak van egy különleges, ösztönös szokásuk: egész életükben a hónuk alatt lévő rejtett kis bőrredőben őrzik a kedvenc kavicsukat. Ezzel nyitják fel a kagylókat, játszanak vele a hullámok hátán lebegve, és soha, semmilyen körülmények között nem hagyják el. Az OtterKeep ugyanezzel a féltő gondoskodással vigyáz a Mac-eden lévő fájlokra, pillanatképekre és emlékekre.",
        .aboutReleaseHighlightsTitle: "Újdonságok az 1.1.0-ás kiadásban",
        .aboutHighlight1: "Natív APFS Copy-on-Write motor zéró redundanciájú, azonnali pillanatképekkel",
        .aboutHighlight2: "Apple Fotótár mentés intelligens iCloud helyfelszabadítási védelemmel",
        .aboutHighlight3: "3-2-1 mentési megfelelőség kliensoldali AES-256 titkosított S3, SFTP és WebDAV replikációval",
        .aboutHighlight4: "Proaktív zsarolóvírus- és anomáliavédelem a sérült mentések megakadályozására",
        .aboutHighlight5: "Finder menü integráció és interaktív időkapszula-visszaállítás QuickLook előnézettel",
        .aboutVersionInfoFormat: "%@ verzió (%@ build) • Végleges kiadás",
        .aboutCopyright: "© 2024–2026 Eszes Richárd és az OtterKeep közreműködői. MIT Licenc.",
        .aboutArchitectureTag: "Apple Silicon & Intel Univerzális bináris",
        .aboutLinksTitle: "Közösség és támogatás",
        .aboutWebsiteButton: "Projekt weboldal",
        .aboutDocumentationButton: "Felhasználói kézikönyv",
        .aboutReleaseNotesButton: "Kiadási jegyzék",
        .aboutCloseButton: "Bezárás",

        // MARK: - Modern UI Tooltips & Feature Badges
        .tooltipStartBackup: "Inkrementális APFS pillanatkép-mentés azonnali indítása",
        .tooltipDryRun: "Változások elemzése és tárhelybecslés tényleges lemezre írás nélkül",
        .tooltipStopBackup: "A folyamatban lévő mentési művelet biztonságos leállítása",
        .tooltipApfsCow: "macOS APFS Copy-on-Write klónozást használ. Az azonos blokkok zéró duplikációval osztoznak a lemezterületen.",
        .tooltip321Rule: "3 példány az adataidból, 2 különféle médiatípuson, 1 példány távoli vagy felhős helyszínen.",
        .tooltipRansomwareShield: "Figyeli a fájlváltozások arányát, és azonnal leállítja a mentést hirtelen tömeges titkosítás vagy törlés esetén.",
        .tooltipICloudEviction: "Ideiglenesen letölti a csak felhőben lévő fotókat a mentéshez, majd kiüríti a helyi gyorsítótárat a tárhely védelmére.",
        .tooltipStorageForecast: "Megbecsli a céllemez megtelésének várható dátumát a korábbi napi adattömeg-növekedés alapján.",
        .tooltipVolumeMount: "Automatikusan elindítja ezt a mentési profilt, amint a külső célmeghajtót csatlakoztatod.",
        .tooltipAutoEject: "A mentés befejezése után biztonságosan leválasztja és kiadja a céllemezt a véletlen lecsatlakoztatás elkerülésére.",
        .tooltipFinderSync: "Közvetlenül a macOS Finderbe építi a jobb klikkes verzióvisszaállítást és a mentési jelvényeket.",
        .tooltipWebhookAlerts: "Valós idejű értesítéseket küld Slack, Discord, Pushover vagy egyéni végpontokra a mentés befejezésekor.",
        .tooltipZstdPackaging: "Egyetlen tömörített archívumba csomagolja a fájlokat, drasztikusan csökkentve az API hívások számát és a felhőtárhely díját.",
        .tooltipQuickLook: "Nyomd le a Szóközt a kijelölt fájlverzió azonnali megtekintéséhez a macOS QuickLook segítségével.",

        // MARK: - Actionable Guidance & Permission Errors
        .errFDAInstructionTitle: "Teljes lemezhozzáférés (FDA) szükséges",
        .errFDAInstructionDesc: "A macOS kifejezett engedélyt kér a védett mappák (pl. Dokumentumok, Íróasztal, Mail) mentéséhez. Nyisd meg a Rendszerbeállítások > Adatvédelem és biztonság > Teljes lemezhozzáférés menüpontot, és engedélyezd az OtterKeep alkalmazást.",
        .errDiskFullRemediationDesc: "A célköteten nincs elegendő szabad hely a mentés befejezéséhez. Futtass tárhely-karbantartást a régi mentések ritkításához, vagy csatlakoztass egy nagyobb kapacitású meghajtót.",
        .errRemoteUnreachableRemediationDesc: "Nem sikerült kapcsolatot létesíteni a távoli mentési végponttal. Ellenőrizd az internetkapcsolatot, a hozzáférési adatokat és a hálózati tűzfalbeállításokat.",
        .errPhotosNotAuthorizedTitle: "Fotótár-hozzáférés korlátozva",
        .errPhotosNotAuthorizedDesc: "Az OtterKeep számára engedély szükséges az Apple Fotótárhoz az inkrementális mentés elvégzéséhez. Engedélyezd a hozzáférést a Rendszerbeállítások > Adatvédelem és biztonság > Fotók menüpontban.",

        // MARK: - Menu Bar Commands & Configuration Archive
        .menuFile: "Fájl",
        .menuBackupActions: "Mentés & Műveletek",
        .menuView: "Nézet",
        .menuWindow: "Ablak",
        .menuHelp: "Súgó",
        .menuCheckForUpdates: "Frissítések keresése…",
        .menuPreferences: "Beállítások…",
        .menuNewProfile: "Új mentési profil…",
        .menuRenameProfile: "Profil átnevezése…",
        .menuExportConfig: "Konfiguráció exportálása…",
        .menuImportConfig: "Konfiguráció importálása…",
        .menuCloseWindow: "Ablak bezárása",
        .menuRunBackupSelected: "Kijelölt profil mentése",
        .menuRunAllBackups: "Összes profil mentése",
        .menuRunPhotosBackup: "Apple Fotótár mentése",
        .menuDryRunBackup: "Mentés szimulációja (Dry-Run)…",
        .menuCancelBackup: "Folyamatban lévő mentés megszakítása",
        .menuBackupInspector: "Mentésvizsgáló & Naplózás…",
        .menuViewOverview: "Áttekintés",
        .menuViewTimeMachine: "Időgép & Pillanatképek",
        .menuViewRulesMaintenance: "Szabályok & Karbantartás",
        .menuViewPhotos: "Apple Fotótár munkaterület",
        .menuViewLogs: "Rendszernaplók",
        .menuToggleTheme: "Megjelenési téma váltása",
        .menuRefreshData: "Adatok és pillanatképek frissítése",
        .menuMainWindow: "OtterKeep főablak",
        .menuDocumentation: "OtterKeep dokumentáció",
        .menuReleaseNotes: "Kiadási megjegyzések",
        .menuRevealLogs: "Naplófájlok megnyitása Finderben",
        .menuReportIssue: "Hibajelentés küldése (GitHub)",
        .exportConfigTitle: "Konfiguráció exportálása",
        .exportConfigSuccessMessage: "A konfiguráció és a mentési profilok sikeresen exportálva.",
        .exportConfigErrorMessage: "Nem sikerült exportálni a konfigurációt: %@",
        .importConfigTitle: "Konfiguráció importálása",
        .importConfigSuccessMessage: "A konfiguráció és a profilok sikeresen importálva és érvényesítve.",
        .importConfigErrorMessage: "Nem sikerült importálni a konfigurációt: %@",
        .importConfigInvalidFile: "A kiválasztott fájl nem érvényes OtterKeep konfigurációs archívum.",
        .importConfigConfirmTitle: "Konfiguráció felülírásának megerősítése",
        .importConfigConfirmMessage: "A konfiguráció importálása felülírja a jelenlegi mentési profilokat és beállításokat. Szeretnéd folytatni?",

        // MARK: - Operation Feedback & Profile Lockout (1.3.1)
        .feedbackSuccessTitle: "Mentés sikeresen befejeződött!",
        .feedbackSuccessMessage: "A(z) '%@' profil biztonsági mentése sikeresen elkészült.",
        .feedbackViewDetails: "Részletek megtekintése",
        .feedbackViewLogs: "Hibanapló megnyitása",
        .feedbackExternalDriveMissingTitle: "A külső tárhely nem található",
        .feedbackExternalDriveMissingMessage: "A(z) '%@' mentési célmeghajtó lecsatlakozott vagy nem elérhető.",
        .feedbackExternalDriveMissingAdvice: "Csatlakoztasd újra a külső meghajtót a Mac-hez, majd próbáld újra a mentést. A korábbi mentéseid és a gépen lévő adataid biztonságban vannak.",
        .feedbackSourceFolderMissingTitle: "A forrásmappa nem található",
        .feedbackSourceFolderMissingMessage: "A menteni kívánt mappa '%@' nem érhető el.",
        .feedbackSourceFolderMissingAdvice: "Ellenőrizd, hogy a forrásmappa nem lett-e áthelyezve, átnevezve vagy egy lecsatlakozott lemezen található.",
        .feedbackDiskFullTitle: "Megtelt a célmeghajtó",
        .feedbackDiskFullMessage: "A céllemezen nincs elegendő szabad tárhely az új pillanatkép mentéséhez.",
        .feedbackDiskFullAdvice: "Szabadíts fel helyet a céllemezen vagy állíts be automatikus retenciót a korábbi pillanatképek karbantartásához.",
        .feedbackPermissionDeniedTitle: "Hozzáférés megtagadva",
        .feedbackPermissionDeniedMessage: "Az OtterKeep nem kapott engedélyt a kiválasztott fájlok vagy mappák eléréséhez.",
        .feedbackPermissionDeniedAdvice: "Kérjük, engedélyezd a Teljes lemezhozzáférést (Full Disk Access) az OtterKeep számára a Rendszerbeállítások > Adatvédelem és biztonság menüpontban.",
        .feedbackGeneralErrorTitle: "A mentési művelet megszakadt",
        .feedbackGeneralErrorAdvice: "A meglévő adataid és korábbi mentéseid sértetlenek maradtak. Tekintsd meg a hibanaplót a hiba pontos részleteiért.",
        .profileLockedBannerTitle: "Mentés folyamatban",
        .profileLockedBannerMessage: "A profil beállításai a mentés befejezéséig zárolva vannak az adatkonzisztencia megőrzése érdekében.",

        // MARK: - Restore & Maintenance (1.4.0)
        .restoredSuffixFormat: " (visszaállított %d)"
    ]


    private static let englishStrings: [Key: String] = [
        .navDashboard: "Overview & Backup",
        .navProfileRules: "Rules & Schedule",
        .navPhotosBackup: "Library & Backup",
        .navPhotosSnapshots: "Photo Snapshots",
        .navRestore: "Time Machine & Restore",
        .navMaintenance: "Storage Maintenance",
        .navLogs: "System Logs",
        .navSettings: "Preferences",

        .cancel: "Cancel",
        .create: "Create",
        .save: "Save",
        .delete: "Delete",
        .confirm: "Confirm",
        .details: "Details...",
        .searchPlaceholder: "Search...",
        .okDone: "Done",
        .unitCountFormat: "%d",
        .filesCountUnit: "files",

        .defaultProfileName: "Default profile",
        .profilesMenuTitle: "Backup Profiles",
        .activeProfileLabel: "Active profile",
        .newProfileButton: "New Backup Profile...",
        .renameProfileButton: "Rename Profile...",
        .deleteProfileButton: "Delete Profile...",
        .newProfileSheetTitle: "Create New Backup Profile",
        .newProfileSheetPrompt: "Enter a name for the new backup profile:",
        .renameProfileSheetTitle: "Rename Profile",
        .renameProfileSheetPrompt: "New profile name:",
        .deleteProfileConfirmTitle: "Are you sure you want to delete this profile?",
        .deleteProfileConfirmMessage: "The profile configuration will be deleted. Previously created backup snapshots on disk will remain intact.",
        .selectSourceFolder: "Select Source Folder",
        .selectDestinationFolder: "Select Destination Folder",
        .selectFolderConfirm: "Choose",
        .browseButton: "Browse...",
        .newProfileSourceDesc: "Choose the directory whose contents you want to back up.",
        .newProfileDestinationDesc: "Choose the destination directory or volume where snapshots will be stored.",
        .newProfileNamePlaceholder: "e.g. Work Documents",
        .invalidFolderSelectionTitle: "Invalid Folder Selection",
        .invalidFolderSelectionMessage: "Source and destination folders cannot be the same, and destination cannot be inside source.",

        .dashboardHeroSubtitle: "APFS Copy-on-Write incremental backup with zero redundancy and cryptographic data integrity.",
        .startBackupButton: "Start Backup Now",
        .backupRunningButton: "Backup in Progress...",
        .stopBackupButton: "Stop Backup",
        .backupStopping: "Stopping backup...",
        .backupCancelled: "Backup cancelled by user",
        .dryRunButton: "Pre-backup Analysis (Dry-Run)",
        .analyzingProgress: "Analyzing...",
        .sourceFolderTitle: "Source Folder (What to back up)",
        .destinationFolderTitle: "Destination Folder (Where to store)",
        .changeFolderButton: "Change...",
        .revealInFinderButton: "Reveal in Finder",
        .excludeRulesTitle: "Exclude Rules (Files / Folders)",
        .addRulePlaceholder: "New pattern, e.g. *.log or node_modules",
        .addRuleButton: "Add Rule",
        .commonRulesTitle: "Common exclusion suggestions:",
        .activeRulesCount: "active rules",
        .backupFoldersTitle: "Backup Folders",
        .icloudStrategyTitle: "iCloud Strategy:",
        .lastBackupSuccess: "Last backup completed successfully",
        .lastBackupWarning: "Last backup completed with warnings",
        .processedFilesSummary: "files processed",
        .spofBannerTitle: "Single Point of Failure (SPOF) Detected",
        .spofBannerDesc: "The backup destination is on the exact same physical drive as the source. In a drive failure, both will be lost simultaneously. Attach an external drive to follow the 3-2-1 rule!",

        .telemetryCopied: "New / Modified",
        .telemetryCloned: "APFS Reflink",
        .telemetrySkipped: "Skipped",
        .telemetryErrors: "Errors",
        .telemetrySpeed: "Speed",
        .telemetryRemaining: "Remaining time",
        .phaseIdle: "Idle",
        .phaseScanning: "Scanning file tree...",
        .phaseAnalyzing: "Analyzing changes...",
        .phaseCopying: "Copying and cloning...",
        .phaseFinalizing: "Finalizing snapshot...",
        .phaseCompleted: "Completed successfully",
        .phaseFailed: "Failed",

        .cowBadgeIntraVolume: "APFS Intra-Volume CoW",
        .cowBadgeSnapshotTarget: "APFS Snapshot CoW",
        .cowBadgeNonAPFS: "Standard Backup (Non-APFS)",
        .cowBadgeExFAT: "exFAT (Fallback Stream)",
        .cowBadgeNTFS: "NTFS (Driver-based)",
        .cowBadgeNTFSReadOnly: "NTFS (Read-Only)",
        .cowDescIntraVolume: "Zero-copy local snapshot with instantaneous APFS reflink cloning.",
        .cowDescSnapshotTarget: "Incremental backup with target-side APFS CoW block deduplication.",
        .cowDescNonAPFS: "Standard copy mode (destination drive does not support APFS block-level cloning).",
        .cowDescExFAT: "exFAT volume: Does not support block-level CoW cloning or hard links; uses physical stream copying.",
        .cowDescNTFS: "NTFS volume: Storage operating via driver support.",
        .cowDescNTFSReadOnly: "macOS native NTFS driver is read-only. It can only be used as a backup source.",
        .errNTFSTargetReadOnly: "The selected destination volume is formatted as NTFS and is read-only. Native macOS NTFS driver does not support writing. Please select an APFS or exFAT drive, or use a writable NTFS driver.",
        .errDestinationReadOnly: "The selected destination volume is read-only. Please select a writable destination drive.",



        .scheduleCardTitle: "Automatic Scheduling & Timers",
        .scheduleCardSubtitle: "Configure when OtterKeep should automatically execute background backups for this profile.",
        .scheduleEnableToggle: "Enable automatic backup schedule",
        .scheduleFrequencyLabel: "Frequency:",
        .scheduleHourly: "Hourly",
        .scheduleDaily: "Daily at specific time",
        .scheduleWeekly: "Weekly on specific day",
        .scheduleInterval: "Custom interval",
        .scheduleIntervalMinutes: "minutes",
        .scheduleIntervalLabel: "Interval:",
        .scheduleHourLabel: "Time:",
        .scheduleDayLabel: "Day of week:",
        .scheduleCatchUpToggle: "Catch up missed backups",
        .scheduleCatchUpDesc: "If your Mac was sleeping or the backup drive was disconnected, run the backup automatically.",
        .scheduleNextRunLabel: "Next scheduled backup:",
        .scheduleNotScheduled: "Automatic backup is disabled",
        .scheduleEveryDayAt: "Every day at:",
        .scheduleEveryWeekOn: "Every week on:",
        .scheduleHourlyDesc: "Runs automatically in the background every hour.",
        .monday: "Monday",
        .tuesday: "Tuesday",
        .wednesday: "Wednesday",
        .thursday: "Thursday",
        .friday: "Friday",
        .saturday: "Saturday",
        .sunday: "Sunday",

        .autoPruningToggleTitle: "Automatic Flattening (Pruning) after backup",
        .autoPruningToggleDesc: "When enabled, automatically deletes older snapshots beyond the retention threshold immediately after a successful backup.",
        .autoPruningRetainCountLabel: "Recent snapshots to retain:",
        .autoPruningRetainFormat: "Retain %d recent snapshots",

        .settingsTitle: "Settings",
        .settingsSubtitle: "Language, appearance, startup, profiles, and persistent storage preferences.",
        .settingsAppearanceSection: "Appearance & Theme",
        .settingsAppearanceDesc: "Choose between system auto, classic light, or harmonious dark theme.",
        .themeAuto: "Auto",
        .themeLight: "Light",
        .themeDark: "Dark",
        .settingsLanguageSection: "Language & Region",
        .settingsLanguageDesc: "Choose application interface language. Defaults to operating system language.",
        .settingsStartupSection: "Launch at Login",
        .settingsLaunchAtLoginToggle: "Automatically launch at login",
        .settingsLaunchAtLoginDesc: "OtterKeep will start automatically in the background when you log in, ensuring scheduled backups and MenuBar presence.",
        .settingsStartMinimizedToggle: "Start minimized (menu bar icon only)",
        .settingsStartMinimizedDesc: "The main window stays hidden on launch; OtterKeep is accessible from the menu bar.",
        .settingsStorageSection: "Persistent Storage & Paths",
        .settingsProfilesPathLabel: "Profiles configuration file:",
        .settingsLogsPathLabel: "Persistent system log file:",
        .settingsOpenFolder: "Reveal in Finder",
        .settingsAboutSection: "About OtterKeep",
        .settingsVersionLabel: "Version: 1.1.0 (Golden Gate UI Release)",
        .settingsEngineDesc: "Native APFS Copy-on-Write incremental backup system engineered for Apple Silicon and Intel Macs.",
        .settingsProfilesSection: "Backup Profiles & Identifiers (UUID)",
        .settingsProfilesSectionDesc: "List of managed backup profiles and their unique UUID identifiers.",
        .settingsCopyUUID: "Copy UUID",
        .settingsUUIDCopied: "Copied!",
        .settingsActiveBadge: "Active",
        .settingsDebugLoggingTitle: "Debug Logging & Diagnostics",
        .settingsDebugLoggingDesc: "Detailed diagnostic logging to human-readable .log files for troubleshooting.",
        .settingsDebugLoggingToggle: "Enable detailed debug file logging (.log)",
        .settingsDebugLoggingActive: "Logging Active",
        .settingsDebugLoggingInactive: "Inactive",
        .settingsDebugLoggingPathLabel: "Active debug log file:",
        .settingsDebugLoggingPrivacyNotice: "🔒 Privacy guarantee: The log file automatically redacts usernames, private file paths, and sensitive personal information.",
        .settingsDebugOpenLogsFolder: "Open Logs Folder",
        .settingsDebugCopyPath: "Copy Path",
        .settingsDebugCopySuccess: "Path copied!",
        .cliDebugActiveNotice: "🦦 OtterKeep: Debug logging active.\n📄 Log file: %@\n🔒 Privacy: Usernames and file paths are anonymized.",
        .cliDebugSavedNotice: "✅ Debug session log saved: %@",
        .cliLogsPathLabel: "Active/latest debug log file path: %@",
        .cliNoLogsFound: "No .log files found in logs directory yet.",
        .cliDebugLoggingEnabled: "✅ Debug file logging successfully enabled.",
        .cliDebugLoggingDisabled: "ℹ️ Debug file logging successfully disabled.",

        .menuBarStatusIdle: "OtterKeep: Idle",
        .menuBarStatusRunning: "OtterKeep: Backing up...",
        .menuBarTriggerBackup: "Start Backup Now",
        .menuBarBackupAll: "Backup All Profiles",
        .menuBarBackupProfile: "Start Backup",
        .menuBarProfilesTitle: "Backup Profiles",
        .menuBarStorageGlance: "Destination Free Storage",
        .menuBarQuickTheme: "Toggle Theme",
        .menuBarOpenLogs: "System Logs",
        .menuBarOpenSettings: "Settings",
        .menuBarOpenApp: "Open Main Window",
        .menuBarQuit: "Quit OtterKeep",
        .menuBarNextRun: "Next backup:",
        .menuBarLastRun: "Last backup:",

        .inspectorTitle: "Backup Operation Details",
        .inspectorSubtitle: "Full transparency for copied, skipped, and error files.",
        .inspectorTabSummary: "Overview & Statistics",
        .inspectorTabSkipped: "Skipped Items",
        .inspectorTabErrors: "Errors & Diagnostics",
        .inspectorCloseButton: "Done / Close",
        .inspectorOpenLogsButton: "Detailed System Logs",
        .inspectorOperationalParams: "Operational Parameters",
        .inspectorDuration: "Duration",
        .inspectorAverageSpeed: "Average Speed",
        .inspectorTotalScanned: "Total Scanned Source",
        .inspectorInProgressNotice: "Backup operation is still in progress...",
        .inspectorDataIntegrityTitle: "Data Integrity & Immutability Protection",
        .inspectorDataIntegrityDesc: "Generated snapshot is atomically committed and sealed. New files verified with cryptographic SHA-256 hashes.",
        .inspectorNoErrorsNotice: "No file read or transfer errors occurred during this backup operation.",
        .inspectorPermissionWarningTitle: "Notice: Some files could not be read",
        .inspectorPermissionWarningDesc: "If you encounter macOS permission errors (TCC / Operation not permitted), open System Settings -> Privacy & Security -> Full Disk Access, and grant access to OtterKeep.",
        .inspectorFullDiskAccessButton: "Open Full Disk Access Settings...",

        .restoreExplorerTitle: "Restore & Time Machine",
        .restoreExplorerSubtitle: "Directory tree browsing, search, and version restoration.",
        .restoreSnapshotMode: "Snapshots (Directory Tree)",
        .restoreTimelineMode: "File Timeline",
        .previewSpaceButton: "Preview (Space)",
        .snapshotsCountTitle: "Snapshots",
        .noSnapshotsAvailable: "No Snapshots Available",
        .noSnapshotsAvailableDesc: "Run a backup from the dashboard to create snapshots.",
        .snapshotFilesCount: "files",
        .noMatchingFilesInSnapshot: "No Matching Files",
        .noMatchingFilesInSnapshotDesc: "No files match the filter in this snapshot.",
        .selectedFileLabel: "Selected:",
        .selectFileToRestorePrompt: "Select a file to restore or press Space to preview",
        .searchFileTitle: "Search Files / Directory Tree",
        .searchFilePlaceholder: "Search backed up files (name or relative path)...",
        .searchTreePlaceholder: "Filter directory tree (filename)...",
        .noMatchingFilesFound: "No Files Found",
        .noMatchingFilesFoundDesc: "No files match your search query.",
        .versionsCountLabel: "versions across backups",
        .timelineSelectPrompt: "Select a file from the directory tree on the left to view its full version history and timeline.",
        .fileSizeLabel: "Size",
        .modificationDateLabel: "Modification Date",
        .sha256IntegrityLabel: "SHA-256 Integrity",
        .restoreThisVersionButton: "Restore this version...",
        .restoreSheetTitle: "Restore File",
        .restoreItemLabel: "Item to restore:",
        .sourceSnapshotLabel: "Source snapshot:",
        .collisionResolutionLabel: "Collision Handling:",
        .collisionKeepBoth: "Keep both files (rename)",
        .collisionOverwrite: "Overwrite existing file",
        .collisionSkip: "Skip (if already exists)",
        .restoreToFolderButton: "Restore to Folder...",
        .restoreSuccessMessage: "File successfully restored to:\n%@",
        .restoreChoosePrompt: "Restore Here",
        .restoreRootFolder: "Root Directory",
        .restoreItemsCountFormat: "%d items",

        .timelineInitialVersion: "Initial version",
        .timelineInitialCreated: "Created (Initial version)",
        .timelineModifiedContent: "Modified content",
        .timelineModifiedMeta: "Modified (Size/Date)",
        .timelineUnmodifiedCoW: "Unmodified (CoW deduplication)",

        .maintenanceTitle: "Storage Maintenance & Flattening",
        .maintenanceSubtitle: "Incremental snapshot consolidation and catalog recovery.",
        .maintenanceTotalSnapshots: "Total Snapshots",
        .maintenanceTotalBackupSize: "Total Backup Size",
        .maintenanceConsolidationTitle: "Snapshot Pruning / Manual Flattening",
        .maintenanceConsolidationDesc: "If disk space is running low, prune older snapshots. APFS Copy-on-Write block references ensure pruned blocks are immediately freed while files referenced in newer snapshots remain intact.",
        .maintenanceKeepSnapshotsLabel: "Recent snapshots to retain:",
        .maintenancePruneButton: "Flatten & Prune Older Snapshots...",
        .maintenancePruneConfirmTitle: "Are you sure you want to prune snapshots?",
        .maintenancePruneConfirmMessage: "Except for the specified recent snapshots, all older snapshots and unreferenced blocks will be permanently removed.",
        .maintenancePruneConfirmAction: "Yes, prune older snapshots",
        .maintenancePruneSuccessMessage: "Flattening completed successfully! Pruned snapshots: %d",
        .maintenanceRecoveryTitle: "Disaster Recovery Catalog Rebuild",
        .maintenanceRecoveryDesc: "If the internal SQLite metadata catalog (.otterkeep/manifest.sqlite) is damaged or missing, this function scans raw snapshot directories on the backup target and rebuilds the complete manifest without data loss.",
        .maintenanceRebuildButton: "Rebuild Catalog from Raw Disk...",
        .maintenanceRebuildConfirmTitle: "Rebuild metadata catalog?",
        .maintenanceRebuildConfirmMessage: "The engine will scan the target directory and refresh the local SQLite index.",
        .maintenanceRebuildConfirmAction: "Start Catalog Rebuild",
        .maintenanceRebuildSuccessMessage: "Catalog rebuild completed successfully! %d snapshots indexed from disk.",

        .dryRunTitle: "Pre-backup Analysis (Dry-Run)",
        .dryRunEstimatedStorage: "Estimated New Storage Required",
        .dryRunCoWGrowth: "CoW deduplicated net storage delta",
        .dryRunTabAll: "All",
        .dryRunTabAdded: "Added",
        .dryRunTabModified: "Modified",
        .dryRunTabDeleted: "Deleted",
        .dryRunNoChangesInTab: "No changes identified in this category.",

        .logsTitle: "Diagnostic System Logs",
        .logsSubtitle: "Real-time and persistent log events preserved across runs.",
        .exportLogsButton: "Export Logs...",
        .logAllLevels: "All Levels",
        .logSearchPlaceholder: "Search messages...",
        .logEmptyTitle: "No Log Entries",
        .logEmptyDesc: "No log events match the current filter criteria.",
        .logExportSuccess: "Logs exported successfully to:\n%@",
        .logExportError: "Log export failed: %@",

        .icloudStrategyDownloadAndEvict: "Download & Evict (Full, space-saving)",
        .icloudStrategyDownloadAndEvictDesc: "Downloads cloud files for backup, then evicts local cache to preserve free space.",
        .icloudStrategyMetadataOnly: "Metadata Only (Bandwidth-saving)",
        .icloudStrategyMetadataOnlyDesc: "Saves placeholder files and metadata without downloading full cloud payloads.",

        .hashModeMetadataOnly: "Metadata Only (mtime + size)",
        .hashModeSmartHash: "Smart Hash (Verify hash on mtime mismatch)",
        .hashModeThoroughSampling: "Thorough Hash (Sampling check on all files)",
        .backupTypeIncremental: "Incremental",
        .backupTypeFull: "Full Backup",
        .startFullBackupButton: "Start Full Backup...",
        .confirmFullBackupTitle: "Start Forced Full Backup",
        .confirmFullBackupMessage: "A full backup recopies and verifies all files from the source regardless of previous snapshots. This may take additional time and storage. Continue?",
        .confirmFullBackupAction: "Start Full Backup",
        .cliCmdBackupFull: "Force a full base backup without CoW cloning from previous snapshots",

        // Photos Backup
        .photosStructureDateHierarchy: "Year / Month structure (YYYY/MM)",
        .photosStructureAlbumHierarchy: "Album based hierarchy",
        .photosStructureFlat: "Flat directory",
        .photosBackupHeroTitle: "Apple Photos Archive",
        .photosBackupHeroSubtitle: "Storage-efficient streaming backup with on-demand iCloud downloads and APFS CoW deduplication",
        .photosStatusAuthorized: "Photos library access granted",
        .photosStatusNotAuthorized: "Photos library access required",
        .photosStatusLimited: "Limited Photos library access",
        .photosRequestPermissionButton: "Request Permission from macOS",
        .photosCardLibraryStatus: "Photos Library Status",
        .photosCardLibraryTotal: "Total Media Items",
        .photosCardLibraryICloud: "Stored in iCloud (On-Demand)",
        .photosCardLibraryLocal: "Available Locally on SSD",
        .photosCardSettings: "Photos Backup Settings",
        .photosExportStructureLabel: "Folder Structure Layout",
        .photosIncludeEditedToggle: "Save edited versions",
        .photosIncludeEditedDesc: "Saves filtered and modified versions into the Adjusted directory alongside raw originals",
        .photosIncludeLivePhotoVideosToggle: "Save Live Photo video components",
        .photosIncludeLivePhotoVideosDesc: "Exports paired .mov video components alongside .heic photos",
        .photosGenerateXMPToggle: "Standard XMP Sidecar metadata",
        .photosGenerateXMPDesc: "Exports EXIF, GPS, tags, and album memberships into standard .xmp sidecars",
        .photosStartBackupButton: "Back Up Photos Now",
        .photosBackupRunningButton: "Backing Up Photos...",
        .photosBufferStatus: "In-Flight Buffer Usage",
        .photosSavedByReflink: "Saved by APFS Deduplication",
        .photosRestorationTitle: "Photos Restore Explorer",
        .photosRestorationSubtitle: "Browse backed up photos with QuickLook preview and export to folder",

        .sidebarSectionFolders: "Folder Backup",
        .sidebarSectionPhotos: "Apple Photos Library",
        .sidebarSectionSystem: "System",
        .sidebarStatusReady: "APFS Ready",
        .sidebarStatusRunning: "Backup in progress...",
        .noProfileSelectedTitle: "No Profile Selected",
        .noProfileSelectedDesc: "Select or create a folder backup profile at the bottom of the sidebar.",
        .rulesProfileSubtitleFormat: "Configuration, exclusions, and scheduling for '%@'.",
        .rulesConfigOnDashboardNotice: "Folder setup: Overview & Backup",
        .commonRulesLabel: "Common patterns:",
        .noActiveRulesNotice: "No active exclusion rules for this profile.",
        .scheduleAndRetentionHeader: "Schedule & Retention Policy",
        .photosAuthRequiredDesc: "OtterKeep requires Photos library access permissions to perform backups.",
        .photosBackupCardTitle: "Photos Library Backup",
        .photosBackupCardSubtitle: "Incremental synchronization and export from Apple Photos database.",
        .photosConfigCardTitle: "Destination & Export Settings",
        .photosDownloadedClonedFormat: "Downloaded: %@ | Cloned: %@",
        .quickStatsSnapshotsTitle: "Saved Snapshots",
        .quickStatsNextRunTitle: "Next Scheduled Run",
        .quickStatsActiveRulesTitle: "Active Exclusion Rules",
        .quickStatsExcludeRulesCountFormat: "%d patterns",
        .sessionSummaryStatsFormat: "%d files processed • %d copied • %d cloned • %.1fs",
        .interval15m: "15 min",
        .interval30m: "30 min",
        .interval1h: "1 hour (60m)",
        .interval2h: "2 hours (120m)",
        .interval4h: "4 hours (240m)",
        .interval8h: "8 hours (480m)",

        .cliDescription: "🦦  OtterKeep CLI v1.0 – Native APFS Backup & Recovery Tool",
        .cliUsage: "Usage: otterkeep <command> [options]",
        .cliCommandsHeader: "Commands:",
        .cliCmdBackup: "Execute backup or pre-backup analysis",
        .cliCmdBackupProfile: "Select backup profile (name or UUID)",
        .cliCmdBackupDryRun: "Perform pre-backup analysis without disk changes",
        .cliCmdStatus: "System status, profiles, and backup metrics",
        .cliCmdProfileList: "List backup profiles",
        .cliCmdProfileCreate: "Create new backup profile",
        .cliCmdProfileName: "Profile name",
        .cliCmdProfileSource: "Source directory path",
        .cliCmdProfileDest: "Destination directory (Backup root) path",
        .cliCmdSnapshotsList: "List snapshots",
        .cliCmdRestore: "Restore file or directory",
        .cliCmdRestoreProfile: "Select backup profile",
        .cliCmdRestoreSnapshot: "Snapshot ID",
        .cliCmdRestoreFile: "Relative file path to restore from root",
        .cliCmdRestoreTarget: "Target directory to restore into",
        .cliCmdLogs: "View persistent system logs",
        .cliCmdLogsLimit: "Number of log entries to display (default: 25)",
        .cliCmdScheduleCheck: "Evaluate and trigger scheduled / catch-up backups",
        .cliExamplesHeader: "Examples:",
        .cliUnknownCommand: "❌ Unknown command: '%@'. Run 'otterkeep --help' for usage.",
        .cliNoProfiles: "❌ No backup profiles configured.",
        .cliProfileNotFound: "❌ Backup profile not found: '%@'",
        .cliMissingParams: "❌ Missing required parameters.",
        .cliProfileCreated: "✅ Profile successfully created: %@",
        .cliProfileDeleted: "✅ Profile successfully deleted: %@",
        .cliProfileSaveError: "❌ Failed to save profile: %@",
        .cliProfileDeleteError: "❌ Failed to delete profile: %@",
        .cliLastProfileError: "❌ Cannot delete the only remaining profile.",
        .cliUnknownSubcommand: "❌ Unknown subcommand: '%@'.",
        .cliDryRunStarting: "🔍 Starting pre-backup analysis (Dry-Run)...",
        .cliDryRunFinished: "✅ Dry-Run Analysis Completed:",
        .cliDryRunError: "❌ Dry-Run error: %@",
        .cliBackupStarting: "🚀 Starting backup...",
        .cliBackupFinished: "✅ Backup completed successfully!",
        .cliBackupError: "❌ Backup error: %@",
        .cliSystemStatus: "🦦  OtterKeep System Status",
        .cliProfilesCountFormat: "Total profiles: %d",
        .cliLastRunFormat: "    Last run: %@",
        .cliNeverRun: "    Last run: Never",
        .cliScheduleCheckStarting: "⏰ Evaluating scheduled and catch-up backups...",
        .cliScheduleCheckDone: "✅ Schedule evaluation completed.",
        .cliDiskWaitNotice: "⏳ Waiting for destination disk mount...",

        .finderContextMenuBrowseVersions: "OtterKeep: Browse Previous Versions...",
        .fileVersionsHistoryTitle: "Previous File Versions",
        .fileVersionsHistorySubtitle: "Available snapshots for the selected file",
        .confirmRestoreTitle: "Confirm File Restoration",
        .confirmRestoreMessage: "Are you sure you want to restore the version from '%@' to '%@'? The file at destination will be overwritten.",
        .confirmRestoreButton: "Confirm Restore",
        .confirmRestoreKeepBoth: "Keep Both",
        .confirmRestoreOverwrite: "Overwrite",
        .noVersionsFoundForFile: "No historical versions found for this file in the backup database.",
        .fileNotUnderAnyProfile: "The selected file is not located within any configured backup profile source directory.",
        .finderExtensionSettingsTitle: "Finder Integration",
        .finderExtensionSettingsDesc: "Right-click contextual menu in profile source directories for direct version browsing and in-place restoration.",
        .finderExtensionToggle: "Enable Finder Integration",
        .finderExtensionActive: "Active",
        .finderExtensionDisabled: "Disabled",
        .finderExtensionToggleDesc: "Displays the 'Browse Previous Versions...' menu item in Finder for all backup profile source directories.",
        .finderExtensionMonitoredFolders: "Monitored Source Directories:",
        .finderExtensionEnableHint: "Enable the OtterKeep Finder extension in System Settings > Extensions.",
        .finderExtensionPermissionCheck: "Check Permissions & Extension",
        .finderExtensionNotEnabledSystem: "The Finder extension is not enabled in macOS System Settings. Please enable it to use this feature.",
        .finderExtensionInaccessibleFolders: "The following source directories lack access permissions (Full Disk Access may be required):",
        .finderExtensionOpenSettings: "Extension Settings",
        .finderExtensionOpenFDA: "Open Full Disk Access",
        .finderExtensionRestartFinder: "Restart Finder",
        .finderExtensionAllPermissionsGranted: "All required system permissions and the Finder extension are active.",
        .refreshStatus: "Refresh Status",
        .cliCmdFileHistory: "Display point-in-time version history for a file",
        .cliCmdFileHistoryPath: "File path",
        .cliCmdFileHistoryGui: "Open version history window in GUI",

        .columnDate: "Date",
        .columnSize: "Size",
        .columnType: "Type",
        .settingsPhotosConfigTitle: "Apple Photos Configuration",
        .remainingSecondsFormat: "~%.0fs left",

        .spofWarningFormat: "⚠️ [SPOF WARNING] Backup destination and source are located on the same physical volume ('%@'). In case of hardware failure, both source and backup may be destroyed simultaneously! According to the 3-2-1 rule, connect an independent external disk.",
        .notifBackupCompletedTitleFormat: "OtterKeep – %@",
        .notifBackupCompletedSuccessFormat: "Backup completed successfully: %d files copied (%.1f s).",
        .notifBackupCompletedWarningFormat: "Backup completed with warnings (%@). Click for details.",
        .notifBackupFailedTitleFormat: "⚠️ OtterKeep Backup Error – %@",
        .notifBackupFailedBodyFormat: "Backup failed: %@",
        .notifStaleBackupTitleFormat: "⏰ Backup Disk Required – %@",
        .notifStaleBackupBodyFormat: "Drive '%@' has not been connected for %d days! Please connect it to create a fresh backup.",
        .notifBitRotTitle: "🚨 Data Corruption (Bit-rot) Detected!",
        .notifBitRotBodyFormat: "OtterKeep Scrubbing verification detected %d corrupted files on '%@'. Inspect the drive immediately!",
        .copyJobTriggerOnPrimary: "Immediately after primary backup",
        .copyJobTriggerScheduled: "Scheduled replication window",
        .copyJobTriggerManual: "Manual trigger only",
        .copyJobPolicyUnmetered: "Unmetered connections only (Wi-Fi / LAN)",
        .copyJobPolicyAny: "Any available internet connection",
        .remoteDestinationsTitle: "Remote Destinations (NAS / Cloud)",
        .remoteS3Title: "S3-Compatible Cloud Storage (AWS / Backblaze / R2)",
        .remoteSMBTitle: "NAS Network Share (SMB / NFS)",
        .rule321StatusCompliant: "3-2-1 Compliant (Local + Off-site Cloud/NAS)",
        .rule321StatusPartial: "Partial 3-2-1 (Local copy only)",
        .rule321StatusLocalOnly: "1 Copy (No redundancy)",
        .smartThrottlingTitle: "Smart Bandwidth Throttling",
        .smartThrottlingDesc: "Limits upload bandwidth to preserve network throughput.",
        .rule321Title: "3-2-1 Backup Rule",
        .rule321Desc: "3 copies of your data, on 2 different media types, with 1 copy off-site.",
        .rule321BadgeLocal: "1. Local APFS",
        .rule321BadgeRemote: "2. NAS Storage",
        .rule321BadgeCloud: "3. Off-site S3",

        .copyJobMasterToggleTitle: "Enable 3-2-1 Backup Copy Job (Secondary Replication)",
        .copyJobMasterToggleDesc: "Automatically replicates changed files to remote S3 cloud or NAS shares in the background after local APFS snapshot completes.",
        .copyJobTriggerLabel: "Trigger replication:",
        .copyJobNetworkPolicyLabel: "Network policy:",
        .copyJobThrottlingUnlimited: "Unlimited speed",
        .copyJobThrottlingGentle: "2 MB/s (Gentle)",
        .copyJobThrottlingRecommended: "5 MB/s (Recommended)",
        .copyJobThrottlingFast: "10 MB/s",
        .copyJobThrottlingHigh: "25 MB/s",
        .addRemoteDestinationButton: "Add Remote Destination...",
        .noRemoteDestinationsNotice: "No remote backup destinations configured.",
        .addRemoteDestinationPrompt: "Add S3 or NAS Destination",
        .editRemoteDestination: "Edit destination",
        .deleteRemoteDestination: "Remove destination",
        .remoteDestEditorAddTitle: "Add Remote Destination",
        .remoteDestEditorEditTitle: "Edit Remote Destination",
        .remoteDestEditorSubtitle: "3-2-1 rule: Off-site cloud (S3/B2/R2) or local network share (SMB)",
        .remoteDestEditorNameLabel: "Destination name:",
        .remoteDestEditorNamePlaceholder: "e.g. AWS S3 Offsite or Synology NAS",
        .remoteDestEditorTypeLabel: "Type:",
        .remoteDestEditorTypeS3: "S3 Cloud Storage (AWS, B2, R2, MinIO)",
        .remoteDestEditorTypeSMB: "SMB / NAS Share (Samba, Synology)",
        .remoteDestEditorS3SettingsTitle: "S3 Cloud Storage Settings",
        .remoteDestEditorPresetsLabel: "Quick presets:",
        .remoteDestEditorEndpointLabel: "Endpoint URL:",
        .remoteDestEditorEndpointPlaceholder: "https://s3.eu-central-1.amazonaws.com",
        .remoteDestEditorBucketLabel: "Bucket name:",
        .remoteDestEditorBucketPlaceholder: "e.g. otterkeep-offsite",
        .remoteDestEditorRegionLabel: "Region:",
        .remoteDestEditorRegionPlaceholder: "e.g. eu-central-1 or auto",
        .remoteDestEditorPrefixLabel: "Path prefix (Optional):",
        .remoteDestEditorPrefixPlaceholder: "e.g. backups/macbook",
        .remoteDestEditorAccessKeyLabel: "Access Key ID:",
        .remoteDestEditorAccessKeyPlaceholder: "AKIAIOSFODNN7EXAMPLE",
        .remoteDestEditorSecretKeyLabel: "Secret Access Key:",
        .remoteDestEditorSecretKeyPlaceholder: "Protected in macOS Keychain",
        .remoteDestEditorForcePathStyle: "Force path-style addressing (for MinIO / custom S3 proxies)",
        .remoteDestEditorSMBSettingsTitle: "SMB / NAS Network Share Settings",
        .remoteDestEditorSMBShareLabel: "Share URL:",
        .remoteDestEditorSMBSharePlaceholder: "smb://synology.local/backups",
        .remoteDestEditorSMBSubfolderLabel: "Subfolder path (Optional):",
        .remoteDestEditorSMBSubfolderPlaceholder: "e.g. OtterKeep_Backups or empty",
        .remoteDestEditorSMBUsernameLabel: "Username (Optional):",
        .remoteDestEditorSMBUsernamePlaceholder: "backup_user",
        .remoteDestEditorSMBPasswordLabel: "Password:",
        .remoteDestEditorSMBPasswordPlaceholder: "Protected in macOS Keychain",
        .remoteDestEditorEncryptionTitle: "Zero-Knowledge AES-256-GCM Encryption",
        .remoteDestEditorEncryptionDesc: "Files are encrypted before upload using the profile key. The storage provider cannot inspect your file contents.",
        .remoteDestEditorEnabledToggle: "Enable destination (replication active)",
        .remoteDestEditorTestButton: "Test Connection",
        .remoteDestEditorTesting: "Testing...",
        .remoteDestEditorAddButton: "Add Destination",
        .runReplicationButton: "Run Replication",
        .replicatingProgress: "Replicating...",
        .testConnectionSuccessS3Format: "Connection successful! Bucket '%@' is accessible and SigV4 authentication is valid.",
        .testConnectionSuccessSMBFormat: "SMB server configuration is valid (%@). Share will be mounted automatically during replication.",
        .testConnectionNoNetwork: "No active network connection.",
        .testConnectionInvalidSMBURL: "Invalid SMB URL (format: smb://server/share).",
        .testConnectionMissingSMBHost: "Missing NAS server host in SMB URL.",
        .s3ConnectionErrorFormat: "S3 Connection Error: %@",

        .notifMissedBackupTitle: "⏰ Missed Backup Catch-Up",
        .notifMissedBackupBodyFormat: "Scheduled run for profile '%@' was missed; automatic catch-up backup has started.",
        .notifPhotosCompletedTitle: "📸 Photos Backup Completed",
        .notifPhotosCompletedBodyFormat: "%d new media items successfully archived (%.1f s).",
        .notifPhotosFailedTitle: "⚠️ Photos Backup Failed",
        .notifRestoreCompletedTitle: "✅ File Restored Successfully",
        .notifRestoreCompletedBodyFormat: "File '%@' successfully restored from profile '%@'.",
        .notifRestoreFailedTitle: "⚠️ Restore Failed",
        .clearLogsButton: "Clear Logs",

        .tabOverview: "Overview",
        .tabTimeMachine: "Time Machine",
        .tabRulesAndMaintenance: "Rules & Maintenance",
        .tabPhotosSync: "Backup & Status",
        .tabPhotosSnapshots: "Photo Versions",
        .pipelineSourceLabel: "Source Folder",
        .pipelineEngineLabel: "Darwin APFS CoW Engine",
        .pipelineTargetLabel: "Destination Disk",
        .storageBackupsLabel: "OtterKeep Backups",
        .storageOtherLabel: "Other Files",
        .storageFreeLabel: "Free Space",
        .statusReady: "Ready",
        .statusRunning: "Backing up...",
        .statusIdle: "Idle",
        .quickBackupAction: "Back Up Now",
        .quickDryRunAction: "Dry-Run Analysis",

        .errProfileAlreadyLocked: "Profile '%@' is currently locked by another active process.",
        .errPermissionDeniedTitle: "Permission Denied",
        .errPermissionDeniedMessage: "Access was denied to: %@",
        .errPermissionDeniedRemediation: "Please grant Full Disk Access to OtterKeep in System Settings > Privacy & Security.",
        .errNotEnoughSpaceTitle: "Insufficient Disk Space",
        .errNotEnoughSpaceMessage: "At least %@ free space is required on destination, but only %@ is available.",
        .errNotEnoughSpaceRemediation: "Free up disk space on the destination drive or select another target drive.",
        .errItemNotFoundTitle: "Item Not Found",
        .errItemNotFoundMessage: "The specified path cannot be found: %@",
        .errItemNotFoundRemediation: "Verify that the source directory or external drive is connected.",
        .errCloneFailedTitle: "APFS CoW Clone Error",
        .errCloneFailedRemediation: "Destination does not support APFS CoW cloning or an I/O error occurred.",
        .errDatabaseTitle: "Catalog Database Error",
        .errDatabaseRemediation: "Run 'Rebuild Catalog' from the Restore tab.",
        .errGenericTitle: "Unexpected Error Occurred",
        .errDestinationUnreachable: "The destination directory is currently unreachable or disconnected.",

        .itemCountUnit: "items",
        .assetsCountUnit: "items",
        .snapshotsCountUnit: "snapshots",
        .itemCountUnitFormat: "%d items",
        .assetsCountUnitFormat: "%d items",
        .uuidLabel: "UUID:",
        .apfsCowBadge: "APFS CoW",

        .notifLowDiskSpaceTitle: "Critically Low Disk Space",
        .notifLowDiskSpaceBodyFormat: "Only %@ free space remaining on '%@' (required: %@).",
        .notifTCCPermissionTitle: "Full Disk Access Required",
        .notifTCCPermissionBodyFormat: "Backup stopped because permission is missing for: %@",
        .notifDestinationDisconnectedTitle: "Destination Disk Disconnected",
        .notifDestinationDisconnectedBodyFormat: "Drive '%@' disconnected during backup of profile '%@'.",
        .notifPruningCompletedTitle: "Retention Pruning Completed",
        .notifPruningCompletedBodyFormat: "%d expired snapshot(s) pruned for profile '%@'.",

        .cliCmdPhotos: "Apple Photos library backup, status, and snapshots",
        .cliCmdPrune: "Prune snapshots according to retention policy or custom limit",
        .cliCmdDaemon: "Manage headless background LaunchAgent (install, uninstall, status, check)",
        .cliCmdDoctor: "System diagnostics and permission verification (Full Disk Access, APFS)",
        .cliOptDebug: "Enable detailed diagnostic logging to a timestamped .log file",
        .cliOptVersion: "Display current software version",
        .cliOptLang: "Specify display language (hu | en)",
        .cliOptHelp: "Show this help screen",
        .cliCmdLogsPath: "Print current or latest .log file path",
        .cliCmdLogsList: "List all available timestamped .log files",
        .cliCmdLogsEnable: "Enable persistent debug file logging",
        .cliCmdLogsDisable: "Disable persistent debug file logging",
        .cliCmdScrubDesc: "Verify snapshot integrity & bit-rot detection",

        // MARK: - v1.5.0 Sprint
        .notifVolumeMountTriggerTitle: "External Drive Detected",
        .notifVolumeMountTriggerBodyFormat: "%@ connected. Starting backup for profile '%@'...",
        .presetDeveloper: "Developer",
        .presetDeveloperDesc: "With node_modules, .build, Pods and Gitignore exclusions",
        .presetDocuments: "Documents",
        .presetDocumentsDesc: "Personal essentials and office documents",
        .presetCreative: "Photos & Media",
        .presetCreativeDesc: "Image collections and media folders with SmartHash verification",
        .enableIgnoreFilesTitle: "Respect .otterkeepignore and folder markers",
        .enableIgnoreFilesDesc: "Skip folders and files matching .nobackup, CACHEDIR.TAG or ignore rules",
        .respectGitIgnoreTitle: "Respect .gitignore files",
        .respectGitIgnoreDesc: "Automatically honor .gitignore exclusion rules in git repositories",
        .backupOnVolumeMountTitle: "Backup on Volume Mount",
        .backupOnVolumeMountDesc: "Automatically trigger backup when destination drive is mounted",
        .autoEjectOnCompletionTitle: "Auto-Eject on Completion",
        .autoEjectOnCompletionDesc: "Safely unmount/eject target volume after backup and WORM protection complete",
        .searchAllSnapshots: "Search all snapshots across time...",
        .searchAllSnapshotsTitle: "Global Cross-Snapshot Search",
        .searchAllSnapshotsDesc: "Quickly locate file versions across all historical snapshots",
        .searchAllSnapshotsEmpty: "No matching files found across snapshots",
        .searchAcrossSnapshotsMode: "Search Across Snapshots",
        .permissionStatusTitle: "System Permission Status",
        .permissionFDAGranted: "Full Disk Access (FDA): Granted",
        .permissionFDAMissing: "Full Disk Access (FDA): Missing",
        .permissionFinderActive: "Finder Extension: Active",
        .permissionFinderInactive: "Finder Extension: Inactive",
        .permissionOpenSettings: "Open System Settings",
        .profilePresetsSection: "Recommended Presets",
        .enableIgnoreFilesToggle: "Respect .otterkeepignore & exclusion markers",
        .respectGitIgnoreToggle: "Respect .gitignore files",
        .backupOnVolumeMountToggle: "Backup on volume mount",
        .autoEjectOnCompletionToggle: "Auto-eject after backup completion",
        .driveAutomationHeader: "External Drive Automation",

        // v1.6.0 Sprint
        .restoreDiffMode: "What Changed?",
        .diffCompareWithLabel: "Compare with:",
        .diffTargetSnapshotLabel: "Target Snapshot:",
        .diffBaseSnapshotLabel: "Base Snapshot:",
        .diffPreviousSnapshot: "Directly preceding version",
        .diffInitialSnapshot: "Initial state (empty)",
        .diffTabAll: "All Changes",
        .diffTabAdded: "Added",
        .diffTabModified: "Modified",
        .diffTabDeleted: "Deleted",
        .diffNoChanges: "No differences between the two snapshots.",
        .diffNetChange: "Net Change:",
        .diffCompareAction: "What Changed?",

        .wifiSectionTitle: "Wi-Fi & Hotspot Filtering",
        .wifiSectionDesc: "Restrict replication and network backups to specified Wi-Fi networks and protect mobile hotspots.",
        .wifiPauseOnMeteredToggle: "Pause on Personal Hotspot & Low Data Mode",
        .wifiPauseOnMeteredDesc: "Prevents draining cellular data limits when connected to iPhone Personal Hotspot.",
        .wifiAllowedSSIDsLabel: "Allowed Wi-Fi Networks (SSID):",
        .wifiDisallowedSSIDsLabel: "Blocked Wi-Fi Networks (SSID):",
        .wifiAddCurrentButton: "Add Current Wi-Fi",
        .wifiNoActiveNetwork: "No active Wi-Fi connection",
        .wifiAllNetworksAllowed: "Any non-blocked Wi-Fi allowed",

        .webhookSectionTitle: "Webhook Remote Monitoring (Slack, Discord, Pushover)",
        .webhookSectionDesc: "Send notifications to chat channels or mobile devices upon backup completion.",
        .webhookMasterToggle: "Enable Webhook Notifications",
        .webhookServiceTypeLabel: "Service Provider:",
        .webhookUrlLabel: "Webhook URL:",
        .webhookUrlPlaceholder: "https://hooks.slack.com/... or Discord / custom URL",
        .webhookTokenLabel: "Auth Token (API Token):",
        .webhookTokenPlaceholder: "Pushover Token or Bearer token",
        .webhookTargetLabel: "Target User / Channel:",
        .webhookTargetPlaceholder: "Pushover User Key or channel",
        .webhookNotifyOnSuccess: "Notify on successful backup",
        .webhookNotifyOnWarning: "Notify when completed with warnings",
        .webhookNotifyOnFailure: "Notify on backup failure",
        .webhookTestButton: "Send Test Webhook",
        .webhookTestSuccess: "Test webhook sent successfully!",
        .webhookTestFailedFormat: "Webhook error: %@",

        .forecastSectionTitle: "Storage Forecast & Capacity",
        .forecastSectionDesc: "Growth rate analysis and proactive capacity exhaustion alerts on destination drive.",
        .forecastDailyGrowthLabel: "Average Daily Growth:",
        .forecastDaysRemainingFormat: "~%d days of storage remaining",
        .forecastSufficientSpace: "Abundant storage capacity (steady)",
        .forecastDiskFullNow: "Destination drive is full!",
        .forecastFullDatePrefix: "Estimated depletion date:",
        .forecastQuotaWarningLabel: "Warning threshold:",
        .forecastQuotaAlertToggle: "Low disk space & quota alerts",
        .forecastQuotaExceededBanner: "Warning: Destination free space has fallen below configured threshold!",
        .unitDay: "day",
        .wifiAllowedPlaceholder: "e.g. Home_WiFi, Office_5G",
        .wifiDisallowedPlaceholder: "e.g. Mobile_Hotspot, Cafe_WiFi",
        .copyRelativePathAction: "Copy Relative Path",
        .copySnapshotIdAction: "Copy Snapshot ID",

        // MARK: - v1.7.0: Ransomware & Rate-of-Change Guard
        .ransomwareSectionTitle: "Ransomware & Rate-of-Change Guard",
        .ransomwareSectionDesc: "Proactive anomaly detection preventing ransomware encryptions and accidental mass file deletions before snapshots are committed.",
        .ransomwareGuardToggle: "Enable Anomaly Shield",
        .ransomwareMaxChangePercentLabel: "Maximum Rate of Change (%):",
        .ransomwareMaxDeletedCountLabel: "Maximum Deleted File Count:",
        .ransomwareDetectExtensionsToggle: "Detect suspicious ransomware extensions (.locked, .crypto, etc.)",
        .ransomwareAbortToggle: "Abort backup immediately upon anomaly detection",
        .ransomwareThresholdPercentFormat: "%.0f%% threshold",
        .ransomwareThresholdCountFormat: "%d files",
        .notifRansomwareAlertTitle: "⚠️ Ransomware / Anomaly Detected!",
        .notifRansomwareAlertBodyFormat: "Backup aborted for profile '%@': %@",

        // MARK: - v1.7.0: Archive Packaging
        .archivePackagingSectionTitle: "Compressed Packaging (Tar.Zstandard / Tar.Gzip)",
        .archivePackagingToggle: "Package snapshots into a single compressed archive",
        .archivePackagingToggleDesc: "Uploads a single streaming .tar.zst or .tar.gz compressed archive instead of tens of thousands of individual files, minimizing S3 API request overhead.",
        .archiveCompressionLevelLabel: "Compression Level:",
        .archiveCompressionLevelFormat: "Level %d",
        .archiveFormatZstd: "Tar.Zstandard (.tar.zst)",
        .archiveFormatGzip: "Tar.Gzip (.tar.gz)",

        // MARK: - v1.7.0: Software Updates
        .settingsUpdatesSection: "Software Updates",
        .settingsUpdatesDesc: "Check for new bug fixes, security updates, and performance improvements automatically or manually.",
        .settingsAutoUpdateToggle: "Automatically check for updates in background",
        .settingsCheckForUpdatesButton: "Check for Updates Now",
        .settingsCurrentVersionFormat: "OtterKeep v%@ (Build %@)",
        .settingsUpdateStatusChecking: "Checking for updates...",
        .settingsUpdateStatusUpToDate: "OtterKeep is up to date. You are running the latest version.",
        .settingsUpdateStatusAvailableFormat: "New update available: v%@!",
        .settingsUpdateStatusFailedFormat: "Failed to check for updates: %@",
        .notifUpdateAvailableTitle: "New OtterKeep Update Available",
        .notifUpdateAvailableBodyFormat: "OtterKeep v%@ is available. Click to view or download.",

        // MARK: - v1.7.0: WebDAV & SFTP Storage Providers
        .remoteDestEditorTypeWebDAV: "WebDAV",
        .remoteDestEditorTypeSFTP: "SFTP",
        .remoteDestEditorWebDAVSettingsTitle: "WebDAV Server Configuration",
        .remoteDestEditorWebDAVURLLabel: "WebDAV Server URL:",
        .remoteDestEditorWebDAVURLPlaceholder: "https://nas.local:5006 or https://cloud.example.com",
        .remoteDestEditorWebDAVPathLabel: "Target Directory Path:",
        .remoteDestEditorWebDAVPathPlaceholder: "/remote.php/dav/files/user/OtterKeep",
        .remoteDestEditorWebDAVUsernameLabel: "Username:",
        .remoteDestEditorWebDAVUsernamePlaceholder: "WebDAV username",
        .remoteDestEditorWebDAVPasswordLabel: "Password / App Password:",
        .remoteDestEditorWebDAVPasswordPlaceholder: "Secret password",
        .remoteDestEditorSFTPSettingsTitle: "SFTP (SSH) Server Configuration",
        .remoteDestEditorSFTPHostLabel: "Hostname or IP Address:",
        .remoteDestEditorSFTPHostPlaceholder: "nas.local or 192.168.1.100",
        .remoteDestEditorSFTPPortLabel: "Port:",
        .remoteDestEditorSFTPUsernameLabel: "SSH Username:",
        .remoteDestEditorSFTPUsernamePlaceholder: "root or backup_user",
        .remoteDestEditorSFTPPasswordLabel: "Password / SSH Key Path:",
        .remoteDestEditorSFTPPasswordPlaceholder: "Password or ~/.ssh/id_ed25519",
        .remoteDestEditorSFTPPathLabel: "Remote Directory Path:",
        .remoteDestEditorSFTPPathPlaceholder: "/var/backups/otterkeep",
        .testConnectionSuccessWebDAVFormat: "WebDAV connection verified: '%@' is reachable!",
        .testConnectionSuccessSFTPFormat: "SFTP connection verified: '%@' reachable on port 22!",
        .testConnectionFailedFormat: "Connection error: %@",
        .remoteDestEditorSFTPAuthMethodLabel: "Authentication Method:",
        .remoteDestEditorSFTPAuthPassword: "Password",
        .remoteDestEditorSFTPAuthKey: "SSH Key File",
        .remoteDestEditorSFTPBrowseKeyButton: "Browse...",
        .remoteDestEditorSFTPSelectKeyTitle: "Select SSH Private Key File",
        .settingsDownloadInBrowser: "Open in Browser",

        // MARK: - About Window & Brand Lore (v1.0.0 Production Release)
        .aboutWindowTitle: "About OtterKeep",
        .aboutTagline: "Keep what you love close to your chest.",
        .aboutLoreTitle: "The Legend of the Favorite Pebble",
        .aboutLoreStory: "Sea otters have an extraordinary, instinctive ritual: throughout their entire lives, they carry their most prized favorite pebble tucked securely into a hidden pocket of skin beneath their forearms. They use it to open shells, play with it while floating on the waves, and never let it go under any circumstances. OtterKeep protects the files, historical snapshots, and precious memories on your Mac with that exact same tender vigilance and devotion.",
        .aboutReleaseHighlightsTitle: "What's New in Version 1.1.0",
        .aboutHighlight1: "Native APFS Copy-on-Write engine with instant zero-cost snapshot creation",
        .aboutHighlight2: "Apple Photos library sync with intelligent iCloud eviction safeguard",
        .aboutHighlight3: "3-2-1 backup compliance with client-side AES-256 encrypted S3, SFTP, and WebDAV replication",
        .aboutHighlight4: "Proactive Ransomware & Anomaly Shield preventing compromised snapshots",
        .aboutHighlight5: "Finder menu integration and interactive Time Machine restoration with QuickLook preview",
        .aboutVersionInfoFormat: "Version %@ (Build %@) • Production Release",
        .aboutCopyright: "© 2024–2026 Richard Eszes & OtterKeep Contributors. MIT License.",
        .aboutArchitectureTag: "Apple Silicon & Intel Universal 64-bit",
        .aboutLinksTitle: "Community & Support",
        .aboutWebsiteButton: "Project Homepage",
        .aboutDocumentationButton: "User Guides & Docs",
        .aboutReleaseNotesButton: "Release Notes",
        .aboutCloseButton: "Close",

        // MARK: - Modern UI Tooltips & Feature Badges
        .tooltipStartBackup: "Execute an incremental APFS snapshot backup now",
        .tooltipDryRun: "Analyze changes and estimate required storage without writing any data to disk",
        .tooltipStopBackup: "Safely abort the ongoing backup operation",
        .tooltipApfsCow: "Uses macOS APFS Copy-on-Write cloning. Identical blocks share physical disk space with zero duplicate overhead.",
        .tooltip321Rule: "3 copies of your data on 2 different media types, with 1 copy stored offsite or in the cloud.",
        .tooltipRansomwareShield: "Monitors rate of file changes and halts backup if sudden mass encryption or file deletions are detected.",
        .tooltipICloudEviction: "Downloads iCloud-only photos temporarily for backup, then evicts local cache so your disk never fills up.",
        .tooltipStorageForecast: "Predicts destination disk depletion date based on historical daily data growth rates.",
        .tooltipVolumeMount: "Automatically triggers this backup profile whenever the external destination volume is plugged in.",
        .tooltipAutoEject: "Safely unmounts and ejects the destination disk after backup completion to prevent accidental disconnects.",
        .tooltipFinderSync: "Integrates right-click version restore and snapshot badges directly into macOS Finder.",
        .tooltipWebhookAlerts: "Pushes real-time alerts to Slack, Discord, Pushover, or custom endpoints upon backup completion.",
        .tooltipZstdPackaging: "Streams files into a single compressed archive to drastically reduce API overhead and cloud storage fees.",
        .tooltipQuickLook: "Press Spacebar to preview the selected file version instantly using macOS QuickLook.",

        // MARK: - Actionable Guidance & Permission Errors
        .errFDAInstructionTitle: "Full Disk Access (FDA) Required",
        .errFDAInstructionDesc: "macOS requires explicit permission to back up protected folders such as Documents, Desktop, and Mail. Open System Settings > Privacy & Security > Full Disk Access and enable OtterKeep.",
        .errDiskFullRemediationDesc: "The destination volume does not have enough free space to complete this snapshot. Run storage maintenance to prune older snapshots or attach a larger drive.",
        .errRemoteUnreachableRemediationDesc: "Unable to establish connection to the remote backup endpoint. Verify your network connection, credentials, and firewall settings.",
        .errPhotosNotAuthorizedTitle: "Photos Access Restricted",
        .errPhotosNotAuthorizedDesc: "OtterKeep needs permission to access your Apple Photos Library to perform incremental backups. Enable access in System Settings > Privacy & Security > Photos.",

        // MARK: - Menu Bar Commands & Configuration Archive
        .menuFile: "File",
        .menuBackupActions: "Backup & Actions",
        .menuView: "View",
        .menuWindow: "Window",
        .menuHelp: "Help",
        .menuCheckForUpdates: "Check for Updates…",
        .menuPreferences: "Settings…",
        .menuNewProfile: "New Backup Profile…",
        .menuRenameProfile: "Rename Profile…",
        .menuExportConfig: "Export Configuration…",
        .menuImportConfig: "Import Configuration…",
        .menuCloseWindow: "Close Window",
        .menuRunBackupSelected: "Run Backup for Selected Profile",
        .menuRunAllBackups: "Run All Backups",
        .menuRunPhotosBackup: "Run Apple Photos Backup",
        .menuDryRunBackup: "Dry-Run / Simulate Backup…",
        .menuCancelBackup: "Cancel Running Backup",
        .menuBackupInspector: "Backup Inspector & Audit…",
        .menuViewOverview: "Overview",
        .menuViewTimeMachine: "Time Machine & Snapshots",
        .menuViewRulesMaintenance: "Rules & Maintenance",
        .menuViewPhotos: "Apple Photos Workspace",
        .menuViewLogs: "Diagnostic Logs",
        .menuToggleTheme: "Toggle Appearance Theme",
        .menuRefreshData: "Refresh Data & Snapshots",
        .menuMainWindow: "OtterKeep Main Window",
        .menuDocumentation: "OtterKeep Documentation",
        .menuReleaseNotes: "Release Notes",
        .menuRevealLogs: "Reveal Logs in Finder",
        .menuReportIssue: "Report an Issue on GitHub",
        .exportConfigTitle: "Export Configuration",
        .exportConfigSuccessMessage: "Configuration and backup profiles successfully exported.",
        .exportConfigErrorMessage: "Failed to export configuration: %@",
        .importConfigTitle: "Import Configuration",
        .importConfigSuccessMessage: "Configuration and backup profiles successfully imported and verified.",
        .importConfigErrorMessage: "Failed to import configuration: %@",
        .importConfigInvalidFile: "The selected file is not a valid OtterKeep configuration archive.",
        .importConfigConfirmTitle: "Confirm Configuration Import",
        .importConfigConfirmMessage: "Importing this configuration will replace your current backup profiles and settings. Do you want to proceed?",

        // MARK: - Operation Feedback & Profile Lockout (1.3.1)
        .feedbackSuccessTitle: "Backup Completed Successfully!",
        .feedbackSuccessMessage: "The backup for profile '%@' has completed successfully.",
        .feedbackViewDetails: "View Details",
        .feedbackViewLogs: "View Diagnostic Logs",
        .feedbackExternalDriveMissingTitle: "External Drive Not Found",
        .feedbackExternalDriveMissingMessage: "The backup destination '%@' was disconnected or is unavailable.",
        .feedbackExternalDriveMissingAdvice: "Reconnect the external drive to your Mac and retry. Your existing snapshots and original Mac files remain safe and sound.",
        .feedbackSourceFolderMissingTitle: "Source Folder Not Found",
        .feedbackSourceFolderMissingMessage: "The source directory '%@' could not be found.",
        .feedbackSourceFolderMissingAdvice: "Verify that the folder was not moved, renamed, or located on a disconnected drive.",
        .feedbackDiskFullTitle: "Destination Disk is Full",
        .feedbackDiskFullMessage: "There is not enough free disk space on the destination volume to store this snapshot.",
        .feedbackDiskFullAdvice: "Free up disk space on the target volume or configure automated retention pruning.",
        .feedbackPermissionDeniedTitle: "Permission Denied",
        .feedbackPermissionDeniedMessage: "OtterKeep does not have permission to access the selected files or directories.",
        .feedbackPermissionDeniedAdvice: "Please grant Full Disk Access to OtterKeep in macOS System Settings > Privacy & Security.",
        .feedbackGeneralErrorTitle: "Backup Operation Failed",
        .feedbackGeneralErrorAdvice: "Your existing data and snapshots remain untouched. Check the diagnostic logs for detailed error telemetry.",
        .profileLockedBannerTitle: "Backup in Progress",
        .profileLockedBannerMessage: "Profile settings are temporarily locked while backup is running to preserve data consistency.",

        // MARK: - Restore & Maintenance (1.4.0)
        .restoredSuffixFormat: " (restored %d)"
    ]
}

