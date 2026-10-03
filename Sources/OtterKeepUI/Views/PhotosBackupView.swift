import SwiftUI
import Photos
import UniformTypeIdentifiers
import OtterKeepCore
import OtterKeepDatabase

/// Modern Apple Photos backup view presenting library metrics, export settings, and live synchronization.
public struct PhotosBackupView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Permission banner
                authorizationBanner

                if appState.photosAuthorizationStatus == .authorized || appState.photosAuthorizationStatus == .limited {
                    // Status cards grid
                    statusCardsGrid

                    // Primary Action and Live Telemetry Section
                    actionAndTelemetrySection

                    // Destination Directory & Export Settings
                    configurationSection

                    // Schedule Settings
                    scheduleSection
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.checkPhotosAuthorization()
            appState.refreshPhotosLibraryStats()
            appState.loadPhotosSnapshots()
        }
    }

    // MARK: - Authorization Banner
    @ViewBuilder
    private var authorizationBanner: some View {
        if appState.photosAuthorizationStatus != .authorized && appState.photosAuthorizationStatus != .limited {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(OtterTheme.statusWarning)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.photosStatusNotAuthorized))
                        .font(.subheadline.bold())
                    Text(L10n.t(.photosAuthRequiredDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(L10n.t(.photosRequestPermissionButton)) {
                    appState.requestPhotosAuthorization()
                }
                .buttonStyle(.borderedProminent)
                .tint(OtterTheme.squirrelOrange)
                .controlSize(.regular)
            }
            .padding(14)
            .background(OtterTheme.cardBackground, in: RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius)
                    .stroke(OtterTheme.statusWarning.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - Status Cards Grid
    private var statusCardsGrid: some View {
        HStack(spacing: 14) {
            // Total media items
            VStack(alignment: .leading, spacing: 6) {
                Label(L10n.t(.photosCardLibraryTotal), systemImage: "photo.on.rectangle.angled")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)

                if appState.isScanningPhotosLibrary {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(L10n.format(.assetsCountUnitFormat, appState.photosLibraryTotalCount))
                        .font(.title2.bold().monospacedDigit())
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OtterTheme.cardBackground, in: RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius)
                    .stroke(OtterTheme.subtleBorder, lineWidth: 1)
            )

            // Buffer protection
            VStack(alignment: .leading, spacing: 6) {
                Label(L10n.t(.photosBufferStatus), systemImage: "shield.lefthalf.filled")
                    .font(.caption.bold())
                    .foregroundStyle(.green)

                Text("Max \(appState.photosConfig.maxInFlightCacheBytes / 1024 / 1024) MB")
                    .font(.title2.bold().monospacedDigit())
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OtterTheme.cardBackground, in: RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius)
                    .stroke(OtterTheme.subtleBorder, lineWidth: 1)
            )

            // APFS Reflink Savings
            VStack(alignment: .leading, spacing: 6) {
                Label(L10n.t(.photosSavedByReflink), systemImage: "leaf.fill")
                    .font(.caption.bold())
                    .foregroundStyle(OtterTheme.cyberTeal)

                let saved = appState.lastPhotosSessionSummary?.reflinkClonedBytes ?? appState.photosProgressState.clonedBytes
                Text(ByteCountFormatter.string(fromByteCount: saved, countStyle: .file))
                    .font(.title2.bold().monospacedDigit())
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OtterTheme.cardBackground, in: RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius)
                    .stroke(OtterTheme.subtleBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Action & Live Telemetry Section
    private var actionAndTelemetrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if appState.isPhotosBackupRunning {
                HStack {
                    Text(appState.photosProgressState.phaseDescription)
                        .font(.headline)
                        .foregroundStyle(OtterTheme.squirrelOrange)
                    Spacer()
                    Text("\(Int(appState.photosProgressState.progressFraction * 100))%")
                        .font(.subheadline.bold().monospacedDigit())
                }

                ProgressView(value: appState.photosProgressState.progressFraction)
                    .progressViewStyle(.linear)

                HStack {
                    Text("\(appState.photosProgressState.processedAssetsCount) / \(appState.photosProgressState.totalAssetsCount) \(L10n.t(.assetsCountUnit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(L10n.format(.photosDownloadedClonedFormat, ByteCountFormatter.string(fromByteCount: appState.photosProgressState.downloadedBytes, countStyle: .file), ByteCountFormatter.string(fromByteCount: appState.photosProgressState.clonedBytes, countStyle: .file)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if !appState.photosProgressState.currentAssetFilename.isEmpty {
                    Text(appState.photosProgressState.currentAssetFilename)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Spacer()
                    Button(L10n.t(.cancel), role: .destructive) {
                        appState.cancelPhotosBackup()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.photosBackupCardTitle))
                            .font(.headline)
                        Text(L10n.t(.photosBackupCardSubtitle))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        appState.startPhotosBackup()
                    } label: {
                        Label(L10n.t(.photosStartBackupButton), systemImage: "arrow.down.circle.fill")
                            .font(.body.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OtterTheme.squirrelOrange)
                    .controlSize(.regular)
                }
            }
        }
        .padding(14)
        .background(OtterTheme.cardBackground, in: RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius)
                .stroke(appState.isPhotosBackupRunning ? OtterTheme.squirrelOrange.opacity(0.3) : OtterTheme.subtleBorder, lineWidth: 1)
        )
    }

    // MARK: - Configuration
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t(.photosConfigCardTitle))
                .font(.headline)

            VStack(alignment: .leading, spacing: 14) {
                // Destination directory row
                HStack(spacing: 12) {
                    Image(systemName: "internaldrive.fill")
                        .font(.title3)
                        .foregroundStyle(OtterTheme.squirrelOrange)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.destinationFolderTitle))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(appState.photosConfig.destinationURL.path)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Button(L10n.t(.changeFolderButton)) {
                        selectDestinationFolder()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([appState.photosConfig.destinationURL])
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward.app")
                            Text(L10n.t(.revealInFinderButton))
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Divider()

                // Directory structure
                HStack {
                    Text(L10n.t(.photosExportStructureLabel))
                        .font(.body)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { appState.photosConfig.exportStructure },
                        set: {
                            appState.photosConfig.exportStructure = $0
                            appState.savePhotosConfig()
                        }
                    )) {
                        ForEach(PhotosExportStructure.allCases, id: \.self) { structure in
                            Text(structure.localizedTitle).tag(structure)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 260)
                }

                Divider()

                // Edited versions
                Toggle(isOn: Binding(
                    get: { appState.photosConfig.includeEditedVersions },
                    set: {
                        appState.photosConfig.includeEditedVersions = $0
                        appState.savePhotosConfig()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.t(.photosIncludeEditedToggle))
                            .font(.body)
                        Text(L10n.t(.photosIncludeEditedDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Live Photo videos
                Toggle(isOn: Binding(
                    get: { appState.photosConfig.includeLivePhotoVideos },
                    set: {
                        appState.photosConfig.includeLivePhotoVideos = $0
                        appState.savePhotosConfig()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.t(.photosIncludeLivePhotoVideosToggle))
                            .font(.body)
                        Text(L10n.t(.photosIncludeLivePhotoVideosDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

                // XMP Sidecar
                Toggle(isOn: Binding(
                    get: { appState.photosConfig.generateXMPSidecars },
                    set: {
                        appState.photosConfig.generateXMPSidecars = $0
                        appState.savePhotosConfig()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.t(.photosGenerateXMPToggle))
                            .font(.body)
                        Text(L10n.t(.photosGenerateXMPDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(OtterTheme.cardBackground, in: RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius)
                    .stroke(OtterTheme.subtleBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Schedule Section
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t(.scheduleCardTitle))
                .font(.headline)

            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(
                    get: { appState.photosConfig.schedule.isEnabled },
                    set: {
                        appState.photosConfig.schedule.isEnabled = $0
                        appState.savePhotosConfig()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.scheduleEnableToggle))
                            .font(.body.weight(.medium))
                        Text(L10n.t(.scheduleCardSubtitle))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

                if appState.photosConfig.schedule.isEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()

                        HStack(spacing: 8) {
                            Text(L10n.t(.scheduleFrequencyLabel))
                                .font(.body)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { appState.photosConfig.schedule.frequency },
                                set: {
                                    appState.photosConfig.schedule.frequency = $0
                                    appState.savePhotosConfig()
                                }
                            )) {
                                ForEach(ScheduleFrequency.allCases, id: \.self) { freq in
                                    Text(freq.localizedTitle).tag(freq)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)
                        }

                        // Detailed frequency controls
                        switch appState.photosConfig.schedule.frequency {
                        case .hourly:
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                                Text(L10n.t(.scheduleHourlyDesc))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)

                        case .daily:
                            HStack {
                                Text(L10n.t(.scheduleHourLabel))
                                    .font(.body)
                                Spacer()
                                HStack(spacing: 8) {
                                    Picker("", selection: Binding(
                                        get: { appState.photosConfig.schedule.hour },
                                        set: {
                                            appState.photosConfig.schedule.hour = $0
                                            appState.savePhotosConfig()
                                        }
                                    )) {
                                        ForEach(0..<24, id: \.self) { h in
                                            Text(String(format: "%02d:00", h)).tag(h)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 90)

                                    Picker("", selection: Binding(
                                        get: { appState.photosConfig.schedule.minute },
                                        set: {
                                            appState.photosConfig.schedule.minute = $0
                                            appState.savePhotosConfig()
                                        }
                                    )) {
                                        ForEach([0, 15, 30, 45], id: \.self) { m in
                                            Text(String(format: ":%02d", m)).tag(m)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 75)
                                }
                            }

                        case .weekly:
                            HStack {
                                Text(L10n.t(.scheduleDayLabel))
                                    .font(.body)
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { appState.photosConfig.schedule.weekday },
                                    set: {
                                        appState.photosConfig.schedule.weekday = $0
                                        appState.savePhotosConfig()
                                    }
                                )) {
                                    Text(L10n.t(.monday)).tag(2)
                                    Text(L10n.t(.tuesday)).tag(3)
                                    Text(L10n.t(.wednesday)).tag(4)
                                    Text(L10n.t(.thursday)).tag(5)
                                    Text(L10n.t(.friday)).tag(6)
                                    Text(L10n.t(.saturday)).tag(7)
                                    Text(L10n.t(.sunday)).tag(1)
                                }
                                .labelsHidden()
                                .frame(width: 120)

                                Picker("", selection: Binding(
                                    get: { appState.photosConfig.schedule.hour },
                                    set: {
                                        appState.photosConfig.schedule.hour = $0
                                        appState.savePhotosConfig()
                                    }
                                )) {
                                    ForEach(0..<24, id: \.self) { h in
                                        Text(String(format: "%02d:00", h)).tag(h)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 90)
                            }

                        case .intervalMinutes:
                            HStack {
                                Text(L10n.t(.scheduleIntervalLabel))
                                    .font(.body)
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { appState.photosConfig.schedule.intervalMinutes },
                                    set: {
                                        appState.photosConfig.schedule.intervalMinutes = $0
                                        appState.savePhotosConfig()
                                    }
                                )) {
                                    Text(L10n.t(.interval15m)).tag(15)
                                    Text(L10n.t(.interval30m)).tag(30)
                                    Text(L10n.t(.interval1h)).tag(60)
                                    Text(L10n.t(.interval2h)).tag(120)
                                    Text(L10n.t(.interval4h)).tag(240)
                                    Text(L10n.t(.interval8h)).tag(480)
                                }
                                .frame(width: 140)
                            }
                        }

                        // Catch-up missed backups toggle
                        Toggle(isOn: Binding(
                            get: { appState.photosConfig.schedule.catchUpIfMissed },
                            set: {
                                appState.photosConfig.schedule.catchUpIfMissed = $0
                                appState.savePhotosConfig()
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t(.scheduleCatchUpToggle))
                                    .font(.body)
                                Text(L10n.t(.scheduleCatchUpDesc))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(14)
            .background(OtterTheme.cardBackground, in: RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius)
                    .stroke(OtterTheme.subtleBorder, lineWidth: 1)
            )
        }
    }

    private func selectDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = L10n.t(.changeFolderButton)

        if panel.runModal() == .OK, let url = panel.url {
            appState.photosConfig.destinationURL = url
            appState.savePhotosConfig()
        }
    }
}
