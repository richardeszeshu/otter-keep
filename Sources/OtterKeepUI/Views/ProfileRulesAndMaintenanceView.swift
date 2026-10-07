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

                // 2. Storage Maintenance & Retention Consolidation (Equal Height Cards)
                Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow {
                        maintenanceSection
                        catalogRecoverySection
                    }
                }

                // 3. Profile Metadata & Technical Identifiers (UUID)
                profileMetadataSection
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

            Spacer(minLength: 8)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .otterCard(padding: 16)
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

            Spacer(minLength: 8)

            HStack {
                Spacer()
                Button(L10n.t(.maintenanceRebuildButton)) {
                    appState.showConfirmRebuild = true
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .otterCard(padding: 16)
    }

    // MARK: - Profile Metadata & Identifiers Card
    private var profileMetadataSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "barcode.viewfinder")
                    .font(.title3)
                    .foregroundStyle(OtterTheme.otterAmber)
                Text(L10n.t(.profileMetadataSectionTitle))
                    .font(.headline)
            }

            Text(L10n.t(.profileMetadataSectionDesc))
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.uuidLabel))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(profile.id.uuidString)
                            .font(.callout.monospaced())
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(profile.id.uuidString, forType: .string)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text(L10n.t(.settingsCopyUUID))
                        }
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Divider()

                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.sourceFolderTitle))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(profile.sourceURL.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.destinationFolderTitle))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(profile.destinationURL.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .otterCard(padding: 16)
    }
}
