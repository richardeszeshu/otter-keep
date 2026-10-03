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
            return "Replication..."
        } else {
            return L10n.t(.menuBarStatusIdle)
        }
    }

    // MARK: - Running Operation Banner
    private var runningOperationBanner: some View {
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
        .padding(8)
        .background(OtterTheme.otterAmber.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(OtterTheme.otterAmber.opacity(0.2), lineWidth: 1)
        )
    }

    private var runningTitle: String {
        if appState.isPhotosBackupRunning {
            return L10n.t(.navPhotosBackup)
        } else if appState.isReplicationRunning {
            return "3-2-1 Replication"
        } else {
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
                    .disabled(appState.isBackupRunning)
                }
            }

            if appState.profiles.isEmpty {
                Text(L10n.t(.noProfileSelectedTitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                let displayedProfiles = Array(appState.profiles.prefix(3))
                VStack(spacing: 4) {
                    ForEach(displayedProfiles) { profile in
                        profileRow(for: profile)
                    }

                    if appState.profiles.count > 3 {
                        Button {
                            openMainWindow()
                        } label: {
                            HStack {
                                Spacer()
                                Text("+\(appState.profiles.count - 3) more profiles...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func profileRow(for profile: BackupProfile) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.selectedProfileId == profile.id ? OtterTheme.otterAmber : Color.secondary.opacity(0.35))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                if profile.schedule.isEnabled {
                    Text(L10n.t(.menuBarNextRun) + " " + appState.nextScheduledRunDescription(for: profile))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(profile.sourceURL.lastPathComponent)
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

            Button {
                appState.startBackup(for: profile)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(appState.isBackupRunning)
            .help(L10n.t(.menuBarBackupProfile))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
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
        if let capacity = appState.destinationStorageCapacity() {
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
                        Text(L10n.t(.menuBarStorageGlance))
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "internaldrive.fill")
                            .font(.caption2)
                            .foregroundStyle(OtterTheme.oceanicTeal)
                    }

                    Spacer()

                    Text(ByteCountFormatter.string(fromByteCount: capacity.availableBytes, countStyle: .file) + " " + L10n.t(.storageFreeLabel))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
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
