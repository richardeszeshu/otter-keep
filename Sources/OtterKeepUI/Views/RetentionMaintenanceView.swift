import SwiftUI
import OtterKeepCore

public struct RetentionMaintenanceView: View {
    public let appState: AppState

    private var maxSnapshotsToKeepBinding: Binding<Int> {
        Binding(get: { appState.maxSnapshotsToKeep }, set: { appState.maxSnapshotsToKeep = $0 })
    }

    private var showConfirmPruneBinding: Binding<Bool> {
        Binding(get: { appState.showConfirmPrune }, set: { appState.showConfirmPrune = $0 })
    }

    private var showConfirmRebuildBinding: Binding<Bool> {
        Binding(get: { appState.showConfirmRebuild }, set: { appState.showConfirmRebuild = $0 })
    }

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Storage statistics
                HStack(spacing: 16) {
                    statisticBox(title: L10n.t(.maintenanceTotalSnapshots), value: "\(appState.snapshots.count)", systemImage: "clock.arrow.circlepath")
                    statisticBox(title: L10n.t(.maintenanceTotalBackupSize), value: totalBackupSizeFormatted, systemImage: "internaldrive")
                }

                // Retention consolidation section
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.t(.maintenanceConsolidationTitle))
                        .font(.title2.bold())
                    Text(L10n.t(.maintenanceConsolidationDesc))
                        .font(.body)
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
                        .tint(.orange)
                        .disabled(appState.snapshots.count <= appState.maxSnapshotsToKeep)
                    }
                }
                .padding()
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))

                // Disaster Recovery Catalog Rebuild Section
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.t(.maintenanceRecoveryTitle))
                        .font(.title2.bold())
                    Text(L10n.t(.maintenanceRecoveryDesc))
                        .font(.body)
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
                .padding()
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
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
    }

    private var totalBackupSizeFormatted: String {
        let total = appState.snapshots.reduce(0) { $0 + $1.totalBytes }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: total)
    }

    private func statisticBox(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.bold().monospacedDigit())
            }
            Spacer()
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}
