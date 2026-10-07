import SwiftUI
import QuickLook
import OtterKeepDatabase
import OtterKeepCore

public struct RestoreExplorerView: View {
    public let appState: AppState

    private var searchFilterBinding: Binding<String> {
        Binding(get: { appState.searchFilter }, set: { appState.searchFilter = $0 })
    }

    private var timelineQueryBinding: Binding<String> {
        Binding(
            get: { appState.timelineSearchQuery },
            set: {
                appState.timelineSearchQuery = $0
                appState.searchTimelinePaths(query: $0, force: true)
            }
        )
    }

    private var showRestoreDialogBinding: Binding<Bool> {
        Binding(get: { appState.showRestoreDialog }, set: { appState.showRestoreDialog = $0 })
    }

    private var showRestoreSnapshotDialogBinding: Binding<Bool> {
        Binding(get: { appState.showRestoreSnapshotDialog }, set: { appState.showRestoreSnapshotDialog = $0 })
    }

    private var collisionChoiceBinding: Binding<CollisionResolution> {
        Binding(get: { appState.collisionChoice }, set: { appState.collisionChoice = $0 })
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .medium
        return df
    }()

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Bar: Mode Selector (Snapshot vs. Timeline)
            headerModeSelector

            Divider()

            // View content based on selected mode
            switch appState.restoreBrowseMode {
            case .snapshot:
                snapshotBrowseView
            case .timeline:
                fileTimelineBrowseView
            case .globalSearch:
                globalSearchBrowseView
            case .snapshotDiff:
                SnapshotDiffView(appState: appState)
            }

        }
        .onAppear {
            appState.loadSnapshots()
            QuickLookCoordinator.shared.startKeyboardMonitoring(for: appState)
        }
        .onDisappear {
            QuickLookCoordinator.shared.stopKeyboardMonitoring()
        }
        .onKeyPress(.space) {
            appState.toggleQuickLook()
            return .handled
        }
        .sheet(isPresented: showRestoreDialogBinding) {
            restoreSheetView
        }
        .sheet(isPresented: showRestoreSnapshotDialogBinding) {
            restoreSnapshotSheetView
        }
    }

    // MARK: - Top Mode Selector Header

    private var headerModeSelector: some View {
        HStack(spacing: 14) {
            Picker("", selection: Binding(
                get: { appState.restoreBrowseMode },
                set: { newMode in
                    appState.restoreBrowseMode = newMode
                    appState.updateQuickLookForCurrentSelection()
                }
            )) {
                ForEach(RestoreBrowseMode.allCases) { mode in
                    Text(mode.localizedTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)
            .fixedSize(horizontal: true, vertical: false)

            Spacer()

            // Quick Look preview button
            Button {
                appState.toggleQuickLook()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                    Text(L10n.t(.previewSpaceButton))
                }
                .font(.body)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(appState.currentSelectedFileURL() == nil)

            Button {
                appState.loadSnapshots(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help(L10n.t(.searchPlaceholder))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - 1. Snapshot Tree Structure & Search Browsing

    private var snapshotBrowseView: some View {
        HSplitView {
            // Left side panel: Snapshots list
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(L10n.t(.snapshotsCountTitle)) (\(appState.snapshots.count))")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                if appState.snapshots.isEmpty {
                    ContentUnavailableView(
                        L10n.t(.noSnapshotsAvailable),
                        systemImage: "clock.arrow.circlepath",
                        description: Text(L10n.t(.noSnapshotsAvailableDesc))
                    )
                } else {
                    List(selection: Binding(
                        get: { appState.selectedSnapshotId },
                        set: {
                            if appState.selectedSnapshotId != $0 {
                                appState.selectedSnapshotId = $0
                                appState.loadFilesForSelectedSnapshot(force: true)
                            }
                        }
                    )) {
                        ForEach(appState.snapshots) { snap in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(Self.dateFormatter.string(from: snap.timestamp))
                                        .font(.body.bold())
                                    if snap.backupType == "full" {
                                        Text(L10n.t(.backupTypeFull))
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1.5)
                                            .background(OtterTheme.oceanicTeal.opacity(0.20), in: Capsule())
                                            .foregroundStyle(OtterTheme.oceanicTeal)
                                    }
                                    Spacer()
                                    Text(formatBytes(snap.totalBytes))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(snap.totalFiles) \(L10n.t(.snapshotFilesCount)) • \(snap.snapshotPath)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .tag(snap.id)
                            .padding(.vertical, 4)
                            .contextMenu {
                                Button {
                                    appState.snapshotToRestoreEntirely = snap
                                    appState.showRestoreSnapshotDialog = true
                                } label: {
                                    Label(L10n.t(.restoreEntireSnapshotButton), systemImage: "arrow.counterclockwise.circle")
                                }

                                Button {
                                    appState.selectedDiffTargetSnapshotId = snap.id
                                    appState.selectedDiffBaseSnapshotId = nil
                                    appState.loadSnapshotDiff(targetId: snap.id, baseId: nil)
                                    appState.restoreBrowseMode = .snapshotDiff
                                } label: {
                                    Label(L10n.t(.diffCompareAction), systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)

                    if let selectedSnap = appState.snapshots.first(where: { $0.id == appState.selectedSnapshotId }) {
                        Button {
                            appState.snapshotToRestoreEntirely = selectedSnap
                            appState.showRestoreSnapshotDialog = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise.circle.fill")
                                Text(L10n.t(.restoreEntireSnapshotButton))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(minWidth: 260, maxWidth: 340)

            // Right Panel: Directory tree and file browser with search
            VStack(alignment: .leading, spacing: 12) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(L10n.t(.searchTreePlaceholder), text: searchFilterBinding)
                        .textFieldStyle(.plain)
                    if !appState.searchFilter.isEmpty {
                        Button { appState.searchFilter = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
                .padding(.top, 8)

                let filteredTree = FileTreeBuilder.filterTree(appState.snapshotTreeNodes, query: appState.searchFilter)

                if filteredTree.isEmpty {
                    ContentUnavailableView(
                        L10n.t(.noMatchingFilesInSnapshot),
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(L10n.t(.noMatchingFilesInSnapshotDesc))
                    )
                } else {
                    // Directory tree outline view
                    List(filteredTree, children: \.children) { node in
                        treeNodeRow(node: node)
                            .tag(node.id)
                    }
                    .listStyle(.inset)
                }

                // Bottom restore action bar
                HStack {
                    if let file = appState.selectedFile {
                        HStack(spacing: 8) {
                            Text("\(L10n.t(.selectedFileLabel)) \(file.relativePath)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if !file.isDirectory {
                                Button {
                                    appState.toggleQuickLook()
                                } label: {
                                    Image(systemName: "eye")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .help(L10n.t(.previewSpaceButton))
                            }
                        }
                    } else {
                        Text(L10n.t(.selectFileToRestorePrompt))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button(L10n.t(.restoreThisVersionButton)) {
                        appState.versionToRestore = nil
                        appState.showRestoreDialog = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.selectedFile == nil)
                }
                .padding()
                .background(.background.secondary)
            }
        }
    }

    private func treeNodeRow(node: FileTreeNode) -> some View {
        let isSelected = appState.selectedFile?.relativePath == node.relativePath
        return HStack(spacing: 8) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(node.isDirectory ? OtterTheme.oceanicTeal : .secondary)
                .font(.body)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.body.weight(node.isDirectory ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !node.isDirectory {
                    Text(node.relativePath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            if !node.isDirectory {
                Text(formatBytes(node.fileSize))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text(Self.dateFormatter.string(from: node.modificationTime))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if let count = node.children?.count {
                Text(L10n.format(.restoreItemsCountFormat, count))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if !node.isDirectory {
                if let rec = node.record {
                    appState.selectedFile = rec
                } else {
                    appState.selectedFile = appState.snapshotFiles.first(where: { $0.relativePath == node.relativePath })
                }
                appState.toggleQuickLook()
            }
        }
        .onTapGesture {
            if !node.isDirectory {
                if let rec = node.record {
                    appState.selectedFile = rec
                } else {
                    appState.selectedFile = appState.snapshotFiles.first(where: { $0.relativePath == node.relativePath })
                }
                appState.updateQuickLookForCurrentSelection()
            }
        }
        .contextMenu {
            if !node.isDirectory {
                Button {
                    if let rec = node.record {
                        appState.selectedFile = rec
                    } else {
                        appState.selectedFile = appState.snapshotFiles.first(where: { $0.relativePath == node.relativePath })
                    }
                    appState.toggleQuickLook()
                } label: {
                    Label(L10n.t(.previewSpaceButton), systemImage: "eye")
                }

                Button {
                    if let rec = node.record {
                        appState.selectedFile = rec
                    } else {
                        appState.selectedFile = appState.snapshotFiles.first(where: { $0.relativePath == node.relativePath })
                    }
                    if let url = appState.currentSelectedFileURL() {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } label: {
                    Label(L10n.t(.revealInFinderButton), systemImage: "arrow.right.circle")
                }
            }
        }
    }

    // MARK: - 2. File Timeline View with Directory Tree

    private var fileTimelineBrowseView: some View {
        HSplitView {
            // Left Panel: Directory tree with search
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.t(.searchFileTitle))
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(L10n.t(.searchFilePlaceholder), text: timelineQueryBinding)
                        .textFieldStyle(.plain)
                    if !appState.timelineSearchQuery.isEmpty {
                        Button {
                            appState.timelineSearchQuery = ""
                            appState.searchTimelinePaths(query: "")
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)

                let filteredTree = FileTreeBuilder.filterTree(appState.timelineTreeNodes, query: appState.timelineSearchQuery)

                if filteredTree.isEmpty {
                    ContentUnavailableView(
                        L10n.t(.noMatchingFilesFound),
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(L10n.t(.noMatchingFilesFoundDesc))
                    )
                } else {
                    List(filteredTree, children: \.children) { node in
                        timelineTreeNodeRow(node: node)
                            .tag(node.id)
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 280, maxWidth: 380)

            // Right Panel: Vertical timeline cards
            VStack(alignment: .leading, spacing: 0) {
                if let selectedPath = appState.selectedTimelinePath, !appState.selectedPathVersions.isEmpty {
                    // File header
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text((selectedPath as NSString).lastPathComponent)
                                .font(.title3.bold())
                            Text(selectedPath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(appState.selectedPathVersions.count) \(L10n.t(.versionsCountLabel))")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(OtterTheme.oceanicTeal.opacity(0.12), in: Capsule())
                            .foregroundStyle(OtterTheme.oceanicTeal)
                    }
                    .padding()
                    .background(.background.secondary)

                    Divider()

                    // Vertical timeline cards
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(appState.selectedPathVersions.enumerated()), id: \.element.snapshot.id) { index, item in
                                let changeState = computeStateChange(at: index, in: appState.selectedPathVersions)
                                let isSelected = appState.selectedTimelineVersion?.snapshot.id == item.snapshot.id

                                timelineNodeRow(
                                    item: item,
                                    changeState: changeState,
                                    isFirst: index == 0,
                                    isLast: index == appState.selectedPathVersions.count - 1,
                                    isSelected: isSelected
                                )
                                .onTapGesture {
                                    appState.selectedTimelineVersion = item
                                    appState.updateQuickLookForCurrentSelection()
                                }
                            }
                        }
                        .padding(20)
                    }
                } else {
                    ContentUnavailableView(
                        L10n.t(.selectFileToRestorePrompt),
                        systemImage: "clock.arrow.circlepath",
                        description: Text(L10n.t(.timelineSelectPrompt))
                    )
                }
            }
        }
    }

    private func timelineTreeNodeRow(node: FileTreeNode) -> some View {
        let isSelected = appState.selectedTimelinePath == node.relativePath
        return HStack(spacing: 8) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.text.fill")
                .foregroundStyle(node.isDirectory ? OtterTheme.oceanicTeal : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.body.weight(node.isDirectory ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !node.isDirectory {
                    Text(node.relativePath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            if !node.isDirectory {
                appState.loadTimeline(for: node.relativePath)
            }
        }
    }

    // MARK: - Timeline Node

    private struct StateChangeInfo {
        let label: String
        let color: Color
        let icon: String
    }

    private func computeStateChange(at index: Int, in versions: [(snapshot: SnapshotRecord, file: FileCatalogRecord)]) -> StateChangeInfo {
        guard !versions.isEmpty, index >= 0, index < versions.count else {
            return StateChangeInfo(label: L10n.t(.timelineInitialVersion), color: OtterTheme.statusGreen, icon: "plus.circle.fill")
        }

        guard index + 1 < versions.count else {
            return StateChangeInfo(label: L10n.t(.timelineInitialCreated), color: OtterTheme.statusGreen, icon: "plus.circle.fill")
        }

        let current = versions[index].file
        let previous = versions[index + 1].file

        if let c1 = current.checksum, let c2 = previous.checksum, c1 != c2 {
            return StateChangeInfo(label: L10n.t(.timelineModifiedContent), color: OtterTheme.otterAmber, icon: "pencil.circle.fill")
        } else if current.fileSize != previous.fileSize || abs(current.modificationTime.timeIntervalSince(previous.modificationTime)) > 0.001 {
            return StateChangeInfo(label: L10n.t(.timelineModifiedMeta), color: OtterTheme.otterAmber, icon: "pencil.circle.fill")
        } else {
            return StateChangeInfo(label: L10n.t(.timelineUnmodifiedCoW), color: OtterTheme.oceanicTeal, icon: "equal.circle.fill")
        }
    }

    private func timelineNodeRow(
        item: (snapshot: SnapshotRecord, file: FileCatalogRecord),
        changeState: StateChangeInfo,
        isFirst: Bool,
        isLast: Bool,
        isSelected: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Left timeline indicator
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : Color.secondary.opacity(0.3))
                    .frame(width: 2, height: 16)

                ZStack {
                    Circle()
                        .fill(changeState.color)
                        .frame(width: 16, height: 16)
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 16, height: 16)
                }

                Rectangle()
                    .fill(isLast ? Color.clear : Color.secondary.opacity(0.3))
                    .frame(width: 2)
                    .frame(minHeight: 80)
            }
            .frame(width: 20)

            // Right side version card
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.dateFormatter.string(from: item.snapshot.timestamp))
                            .font(.headline)
                        Text("Snapshot: \(item.snapshot.snapshotPath)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    // State change badge
                    HStack(spacing: 4) {
                        Image(systemName: changeState.icon)
                        Text(changeState.label)
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(changeState.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(changeState.color)
                }

                Divider()

                // Detailed attributes
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.fileSizeLabel))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(formatBytes(item.file.fileSize))
                            .font(.caption.bold().monospacedDigit())
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.modificationDateLabel))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(Self.dateFormatter.string(from: item.file.modificationTime))
                            .font(.caption)
                    }

                    if let hash = item.file.checksum {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t(.sha256IntegrityLabel))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(hash.prefix(12)) + "...")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }

                // Card action buttons
                HStack(spacing: 10) {
                    Button {
                        appState.selectedTimelineVersion = item
                        appState.toggleQuickLook()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "eye")
                            Text(L10n.t(.previewSpaceButton))
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        appState.versionToRestore = item
                        appState.showRestoreDialog = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                            Text(L10n.t(.restoreThisVersionButton))
                        }
                        .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.2), lineWidth: isSelected ? 1.5 : 1)
            )
            .padding(.bottom, 14)
        }
    }

    // MARK: - Restore Modal Sheet

    private var restoreSheetView: some View {
        let activeVersion = appState.versionToRestore ?? {
            guard let file = appState.selectedFile,
                  let sId = appState.selectedSnapshotId,
                  let snap = appState.snapshots.first(where: { $0.id == sId }) else { return nil }
            return (snapshot: snap, file: file)
        }()

        return VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t(.restoreSheetTitle))
                .font(.title2.bold())

            if let (snap, file) = activeVersion {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(L10n.t(.restoreItemLabel)) \(file.relativePath)")
                        .font(.subheadline.bold())
                    Text("\(L10n.t(.sourceSnapshotLabel)) \(snap.snapshotPath) (\(Self.dateFormatter.string(from: snap.timestamp)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t(.collisionResolutionLabel))
                    .fontWeight(.medium)
                Picker("", selection: collisionChoiceBinding) {
                    Text(L10n.t(.collisionKeepBoth)).tag(CollisionResolution.keepBoth)
                    Text(L10n.t(.collisionOverwrite)).tag(CollisionResolution.overwrite)
                    Text(L10n.t(.collisionSkip)).tag(CollisionResolution.skip)
                }
                .pickerStyle(.radioGroup)
            }

            HStack {
                Button(L10n.t(.cancel)) {
                    appState.showRestoreDialog = false
                    appState.versionToRestore = nil
                }
                Spacer()
                Button(L10n.t(.restoreToFolderButton)) {
                    appState.showRestoreDialog = false
                    if let target = activeVersion {
                        chooseRestoreDestination { targetURL in
                            appState.restoreVersion(
                                snapshot: target.snapshot,
                                file: target.file,
                                to: targetURL,
                                collision: appState.collisionChoice
                            )
                            appState.versionToRestore = nil
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 460)
    }

    private var restoreSnapshotSheetView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.title)
                    .foregroundStyle(OtterTheme.oceanicTeal)
                Text(L10n.t(.restoreEntireSnapshotTitle))
                    .font(.title2.bold())
            }

            if let snap = appState.snapshotToRestoreEntirely {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(L10n.t(.sourceSnapshotLabel)) \(snap.snapshotPath)")
                            .font(.subheadline.bold())
                        Spacer()
                        Text(Self.dateFormatter.string(from: snap.timestamp))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("\(snap.totalFiles) \(L10n.t(.snapshotFilesCount)) • \(formatBytes(snap.totalBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t(.collisionResolutionLabel))
                    .fontWeight(.medium)
                Picker("", selection: collisionChoiceBinding) {
                    Text(L10n.t(.collisionKeepBoth)).tag(CollisionResolution.keepBoth)
                    Text(L10n.t(.collisionOverwrite)).tag(CollisionResolution.overwrite)
                    Text(L10n.t(.collisionSkip)).tag(CollisionResolution.skip)
                }
                .pickerStyle(.radioGroup)
            }

            if appState.isSnapshotRestoreInProgress {
                VStack(alignment: .leading, spacing: 6) {
                    if let prog = appState.snapshotRestoreProgress {
                        ProgressView(value: Double(prog.processedFiles), total: max(1.0, Double(prog.totalFiles)))
                        HStack {
                            Text("\(prog.processedFiles) / \(prog.totalFiles) \(L10n.t(.snapshotFilesCount))")
                                .font(.caption2.monospacedDigit())
                            Spacer()
                            Text(formatBytes(prog.processedBytes))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if !prog.currentItem.isEmpty {
                            Text(prog.currentItem)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } else {
                        ProgressView()
                    }
                }
                .padding(.vertical, 4)
            }

            HStack {
                Button(L10n.t(.cancel)) {
                    appState.showRestoreSnapshotDialog = false
                    appState.snapshotToRestoreEntirely = nil
                }
                .disabled(appState.isSnapshotRestoreInProgress)

                Spacer()

                Button(L10n.t(.restoreToFolderButton)) {
                    if let snap = appState.snapshotToRestoreEntirely {
                        chooseRestoreDestination { targetURL in
                            appState.showRestoreSnapshotDialog = false
                            appState.restoreEntireSnapshot(
                                snapshot: snap,
                                to: targetURL,
                                collision: appState.collisionChoice
                            )
                            appState.snapshotToRestoreEntirely = nil
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isSnapshotRestoreInProgress || appState.snapshotToRestoreEntirely == nil)
            }
        }
        .padding()
        .frame(minWidth: 480)
    }

    private func chooseRestoreDestination(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.t(.restoreChoosePrompt)
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - 3. Cross-Snapshot Global Search

    private var globalSearchBrowseView: some View {
        VStack(spacing: 0) {
            // Search Input Header
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.body)
                    .foregroundStyle(.secondary)

                TextField(L10n.t(.searchAllSnapshots), text: Binding(
                    get: { appState.globalSearchQuery },
                    set: { appState.searchGlobalSnapshots(query: $0) }
                ))
                .textFieldStyle(.plain)
                .font(.body)

                if appState.isGlobalSearching {
                    ProgressView()
                        .controlSize(.small)
                } else if !appState.globalSearchResults.isEmpty && !appState.globalSearchQuery.isEmpty {
                    Text("\(appState.globalSearchResults.count)")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }

                if !appState.globalSearchQuery.isEmpty {
                    Button {
                        appState.searchGlobalSnapshots(query: "")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .padding(14)

            Divider()

            // Results Content
            if appState.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    L10n.t(.searchAllSnapshotsTitle),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(L10n.t(.searchAllSnapshotsDesc))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.globalSearchResults.isEmpty && !appState.isGlobalSearching {
                ContentUnavailableView(
                    L10n.t(.searchAllSnapshotsEmpty),
                    systemImage: "magnifyingglass",
                    description: Text(L10n.t(.searchAllSnapshotsDesc))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { appState.selectedGlobalSearchResult?.id },
                    set: { selectedId in
                        if let hit = appState.globalSearchResults.first(where: { $0.id == selectedId }) {
                            appState.selectedGlobalSearchResult = hit
                            appState.updateQuickLookForCurrentSelection()
                        }
                    }
                )) {
                    ForEach(appState.globalSearchResults) { result in
                        globalSearchResultRow(result)
                            .tag(result.id)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func globalSearchResultRow(_ result: GlobalSearchResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconForPath(result.fileRecord.relativePath))
                .font(.title3)
                .foregroundStyle(OtterTheme.oceanicTeal)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(URL(fileURLWithPath: result.fileRecord.relativePath).lastPathComponent)
                    .font(.body.weight(.medium))

                Text(result.fileRecord.relativePath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 6) {
                    Text(Self.dateFormatter.string(from: result.snapshotDate))
                        .font(.caption.bold())
                    Text(result.snapshotId)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }

                HStack(spacing: 10) {
                    Text(formatBytes(result.fileRecord.fileSize))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if let hash = result.fileRecord.checksum {
                        Text(String(hash.prefix(8)))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            HStack(spacing: 6) {
                Button {
                    appState.selectedGlobalSearchResult = result
                    appState.toggleQuickLook()
                } label: {
                    Image(systemName: "eye")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L10n.t(.previewSpaceButton))

                Button {
                    appState.revealGlobalSearchResultInSnapshot(result)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L10n.t(.snapshotsCountTitle))

                Button {
                    let fakeSnap = SnapshotRecord(
                        id: result.snapshotId,
                        timestamp: result.snapshotTimestamp,
                        status: "completed",
                        totalFiles: 0,
                        totalBytes: 0,
                        snapshotPath: result.snapshotPath,
                        backupType: "incremental"
                    )
                    appState.versionToRestore = (snapshot: fakeSnap, file: result.fileRecord)
                    appState.showRestoreDialog = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.uturn.backward")
                        Text(L10n.t(.restoreThisVersionButton))
                    }
                    .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                appState.selectedGlobalSearchResult = result
                appState.toggleQuickLook()
            } label: {
                Label(L10n.t(.previewSpaceButton), systemImage: "eye")
            }

            Button {
                appState.revealGlobalSearchResultInSnapshot(result)
            } label: {
                Label(L10n.t(.snapshotsCountTitle), systemImage: "arrow.up.right.square")
            }

            Button {
                let fakeSnap = SnapshotRecord(
                    id: result.snapshotId,
                    timestamp: result.snapshotTimestamp,
                    status: "completed",
                    totalFiles: 0,
                    totalBytes: 0,
                    snapshotPath: result.snapshotPath,
                    backupType: "incremental"
                )
                appState.versionToRestore = (snapshot: fakeSnap, file: result.fileRecord)
                appState.showRestoreDialog = true
            } label: {
                Label(L10n.t(.restoreThisVersionButton), systemImage: "arrow.uturn.backward")
            }

            Divider()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.fileRecord.relativePath, forType: .string)
            } label: {
                Label(L10n.t(.copyRelativePathAction), systemImage: "doc.on.doc")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.snapshotId, forType: .string)
            } label: {
                Label(L10n.t(.copySnapshotIdAction), systemImage: "number")
            }
        }
    }

    private func iconForPath(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "heic", "gif", "svg": return "photo"
        case "mp4", "mov", "m4v", "mkv": return "film"
        case "mp3", "m4a", "flac", "wav": return "music.note"
        case "pdf": return "doc.richtext"
        case "zip", "tar", "gz", "7z": return "doc.zipper"
        case "swift", "py", "js", "ts", "json", "c", "cpp", "h", "rs", "go": return "curlybraces"
        default: return "doc.text"
        }
    }
}
