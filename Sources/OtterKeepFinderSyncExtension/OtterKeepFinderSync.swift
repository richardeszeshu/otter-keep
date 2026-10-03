import Cocoa
import FinderSync
import os
import OtterKeepCore

/// Native macOS Finder Sync Extension providing contextual menu integration for backup profiles.
///
/// This extension registers all configured backup profile source directories with `FIFinderSyncController`
/// and injects a context menu item allowing users to browse and restore previous versions of any file.
@objc(OtterKeepFinderSync)
public final class OtterKeepFinderSync: FIFinderSync, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.otterkeep", category: "FinderSync")
    private var monitoredDirectoryURLs: Set<URL> = []

    public override init() {
        super.init()
        logger.info("Initializing OtterKeepFinderSync extension...")
        updateMonitoredDirectories()

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.otterkeep.finderIntegrationChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateMonitoredDirectories()
        }
    }

    /// Reloads backup profile source directories and their iCloud Drive counterparts, updating `FIFinderSyncController`.
    public func updateMonitoredDirectories() {
        let isEnabled = FinderIntegrationStore.shared.isEnabled
        logger.info("updateMonitoredDirectories() called. isEnabled: \(isEnabled, privacy: .public)")
        guard isEnabled else {
            if !monitoredDirectoryURLs.isEmpty {
                monitoredDirectoryURLs = []
                FIFinderSyncController.default().directoryURLs = []
                logger.info("Finder Integration is disabled: cleared monitored directories.")
            } else {
                logger.info("Finder Integration is disabled and monitored directories are already empty.")
            }
            return
        }

        var candidateURLs: Set<URL> = []
        let profiles = ProfileStore.shared.loadProfiles()
        for profile in profiles {
            let url = profile.sourceURL.standardizedFileURL.resolvingSymlinksInPath()
            candidateURLs.insert(url)
        }

        if candidateURLs != monitoredDirectoryURLs {
            monitoredDirectoryURLs = candidateURLs
            FIFinderSyncController.default().directoryURLs = candidateURLs
            logger.info("Updated monitored Finder Sync directories: \(candidateURLs.count, privacy: .public) directories registered: \(candidateURLs.map { $0.path }, privacy: .public)")
        } else {
            logger.info("Monitored Finder Sync directories already match current set (\(candidateURLs.count, privacy: .public) directories).")
        }
    }

    // MARK: - Directory Observation Lifecycle

    public override func beginObservingDirectory(at url: URL) {
        logger.info("beginObservingDirectory(at: '\(url.path, privacy: .public)')")
    }

    public override func endObservingDirectory(at url: URL) {
        logger.info("endObservingDirectory(at: '\(url.path, privacy: .public)')")
    }

    // MARK: - Toolbar Item Integration

    public override var toolbarItemName: String {
        "OtterKeep"
    }

    public override var toolbarItemToolTip: String {
        L10n.t(.finderContextMenuBrowseVersions)
    }

    public override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "OtterKeep") ?? NSImage()
    }

    // MARK: - Menu and Contextual Items

    public override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let isEnabled = FinderIntegrationStore.shared.isEnabled
        let selectedURLs = FIFinderSyncController.default().selectedItemURLs()
        let targetedURL = FIFinderSyncController.default().targetedURL()
        let selectedPaths = selectedURLs?.map { $0.path } ?? []
        let targetedPath = targetedURL?.path ?? "nil"

        logger.info("menu(for: \(menuKind.rawValue, privacy: .public)) invoked. isEnabled: \(isEnabled, privacy: .public), selected: \(selectedPaths, privacy: .public), targeted: \(targetedPath, privacy: .public)")

        guard isEnabled else {
            return nil
        }

        guard menuKind == .contextualMenuForItems ||
              menuKind == .contextualMenuForContainer ||
              menuKind == .contextualMenuForSidebar ||
              menuKind == .toolbarItemMenu else {
            logger.info("menu(for:) skipped for kind: \(menuKind.rawValue, privacy: .public)")
            return nil
        }

        let menu = NSMenu(title: "")
        let menuItem = NSMenuItem(
            title: L10n.t(.finderContextMenuBrowseVersions),
            action: #selector(browseVersionsAction(_:)),
            keyEquivalent: ""
        )
        menuItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        menuItem.target = self
        menu.addItem(menuItem)

        logger.info("menu(for: \(menuKind.rawValue, privacy: .public)) returning menu with item: '\(menuItem.title, privacy: .public)'")
        return menu
    }

    /// Action invoked when user selects the contextual menu item in Finder.
    @objc(browseVersionsAction:)
    public func browseVersionsAction(_ sender: AnyObject?) {
        let selectedURLs = FIFinderSyncController.default().selectedItemURLs()
        let targetedURL = FIFinderSyncController.default().targetedURL()
        guard let targetURL = selectedURLs?.first ?? targetedURL else {
            logger.warning("No item selected or targeted in Finder.")
            return
        }

        let rawPath = targetURL.path(percentEncoded: false)
        let targetPath = BackupProfile.canonicalizePath(rawPath)
        logger.info("User requested version history for: '\(targetPath, privacy: .public)' (raw: '\(rawPath, privacy: .public)')")

        // 1. First attempt to signal the running primary GUI instance via Unix Domain Socket IPC
        let message = SingleInstanceMessage(action: .openVersionHistory, filePath: targetPath)
        let delivered = SingleInstanceManager.shared.sendMessageToRunningInstance(message)

        if delivered {
            logger.info("Delivered version history request to active GUI instance via IPC.")
            return
        }

        // 2. Fallback: Launch or activate GUI with URL scheme or CLI invocation
        var components = URLComponents()
        components.scheme = "otterkeep"
        components.host = "restore-versions"
        components.queryItems = [URLQueryItem(name: "path", value: targetPath)]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }
}
