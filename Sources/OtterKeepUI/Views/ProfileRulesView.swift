import SwiftUI
import AppKit
import OtterKeepStorage
import OtterKeepCore

/// Dedicated view for managing profile rules, directories, exclusions, iCloud, and backup schedules.
public struct ProfileRulesView: View {
    public let appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var excludePatternBinding: Binding<String> {
        Binding(
            get: { appState.newExcludePattern },
            set: { appState.newExcludePattern = $0 }
        )
    }

    private var showDestinationEditorBinding: Binding<Bool> {
        Binding(
            get: { appState.showRemoteDestinationEditorSheet },
            set: { appState.showRemoteDestinationEditorSheet = $0 }
        )
    }

    public var body: some View {
        ScrollView {
            content
                .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: showDestinationEditorBinding) {
            RemoteDestinationEditorModalView(appState: appState)
        }
    }

    public var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let profile = appState.selectedProfile {
                let isLocked = appState.isBackupRunning(for: profile.id)

                if isLocked {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title3)
                            .foregroundStyle(OtterTheme.otterAmber)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t(.profileLockedBannerTitle))
                                .font(.subheadline.bold())
                                .foregroundStyle(OtterTheme.otterAmber)
                            Text(L10n.t(.profileLockedBannerMessage))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .otterCard(padding: OtterTheme.spacing12)
                }

                Group {
                    // 1. Directory Paths Card
                    folderPathsSection(profile: profile)

                    // 2. iCloud Storage Strategy
                    icloudStrategySection(profile: profile)

                    // 3. Exclusion Rules (Tag cloud + Quick presets)
                    exclusionRulesSection(profile: profile)

                    // 4. Automatic Scheduling & Retention
                    scheduleAndRetentionSection(profile: profile)

                    // 5. External Drive Automation
                    externalDriveSection(profile: profile)

                    // 6. 3-2-1 Backup Copy Job & Remote Targets
                    backupCopyJobSection(profile: profile)

                    // 7. Wi-Fi SSID & Metered Hotspot Protection
                    WiFiProtectionCardView(appState: appState, profile: profile)

                    // 8. Outbound Webhook Remote Monitoring (Slack, Discord, Pushover)
                    WebhookSettingsCardView(appState: appState, profile: profile)

                    // 9. Ransomware & Rate-of-Change Anomaly Guard
                    ransomwareGuardSection(profile: profile)
                }
                .disabled(isLocked)
            } else {

                ContentUnavailableView(
                    L10n.t(.noProfileSelectedTitle),
                    systemImage: "folder.badge.questionmark",
                    description: Text(L10n.t(.noProfileSelectedDesc))
                )
            }
        }
    }

    // MARK: - 1. Folder Paths (Read-Only Overview)
    private func folderPathsSection(profile: BackupProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.t(.backupFoldersTitle))
                    .font(.headline)
                Spacer()
                Text(L10n.t(.rulesConfigOnDashboardNotice))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                folderRow(
                    title: L10n.t(.sourceFolderTitle),
                    url: profile.sourceURL,
                    icon: "folder.fill",
                    iconColor: OtterTheme.oceanicTeal,
                    onChange: {
                        appState.selectSourceDirectory()
                    }
                )

                Divider()

                folderRow(
                    title: L10n.t(.destinationFolderTitle),
                    url: profile.destinationURL,
                    icon: "internaldrive.fill",
                    iconColor: OtterTheme.otterAmber,
                    onChange: {
                        appState.selectDestinationDirectory()
                    }
                )
            }
            .otterCard()
        }
    }

    private func folderRow(
        title: String,
        url: URL,
        icon: String,
        iconColor: Color,
        onChange: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(url.path)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let onChange = onChange {
                Button {
                    onChange()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.gearshape")
                        Text(L10n.t(.changeFolderButton))
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
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
    }

    // MARK: - 2. iCloud Strategy
    private func icloudStrategySection(profile: BackupProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t(.icloudStrategyTitle))
                .font(.headline)

            HStack {
                Image(systemName: "icloud.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.icloudStrategy.localizedTitle)
                        .font(.body.weight(.medium))
                    Text(profile.icloudStrategy.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("", selection: Binding(
                    get: { profile.icloudStrategy },
                    set: { strat in
                        var updated = profile
                        updated.icloudStrategy = strat
                        appState.selectedProfile = updated
                    }
                )) {
                    ForEach(ICloudBackupStrategy.allCases, id: \.self) { strat in
                        Text(strat.localizedTitle).tag(strat)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 280)
            }
            .otterCard()
        }
    }

    // MARK: - 3. Exclusion Rules
    private func exclusionRulesSection(profile: BackupProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.t(.excludeRulesTitle))
                    .font(.headline)
                Spacer()
                Text("\(profile.excludePatterns.count) \(L10n.t(.activeRulesCount))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                // Input field for new pattern
                HStack(spacing: 8) {
                    TextField(L10n.t(.addRulePlaceholder), text: excludePatternBinding)
                        .textFieldStyle(.roundedBorder)

                    Button(L10n.t(.addRuleButton)) {
                        let trimmed = appState.newExcludePattern.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            appState.addExcludePattern(trimmed)
                            appState.newExcludePattern = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(appState.newExcludePattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                // Quick preset buttons
                FlowLayout(spacing: OtterTheme.spacing6) {
                    Text(L10n.t(.commonRulesLabel))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(["node_modules", ".git", ".DS_Store", "DerivedData", "*.tmp"], id: \.self) { preset in
                        let isAdded = profile.excludePatterns.contains(preset)
                        Button {
                            if !isAdded {
                                appState.addExcludePattern(preset)
                            }
                        } label: {
                            HStack(spacing: 3) {
                                if isAdded {
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
                                }
                                Text(preset)
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(isAdded)
                    }
                }

                Divider()

                // Active exclusion tags
                if profile.excludePatterns.isEmpty {
                    Text(L10n.t(.noActiveRulesNotice))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(profile.excludePatterns, id: \.self) { pattern in
                            HStack(spacing: 5) {
                                Image(systemName: "nosign")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(pattern)
                                    .font(.caption.monospaced())
                                Button {
                                    appState.removeExcludePattern(pattern)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                    }
                }

                Divider()

                // Ignore files and markers engine toggles
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { profile.enableIgnoreFiles },
                        set: { val in
                            var updated = profile
                            updated.enableIgnoreFiles = val
                            appState.selectedProfile = updated
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t(.enableIgnoreFilesToggle))
                                .font(.body.weight(.medium))
                            Text(L10n.t(.enableIgnoreFilesDesc))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Toggle(isOn: Binding(
                        get: { profile.respectGitIgnore },
                        set: { val in
                            var updated = profile
                            updated.respectGitIgnore = val
                            appState.selectedProfile = updated
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t(.respectGitIgnoreToggle))
                                .font(.body)
                            Text(L10n.t(.respectGitIgnoreDesc))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(.leading, 20)
                    .disabled(!profile.enableIgnoreFiles)
                    .opacity(profile.enableIgnoreFiles ? 1.0 : 0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .otterCard()
        }
    }

    // MARK: - 4. Schedule and Retention
    private func scheduleAndRetentionSection(profile: BackupProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t(.scheduleAndRetentionHeader))
                .font(.headline)

            VStack(alignment: .leading, spacing: 14) {
                // Schedule toggle
                Toggle(isOn: Binding(
                    get: { profile.schedule.isEnabled },
                    set: { enabled in
                        var updated = profile
                        updated.schedule.isEnabled = enabled
                        appState.selectedProfile = updated
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

                if profile.schedule.isEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()

                        HStack(spacing: 8) {
                            Text(L10n.t(.scheduleFrequencyLabel))
                                .font(.body)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { profile.schedule.frequency },
                                set: { freq in
                                    var updated = profile
                                    updated.schedule.frequency = freq
                                    appState.selectedProfile = updated
                                }
                            )) {
                                ForEach(ScheduleFrequency.allCases, id: \.self) { freq in
                                    Text(freq.localizedTitle).tag(freq)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)
                        }

                        // Detailed controls for selected frequency
                        switch profile.schedule.frequency {
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
                                        get: { profile.schedule.hour },
                                        set: { h in
                                            var updated = profile
                                            updated.schedule.hour = h
                                            appState.selectedProfile = updated
                                        }
                                    )) {
                                        ForEach(0..<24, id: \.self) { h in
                                            Text(String(format: "%02d:00", h)).tag(h)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 90)

                                    Picker("", selection: Binding(
                                        get: { profile.schedule.minute },
                                        set: { m in
                                            var updated = profile
                                            updated.schedule.minute = m
                                            appState.selectedProfile = updated
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
                                    get: { profile.schedule.weekday },
                                    set: { w in
                                        var updated = profile
                                        updated.schedule.weekday = w
                                        appState.selectedProfile = updated
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
                                    get: { profile.schedule.hour },
                                    set: { h in
                                        var updated = profile
                                        updated.schedule.hour = h
                                        appState.selectedProfile = updated
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
                                    get: { profile.schedule.intervalMinutes },
                                    set: { val in
                                        var updated = profile
                                        updated.schedule.intervalMinutes = val
                                        appState.selectedProfile = updated
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
                            get: { profile.schedule.catchUpIfMissed },
                            set: { val in
                                var updated = profile
                                updated.schedule.catchUpIfMissed = val
                                appState.selectedProfile = updated
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

                Divider()

                // Auto-pruning toggle
                Toggle(isOn: Binding(
                    get: { profile.pruningPolicy.isAutoPruningEnabled },
                    set: { enabled in
                        var updated = profile
                        updated.pruningPolicy.isAutoPruningEnabled = enabled
                        appState.selectedProfile = updated
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.autoPruningToggleTitle))
                            .font(.body.weight(.medium))
                        Text(L10n.t(.autoPruningToggleDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

                if profile.pruningPolicy.isAutoPruningEnabled {
                    HStack {
                        Text(L10n.t(.autoPruningRetainCountLabel))
                            .font(.body)
                        Spacer()
                        Stepper(value: Binding(
                            get: { profile.pruningPolicy.maxSnapshotsToKeep ?? 5 },
                            set: { val in
                                var updated = profile
                                updated.pruningPolicy.maxSnapshotsToKeep = max(1, val)
                                appState.selectedProfile = updated
                            }
                        ), in: 1...100) {
                            Text("\(profile.pruningPolicy.maxSnapshotsToKeep ?? 5) db")
                                .monospacedDigit()
                        }
                    }
                }

            }
            .otterCard()
        }
    }

    // MARK: - 5. External Drive Automation
    private func externalDriveSection(profile: BackupProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive.badge.timemachine")
                    .foregroundStyle(OtterTheme.otterAmber)
                Text(L10n.t(.driveAutomationHeader))
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { profile.backupOnVolumeMount },
                    set: { val in
                        var updated = profile
                        updated.backupOnVolumeMount = val
                        appState.selectedProfile = updated
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.backupOnVolumeMountToggle))
                            .font(.body.weight(.medium))
                        Text(L10n.t(.backupOnVolumeMountDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle(isOn: Binding(
                    get: { profile.autoEjectOnCompletion },
                    set: { val in
                        var updated = profile
                        updated.autoEjectOnCompletion = val
                        appState.selectedProfile = updated
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.autoEjectOnCompletionToggle))
                            .font(.body)
                        Text(L10n.t(.autoEjectOnCompletionDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.leading, 20)
                .disabled(!profile.backupOnVolumeMount)
                .opacity(profile.backupOnVolumeMount ? 1.0 : 0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .otterCard()
        }
    }

    // MARK: - 6. 3-2-1 Backup Copy Job & Remote Targets
    private func backupCopyJobSection(profile: BackupProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.t(.rule321Title), systemImage: "shield.lefthalf.filled.badge.checkmark")
                    .font(.headline)
                    .foregroundStyle(OtterTheme.oceanicTeal)
                Spacer()
                Text(L10n.t(.rule321Desc))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                // Master Copy Job Toggle
                Toggle(isOn: Binding(
                    get: { profile.copyJobConfig.isEnabled },
                    set: { enabled in
                        var updated = profile
                        updated.copyJobConfig.isEnabled = enabled
                        if enabled && updated.copyJobConfig.destinations.isEmpty {
                            // Provide default Cloud and NAS destinations
                            let defaultS3 = RemoteDestination(
                                name: "AWS S3 / Backblaze Cloud",
                                type: .s3(S3Configuration(endpoint: "https://s3.eu-central-1.amazonaws.com", bucket: "otterkeep-offsite", region: "eu-central-1", pathPrefix: "backups")),
                                isClientEncryptionEnabled: true
                            )
                            updated.copyJobConfig.destinations.append(defaultS3)
                        }
                        appState.selectedProfile = updated
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.copyJobMasterToggleTitle))
                            .font(.body.weight(.medium))
                        Text(L10n.t(.copyJobMasterToggleDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

                if profile.copyJobConfig.isEnabled {
                    Divider()

                    // Trigger Selection
                    HStack {
                        Text(L10n.t(.copyJobTriggerLabel))
                            .font(.body)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { profile.copyJobConfig.trigger },
                            set: { val in
                                var updated = profile
                                updated.copyJobConfig.trigger = val
                                appState.selectedProfile = updated
                            }
                        )) {
                            ForEach(CopyJobTrigger.allCases, id: \.self) { trg in
                                Text(trg.localizedTitle).tag(trg)
                            }
                        }
                        .frame(width: 220)
                    }

                    // Network Policy
                    HStack {
                        Text(L10n.t(.copyJobNetworkPolicyLabel))
                            .font(.body)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { profile.copyJobConfig.networkPolicy },
                            set: { val in
                                var updated = profile
                                updated.copyJobConfig.networkPolicy = val
                                appState.selectedProfile = updated
                            }
                        )) {
                            ForEach(CopyJobNetworkPolicy.allCases, id: \.self) { pol in
                                Text(pol.localizedTitle).tag(pol)
                            }
                        }
                        .frame(width: 220)
                    }

                    // Smart Bandwidth Throttling
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t(.smartThrottlingTitle))
                                .font(.body)
                            Text(L10n.t(.smartThrottlingDesc))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { profile.copyJobConfig.maxBandwidthBytesPerSec },
                            set: { val in
                                var updated = profile
                                updated.copyJobConfig.maxBandwidthBytesPerSec = val
                                appState.selectedProfile = updated
                            }
                        )) {
                            Text(L10n.t(.copyJobThrottlingUnlimited)).tag(Int64(0))
                            Text(L10n.t(.copyJobThrottlingGentle)).tag(Int64(2 * 1024 * 1024))
                            Text(L10n.t(.copyJobThrottlingRecommended)).tag(Int64(5 * 1024 * 1024))
                            Text(L10n.t(.copyJobThrottlingFast)).tag(Int64(10 * 1024 * 1024))
                            Text(L10n.t(.copyJobThrottlingHigh)).tag(Int64(25 * 1024 * 1024))
                        }
                        .frame(width: 180)
                    }

                    Divider()

                    // Remote Destinations List Header with Add Button
                    HStack {
                        Text(L10n.t(.remoteDestinationsTitle))
                            .font(.subheadline.bold())
                        Spacer()
                        Button {
                            appState.openDestinationEditor(destination: nil)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                Text(L10n.t(.addRemoteDestinationButton))
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(OtterTheme.otterAmber)
                        .controlSize(.small)
                    }

                    if profile.copyJobConfig.destinations.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "cloud.slash")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(L10n.t(.noRemoteDestinationsNotice))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(L10n.t(.addRemoteDestinationPrompt)) {
                                appState.openDestinationEditor(destination: nil)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else {
                        ForEach(profile.copyJobConfig.destinations) { dest in
                            HStack(spacing: 12) {
                                Image(systemName: {
                                    switch dest.type {
                                    case .s3: return "icloud.fill"
                                    case .smb: return "server.rack"
                                    case .webdav: return "network"
                                    case .sftp: return "terminal.fill"
                                    }
                                }())
                                .foregroundStyle(OtterTheme.oceanicTeal)
                                .font(.title3)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(dest.name)
                                            .font(.body.weight(.medium))
                                            .lineLimit(1)
                                        if dest.isClientEncryptionEnabled {
                                            HStack(spacing: 3) {
                                                Image(systemName: "lock.fill")
                                                Text("AES-256")
                                            }
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(OtterTheme.oceanicTeal.opacity(0.15), in: Capsule())
                                            .foregroundStyle(OtterTheme.oceanicTeal)
                                        }
                                        if dest.archivePackagingEnabled {
                                            HStack(spacing: 3) {
                                                Image(systemName: "archivebox.fill")
                                                Text("TAR.ZST (L\(dest.archiveCompressionLevel))")
                                            }
                                            .font(.caption2.bold().monospacedDigit())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(OtterTheme.otterAmber.opacity(0.15), in: Capsule())
                                            .foregroundStyle(OtterTheme.otterAmber)
                                        }
                                    }

                                    Text({ () -> String in
                                        switch dest.type {
                                        case .s3(let cfg): return "S3: \(cfg.endpoint) [\(cfg.bucket)]"
                                        case .smb(let cfg): return "SMB: \(cfg.shareURL)"
                                        case .webdav(let cfg): return "WebDAV: \(cfg.serverURL)\(cfg.destinationPath)"
                                        case .sftp(let cfg): return "SFTP: \(cfg.host):\(cfg.port)\(cfg.remotePath)"
                                        }
                                    }())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                HStack(spacing: 6) {
                                    Button {
                                        appState.openDestinationEditor(destination: dest)
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help(L10n.t(.editRemoteDestination))

                                    Button {
                                        appState.deleteDestinationEditor(destinationId: dest.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                            .foregroundStyle(OtterTheme.statusError)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help(L10n.t(.deleteRemoteDestination))

                                    Toggle("", isOn: Binding(
                                        get: { dest.isEnabled },
                                        set: { enabled in
                                            var updated = profile
                                            if let idx = updated.copyJobConfig.destinations.firstIndex(where: { $0.id == dest.id }) {
                                                updated.copyJobConfig.destinations[idx].isEnabled = enabled
                                                appState.selectedProfile = updated
                                            }
                                        }
                                    ))
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .labelsHidden()
                                    .fixedSize()
                                }
                                .fixedSize(horizontal: true, vertical: false)
                            }
                            .otterCard(padding: 10, cornerRadius: 8)
                        }
                    }
                }
            }
            .otterCard()
        }
    }

    // MARK: - 9. Ransomware & Rate-of-Change Anomaly Guard
    private func ransomwareGuardSection(profile: BackupProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled.trianglebadge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(OtterTheme.statusWarning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.ransomwareSectionTitle))
                        .font(.headline)
                    Text(L10n.t(.ransomwareSectionDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { profile.enableRateOfChangeGuard },
                    set: { val in
                        var updated = profile
                        updated.enableRateOfChangeGuard = val
                        appState.selectedProfile = updated
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .fixedSize()
            }

            if profile.enableRateOfChangeGuard {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    // Percent threshold
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n.t(.ransomwareMaxChangePercentLabel))
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: L10n.t(.ransomwareThresholdPercentFormat), profile.maxChangeThresholdPercent))
                                .font(.subheadline.monospacedDigit().bold())
                                .foregroundStyle(OtterTheme.oceanicTeal)
                        }
                        Slider(
                            value: Binding(
                                get: { profile.maxChangeThresholdPercent },
                                set: { val in
                                    var updated = profile
                                    updated.maxChangeThresholdPercent = val
                                    appState.selectedProfile = updated
                                }
                            ),
                            in: 5...100,
                            step: 5
                        )
                    }

                    // Deleted threshold
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n.t(.ransomwareMaxDeletedCountLabel))
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: L10n.t(.ransomwareThresholdCountFormat), profile.maxDeletedThresholdCount))
                                .font(.subheadline.monospacedDigit().bold())
                                .foregroundStyle(OtterTheme.oceanicTeal)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(profile.maxDeletedThresholdCount) },
                                set: { val in
                                    var updated = profile
                                    updated.maxDeletedThresholdCount = Int(val)
                                    appState.selectedProfile = updated
                                }
                            ),
                            in: 10...5000,
                            step: 10
                        )
                    }

                    Divider()

                    // Known extensions
                    Toggle(L10n.t(.ransomwareDetectExtensionsToggle), isOn: Binding(
                        get: { profile.detectKnownRansomwareExtensions },
                        set: { val in
                            var updated = profile
                            updated.detectKnownRansomwareExtensions = val
                            appState.selectedProfile = updated
                        }
                    ))
                    .font(.subheadline)

                    // Abort on anomaly
                    Toggle(isOn: Binding(
                        get: { profile.abortOnAnomaly },
                        set: { val in
                            var updated = profile
                            updated.abortOnAnomaly = val
                            appState.selectedProfile = updated
                        }
                    )) {
                        HStack {
                            Text(L10n.t(.ransomwareAbortToggle))
                                .font(.subheadline)
                            if profile.abortOnAnomaly {
                                Text("ABORT")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(OtterTheme.statusError.opacity(0.12), in: Capsule())
                                    .foregroundStyle(OtterTheme.statusError)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .otterCard()
    }
}
