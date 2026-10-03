import SwiftUI
import AppKit
import OtterKeepCore

/// Unified view combining profile rules, exclusion patterns, iCloud strategy,
/// backup schedules, retention policies, and catalog recovery maintenance.
public struct ProfileRulesAndMaintenanceView: View {
    public let appState: AppState
    public let profile: BackupProfile

    public init(appState: AppState, profile: BackupProfile) {
        self.appState = appState
        self.profile = profile
    }

    private var maxSnapshotsToKeepBinding: Binding<Int> {
        Binding(get: { appState.maxSnapshotsToKeep }, set: { appState.maxSnapshotsToKeep = $0 })
    }

    private var showConfirmPruneBinding: Binding<Bool> {
        Binding(get: { appState.showConfirmPrune }, set: { appState.showConfirmPrune = $0 })
    }

    private var showConfirmRebuildBinding: Binding<Bool> {
        Binding(get: { appState.showConfirmRebuild }, set: { appState.showConfirmRebuild = $0 })
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Existing Profile Rules (Directories, iCloud, Exclusions, Schedules)
                ProfileRulesView(appState: appState).content

                // 2. Storage Maintenance & Retention Consolidation
                maintenanceSection

                // 3. Disaster Recovery Catalog Rebuild
                catalogRecoverySection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(
            L10n.t(.maintenancePruneConfirmTitle),
            isPresented: showConfirmPruneBinding,
            titleVisibility: .visible
        ) {
            Button(L10n.t(.maintenancePruneConfirmAction), role: .destructive) {
                appState.pruneOldSnapshots(maxKeep: appState.maxSnapshotsToKeep)
            }
            Button(L10n.t(.cancel), role: .cancel) {}
        } message: {
            Text(L10n.t(.maintenancePruneConfirmMessage))
        }
        .confirmationDialog(
            L10n.t(.maintenanceRebuildConfirmTitle),
            isPresented: showConfirmRebuildBinding,
            titleVisibility: .visible
        ) {
            Button(L10n.t(.maintenanceRebuildConfirmAction)) {
                appState.disasterRebuildCatalog()
            }
            Button(L10n.t(.cancel), role: .cancel) {}
        } message: {
            Text(L10n.t(.maintenanceRebuildConfirmMessage))
        }
        .sheet(isPresented: Binding(
            get: { appState.showRemoteDestinationEditorSheet },
            set: { appState.showRemoteDestinationEditorSheet = $0 }
        )) {
            RemoteDestinationEditorModalView(appState: appState)
        }
    }

    // MARK: - Retention Consolidation Card
    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "scissors")
                    .font(.title3)
                    .foregroundStyle(OtterTheme.squirrelOrange)
                Text(L10n.t(.maintenanceConsolidationTitle))
                    .font(.headline)
            }

            Text(L10n.t(.maintenanceConsolidationDesc))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Text(L10n.t(.maintenanceKeepSnapshotsLabel))
                    .font(.body.weight(.medium))

                Stepper(L10n.format(.unitCountFormat, appState.maxSnapshotsToKeep), value: maxSnapshotsToKeepBinding, in: 1...50)
                    .font(.body)
                    .frame(width: 140)

                Spacer()

                Button(L10n.t(.maintenancePruneButton)) {
                    appState.showConfirmPrune = true
                }
                .buttonStyle(.borderedProminent)
                .tint(OtterTheme.squirrelOrange)
                .disabled(appState.snapshots.count <= appState.maxSnapshotsToKeep)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .squirrelCard()
    }

    // MARK: - Disaster Recovery Card
    private var catalogRecoverySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.title3)
                    .foregroundStyle(OtterTheme.cyberTeal)
                Text(L10n.t(.maintenanceRecoveryTitle))
                    .font(.headline)
            }

            Text(L10n.t(.maintenanceRecoveryDesc))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(L10n.t(.maintenanceRebuildButton)) {
                    appState.showConfirmRebuild = true
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .squirrelCard()
    }
}
