import SwiftUI
import AppKit
import OtterKeepCore

/// Main application window featuring a native macOS Source List sidebar, streamlined 4-area workspace structure,
/// and unified profile & photos workspaces.
public struct MainWindowView: View {
    private let appState: AppState

    public init(appState: AppState = AppState()) {
        self.appState = appState
    }

    public var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
        } detail: {
            detailContent
                .frame(minWidth: 640, minHeight: 500)
                .background(Color(nsColor: .windowBackgroundColor))
                .navigationTitle("")
        }
        .toolbar(removing: .sidebarToggle)
        .onAppear {
            appState.loadSnapshots()
            appState.loadPhotosSnapshots()
            appState.refreshLogs()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.loadSnapshots()
            appState.loadPhotosSnapshots()
        }
        .background(WindowTitleConfigurator(appState: appState))
        .sheet(isPresented: Binding(
            get: { appState.showInspectorModal },
            set: { appState.showInspectorModal = $0 }
        )) {
            BackupInspectorModalView(appState: appState)
        }
        .sheet(isPresented: Binding(
            get: { appState.showFileVersionHistoryModal },
            set: { appState.showFileVersionHistoryModal = $0 }
        )) {
            FileVersionHistoryModalView(appState: appState)
        }
        .sheet(isPresented: Binding(
            get: { appState.showRemoteDestinationEditorSheet },
            set: { appState.showRemoteDestinationEditorSheet = $0 }
        )) {
            RemoteDestinationEditorModalView(appState: appState)
        }
        .onOpenURL { url in
            if url.scheme == "otterkeep" && url.host == "restore-versions" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let pathItem = components.queryItems?.first(where: { $0.name == "path" })?.value {
                    let fileURL = URL(fileURLWithPath: pathItem)
                    appState.openVersionHistory(for: fileURL)
                }
            }
        }
        .alert("OtterKeep", isPresented: Binding(get: { appState.showAlert }, set: { appState.showAlert = $0 })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.alertMessage ?? "")
        }
        .sheet(isPresented: Binding(
            get: { appState.showNewProfileSheet },
            set: { appState.showNewProfileSheet = $0 }
        )) {
            NewProfileModalView(appState: appState)
        }
        .alert(L10n.t(.renameProfileSheetTitle), isPresented: Binding(
            get: { appState.showRenameProfileSheet },
            set: { appState.showRenameProfileSheet = $0 }
        )) {
            TextField(L10n.t(.renameProfileSheetPrompt), text: Binding(
                get: { appState.renameProfileName },
                set: { appState.renameProfileName = $0 }
            ))
            Button(L10n.t(.save)) {
                if let id = appState.selectedProfileId {
                    appState.renameProfile(id: id, newName: appState.renameProfileName)
                }
                appState.renameProfileName = ""
            }
            Button(L10n.t(.cancel), role: .cancel) {
                appState.renameProfileName = ""
            }
        } message: {
            Text(L10n.t(.renameProfileSheetPrompt))
        }
        .preferredColorScheme(appState.currentTheme.colorScheme)
    }

    // MARK: - Detail Content Routing
    @ViewBuilder
    private var detailContent: some View {
        switch appState.activeNavigation {
        case .profile(let id):
            if let profile = appState.profiles.first(where: { $0.id == id }) ?? appState.selectedProfile {
                ProfileWorkspaceView(profile: profile, appState: appState)
            } else {
                ContentUnavailableView(
                    L10n.t(.noProfileSelectedTitle),
                    systemImage: "folder.badge.questionmark",
                    description: Text(L10n.t(.noProfileSelectedDesc))
                )
            }
        case .photos, .photosBackup, .photosSnapshots:
            UnifiedPhotosWorkspaceView(appState: appState)
        case .logs:
            DiagnosticLogView(appState: appState)
        case .settings:
            SettingsView(appState: appState)
        case .dashboard, .restoreExplorer, .profileRules, .maintenance:
            if let profile = appState.selectedProfile {
                ProfileWorkspaceView(profile: profile, appState: appState)
            } else {
                ContentUnavailableView(
                    L10n.t(.noProfileSelectedTitle),
                    systemImage: "folder.badge.questionmark"
                )
            }
        }
    }

    // MARK: - Modern Sidebar Content
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Brand & Header
            brandHeader
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 10)

            // Navigation List
            List(selection: Binding(
                get: { appState.activeNavigation },
                set: { newNav in
                    if let newNav = newNav {
                        appState.activeNavigation = newNav
                        if case .profile(let id) = newNav {
                            appState.selectProfile(id: id)
                        }
                    }
                }
            )) {
                // MARK: 1. Backup Profiles Section
                Section {
                    ForEach(appState.profiles) { profile in
                        NavigationLink(value: NavigationSection.profile(profile.id)) {
                            Label {
                                HStack {
                                    Text(profile.name)
                                        .font(.body)
                                    Spacer()
                                    if appState.isBackupRunning && appState.selectedProfileId == profile.id {
                                        ProgressView()
                                            .controlSize(.mini)
                                    } else {
                                        Circle()
                                            .fill(OtterTheme.statusGreen)
                                            .frame(width: 6, height: 6)
                                    }
                                }
                            } icon: {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contextMenu {
                            Button {
                                appState.renameProfileName = profile.name
                                appState.selectedProfileId = profile.id
                                appState.showRenameProfileSheet = true
                            } label: {
                                Label(L10n.t(.renameProfileButton), systemImage: "pencil")
                            }

                            if appState.profiles.count > 1 {
                                Divider()
                                Button(role: .destructive) {
                                    appState.deleteProfile(id: profile.id)
                                } label: {
                                    Label(L10n.t(.deleteProfileButton), systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(L10n.t(.sidebarSectionFolders))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            appState.resetNewProfileDraft()
                            appState.showNewProfileSheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.body)
                                .foregroundStyle(OtterTheme.otterAmber)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.t(.newProfileButton))
                    }
                }

                // MARK: 2. Apple Photos Section
                Section {
                    NavigationLink(value: NavigationSection.photos) {
                        Label {
                            HStack {
                                Text(L10n.t(.photosBackupHeroTitle))
                                Spacer()
                                if appState.isPhotosBackupRunning {
                                    ProgressView()
                                        .controlSize(.mini)
                                } else if !appState.photosSnapshots.isEmpty {
                                    Text("\(appState.photosSnapshots.count)")
                                        .font(.caption.monospacedDigit().bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(.quaternary, in: Capsule())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "photo.stack.fill")
                                .foregroundStyle(OtterTheme.otterAmber)
                        }
                    }
                } header: {
                    Text(L10n.t(.sidebarSectionPhotos))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                // MARK: 3. System Section
                Section {
                    NavigationLink(value: NavigationSection.logs) {
                        Label(L10n.t(.navLogs), systemImage: "terminal")
                            .foregroundStyle(.primary)
                    }

                    NavigationLink(value: NavigationSection.settings) {
                        Label(L10n.t(.navSettings), systemImage: "gearshape")
                            .foregroundStyle(.primary)
                    }
                } header: {
                    Text(L10n.t(.sidebarSectionSystem))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)

            Spacer(minLength: 0)

            Divider()
                .padding(.horizontal, 10)

            // Bottom Bar: Backup Inspector Trigger
            sidebarInspectorButton
                .padding(10)
        }
        .background(.ultraThinMaterial)
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            OtterKeepLogoView(size: 34, withGlow: false, withBorder: true)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("OtterKeep")
                        .font(.subheadline.bold())

                    Text("v\(CoreEngine.version)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(OtterTheme.otterAmber.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(OtterTheme.otterAmber)
                }

                HStack(spacing: 4) {
                    let isRunning = appState.isBackupRunning || appState.isPhotosBackupRunning
                    Circle()
                        .fill(isRunning ? OtterTheme.otterAmber : OtterTheme.statusGreen)
                        .frame(width: 6, height: 6)

                    Text(isRunning ? L10n.t(.sidebarStatusRunning) : L10n.t(.sidebarStatusReady))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    private var sidebarInspectorButton: some View {
        Button {
            appState.showInspectorModal = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.caption)
                    .foregroundStyle(OtterTheme.oceanicTeal)

                Text(L10n.t(.inspectorTitle))
                    .font(.caption.weight(.medium))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(L10n.t(.inspectorSubtitle))
    }
}

/// Dedicated window delegate ensuring the single main window is hidden (orderOut) on close rather than destroyed.
public final class MainWindowDelegate: NSObject, NSWindowDelegate, @unchecked Sendable {
    public static let shared = MainWindowDelegate()

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false // Intercept window close to preserve single-instance state and prevent scene destruction
    }
}

/// Central manager for focusing, displaying, and managing the primary single application window.
@MainActor
public enum WindowManager {
    public static let mainWindowIdentifier = "OtterKeepMainWindow"

    /// Focuses and brings the single primary main window to the front, unhiding it if previously closed.
    public static func showAndFocusMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        let targetWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == mainWindowIdentifier })
            ?? NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain })
            ?? NSApp.mainWindow

        if let window = targetWindow {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
}

/// Helper `NSViewRepresentable` configuring window title visibility, style masks, titlebar transparency, and single-window delegate.
public struct WindowTitleConfigurator: NSViewRepresentable {
    public let appState: AppState?

    public init(appState: AppState? = nil) {
        self.appState = appState
    }

    @MainActor
    private static var hasPerformedInitialMinimization = false

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            configure(window: window)
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        configure(window: window)
    }

    private func configure(window: NSWindow) {
        window.identifier = NSUserInterfaceItemIdentifier(WindowManager.mainWindowIdentifier)
        window.title = "OtterKeep"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isReleasedWhenClosed = false
        window.delegate = MainWindowDelegate.shared
        if let toolbar = window.toolbar {
            if let index = toolbar.items.firstIndex(where: { $0.itemIdentifier.rawValue.contains("ToggleSidebar") || $0.itemIdentifier == .toggleSidebar }) {
                toolbar.removeItem(at: index)
            }
        }

        if let appState = appState, appState.startMinimized && !Self.hasPerformedInitialMinimization {
            Self.hasPerformedInitialMinimization = true
            window.orderOut(nil)
        }
    }
}
