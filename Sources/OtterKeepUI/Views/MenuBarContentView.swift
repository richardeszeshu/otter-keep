import SwiftUI
import AppKit
import OtterKeepCore
import OtterKeepStorage

/// MenuBar popup window interface presenting live backup status, all configured profiles, quick trigger actions, and system shortcuts.
public struct MenuBarContentView: View {
    public let appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerView

            if isAnyOperationRunning {
                runningOperationBanner
            }

            if let update = appState.softwareUpdateAvailableInfo {
                updateAvailableBanner(update: update)
            }

            Divider()

            // Profiles list & trigger all
            profilesSection

            Divider()

            // Apple Photos Backup Card
            photosBackupCard

            // Destination Storage Glance Card (if available)
            storageGlanceCard

            Divider()

            // Bottom action controls
            footerControls
        }
        .padding(12)
        .frame(width: 320)
        .preferredColorScheme(appState.currentTheme.colorScheme)
    }

    private var isAnyOperationRunning: Bool {
        appState.isBackupRunning || appState.isPhotosBackupRunning || appState.isReplicationRunning
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 8) {
            OtterKeepLogoView(size: 26, withGlow: true, withBorder: true)

            VStack(alignment: .leading, spacing: 2) {
                Text("OtterKeep")
                    .font(.body.bold())
                HStack(spacing: 5) {
                    Circle()
                        .fill(isAnyOperationRunning ? OtterTheme.otterAmber : OtterTheme.statusGreen)
                        .frame(width: 6, height: 6)
                    Text(statusSummaryText)
                        .font(.caption2)
                        .foregroundStyle(isAnyOperationRunning ? OtterTheme.otterAmber : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Quick Time Machine / Restore Explorer Shortcut Button
            Button {
                openRestoreExplorer()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OtterTheme.oceanicTeal)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t(.menuBarTimeMachine))

            // Quick Theme Switcher Button
            Button {
                cycleTheme()
            } label: {
                Image(systemName: appState.currentTheme.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t(.menuBarQuickTheme))

            // Settings Shortcut Button
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t(.menuBarOpenSettings))
        }
    }

    private var statusSummaryText: String {
        if appState.isPhotosBackupRunning {
            return "\(L10n.t(.navPhotosBackup)): " + appState.photosProgressState.phaseDescription
        } else if appState.isBackupRunning {
            return L10n.t(.menuBarStatusRunning)
        } else if appState.isReplicationRunning {
            return L10n.t(.menuBarReplicationRunning)
        } else {
            return L10n.t(.menuBarStatusIdle)
        }
    }

    // MARK: - Running Operation Banner
    private var runningOperationBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.mini)

                VStack(alignment: .leading, spacing: 1) {
                    Text(runningTitle)
                        .font(.caption.bold())
                        .foregroundStyle(OtterTheme.otterAmber)
                    Text(runningDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(role: .destructive) {
                    appState.cancelBackup()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.circle.fill")
                        Text(L10n.t(.stopBackupButton))
                    }
                    .font(.caption2.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(OtterTheme.statusError)
                .controlSize(.mini)
            }

            // Live Linear Progress & Telemetry
            if let fraction = runningProgressFraction {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(OtterTheme.otterAmber)

                    HStack {
                        Text("\(Int(fraction * 100))%")
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundStyle(OtterTheme.otterAmber)

                        if let speed = runningSpeedText {
                            Spacer()
                            Label(speed, systemImage: "bolt.fill")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(OtterTheme.oceanicTeal)
                        }

                        if let metrics = runningMetricsText {
                            Spacer()
                            Text(metrics)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(OtterTheme.otterAmber.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(OtterTheme.otterAmber.opacity(0.2), lineWidth: 1)
        )
    }

    private var runningProgressFraction: Double? {
        if appState.isPhotosBackupRunning {
            return appState.photosProgressState.progressFraction
        } else if appState.isBackupRunning {
            let prog = appState.progressState
            if prog.totalBytes > 0 {
                return min(1.0, max(0.0, Double(prog.processedBytes) / Double(prog.totalBytes)))
            } else if prog.totalFiles > 0 {
                let processed = prog.copiedCount + prog.clonedCount + prog.skippedCount
                return min(1.0, max(0.0, Double(processed) / Double(prog.totalFiles)))
            }
        }
        return nil
    }

    private var runningSpeedText: String? {
        if appState.isPhotosBackupRunning && appState.photosProgressState.currentSpeedBytesPerSecond > 0 {
            let spd = ByteCountFormatter.string(fromByteCount: Int64(appState.photosProgressState.currentSpeedBytesPerSecond), countStyle: .file)
            return "\(spd)/s"
        } else if appState.isBackupRunning && appState.progressState.speedBytesPerSecond > 0 {
            let spd = ByteCountFormatter.string(fromByteCount: Int64(appState.progressState.speedBytesPerSecond), countStyle: .file)
            return "\(spd)/s"
        }
        return nil
    }

    private var runningMetricsText: String? {
        if appState.isPhotosBackupRunning {
            if appState.photosProgressState.totalAssetsCount > 0 {
                return "\(appState.photosProgressState.processedAssetsCount)/\(appState.photosProgressState.totalAssetsCount)"
            }
        } else if appState.isBackupRunning {
            let prog = appState.progressState
            if prog.totalFiles > 0 {
                let processed = prog.copiedCount + prog.clonedCount + prog.skippedCount
                return "\(processed)/\(prog.totalFiles)"
            }
        }
        return nil
    }

    private var runningTitle: String {
        if appState.isPhotosBackupRunning {
            return L10n.t(.navPhotosBackup)
        } else if appState.isReplicationRunning {
            return L10n.t(.menuBarReplicationRunning)
        } else {
            let runningProfiles = appState.profiles.filter { appState.isBackupRunning(for: $0.id) }
            if runningProfiles.count == 1, let single = runningProfiles.first {
                return single.name
            } else if runningProfiles.count > 1 {
                return "\(L10n.t(.menuBarStatusRunning)) (\(runningProfiles.count))"
            }
            return L10n.t(.menuBarStatusRunning)
        }
    }

    private var runningDetail: String {
        if appState.isPhotosBackupRunning {
            return appState.photosProgressState.phaseDescription
        } else if appState.isBackupRunning {
            let item = appState.progressState.currentItem
            return item.isEmpty ? appState.progressState.phase.rawValue.capitalized : item
        } else {
            return ""
        }
    }

    // MARK: - Software Update Notice Banner
    private func updateAvailableBanner(update: SoftwareUpdateInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption.bold())
                .foregroundStyle(OtterTheme.otterAmber)

            Text(L10n.format(.settingsUpdateStatusAvailableFormat, update.version))
                .font(.caption2.bold())
                .lineLimit(1)

            Spacer()

            Button {
                openSettings()
            } label: {
                Text(L10n.t(.settingsDownloadInBrowser))
                    .font(.caption2.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(OtterTheme.otterAmber)
            .controlSize(.mini)
        }
        .padding(8)
        .background(OtterTheme.otterAmber.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Profiles Section
    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text(L10n.t(.menuBarProfilesTitle))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.caption)
                        .foregroundStyle(OtterTheme.oceanicTeal)
                }

                Spacer()

                if !appState.profiles.isEmpty {
                    Button {
                        appState.startBackupAll(mode: .incremental)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 9))
                            Text(L10n.t(.menuBarBackupAll))
                                .font(.caption2.bold())
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OtterTheme.otterAmber)
                    .controlSize(.mini)
                }
            }

            if appState.profiles.isEmpty {
                Text(L10n.t(.noProfileSelectedTitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else if appState.profiles.count <= 3 {
                VStack(spacing: 4) {
                    ForEach(appState.profiles) { profile in
                        profileRow(for: profile)
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(appState.profiles) { profile in
                            profileRow(for: profile)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }

    private func profileRow(for profile: BackupProfile) -> some View {
        let isRunning = appState.isBackupRunning(for: profile.id)
        let statusInfo = appState.lastStatusInfo(for: profile)

        return HStack(spacing: 8) {
            if isRunning {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(statusInfo.statusColor)
                    .frame(width: 6, height: 6)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                if isRunning {
                    let prog = appState.progressState(for: profile.id)
                    Text(L10n.t(prog.phase.localizedKey))
                        .font(.caption2)
                        .foregroundStyle(OtterTheme.otterAmber)
                        .lineLimit(1)
                } else if profile.schedule.isEnabled {
                    Text(L10n.t(.menuBarNextRun) + " " + appState.nextScheduledRunDescription(for: profile))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(statusInfo.displayDetailText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                appState.selectProfile(id: profile.id)
                openMainWindow()
            }

            Spacer()

            if isRunning {
                Button {
                    appState.cancelBackup(for: profile.id)
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9))
                }
                .buttonStyle(.bordered)
                .tint(OtterTheme.statusError)
                .controlSize(.mini)
                .help(L10n.t(.stopBackupButton))
            } else {
                Button {
                    appState.startBackup(for: profile, mode: .incremental)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help(L10n.t(.menuBarBackupProfile))

                // Profile action menu
                Menu {
                    Button {
                        appState.startBackup(for: profile, mode: .incremental)
                    } label: {
                        Label(L10n.t(.menuBarBackupProfile), systemImage: "play.circle")
                    }
                    .disabled(isRunning)

                    Button {
                        appState.startBackup(for: profile, mode: .full)
                    } label: {
                        Label(L10n.t(.menuBarFullBackup), systemImage: "arrow.clockwise.circle")
                    }
                    .disabled(isRunning)

                    Button {
                        appState.selectProfile(id: profile.id)
                        appState.performDryRun(mode: .incremental)
                        openMainWindow()
                    } label: {
                        Label(L10n.t(.menuBarSimulateDryRun), systemImage: "wand.and.stars")
                    }
                    .disabled(isRunning)

                    Divider()

                    Button {
                        appState.selectProfile(id: profile.id)
                        openRestoreExplorer()
                    } label: {
                        Label(L10n.t(.menuBarTimeMachine), systemImage: "clock.arrow.circlepath")
                    }

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([profile.destinationURL])
                    } label: {
                        Label(L10n.t(.menuBarRevealDestination), systemImage: "arrow.up.forward.app")
                    }

                    Button {
                        appState.selectProfile(id: profile.id)
                        appState.activeProfileTab = .rulesAndMaintenance
                        openMainWindow()
                    } label: {
                        Label(L10n.t(.menuBarOpenRules), systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 18, height: 18)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
        .contextMenu {
            Button {
                appState.startBackup(for: profile, mode: .incremental)
            } label: {
                Label(L10n.t(.menuBarBackupProfile), systemImage: "play.circle")
            }
            .disabled(isRunning)

            Button {
                appState.startBackup(for: profile, mode: .full)
            } label: {
                Label(L10n.t(.menuBarFullBackup), systemImage: "arrow.clockwise.circle")
            }
            .disabled(isRunning)

            Button {
                appState.selectProfile(id: profile.id)
                appState.performDryRun(mode: .incremental)
                openMainWindow()
            } label: {
                Label(L10n.t(.menuBarSimulateDryRun), systemImage: "wand.and.stars")
            }
            .disabled(isRunning)

            Divider()

            Button {
                appState.selectProfile(id: profile.id)
                openRestoreExplorer()
            } label: {
                Label(L10n.t(.menuBarTimeMachine), systemImage: "clock.arrow.circlepath")
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([profile.destinationURL])
            } label: {
                Label(L10n.t(.menuBarRevealDestination), systemImage: "arrow.up.forward.app")
            }

            Button {
                appState.selectProfile(id: profile.id)
                appState.activeProfileTab = .rulesAndMaintenance
                openMainWindow()
            } label: {
                Label(L10n.t(.menuBarOpenRules), systemImage: "slider.horizontal.3")
            }
        }
    }

    // MARK: - Apple Photos Backup Card
    private var photosBackupCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text(L10n.t(.navPhotosBackup))
                        .font(.caption.bold())
                } icon: {
                    Image(systemName: "photo.stack.fill")
                        .font(.caption)
                        .foregroundStyle(OtterTheme.otterAmber)
                }

                Spacer()

                if appState.isPhotosBackupRunning {
                    ProgressView()
                        .controlSize(.mini)
                } else if appState.photosLibraryTotalCount > 0 {
                    Text(L10n.format(.assetsCountUnitFormat, appState.photosLibraryTotalCount))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                appState.startPhotosBackup()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: appState.isPhotosBackupRunning ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill")
                    Text(appState.isPhotosBackupRunning ? L10n.t(.photosBackupRunningButton) : L10n.t(.photosStartBackupButton))
                }
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.isPhotosBackupRunning)
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Storage Glance Card
    @ViewBuilder
    private var storageGlanceCard: some View {
        if let profile = appState.selectedProfile {
            let isReachable = appState.isDestinationReachable(for: profile)
            let isRemovable = appState.isDestinationRemovable(for: profile)
            let volName = appState.destinationVolumeName(for: profile) ?? profile.destinationURL.lastPathComponent

            if !isReachable {
                // Destination offline / unmounted notice
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(OtterTheme.statusWarning)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(volName)
                            .font(.caption2.bold())
                        Text(L10n.t(.menuBarExternalVolumeDisconnected))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(8)
                .background(OtterTheme.statusWarning.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            } else if let capacity = appState.destinationStorageCapacity() {
                let usedBytes = max(0, capacity.totalBytes - capacity.availableBytes)
                let usedFraction = capacity.totalBytes > 0 ? Double(usedBytes) / Double(capacity.totalBytes) : 0.0
                let gaugeColor: Color = {
                    if usedFraction > 0.9 {
                        return OtterTheme.statusError
                    } else if usedFraction > 0.8 {
                        return OtterTheme.statusWarning
                    } else {
                        return OtterTheme.oceanicTeal
                    }
                }()

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label {
                            Text(volName)
                                .font(.caption2.bold())
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: isRemovable ? "externaldrive.fill" : "internaldrive.fill")
                                .font(.caption2)
                                .foregroundStyle(OtterTheme.oceanicTeal)
                        }

                        Spacer()

                        Text(ByteCountFormatter.string(fromByteCount: capacity.availableBytes, countStyle: .file) + " " + L10n.t(.storageFreeLabel))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)

                        if isRemovable {
                            Button {
                                appState.ejectDestinationVolume(for: profile)
                            } label: {
                                Image(systemName: "eject.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(L10n.t(.menuBarEjectVolume))
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 4)
                            Capsule()
                                .fill(gaugeColor)
                                .frame(width: geo.size.width * CGFloat(min(1.0, max(0.0, usedFraction))), height: 4)
                        }
                    }
                    .frame(height: 4)
                }
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Footer Controls
    private var footerControls: some View {
        HStack(spacing: 8) {
            Button {
                openMainWindow()
            } label: {
                Label(L10n.t(.menuBarOpenApp), systemImage: "macwindow")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            Spacer()

            // Check for Updates button
            Button {
                appState.checkForSoftwareUpdates(silent: false)
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .rotationEffect(appState.isCheckingForSoftwareUpdates ? .degrees(360) : .zero)
                    .animation(appState.isCheckingForSoftwareUpdates ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: appState.isCheckingForSoftwareUpdates)
            }
            .buttonStyle(.plain)
            .help(L10n.t(.menuBarCheckUpdates))

            Button {
                AboutWindowController.shared.show()
            } label: {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.t(.aboutWindowTitle))

            Button {
                openLogs()
            } label: {
                Image(systemName: "list.bullet.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.t(.menuBarOpenLogs))

            Divider()
                .frame(height: 12)

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.caption)
                    .foregroundStyle(OtterTheme.statusError)
            }
            .buttonStyle(.plain)
            .help(L10n.t(.menuBarQuit))
        }
        .padding(.top, 2)
    }

    private func openMainWindow() {
        WindowManager.showAndFocusMainWindow()
    }

    private func openRestoreExplorer() {
        if let sel = appState.selectedProfileId ?? appState.profiles.first?.id {
            appState.selectProfile(id: sel)
            appState.activeProfileTab = .timeMachine
        }
        WindowManager.showAndFocusMainWindow()
    }

    private func openSettings() {
        appState.activeNavigation = .settings
        WindowManager.showAndFocusMainWindow()
    }

    private func openLogs() {
        appState.activeNavigation = .logs
        WindowManager.showAndFocusMainWindow()
    }

    private func cycleTheme() {
        switch appState.currentTheme {
        case .system:
            appState.currentTheme = .light
        case .light:
            appState.currentTheme = .dark
        case .dark:
            appState.currentTheme = .system
        }
    }
}
