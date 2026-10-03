import SwiftUI
import AppKit
import OtterKeepCore

/// Unified workspace for an individual backup profile, featuring a top segmented navigation bar
/// between Overview (live telemetry & pipeline), Time Machine (restore explorer), and Rules & Maintenance.
public struct ProfileWorkspaceView: View {
    public let profile: BackupProfile
    public let appState: AppState

    public init(profile: BackupProfile, appState: AppState) {
        self.profile = profile
        self.appState = appState
    }

    private var activeTabBinding: Binding<ProfileWorkspaceTab> {
        Binding(
            get: { appState.activeProfileTab },
            set: { appState.activeProfileTab = $0 }
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Modern Navigation & Action Bar
            workspaceHeaderBar

            Divider()

            // Tab Content
            switch appState.activeProfileTab {
            case .overview:
                MainDashboardView(appState: appState)
            case .timeMachine:
                RestoreExplorerView(appState: appState)
            case .rulesAndMaintenance:
                ProfileRulesAndMaintenanceView(appState: appState, profile: profile)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Modern Workspace Header Bar
    private var workspaceHeaderBar: some View {
        HStack(spacing: 16) {
            // Profile Title and APFS Badge
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.headline.bold())

                    let cowMode = appState.volumeEvaluation?.cowMode ?? .intraVolumeCoW
                    HStack(spacing: 4) {
                        Image(systemName: cowMode == .nonAPFS ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                        Text(L10n.t(cowMode.badgeKey))
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(cowMode == .nonAPFS ? OtterTheme.statusWarning : OtterTheme.statusGreen)
                }
            }

            Spacer()

            // Centered Segmented Workspace Tabs
            Picker("", selection: activeTabBinding) {
                ForEach(ProfileWorkspaceTab.allCases) { tab in
                    Label(tab.localizedTitle, systemImage: tab.iconName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)
            .frame(maxWidth: 420)

            Spacer()

            // Quick Action Buttons
            HStack(spacing: 8) {
                // Dry-Run Button
                Button {
                    appState.performDryRun()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: appState.isDryRunRunning ? "arrow.triangle.2.circlepath" : "magnifyingglass")
                            .symbolEffect(.rotate, isActive: appState.isDryRunRunning)
                        Text(appState.isDryRunRunning ? L10n.t(.analyzingProgress) : L10n.t(.quickDryRunAction))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(appState.isBackupRunning || appState.isDryRunRunning)

                // Backup Now / Stop Button
                if appState.isBackupRunning {
                    Button(role: .destructive) {
                        appState.cancelBackup()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.circle.fill")
                            Text(L10n.t(.stopBackupButton))
                        }
                        .font(.body.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OtterTheme.statusError)
                    .controlSize(.regular)
                } else {
                    Button {
                        appState.startBackup()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                            Text(L10n.t(.quickBackupAction))
                        }
                        .font(.body.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OtterTheme.squirrelOrange)
                    .controlSize(.regular)
                    .disabled(appState.isDryRunRunning)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}
