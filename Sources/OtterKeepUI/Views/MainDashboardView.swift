import SwiftUI
import AppKit
import OtterKeepCore

/// Overview and primary backup dashboard view for the currently selected folder profile,
/// featuring the visual APFS CoW pipeline, Apple-style storage gauge, and live telemetry.
public struct MainDashboardView: View {
    public let appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OtterTheme.spacing16) {
                if let profile = appState.selectedProfile {
                    // SPOF Warning Banner (Hardware Redundancy Alert)
                    if appState.volumeEvaluation?.isSameVolume == true {
                        spofWarningBanner()
                    }

                    // 1. Visual APFS CoW Pipeline
                    BackupPipelineView(
                        sourceURL: profile.sourceURL,
                        destinationURL: profile.destinationURL,
                        cowMode: appState.volumeEvaluation?.cowMode ?? .intraVolumeCoW,
                        isActive: appState.isBackupRunning
                    )

                    // 2. Storage Gauge Card
                    if let capacity = appState.destinationStorageCapacity() {
                        StorageGaugeBar(
                            totalBytes: capacity.totalBytes,
                            backupBytes: appState.totalBackupSize(),
                            freeBytes: capacity.availableBytes,
                            title: L10n.t(.destinationFolderTitle),
                            subtitle: profile.destinationURL.lastPathComponent
                        )
                        .otterCard()
                    }

                    // 3. 3-2-1 Rule & Off-site Compliance Card
                    rule321ComplianceCard(profile: profile)

                    // 4. Live Replication Banner
                    if appState.isReplicationRunning {
                        liveReplicationBanner
                    }

                    // 5. Live Telemetry HUD (When backup is actively running) or Last Session Summary
                    if appState.isBackupRunning {
                        liveTelemetryHUD
                    } else if let summary = appState.lastSessionSummary {
                        lastSessionCard(summary: summary)
                    } else if appState.progressState.phase != .idle {
                        liveTelemetryHUD
                    }

                    // Storage Capacity Forecasting & Quota Alerts
                    StorageForecastCardView(appState: appState)

                    // 4. Source & Destination Folders Overview
                    storageOverviewSection(profile: profile)

                    // 5. Quick Statistics
                    quickStatsSection(profile: profile)

                } else {
                    ContentUnavailableView(
                        L10n.t(.noProfileSelectedTitle),
                        systemImage: "folder.badge.questionmark",
                        description: Text(L10n.t(.noProfileSelectedDesc))
                    )
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: Binding(
            get: { appState.showDryRunModal },
            set: { appState.showDryRunModal = $0 }
        )) {
            if let summary = appState.dryRunSummary {
                DryRunModalView(appState: appState, summary: summary)
            }
        }
    }

    // MARK: - SPOF Warning Banner
    private func spofWarningBanner() -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(OtterTheme.statusWarning)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(.spofBannerTitle))
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Text(L10n.t(.spofBannerDesc))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(OtterTheme.statusWarning.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(OtterTheme.statusWarning.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - 3-2-1 Compliance Card
    private func rule321ComplianceCard(profile: BackupProfile) -> some View {
        let compliance = appState.rule321Compliance
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: profile.copyJobConfig.isEnabled ? "shield.lefthalf.filled.badge.checkmark" : "shield.slash")
                .font(.title2)
                .foregroundStyle(compliance.color)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(L10n.t(.rule321Title))
                        .font(.subheadline.bold())

                    Text(compliance.badgeText)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(compliance.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(compliance.color)
                }

                Text(L10n.t(.rule321Desc))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if profile.copyJobConfig.isEnabled {
                Button {
                    appState.startReplication(for: profile)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: appState.isReplicationRunning ? "arrow.triangle.2.circlepath" : "arrow.up.forward.circle")
                            .symbolEffect(.rotate, isActive: appState.isReplicationRunning)
                        Text(appState.isReplicationRunning ? L10n.t(.replicatingProgress) : L10n.t(.runReplicationButton))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.isReplicationRunning)
            }
        }
        .otterCard()
    }

    // MARK: - Live Replication Banner
    private var liveReplicationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "icloud.and.arrow.up.fill")
                .font(.title3)
                .foregroundStyle(OtterTheme.oceanicTeal)
                .symbolEffect(.pulse)

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.replicationProgressState.statusMessage)
                    .font(.subheadline.bold())
                if !appState.replicationProgressState.currentFile.isEmpty {
                    Text(appState.replicationProgressState.currentFile)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if appState.replicationProgressState.totalFiles > 0 {
                Text("\(appState.replicationProgressState.processedFiles)/\(appState.replicationProgressState.totalFiles)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(OtterTheme.oceanicTeal.opacity(0.1), in: RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius)
                .stroke(OtterTheme.oceanicTeal.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Live Telemetry HUD
    private var liveTelemetryHUD: some View {
        let progressValue: Double = {
            if appState.progressState.totalFiles > 0 {
                let processed = appState.progressState.copiedCount + appState.progressState.clonedCount + appState.progressState.skippedCount
                return Double(processed) / Double(appState.progressState.totalFiles)
            }
            return 0.0
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    if appState.isBackupRunning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(OtterTheme.statusGreen)
                    }

                    Text(L10n.t(appState.progressState.phase.localizedKey))
                        .font(.headline)
                }

                Spacer()

                if appState.progressState.speedBytesPerSecond > 0 {
                    let formattedSpeed = ByteCountFormatter.string(fromByteCount: Int64(appState.progressState.speedBytesPerSecond), countStyle: .file)
                    Label("\(formattedSpeed)/s", systemImage: "bolt.fill")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(OtterTheme.oceanicTeal)
                }

                if appState.progressState.totalFiles > 0 {
                    let processed = appState.progressState.copiedCount + appState.progressState.clonedCount + appState.progressState.skippedCount
                    Text("\(processed) / \(appState.progressState.totalFiles) (\(Int(progressValue * 100))%)")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: progressValue)
                .progressViewStyle(.linear)

            HStack(spacing: 12) {
                Label("\(appState.progressState.copiedCount) \(L10n.t(.telemetryCopied))", systemImage: "arrow.down.doc.fill")
                    .foregroundStyle(OtterTheme.statusGreen)
                Label("\(appState.progressState.clonedCount) \(L10n.t(.telemetryCloned))", systemImage: "link.badge.plus")
                    .foregroundStyle(OtterTheme.oceanicTeal)
                Label("\(appState.progressState.skippedCount) \(L10n.t(.telemetrySkipped))", systemImage: "hand.raised.fill")
                    .foregroundStyle(.secondary)
                if appState.progressState.errorCount > 0 {
                    Label("\(appState.progressState.errorCount) \(L10n.t(.telemetryErrors))", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(OtterTheme.statusError)
                }
                Spacer()
            }
            .font(.caption.monospacedDigit())

            if !appState.progressState.currentItem.isEmpty {
                Text(appState.progressState.currentItem)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .otterCard()
    }

    private func lastSessionCard(summary: BackupSessionSummary) -> some View {
        let isSuccess = summary.errorCount == 0
        return HStack(spacing: 12) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isSuccess ? OtterTheme.statusGreen : OtterTheme.statusWarning)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(isSuccess ? L10n.t(.lastBackupSuccess) : L10n.t(.lastBackupWarning))
                    .font(.subheadline.bold())
                Text(L10n.format(.sessionSummaryStatsFormat, summary.totalScannedFiles, summary.copiedCount, summary.clonedCount, summary.durationSeconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(L10n.t(.details)) {
                appState.showInspectorModal = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .otterCard(padding: OtterTheme.spacing12)
    }

    // MARK: - 4. Storage & Paths Overview
    private func storageOverviewSection(profile: BackupProfile) -> some View {
        HStack(spacing: 14) {
            // Source directory card
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.t(.sourceFolderTitle), systemImage: "folder.fill")
                    .font(.caption.bold())
                    .foregroundStyle(OtterTheme.oceanicTeal)

                Text(profile.sourceURL.path)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack {
                    Button {
                        appState.selectSourceDirectory()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.badge.gearshape")
                            Text(L10n.t(.changeFolderButton))
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([profile.sourceURL])
                    } label: {
                        Text(L10n.t(.revealInFinderButton))
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OtterTheme.oceanicTeal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .otterCard(padding: OtterTheme.spacing12)

            // Destination directory card
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.t(.destinationFolderTitle), systemImage: "internaldrive.fill")
                    .font(.caption.bold())
                    .foregroundStyle(OtterTheme.otterAmber)

                Text(profile.destinationURL.path)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack {
                    Button {
                        appState.selectDestinationDirectory()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "externaldrive.badge.plus")
                            Text(L10n.t(.changeFolderButton))
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([profile.destinationURL])
                    } label: {
                        Text(L10n.t(.revealInFinderButton))
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OtterTheme.otterAmber)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .otterCard(padding: OtterTheme.spacing12)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 5. Quick Statistics
    private func quickStatsSection(profile: BackupProfile) -> some View {
        HStack(spacing: 14) {
            // Snapshots count
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t(.quickStatsSnapshotsTitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L10n.format(.itemCountUnitFormat, appState.snapshots.count))
                    .font(.title3.bold().monospacedDigit())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .otterCard(padding: OtterTheme.spacing12)

            // Next scheduled run
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t(.quickStatsNextRunTitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(profile.schedule.isEnabled ? appState.nextScheduledRunDescription : L10n.t(.scheduleNotScheduled))
                    .font(.title3.bold())
                    .foregroundStyle(profile.schedule.isEnabled ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .otterCard(padding: OtterTheme.spacing12)

            // Exclusion rules
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t(.quickStatsActiveRulesTitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L10n.format(.quickStatsExcludeRulesCountFormat, profile.excludePatterns.count))
                    .font(.title3.bold().monospacedDigit())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .otterCard(padding: OtterTheme.spacing12)
        }
        .frame(maxWidth: .infinity)
    }
}
