import SwiftUI
import AppKit
import OtterKeepCore

public struct SettingsView: View {
    public let appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var themeBinding: Binding<AppThemeMode> {
        Binding(
            get: { appState.currentTheme },
            set: { appState.currentTheme = $0 }
        )
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { appState.currentLanguage },
            set: { appState.currentLanguage = $0 }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { appState.launchAtLoginEnabled },
            set: { appState.launchAtLoginEnabled = $0 }
        )
    }

    private var startMinimizedBinding: Binding<Bool> {
        Binding(
            get: { appState.startMinimized },
            set: { appState.startMinimized = $0 }
        )
    }

    private var finderIntegrationBinding: Binding<Bool> {
        Binding(
            get: { appState.isFinderIntegrationEnabled },
            set: { appState.isFinderIntegrationEnabled = $0 }
        )
    }

    private var debugLoggingBinding: Binding<Bool> {
        Binding(
            get: { appState.isDebugFileLoggingEnabled },
            set: { appState.isDebugFileLoggingEnabled = $0 }
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Permission Status HUD
                permissionStatusHUD

                // Top Preferences: 1. Nyelvválasztó, 2. Témaválasztó (középen), 3. Rendszerindítás
                Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow {
                        // 1. Language Selection Section
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 8) {
                                Image(systemName: "globe")
                                    .font(.title2)
                                    .foregroundStyle(OtterTheme.otterAmber)
                                Text(L10n.t(.settingsLanguageSection))
                                    .font(.title3.bold())
                            }

                            Text(L10n.t(.settingsLanguageDesc))
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 4)

                            Picker("", selection: languageBinding) {
                                ForEach(AppLanguage.allCases, id: \.self) { lang in
                                    Text(lang.displayName).tag(lang)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            .font(.body)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))

                        // 2. Appearance & Theme Selection Card (Középen a Nyelv és Indítás között)
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 8) {
                                Image(systemName: "circle.lefthalf.filled")
                                    .font(.title2)
                                    .foregroundStyle(OtterTheme.otterAmber)
                                Text(L10n.t(.settingsAppearanceSection))
                                    .font(.title3.bold())
                            }

                            Text(L10n.t(.settingsAppearanceDesc))
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 4)

                            Picker("", selection: themeBinding) {
                                ForEach(AppThemeMode.allCases, id: \.self) { mode in
                                    Label(mode.localizedTitle, systemImage: mode.iconName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))

                        // 3. Launch at Login & Start Minimized Section
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 8) {
                                Image(systemName: "power.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(OtterTheme.oceanicTeal)
                                Text(L10n.t(.settingsStartupSection))
                                    .font(.title3.bold())
                            }

                            Text(L10n.t(.settingsLaunchAtLoginDesc))
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 4)

                            Toggle(isOn: launchAtLoginBinding) {
                                Text(L10n.t(.settingsLaunchAtLoginToggle))
                                    .font(.body.weight(.medium))
                            }
                            .toggleStyle(.switch)

                            Divider()
                                .padding(.vertical, 2)

                            Toggle(isOn: startMinimizedBinding) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.t(.settingsStartMinimizedToggle))
                                        .font(.body.weight(.medium))
                                    Text(L10n.t(.settingsStartMinimizedDesc))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                    }
                }

                // 4. Persistent Files & Storage Section
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        Text(L10n.t(.settingsStorageSection))
                            .font(.title2.bold())
                    }

                    // Profiles file
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.t(.settingsProfilesPathLabel))
                                .font(.body.weight(.medium))
                            Text(ProfileStore.shared.profilesFileURL.path)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button(L10n.t(.settingsOpenFolder)) {
                            NSWorkspace.shared.activateFileViewerSelecting([ProfileStore.shared.profilesFileURL])
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }

                    Divider()

                    // Apple Photos configuration file
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.t(.settingsPhotosConfigTitle))
                                .font(.body.weight(.medium))
                            Text(PhotosProfileStore.shared.configFileURL.path)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button(L10n.t(.settingsOpenFolder)) {
                            NSWorkspace.shared.activateFileViewerSelecting([PhotosProfileStore.shared.configFileURL])
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }

                    Divider()

                    // Persistent log file
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.t(.settingsLogsPathLabel))
                                .font(.body.weight(.medium))
                            Text(LogManager.shared.logFileURL.path)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button(L10n.t(.settingsOpenFolder)) {
                            NSWorkspace.shared.activateFileViewerSelecting([LogManager.shared.logFileURL])
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                }
                .padding(20)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))

                // 5. Debug Logging & Diagnostics Section (.log)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "ladybug.fill")
                                .font(.title2)
                                .foregroundStyle(OtterTheme.otterAmber)
                            Text(L10n.t(.settingsDebugLoggingTitle))
                                .font(.title2.bold())
                        }

                        Spacer()

                        // Status Badge
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.isDebugFileLoggingEnabled ? OtterTheme.statusSuccess : .secondary)
                                .frame(width: 8, height: 8)
                            Text(appState.isDebugFileLoggingEnabled ? L10n.t(.settingsDebugLoggingActive) : L10n.t(.settingsDebugLoggingInactive))
                                .font(.subheadline.bold())
                                .foregroundStyle(appState.isDebugFileLoggingEnabled ? OtterTheme.statusSuccess : .secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            (appState.isDebugFileLoggingEnabled ? OtterTheme.statusSuccess : Color.secondary).opacity(0.12),
                            in: Capsule()
                        )
                    }

                    Text(L10n.t(.settingsDebugLoggingDesc))
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Toggle(isOn: debugLoggingBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t(.settingsDebugLoggingToggle))
                                .font(.body.weight(.medium))
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(.vertical, 2)

                    if appState.isDebugFileLoggingEnabled, let logURL = (appState.currentDebugLogFileURL ?? LogManager.shared.currentDebugLogFileURL) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.t(.settingsDebugLoggingPathLabel))
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    Text(logURL.path(percentEncoded: false))
                                        .font(.callout.monospaced())
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                            }

                            HStack(spacing: 8) {
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([logURL])
                                } label: {
                                    Label(L10n.t(.settingsOpenFolder), systemImage: "folder")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                Button {
                                    appState.copyDebugLogPath()
                                } label: {
                                    Label(L10n.t(.settingsDebugCopyPath), systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button {
                                    NSWorkspace.shared.open(LogManager.shared.debugLogsDirectory)
                                } label: {
                                    Label(L10n.t(.settingsDebugOpenLogsFolder), systemImage: "folder.badge.gearshape")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Privacy notice
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(OtterTheme.oceanicTeal)
                            .font(.callout)
                        Text(L10n.t(.settingsDebugLoggingPrivacyNotice))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
                .padding(20)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))

                // 6. Finder Integration Section (Global Toggle)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title2)
                                .foregroundStyle(OtterTheme.otterAmber)
                            Text(L10n.t(.finderExtensionSettingsTitle))
                                .font(.title2.bold())
                        }

                        Spacer()

                        // Global Status Badge
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.isFinderIntegrationEnabled ? OtterTheme.statusSuccess : .secondary)
                                .frame(width: 8, height: 8)
                            Text(appState.isFinderIntegrationEnabled ? L10n.t(.finderExtensionActive) : L10n.t(.finderExtensionDisabled))
                                .font(.subheadline.bold())
                                .foregroundStyle(appState.isFinderIntegrationEnabled ? OtterTheme.statusSuccess : .secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            (appState.isFinderIntegrationEnabled ? OtterTheme.statusSuccess : Color.secondary).opacity(0.12),
                            in: Capsule()
                        )
                    }

                    Text(L10n.t(.finderExtensionSettingsDesc))
                        .font(.body)
                        .foregroundStyle(.secondary)

                    // Master Toggle Switch
                    Toggle(isOn: finderIntegrationBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t(.finderExtensionToggle))
                                .font(.body.weight(.medium))
                            Text(L10n.t(.finderExtensionToggleDesc))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(.vertical, 4)

                    // Permission & Extension Diagnostics Panel
                    if appState.isFinderIntegrationEnabled {
                        if let status = appState.finderPermissionStatus {
                            if !status.isExtensionEnabled {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.orange)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(L10n.t(.finderExtensionNotEnabledSystem))
                                            .font(.callout.bold())
                                            .foregroundStyle(.primary)
                                        HStack(spacing: 8) {
                                            Button {
                                                FinderPermissionManager.shared.openSystemExtensionSettings()
                                            } label: {
                                                Label(L10n.t(.finderExtensionOpenSettings), systemImage: "gearshape")
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)

                                            Button {
                                                appState.refreshFinderPermissionStatus()
                                            } label: {
                                                Label(L10n.t(.refreshStatus), systemImage: "arrow.clockwise")
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            } else if !status.inaccessibleSourcePaths.isEmpty {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "lock.shield.fill")
                                        .font(.title3)
                                        .foregroundStyle(.red)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(L10n.t(.finderExtensionInaccessibleFolders))
                                            .font(.callout.bold())
                                        ForEach(status.inaccessibleSourcePaths, id: \.self) { p in
                                            Text("• \(p)")
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                        HStack(spacing: 8) {
                                            Button {
                                                FinderPermissionManager.shared.openFullDiskAccessSettings()
                                            } label: {
                                                Label(L10n.t(.finderExtensionOpenFDA), systemImage: "lock.open")
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)

                                            Button {
                                                appState.refreshFinderPermissionStatus()
                                            } label: {
                                                Label(L10n.t(.refreshStatus), systemImage: "arrow.clockwise")
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            } else {
                                HStack(spacing: 10) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(OtterTheme.statusSuccess)
                                    Text(L10n.t(.finderExtensionAllPermissionsGranted))
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button {
                                        FinderPermissionManager.shared.restartFinder()
                                    } label: {
                                        Label(L10n.t(.finderExtensionRestartFinder), systemImage: "arrow.clockwise")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                .padding(10)
                                .background(OtterTheme.statusSuccess.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.t(.finderExtensionMonitoredFolders))
                            .font(.body.weight(.medium))
                            .foregroundStyle(appState.isFinderIntegrationEnabled ? .primary : .secondary)

                        ForEach(appState.profiles) { prof in
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(appState.isFinderIntegrationEnabled ? .blue : .secondary)
                                Text(prof.name)
                                    .font(.callout.bold())
                                    .foregroundStyle(appState.isFinderIntegrationEnabled ? .primary : .secondary)
                                Text("(\(prof.sourceURL.path))")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .opacity(appState.isFinderIntegrationEnabled ? 1.0 : 0.6)

                    Text(L10n.t(.finderExtensionEnableHint))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(20)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))

                // 7. Software Updates Section (Sparkle 2.0 / Appcast)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                .font(.title2)
                                .foregroundStyle(OtterTheme.oceanicTeal)
                            Text(L10n.t(.settingsUpdatesSection))
                                .font(.title2.bold())
                        }

                        Spacer()

                        Text(String(format: L10n.t(.settingsCurrentVersionFormat), SoftwareUpdateCoordinator.shared.currentVersion, SoftwareUpdateCoordinator.shared.currentBuild))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Text(L10n.t(.settingsUpdatesDesc))
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Toggle(isOn: Binding(
                        get: { appState.automaticallyChecksForUpdates },
                        set: { appState.automaticallyChecksForUpdates = $0 }
                    )) {
                        Text(L10n.t(.settingsAutoUpdateToggle))
                            .font(.body.weight(.medium))
                    }
                    .toggleStyle(.switch)
                    .padding(.vertical, 2)

                    HStack(spacing: 12) {
                        Button {
                            appState.checkForSoftwareUpdates()
                        } label: {
                            HStack(spacing: 6) {
                                if appState.isCheckingForSoftwareUpdates {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text(L10n.t(.settingsCheckForUpdatesButton))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(appState.isCheckingForSoftwareUpdates)

                        if let status = appState.softwareUpdateStatusMessage {
                            Text(status)
                                .font(.callout)
                                .foregroundStyle(appState.softwareUpdateAvailableInfo != nil ? OtterTheme.statusSuccess : .secondary)
                        }
                    }

                    if let update = appState.softwareUpdateAvailableInfo {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("OtterKeep v\(update.version)")
                                    .font(.headline)
                                Spacer()
                                Text("Build \(update.buildNumber)")
                                    .font(.subheadline.bold().monospacedDigit())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(OtterTheme.statusSuccess.opacity(0.15), in: Capsule())
                                    .foregroundStyle(OtterTheme.statusSuccess)
                            }
                            if !update.releaseNotes.isEmpty {
                                Text(update.releaseNotes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button(L10n.t(.settingsDownloadInBrowser)) {
                                NSWorkspace.shared.open(update.downloadURL)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OtterTheme.statusSuccess.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .otterCard(padding: 20)

                // 8. About Section
                HStack(spacing: 16) {
                    OtterKeepLogoView(size: 52, withGlow: true, withBorder: true)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("OtterKeep")
                                .font(.headline.bold())

                            Text("v\(CoreEngine.version) (Build \(CoreEngine.buildNumber))")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(OtterTheme.oceanicTeal.opacity(0.15), in: Capsule())
                                .foregroundStyle(OtterTheme.oceanicTeal)
                        }

                        Text("„Keep what you love close to your chest.”")
                            .font(.caption.italic())
                            .foregroundStyle(OtterTheme.otterAmber)

                        Text("Subsystems: Storage v\(CoreEngine.storageVersion) • DB v\(CoreEngine.databaseVersion) • Core v\(CoreEngine.coreVersion) • UI v\(CoreEngine.uiVersion) • CLI v\(CoreEngine.cliVersion)")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.secondary)

                    }

                    Spacer()

                    Button {
                        AboutWindowController.shared.show()
                    } label: {
                        Label(L10n.t(.aboutWindowTitle), systemImage: "info.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .otterCard(padding: 16)
            }
            .padding(24)
        }
        .onAppear {
            appState.refreshFinderPermissionStatus()
        }
    }

    // MARK: - Permission Status HUD
    private var permissionStatusHUD: some View {
        let status = appState.finderPermissionStatus ?? FinderPermissionManager.shared.evaluateStatus(for: appState.profiles)
        let hasFDA = status.hasFullDiskAccess
        let isFinderEnabled = status.isExtensionEnabled

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle((hasFDA && isFinderEnabled) ? OtterTheme.statusSuccess : OtterTheme.otterAmber)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.permissionStatusTitle))
                        .font(.headline.bold())
                    Text(L10n.t(.finderExtensionSettingsDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    appState.refreshFinderPermissionStatus()
                } label: {
                    Label(L10n.t(.refreshStatus), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow {
                    // FDA Status Card
                    HStack(spacing: 10) {
                        Circle()
                            .fill(hasFDA ? OtterTheme.statusSuccess : OtterTheme.statusWarning)
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(hasFDA ? L10n.t(.permissionFDAGranted) : L10n.t(.permissionFDAMissing))
                                .font(.callout.weight(.medium))
                            Text(hasFDA ? "macOS Full Disk Access active" : "Required for background backups")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if !hasFDA {
                            Button {
                                FinderPermissionManager.shared.openFullDiskAccessSettings()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "gearshape")
                                    Text(L10n.t(.permissionOpenSettings))
                                }
                                .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(hasFDA ? OtterTheme.statusSuccess.opacity(0.08) : OtterTheme.statusWarning.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                    // Finder Extension Status Card
                    HStack(spacing: 10) {
                        Circle()
                            .fill(isFinderEnabled ? OtterTheme.statusSuccess : .secondary)
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(isFinderEnabled ? L10n.t(.permissionFinderActive) : L10n.t(.permissionFinderInactive))
                                .font(.callout.weight(.medium))
                            Text(isFinderEnabled ? "Context menu & badges active" : "Finder contextual restore & badges")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if !isFinderEnabled {
                            Button {
                                FinderPermissionManager.shared.openSystemExtensionSettings()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "gearshape")
                                    Text(L10n.t(.permissionOpenSettings))
                                }
                                .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(isFinderEnabled ? OtterTheme.statusSuccess.opacity(0.08) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .otterCard(padding: 16)
    }
}
