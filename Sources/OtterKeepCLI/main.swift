import Foundation
import OtterKeepStorage
import OtterKeepDatabase
import OtterKeepCore

/// Command-line interface entry point for OtterKeep.
///
/// Provides headless backup execution, pre-backup dry-run simulation, profile management,
/// snapshot inspection, point-in-time file restoration, and log inspection.
@main
struct OtterKeepCLI {

    /// Terminates the CLI process, flushing and printing the debug log notice if debug logging was active.
    static func exitCLI(_ code: Int32) -> Never {
        if let url = LogManager.shared.currentDebugLogFileURL {
            LogManager.shared.flush()
            print("\n" + L10n.format(.cliDebugSavedNotice, url.path(percentEncoded: false)))
        }
        exit(code)
    }

    /// Main entrypoint parsing arguments and dispatching subcommands.
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())

        // 1. Handle optional --lang flag
        if let langIdx = args.firstIndex(of: "--lang"), langIdx + 1 < args.count {
            let langCode = args[langIdx + 1].lowercased()
            if langCode == "hu" || langCode == "magyar" {
                LocalizationManager.shared.currentLanguage = .hungarian
            } else if langCode == "en" || langCode == "english" {
                LocalizationManager.shared.currentLanguage = .english
            }
            args.removeSubrange(langIdx...langIdx + 1)
        }

        // 2. Handle optional --debug flag
        if let debugIdx = args.firstIndex(of: "--debug") {
            args.remove(at: debugIdx)
            let logURL = LogManager.shared.enableDebugFileLogging(persistSetting: false)
            print(L10n.format(.cliDebugActiveNotice, logURL.path(percentEncoded: false)))
            print()
        }

        // 3. Handle version query
        if args.contains("--version") || args.contains("-v") || args.first == "version" {
            print("🦦 OtterKeep v\(CoreEngine.version) (Build \(CoreEngine.buildNumber))")
            print("   ├── OtterKeepStorage:  v\(CoreEngine.storageVersion)")
            print("   ├── OtterKeepDatabase: v\(CoreEngine.databaseVersion)")
            print("   ├── OtterKeepCore:     v\(CoreEngine.coreVersion)")
            print("   ├── OtterKeepUI:       v\(CoreEngine.uiVersion)")
            print("   └── OtterKeepCLI:      v\(CoreEngine.cliVersion)")
            exitCLI(0)
        }


        // 4. Handle help request
        if args.isEmpty || args.contains("--help") || args.contains("-h") || args.first == "help" {
            printHelp()
            exitCLI(0)
        }

        let command = args[0]
        let subArgs = Array(args.dropFirst())

        switch command {
        case "backup":
            await handleBackup(subArgs)
        case "status":
            await handleStatus()
        case "replicate", "copy-job", "sync":
            await handleReplicate(subArgs)
        case "photos":
            await handlePhotos(subArgs)
        case "prune":
            await handlePrune(subArgs)
        case "daemon":
            handleDaemon(subArgs)
        case "doctor":
            await handleDoctor()
        case "profile", "profiles":
            await handleProfile(subArgs)
        case "snapshots", "snapshot":
            await handleSnapshots(subArgs)
        case "restore":
            await handleRestore(subArgs)
        case "restore-snapshot":
            await handleRestoreSnapshot(subArgs)
        case "file-history", "history":
            await handleFileHistory(subArgs)
        case "logs", "log":
            handleLogs(subArgs)
        case "schedule":
            await handleSchedule(subArgs)
        case "scrub":
            await handleScrub(subArgs)
        case "diff":
            await handleDiff(subArgs)
        case "lock":
            await handleLock(subArgs)
        case "unlock":
            await handleUnlock(subArgs)
        default:
            print(L10n.format(.cliUnknownCommand, command))
            exitCLI(1)
        }
    }

    // MARK: - Help

    /// Prints the CLI usage instructions and available commands.
    static func printHelp() {
        print("""
        \(L10n.t(.cliDescription))
        \(L10n.t(.cliUsage))

        \(L10n.t(.cliCommandsHeader))
          backup                    \(L10n.t(.cliCmdBackup))
            --profile <name|uuid>   \(L10n.t(.cliCmdBackupProfile))
            --dry-run               \(L10n.t(.cliCmdBackupDryRun))
            --full                  \(L10n.t(.cliCmdBackupFull))

          replicate                 Trigger 3-2-1 secondary replication (Backup Copy Job)
            --profile <name|uuid>   Specify profile to replicate
            --snapshot <id>         Specify snapshot ID (defaults to latest)

          photos                    \(L10n.t(.cliCmdPhotos))
            status                  View configuration and library status
            backup                  Trigger Photos backup
            snapshots               List completed Photos snapshots

          prune                     \(L10n.t(.cliCmdPrune))
            --profile <name|uuid>   Specify profile to prune
            --keep <number>         Keep count of latest snapshots (default: profile policy)

          daemon                    \(L10n.t(.cliCmdDaemon))
            install                 Install & enable 15-minute background LaunchAgent
            uninstall               Disable & remove background LaunchAgent
            status                  Check background LaunchAgent registration
            check                   Run single evaluation check

          doctor                    \(L10n.t(.cliCmdDoctor))

          status                    \(L10n.t(.cliCmdStatus))

          profile list              \(L10n.t(.cliCmdProfileList))
          profile create            \(L10n.t(.cliCmdProfileCreate))
            --name <name>           \(L10n.t(.cliCmdProfileName))
            --source <path>         \(L10n.t(.cliCmdProfileSource))
            --destination <path>    \(L10n.t(.cliCmdProfileDest))

          snapshots list            \(L10n.t(.cliCmdSnapshotsList))
            --profile <name|uuid>   \(L10n.t(.cliCmdBackupProfile))

          restore                   \(L10n.t(.cliCmdRestore))
            --profile <name|uuid>   \(L10n.t(.cliCmdRestoreProfile))
            --snapshot <id>         \(L10n.t(.cliCmdRestoreSnapshot))
            --file <rel_path>       \(L10n.t(.cliCmdRestoreFile))
            --target <path>         \(L10n.t(.cliCmdRestoreTarget))

          restore-snapshot          \(L10n.t(.cliCmdRestoreEntireSnapshot))
            --profile <name|uuid>   \(L10n.t(.cliCmdRestoreProfile))
            --snapshot <id>         \(L10n.t(.cliCmdRestoreSnapshot))
            --target <path>         \(L10n.t(.cliCmdRestoreTarget))
            --collision <mode>      \(L10n.t(.cliOptionCollision))

          file-history <path>       \(L10n.t(.cliCmdFileHistory))
            --gui                   \(L10n.t(.cliCmdFileHistoryGui))

          logs                      \(L10n.t(.cliCmdLogs))
            --path                  \(L10n.t(.cliCmdLogsPath))
            --list                  \(L10n.t(.cliCmdLogsList))
            --enable                \(L10n.t(.cliCmdLogsEnable))
            --disable               \(L10n.t(.cliCmdLogsDisable))
            --limit <number>        \(L10n.t(.cliCmdLogsLimit))

          schedule check            \(L10n.t(.cliCmdScheduleCheck))

          scrub                     \(L10n.t(.cliCmdScrubDesc))
            --profile <name|uuid>   Specify profile to scrub
            --limit <number>        Limit count of recent snapshots to inspect

          diff                      Compare two snapshots or side-by-side file contents
            --profile <name|uuid>   Specify profile
            --target <id>           Target snapshot ID (default: latest)
            --base <id>             Base snapshot ID (default: previous)
            --file <rel_path>       Specific file to compare
            --side-by-side          Render aligned side-by-side line comparison

          lock                      Apply WORM immutability protection to a snapshot
            --profile <name|uuid>   Specify profile
            --snapshot <id>         Specify snapshot ID
            --days <count>          Lock duration in days (default: 30)

          unlock                    Remove user immutable flag from a snapshot
            --profile <name|uuid>   Specify profile
            --snapshot <id>         Specify snapshot ID

        Options:
          --debug                   \(L10n.t(.cliOptDebug))
          --version, -v             \(L10n.t(.cliOptVersion))
          --lang <en|hu>            \(L10n.t(.cliOptLang))
          --help, -h                \(L10n.t(.cliOptHelp))

        \(L10n.t(.cliExamplesHeader))
          otterkeep backup --dry-run --debug
          otterkeep backup --profile "Default profile"
          otterkeep replicate --profile "Default profile"
          otterkeep photos backup
          otterkeep prune --keep 5
          otterkeep doctor
          otterkeep daemon status
          otterkeep snapshots list
          otterkeep logs --path
          otterkeep logs --list
          otterkeep logs --limit 10
        """)
    }

    // MARK: - Backup

    /// Handles backup operations including pre-backup dry-run simulations.
    /// - Parameter args: Command-line arguments passed to the backup subcommand.
    static func handleBackup(_ args: [String]) async {
        let isDryRun = args.contains("--dry-run")
        let isFull = args.contains("--full")
        let backupMode: BackupMode = isFull ? .full : .incremental
        let profileName = getOption("--profile", from: args)

        let store = ProfileStore.shared
        let profiles = store.loadProfiles()
        guard !profiles.isEmpty else {
            print(L10n.t(.cliNoProfiles))
            exitCLI(1)
        }

        let profile: BackupProfile
        if let target = profileName {
            guard let matched = profiles.first(where: { $0.name.lowercased() == target.lowercased() || $0.id.uuidString.lowercased() == target.lowercased() }) else {
                print(L10n.format(.cliProfileNotFound, target))
                exitCLI(1)
            }
            profile = matched
        } else {
            profile = profiles[0]
        }

        let storage = APFSFileSystemProvider()
        let database = DatabaseEngine()
        let retentionManager = RetentionManager(storage: storage, database: database)
        let coordinator = BackupSessionCoordinator(storage: storage, database: database, retentionManager: retentionManager)

        let modeLabel = isFull ? " [\(L10n.t(.backupTypeFull).uppercased())]" : ""
        LogManager.shared.log("CLI backup initiated for profile '\(profile.name)' [UUID: \(profile.id.uuidString)] (DryRun: \(isDryRun), Full: \(isFull))", level: .info, category: "CLI")

        if isDryRun {
            print(L10n.t(.cliDryRunStarting) + modeLabel)
            print("📁 \(L10n.t(.activeProfileLabel)): \(profile.name)")
            print("📂 \(L10n.t(.sourceFolderTitle)): \(profile.sourceURL.path)")
            print("🎯 \(L10n.t(.destinationFolderTitle)): \(profile.destinationURL.path)\n")

            do {
                let summary = try await coordinator.performDryRun(profile: profile, mode: backupMode)
                LogManager.shared.log("CLI Dry-Run completed for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: Scanned: \(summary.totalScannedFiles) (\(summary.totalScannedBytes) bytes), Added: \(summary.addedCount), Modified: \(summary.modifiedCount), Unmodified (CoW): \(summary.unmodifiedCount), Deleted: \(summary.deletedCount)", level: .info, category: "CLI")
                print(L10n.t(.cliDryRunFinished) + modeLabel)
                print("   • \(L10n.t(.inspectorTotalScanned)): \(summary.totalScannedFiles) (\(formatBytes(summary.totalScannedBytes)))")
                print("   • \(L10n.t(.dryRunTabAdded)):             \(summary.addedCount) (\(formatBytes(summary.addedBytes)))")
                print("   • \(L10n.t(.dryRunTabModified)):        \(summary.modifiedCount) (\(formatBytes(summary.modifiedBytes)))")
                print("   • \(L10n.t(.timelineUnmodifiedCoW)):      \(summary.unmodifiedCount)")
                print("   • \(L10n.t(.dryRunTabDeleted)):          \(summary.deletedCount)")
                exitCLI(0)
            } catch {
                LogManager.shared.log("CLI Dry-Run failed for profile '\(profile.name)': \(error.localizedDescription)", level: .error, category: "CLI")
                print(L10n.format(.cliDryRunError, error.localizedDescription))
                exitCLI(1)
            }
        } else {
            print(L10n.t(.cliBackupStarting) + modeLabel)
            print("📁 \(L10n.t(.activeProfileLabel)): \(profile.name)")
            print("📂 \(L10n.t(.sourceFolderTitle)): \(profile.sourceURL.path)")
            print("🎯 \(L10n.t(.destinationFolderTitle)): \(profile.destinationURL.path)\n")

            do {
                _ = try await coordinator.performBackup(profile: profile, mode: backupMode) { progress in
                    if progress.totalFiles > 0 {
                        let pct = Int((Double(progress.processedFiles) / Double(progress.totalFiles)) * 100)
                        let file = progress.currentItem.isEmpty ? "" : " - \(progress.currentItem)"
                        print("\r[\(progress.phase.localizedDescription)] \(pct)% (\(progress.processedFiles)/\(progress.totalFiles))\(file)", terminator: "")
                        fflush(stdout)
                    }
                }
                print("\n")

                if let sum = await coordinator.lastSessionSummary {
                    print(L10n.t(.cliBackupFinished) + modeLabel)
                    print("   • Snapshot ID:       \(sum.snapshotId)")
                    print("   • \(L10n.t(.telemetryCopied)):  \(sum.copiedCount) (\(formatBytes(sum.copiedBytes)))")
                    print("   • \(L10n.t(.telemetryCloned)):  \(sum.clonedCount)")
                    print("   • \(L10n.t(.telemetrySkipped)): \(sum.skippedCount)")
                    print("   • \(L10n.t(.telemetryErrors)):  \(sum.errorCount)")
                    print("   • \(L10n.t(.inspectorDuration)): \(String(format: "%.1f", sum.durationSeconds)) s")

                    var updated = profile
                    updated.schedule.lastRunDate = Date()
                    try? store.updateProfile(updated)
                    LogManager.shared.log("CLI backup completed successfully for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: Snapshot \(sum.snapshotId), Copied: \(sum.copiedCount), Cloned: \(sum.clonedCount)", level: .info, category: "CLI")
                }
                LogManager.shared.flush()
                exitCLI(0)
            } catch {
                LogManager.shared.log("Backup failed via CLI for profile '\(profile.name)' [UUID: \(profile.id.uuidString)]: \(error.localizedDescription)", level: .error, category: "CLI")
                LogManager.shared.flush()
                print("\n" + L10n.format(.cliBackupError, error.localizedDescription))
                exitCLI(1)
            }
        }
    }

    // MARK: - Status

    /// Displays current system status, configured profiles, paths, 3-2-1 compliance, and scheduling details.
    static func handleStatus() async {
        let store = ProfileStore.shared
        let profiles = store.loadProfiles()
        LogManager.shared.log("CLI status queried. Total profiles: \(profiles.count)", level: .info, category: "CLI")

        print("\(L10n.t(.cliSystemStatus))\n")
        print(L10n.format(.cliProfilesCountFormat, profiles.count))

        for (idx, p) in profiles.enumerated() {
            print("\n[\(idx + 1)] \(L10n.t(.activeProfileLabel)): \(p.name) (UUID: \(p.id))")
            print("    \(L10n.t(.sourceFolderTitle)):      \(p.sourceURL.path)")
            print("    \(L10n.t(.destinationFolderTitle)): \(p.destinationURL.path)")
            print("    \(L10n.t(.excludeRulesTitle)):   \(p.excludePatterns.joined(separator: ", "))")
            let sched = p.schedule
            let schedStatus = sched.isEnabled ? "\(L10n.t(.scheduleEnableToggle)) (\(sched.frequency.rawValue))" : L10n.t(.scheduleNotScheduled)
            print("    \(L10n.t(.scheduleCardTitle)):    \(schedStatus)")
            if let last = sched.lastRunDate {
                print(L10n.format(.cliLastRunFormat, ISO8601DateFormatter().string(from: last)))
            } else {
                print(L10n.t(.cliNeverRun))
            }
            if p.pruningPolicy.isAutoPruningEnabled {
                print("    \(L10n.t(.autoPruningToggleTitle)): \(L10n.format(.autoPruningRetainFormat, p.pruningPolicy.maxSnapshotsToKeep ?? 5))")
            }

            // 3-2-1 Compliance Calculation & Remote Targets
            var copies = 2 // Source + Local Destination
            var mediaTypes: Set<String> = ["local_source", "local_destination"]
            var hasOffsite = false
            let activeDestinations = p.copyJobConfig.isEnabled ? p.copyJobConfig.destinations.filter { $0.isEnabled } : []

            for dest in activeDestinations {
                copies += 1
                switch dest.type {
                case .s3:
                    mediaTypes.insert("cloud_s3")
                    hasOffsite = true
                case .backblazeB2:
                    mediaTypes.insert("cloud_b2")
                    hasOffsite = true
                case .smb:
                    mediaTypes.insert("network_smb")
                    hasOffsite = true
                case .webdav:
                    mediaTypes.insert("cloud_webdav")
                    hasOffsite = true
                case .sftp:
                    mediaTypes.insert("remote_sftp")
                    hasOffsite = true
                }
            }

            let isCompliant = copies >= 3 && mediaTypes.count >= 2 && hasOffsite
            let complianceTag = isCompliant ? "✅ \(L10n.t(.rule321StatusCompliant))" : (hasOffsite ? "⚠️ \(L10n.t(.rule321StatusPartial))" : "⚠️ \(L10n.t(.rule321StatusLocalOnly))")

            print("    🛡️ 3-2-1 Mentési Szabály: \(complianceTag)")
            print("       • Másolatok: \(copies)/3 (Forrás + Helyi APFS + \(activeDestinations.count) távoli)")
            print("       • Média típusok: \(mediaTypes.count)/2 (\(mediaTypes.joined(separator: ", ")))")
            print("       • Off-site / Felhő tároló: \(hasOffsite ? "Igen" : "Nem")")

            if p.copyJobConfig.isEnabled && !p.copyJobConfig.destinations.isEmpty {
                print("    🌐 Távoli célok (Backup Copy Job) [\(p.copyJobConfig.trigger.localizedTitle)]:")
                for dest in p.copyJobConfig.destinations {
                    let encTag = dest.isClientEncryptionEnabled ? " [🔒 Titkosított (AES-GCM)]" : ""
                    let statusTag = dest.isEnabled ? "Aktív" : "Kikapcsolva"
                    print("       • [\(dest.type.typeDisplayName)] \(dest.name) (\(statusTag))\(encTag)")
                }
            }
        }
        exitCLI(0)
    }

    // MARK: - Replicate

    /// Manually triggers 3-2-1 secondary replication (Backup Copy Job) for a profile.
    /// - Parameter args: Arguments passed to replicate subcommand.
    static func handleReplicate(_ args: [String]) async {
        let profileName = getOption("--profile", from: args)
        let snapshotId = getOption("--snapshot", from: args)

        let store = ProfileStore.shared
        let profiles = store.loadProfiles()
        guard !profiles.isEmpty else {
            print(L10n.t(.cliNoProfiles))
            exitCLI(1)
        }

        let profile: BackupProfile
        if let target = profileName {
            guard let matched = profiles.first(where: { $0.name.lowercased() == target.lowercased() || $0.id.uuidString.lowercased() == target.lowercased() }) else {
                print(L10n.format(.cliProfileNotFound, target))
                exitCLI(1)
            }
            profile = matched
        } else {
            profile = profiles[0]
        }

        guard profile.copyJobConfig.isEnabled, !profile.copyJobConfig.destinations.filter({ $0.isEnabled }).isEmpty else {
            print("⚠️ No remote replication destinations enabled for profile '\(profile.name)'.")
            exitCLI(0)
        }

        let dbPath = profile.destinationURL.appendingPathComponent(".otterkeep/manifest.sqlite").path
        let db = DatabaseEngine()
        do {
            try await db.open(at: dbPath)
            let snaps = try await db.listSnapshots()
            guard !snaps.isEmpty else {
                print("❌ No snapshots available to replicate in profile '\(profile.name)'.")
                exitCLI(1)
            }

            let snap: SnapshotRecord
            if let targetSnapId = snapshotId {
                guard let found = snaps.first(where: { $0.id == targetSnapId }) else {
                    print("❌ Snapshot '\(targetSnapId)' not found.")
                    exitCLI(1)
                }
                snap = found
            } else {
                snap = snaps.first!
            }

            print("🦦 Starting 3-2-1 Remote Replication Copy Job...")
            print("📁 Profile:     \(profile.name)")
            print("📸 Snapshot ID: \(snap.id) (\(snap.snapshotPath))")
            print("🎯 Remote Targets (\(profile.copyJobConfig.destinations.filter({ $0.isEnabled }).count)):")
            for dest in profile.copyJobConfig.destinations where dest.isEnabled {
                print("   • [\(dest.type.typeDisplayName)] \(dest.name)")
            }
            print()

            let storage = APFSFileSystemProvider()
            let coordinator = BackupCopyJobCoordinator(storage: storage, database: db)
            await coordinator.setProgressHandler { state in
                if state.totalFiles > 0 {
                    let pct = Int((Double(state.processedFiles) / Double(state.totalFiles)) * 100)
                    let file = state.currentFile.isEmpty ? "" : " - \(state.currentFile)"
                    print("\r[\(state.currentDestinationName)] \(pct)% (\(state.processedFiles)/\(state.totalFiles))\(file)", terminator: "")
                    fflush(stdout)
                }
            }

            let summary = try await coordinator.executeReplication(
                profile: profile,
                targetSnapshotId: snap.id
            )

            let statusDisplay: String
            switch summary.status {
            case "completed":
                statusDisplay = "completed"
            case "completed_with_errors":
                statusDisplay = "completed_with_errors"
            default:
                statusDisplay = "failed"
            }

            print("\n")
            print("✅ 3-2-1 Replication Completed:")
            print("   • Status:                  \(statusDisplay)")
            print("   • Successful Destinations: \(summary.successfulDestinations)/\(summary.totalDestinations)")
            print("   • Replicated Files:        \(summary.replicatedFiles)")
            print("   • Replicated Bytes:        \(formatBytes(summary.replicatedBytes))")
            print("   • Skipped (Deduplicated):  \(summary.skippedFiles)")
            print("   • Duration:                \(String(format: "%.2f", summary.durationSeconds)) s")
            exitCLI(0)
        } catch {
            print("\n❌ Replication failed: \(error.localizedDescription)")
            exitCLI(1)
        }
    }

    // MARK: - Profile

    /// Manages backup profiles (listing, creating, and deleting).
    /// - Parameter args: Command-line arguments passed to the profile subcommand.
    static func handleProfile(_ args: [String]) async {
        guard let sub = args.first else {
            await handleStatus()
            return
        }

        let store = ProfileStore.shared

        switch sub {
        case "list":
            let profiles = store.loadProfiles()
            print("\(L10n.t(.profilesMenuTitle)) (\(profiles.count)):")
            for p in profiles {
                print("• \(p.name) [ID: \(p.id)] -> \(p.sourceURL.path) ==> \(p.destinationURL.path)")
            }
        case "create":
            guard let name = getOption("--name", from: args),
                  let src = getOption("--source", from: args),
                  let dst = getOption("--destination", from: args) else {
                print("\(L10n.t(.cliMissingParams)) Required: --name <name> --source <path> --destination <path>")
                exitCLI(1)
            }
            let newP = BackupProfile(
                name: name,
                sourceURL: URL(fileURLWithPath: src),
                destinationURL: URL(fileURLWithPath: dst)
            )
            do {
                try store.updateProfile(newP)
                print(L10n.format(.cliProfileCreated, name))
            } catch {
                print(L10n.format(.cliProfileSaveError, error.localizedDescription))
                exitCLI(1)
            }
        case "delete", "remove":
            guard let target = getOption("--name", from: args) else {
                print("\(L10n.t(.cliMissingParams)) --name <name|uuid>")
                exitCLI(1)
            }
            let profiles = store.loadProfiles()
            guard let matched = profiles.first(where: { $0.name.lowercased() == target.lowercased() || $0.id.uuidString.lowercased() == target.lowercased() }) else {
                print(L10n.format(.cliProfileNotFound, target))
                exitCLI(1)
            }
            guard profiles.count > 1 else {
                print(L10n.t(.cliLastProfileError))
                exitCLI(1)
            }
            do {
                try store.deleteProfile(id: matched.id)
                print(L10n.format(.cliProfileDeleted, matched.name))
            } catch {
                print(L10n.format(.cliProfileDeleteError, error.localizedDescription))
                exitCLI(1)
            }
        default:
            print(L10n.format(.cliUnknownSubcommand, sub))
            exitCLI(1)
        }
    }

    // MARK: - Snapshots

    /// Lists completed snapshots stored in the manifest catalog of the given profile.
    /// - Parameter args: Command-line arguments passed to the snapshots subcommand.
    static func handleSnapshots(_ args: [String]) async {
        let store = ProfileStore.shared
        let profiles = store.loadProfiles()
        let profileName = getOption("--profile", from: args)

        let profile: BackupProfile
        if let target = profileName {
            guard let matched = profiles.first(where: { $0.name.lowercased() == target.lowercased() }) else {
                print(L10n.format(.cliProfileNotFound, target))
                exitCLI(1)
            }
            profile = matched
        } else {
            profile = profiles[0]
        }

        let dbPath = profile.destinationURL.appendingPathComponent(".otterkeep/manifest.sqlite").path
        let db = DatabaseEngine()
        do {
            try await db.open(at: dbPath)
            let snaps = try await db.listSnapshots()
            if snaps.isEmpty {
                print(L10n.t(.noSnapshotsAvailable))
            } else {
                print("\(L10n.t(.snapshotsCountTitle)) [\(profile.name)] (\(snaps.count)):")
                let df = ISO8601DateFormatter()
                for s in snaps {
                    let typeTag = s.backupType == "full" ? "[FULL]" : "[INC] "
                    let lockTag = s.isLocked ? " 🔒[WORM LOCKED]" : ""
                    print("• \(typeTag) [\(s.id)]  \(df.string(from: s.timestamp))  \(s.totalFiles) \(L10n.t(.filesCountUnit))  \(formatBytes(s.totalBytes))  (\(s.snapshotPath))\(lockTag)")
                }
            }
        } catch {
            print("❌ \(error.localizedDescription)")
            exitCLI(1)
        }
    }

    // MARK: - Restore

    /// Restores a file or directory from a specific snapshot back to a target directory.
    /// - Parameter args: Command-line arguments passed to the restore subcommand.
    static func handleRestore(_ args: [String]) async {
        guard let snapId = getOption("--snapshot", from: args),
              let filePath = getOption("--file", from: args),
              let target = getOption("--target", from: args) else {
            print("\(L10n.t(.cliMissingParams)) --snapshot <id> --file <rel_path> --target <dest_dir>")
            exitCLI(1)
        }

        let profileName = getOption("--profile", from: args)
        let store = ProfileStore.shared
        let profiles = store.loadProfiles()
        guard !profiles.isEmpty else {
            print(L10n.t(.cliNoProfiles))
            exitCLI(1)
        }

        let profile: BackupProfile
        if let target = profileName {
            guard let matched = profiles.first(where: { $0.name.lowercased() == target.lowercased() || $0.id.uuidString.lowercased() == target.lowercased() }) else {
                print(L10n.format(.cliProfileNotFound, target))
                exitCLI(1)
            }
            profile = matched
        } else {
            profile = profiles[0]
        }

        let dbPath = profile.destinationURL.appendingPathComponent(".otterkeep/manifest.sqlite").path
        let db = DatabaseEngine()
        let storage = APFSFileSystemProvider()
        let engine = RestoreEngine(storage: storage, database: db)

        do {
            try await db.open(at: dbPath)
            let snaps = try await db.listSnapshots()
            guard let snap = snaps.first(where: { $0.id == snapId }) else {
                print("❌ Snapshot not found: '\(snapId)'")
                exitCLI(1)
            }

            let destURL = try await engine.restore(
                snapshotPath: snap.snapshotPath,
                backupRootURL: profile.destinationURL,
                relativePath: filePath,
                targetDirectoryURL: URL(fileURLWithPath: target),
                collisionResolution: .overwrite
            )
            print(L10n.format(.restoreSuccessMessage, destURL.path))
            exitCLI(0)
        } catch {
            print("❌ \(error.localizedDescription)")
            exitCLI(1)
        }
    }

    /// Restores all files and directory structure of an entire snapshot to a target directory.
    /// - Parameter args: Command-line arguments passed to the restore-snapshot subcommand.
    static func handleRestoreSnapshot(_ args: [String]) async {
        guard let snapId = getOption("--snapshot", from: args),
              let target = getOption("--target", from: args) else {
            print("\(L10n.t(.cliMissingParams)) --snapshot <id> --target <dest_dir> [--profile <name>] [--collision overwrite|keepBoth|skip]")
            exitCLI(1)
        }

        let collisionModeStr = getOption("--collision", from: args)?.lowercased() ?? "keepboth"
        let collision: CollisionResolution
        switch collisionModeStr {
        case "overwrite": collision = .overwrite
        case "skip": collision = .skip
        default: collision = .keepBoth
        }

        let profileName = getOption("--profile", from: args)
        let store = ProfileStore.shared
        let profiles = store.loadProfiles()
        guard !profiles.isEmpty else {
            print(L10n.t(.cliNoProfiles))
            exitCLI(1)
        }

        let profile: BackupProfile
        if let targetProfile = profileName {
            guard let matched = profiles.first(where: { $0.name.lowercased() == targetProfile.lowercased() || $0.id.uuidString.lowercased() == targetProfile.lowercased() }) else {
                print(L10n.format(.cliProfileNotFound, targetProfile))
                exitCLI(1)
            }
            profile = matched
        } else {
            profile = profiles[0]
        }

        let dbPath = profile.destinationURL.appendingPathComponent(".otterkeep/manifest.sqlite").path
        let db = DatabaseEngine()
        let storage = APFSFileSystemProvider()
        let engine = RestoreEngine(storage: storage, database: db)

        do {
            try await db.open(at: dbPath)
            let snaps = try await db.listSnapshots()
            guard let snap = snaps.first(where: { $0.id == snapId || $0.snapshotPath == snapId }) else {
                print("❌ Snapshot not found: '\(snapId)'")
                exitCLI(1)
            }

            print("🔄 Restoring entire snapshot '\(snap.snapshotPath)' (\(snap.totalFiles) files) to '\(target)'...")

            let summary = try await engine.restoreSnapshot(
                snapshotPath: snap.snapshotPath,
                backupRootURL: profile.destinationURL,
                targetDirectoryURL: URL(fileURLWithPath: target),
                collisionResolution: collision,
                progress: { prog in
                    if prog.phase == .restoring && !prog.currentItem.isEmpty {
                        print("  [\(prog.processedFiles)/\(prog.totalFiles)] \(prog.currentItem)")
                    }
                }
            )

            print("✅ \(L10n.format(.restoreEntireSnapshotSuccessFormat, snap.snapshotPath, Int64(summary.restoredFiles), target))")
            print("⏱️ Duration: \(String(format: "%.2f", summary.durationSeconds))s, Restored: \(ByteCountFormatter.string(fromByteCount: summary.restoredBytes, countStyle: .file))")
            exitCLI(0)
        } catch {
            print("❌ \(error.localizedDescription)")
            exitCLI(1)
        }
    }

    // MARK: - File History

    /// Handles inspecting version history for a file or requesting the GUI to open version history.
    /// - Parameter args: Arguments passed to file-history.
    static func handleFileHistory(_ args: [String]) async {
        guard let filePath = args.first(where: { !$0.hasPrefix("-") }) else {
            print("❌ Missing required file path. Usage: otterkeep file-history <path> [--gui]")
            exitCLI(1)
        }

        let isGui = args.contains("--gui")
        let fileURL = URL(fileURLWithPath: filePath).standardizedFileURL
        let fullPath = fileURL.path(percentEncoded: false)

        if isGui {
            let delivered = SingleInstanceManager.shared.sendMessageToRunningInstance(
                SingleInstanceMessage(action: .openVersionHistory, filePath: fullPath)
            )
            if delivered {
                print("✅ Opened version history for '\(fullPath)' in active OtterKeep GUI instance.")
                exitCLI(0)
            } else {
                print("ℹ️ OtterKeep GUI is not currently running. Launching GUI...")
                let proc = Process()
                var components = URLComponents()
                components.scheme = "otterkeep"
                components.host = "restore-versions"
                components.queryItems = [URLQueryItem(name: "path", value: fullPath)]
                if let url = components.url {
                    proc.arguments = [url.absoluteString]
                    try? proc.run()
                }
                exitCLI(0)
            }
        }

        // CLI inspection mode
        let profiles = ProfileStore.shared.loadProfiles()
        guard let matchingProfile = profiles.first(where: { $0.containsPath(fullPath) }) else {
            print(L10n.t(.fileNotUnderAnyProfile))
            exitCLI(1)
        }

        guard let relPath = matchingProfile.relativePath(for: fullPath), !relPath.isEmpty else {
            print("❌ Cannot inspect version history of the root source directory.")
            exitCLI(1)
        }

        let db = DatabaseEngine()
        let dbPath = matchingProfile.destinationURL.appendingPathComponent(".otterkeep").appendingPathComponent("manifest.sqlite").path(percentEncoded: false)

        do {
            try await db.open(at: dbPath)
            let versions = try await db.listVersions(ofRelativePath: relPath)
            if versions.isEmpty {
                print(L10n.t(.noVersionsFoundForFile))
                exitCLI(0)
            }

            print("🦦 OtterKeep: \(versions.count) version(s) found for '\(relPath)' in profile '\(matchingProfile.name)':")
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .medium

            for (idx, item) in versions.enumerated() {
                let snap = item.snapshot
                let file = item.file
                let sizeStr = formatBytes(file.fileSize)
                let dateStr = df.string(from: snap.timestamp)
                let checksumStr = file.checksum.map { String($0.prefix(12)) + "..." } ?? "none"
                print("  [\(idx + 1)] Snapshot: \(snap.snapshotPath) (\(dateStr)) | Size: \(sizeStr) | SHA-256: \(checksumStr)")
            }

            print("\n💡 Tip: Run 'otterkeep file-history \"\(filePath)\" --gui' to inspect or restore in GUI.")
            exitCLI(0)
        } catch {
            print("❌ Failed to query version history: \(error.localizedDescription)")
            exitCLI(1)
        }
    }

    /// Prints or manages persistent system log entries and debug .log files.
    /// - Parameter args: Command-line arguments passed to the logs subcommand.
    static func handleLogs(_ args: [String]) {
        if args.contains("--enable") {
            let url = LogManager.shared.enableDebugFileLogging(persistSetting: true)
            print(L10n.t(.cliDebugLoggingEnabled))
            print(L10n.format(.cliLogsPathLabel, url.path(percentEncoded: false)))
            exitCLI(0)
        }

        if args.contains("--disable") {
            LogManager.shared.disableDebugFileLogging(persistSetting: true)
            print(L10n.t(.cliDebugLoggingDisabled))
            exitCLI(0)
        }

        if args.contains("--path") || args.contains("--file") {
            if let activeURL = LogManager.shared.currentDebugLogFileURL {
                print(L10n.format(.cliLogsPathLabel, activeURL.path(percentEncoded: false)))
            } else if let latestURL = LogManager.shared.listDebugLogFiles().first {
                print(L10n.format(.cliLogsPathLabel, latestURL.path(percentEncoded: false)))
            } else {
                print(L10n.t(.cliNoLogsFound))
            }
            exitCLI(0)
        }

        if args.contains("--list") {
            let files = LogManager.shared.listDebugLogFiles()
            if files.isEmpty {
                print(L10n.t(.cliNoLogsFound))
            } else {
                print("\(L10n.t(.logsTitle)) (\(files.count)):")
                let df = ISO8601DateFormatter()
                for (idx, f) in files.enumerated() {
                    let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                    let isCurrent = (f == LogManager.shared.currentDebugLogFileURL) ? " [ACTIVE]" : ""
                    print("  [\(idx + 1)] \(f.lastPathComponent)\(isCurrent)  (\(formatBytes(Int64(size))))  \(df.string(from: date))")
                }
            }
            exitCLI(0)
        }

        let limitStr = getOption("--limit", from: args) ?? getOption("--tail", from: args) ?? "25"
        let limit = Int(limitStr) ?? 25

        let entries = LogManager.shared.getEntries()
        let toShow = entries.suffix(limit)

        print("\(L10n.t(.logsTitle)) (\(toShow.count)):")
        let df = ISO8601DateFormatter()
        for e in toShow {
            print("[\(df.string(from: e.timestamp))] [\(e.level.rawValue)] [\(e.category)]: \(e.message)")
        }
        exitCLI(0)
    }

    // MARK: - Schedule Check

    /// Evaluates scheduled backup profiles and triggers missed or due catch-up backups.
    /// - Parameter args: Command-line arguments passed to the schedule subcommand.
    static func handleSchedule(_ args: [String]) async {
        print(L10n.t(.cliScheduleCheckStarting))
        let storage = APFSFileSystemProvider()
        let database = DatabaseEngine()
        let retentionManager = RetentionManager(storage: storage, database: database)
        let coordinator = BackupSessionCoordinator(storage: storage, database: database, retentionManager: retentionManager)
        let store = ProfileStore.shared

        let scheduler = BackupScheduler.shared
        scheduler.start(triggerHandler: { profile, isCatchUp in
            let tag = isCatchUp ? "[Catch-Up]" : "[Scheduled]"
            print("🚀 \(tag) Starting backup for profile '\(profile.name)'...")
            do {
                _ = try await coordinator.performBackup(profile: profile, mode: .incremental)
                var updated = profile
                updated.schedule.lastRunDate = Date()
                try? store.updateProfile(updated)
                print("✅ Backup completed for profile '\(profile.name)'.")
            } catch {
                print("❌ Backup failed for profile '\(profile.name)': \(error.localizedDescription)")
            }
        })

        await scheduler.checkAndRunCatchUpBackups()
        await scheduler.evaluateSchedules()
        scheduler.stop()
        LogManager.shared.flush()
        print(L10n.t(.cliScheduleCheckDone))
    }

    // MARK: - Scrub

    /// Performs cryptographic data scrubbing and bit-rot detection on historical snapshots.
    /// - Parameter args: Command-line arguments.
    static func handleScrub(_ args: [String]) async {
        let profileName = getOption("--profile", from: args)
        let limitStr = getOption("--limit", from: args)
        let limit = limitStr.flatMap(Int.init)

        let store = ProfileStore.shared
        let profiles = store.loadProfiles()
        guard !profiles.isEmpty else {
            print(L10n.t(.cliNoProfiles))
            exitCLI(1)
        }

        let profile: BackupProfile
        if let target = profileName {
            guard let matched = profiles.first(where: { $0.name.lowercased() == target.lowercased() || $0.id.uuidString.lowercased() == target.lowercased() }) else {
                print(L10n.format(.cliProfileNotFound, target))
                exitCLI(1)
            }
            profile = matched
        } else {
            profile = profiles[0]
        }

        print("🔍 Starting cryptographic data scrubbing pass...")
        print("📁 Profile: \(profile.name)")
        print("🎯 Destination: \(profile.destinationURL.path(percentEncoded: false))\n")

        let scrubber = DataScrubberEngine()
        do {
            let record = try await scrubber.performScrub(backupRootURL: profile.destinationURL, limitSnapshots: limit) { progress in
                if progress.totalFiles > 0 {
                    let pct = Int((Double(progress.checkedFiles) / Double(progress.totalFiles)) * 100)
                    print("\r[Scrubbing] \(pct)% (\(progress.checkedFiles)/\(progress.totalFiles)) - \(progress.currentSnapshot)", terminator: "")
                    fflush(stdout)
                }
            }
            print("\n")
            print("✅ Scrubbing audit completed successfully:")
            print("   • Snapshots audited: \(record.checkedSnapshotsCount)")
            print("   • Files verified:    \(record.checkedFilesCount)")
            print("   • Corrupted files:   \(record.corruptedFilesCount)")
            print("   • Status:            \(record.status)")
            if record.corruptedFilesCount > 0 {
                if let details = record.detailsJson {
                    print("\n⚠️ Corrupted details:\n\(details)")
                }
                exitCLI(1)
            }
            exitCLI(0)
        } catch {
            print("\n❌ Scrubbing failed: \(error.localizedDescription)")
            exitCLI(1)
        }
    }

    // MARK: - Diff & Side-by-Side Comparison

    static func handleDiff(_ args: [String]) async {
        let profileName = getOption("--profile", from: args)
        let targetId = getOption("--target", from: args)
        let baseId = getOption("--base", from: args)
        let fileRel = getOption("--file", from: args)
        let sideBySide = args.contains("--side-by-side")

        let store = ProfileStore.shared
        let profiles = store.loadProfiles()
        guard !profiles.isEmpty else {
            print(L10n.t(.cliNoProfiles))
            exitCLI(1)
        }

        let profile: BackupProfile
        if let target = profileName {
            guard let matched = profiles.first(where: { $0.name.lowercased() == target.lowercased() || $0.id.uuidString.lowercased() == target.lowercased() }) else {
                print(L10n.format(.cliProfileNotFound, target))
                exitCLI(1)
            }
            profile = matched
        } else {
            profile = profiles[0]
        }

        let dbPath = profile.destinationURL.appendingPathComponent(".otterkeep/manifest.sqlite").path
        let db = DatabaseEngine()
        do {
            try await db.open(at: dbPath)
            let snaps = try await db.listSnapshots()
            guard !snaps.isEmpty else {
                print(L10n.t(.noSnapshotsAvailable))
                exitCLI(1)
            }

            let effectiveTargetId = targetId ?? snaps[0].id
            let effectiveBaseId = baseId ?? (snaps.count > 1 ? snaps[1].id : nil)

            if let filePath = fileRel {
                guard let bId = effectiveBaseId,
                      let snapBase = snaps.first(where: { $0.id == bId }),
                      let snapTarget = snaps.first(where: { $0.id == effectiveTargetId }) else {
                    print("❌ Requires at least two snapshots to compare file content.")
                    exitCLI(1)
                }

                let urlA = profile.destinationURL.appendingPathComponent(snapBase.snapshotPath).appendingPathComponent("root").appendingPathComponent(filePath)
                let urlB = profile.destinationURL.appendingPathComponent(snapTarget.snapshotPath).appendingPathComponent("root").appendingPathComponent(filePath)

                let diffResult = try TextDiffEngine().diffFiles(leftURL: urlA, rightURL: urlB, relativePath: filePath)
                print("📄 File comparison: '\(filePath)'")
                print("   Base:   [\(snapBase.id)] (\(snapBase.snapshotPath))")
                print("   Target: [\(snapTarget.id)] (\(snapTarget.snapshotPath))\n")

                if diffResult.isBinary {
                    print("⚠️ Binary file detected: inline text diff is not available.")
                    print("   Base size:   \(diffResult.leftSize) bytes")
                    print("   Target size: \(diffResult.rightSize) bytes")
                    exitCLI(0)
                }

                if diffResult.addedLinesCount == 0 && diffResult.deletedLinesCount == 0 && diffResult.modifiedLinesCount == 0 {
                    print("✅ Files are identical.")
                    exitCLI(0)
                }

                print("Changes: +\(diffResult.addedLinesCount) lines, -\(diffResult.deletedLinesCount) lines\n")

                if sideBySide {
                    print("┌─── BASE ──────────────────────────────┬─── TARGET ────────────────────────────┐")
                    for row in diffResult.rows {
                        let leftNum = row.leftLineNumber.map { String(format: "%3d", $0) } ?? "   "
                        let leftContent = (row.leftText ?? "").prefix(34).padding(toLength: 34, withPad: " ", startingAt: 0)
                        let rightNum = row.rightLineNumber.map { String(format: "%3d", $0) } ?? "   "
                        let rightContent = (row.rightText ?? "").prefix(34).padding(toLength: 34, withPad: " ", startingAt: 0)
                        let sep: String
                        switch row.type {
                        case .added: sep = "│ + "
                        case .deleted: sep = "│ - "
                        case .modified: sep = "│ ~ "
                        case .unchanged: sep = "│   "
                        }
                        print("│ \(leftNum) \(leftContent) \(sep)\(rightNum) \(rightContent) │")
                    }
                    print("└───────────────────────────────────────┴───────────────────────────────────────┘")
                } else {
                    for row in diffResult.rows {
                        switch row.type {
                        case .added:
                            print("+ [\(row.rightLineNumber ?? 0)] \(row.rightText ?? "")")
                        case .deleted:
                            print("- [\(row.leftLineNumber ?? 0)] \(row.leftText ?? "")")
                        case .modified:
                            print("~ [\(row.leftLineNumber ?? 0) → \(row.rightLineNumber ?? 0)] \(row.rightText ?? "")")
                        case .unchanged:
                            break
                        }
                    }
                }
            } else {
                let report = try await SnapshotDiffEngine.shared.diff(
                    database: db,
                    targetSnapshotId: effectiveTargetId,
                    baseSnapshotId: effectiveBaseId
                )
                print("📊 Snapshot Diff Report:")
                print("   Base:   \(report.baseSnapshotId ?? "Initial State")")
                print("   Target: \(report.targetSnapshotId)\n")
                print("   • Added:     \(report.addedCount) files")
                print("   • Modified:  \(report.modifiedCount) files")
                print("   • Deleted:   \(report.deletedCount) files")
                print("   • Net size:  \(formatBytes(report.netBytesDelta))\n")

                for item in report.items where item.changeType != .unchanged {
                    let symbol = item.changeType == .added ? "+" : (item.changeType == .deleted ? "-" : "~")
                    print("  \(symbol) \(item.relativePath)")
                }
            }
        } catch {
            print("❌ Diff failed: \(error.localizedDescription)")
            exitCLI(1)
        }
    }

    // MARK: - WORM Immutability Locking

    static func handleLock(_ args: [String]) async {
        guard let snapId = getOption("--snapshot", from: args) else {
            print("❌ Missing required parameter: --snapshot <id>")
            exitCLI(1)
        }
        let profileName = getOption("--profile", from: args)
        let days = getOption("--days", from: args).flatMap(Int.init) ?? 30

        let store = ProfileStore.shared
        let profiles = store.loadProfiles()
        guard !profiles.isEmpty else {
            print(L10n.t(.cliNoProfiles))
            exitCLI(1)
        }

        let profile = profileName.flatMap { target in
            profiles.first(where: { $0.name.lowercased() == target.lowercased() || $0.id.uuidString.lowercased() == target.lowercased() })
        } ?? profiles[0]

        let dbPath = profile.destinationURL.appendingPathComponent(".otterkeep/manifest.sqlite").path
        let db = DatabaseEngine()
        do {
            try await db.open(at: dbPath)
            let snaps = try await db.listSnapshots()
            guard let snap = snaps.first(where: { $0.id == snapId }) else {
                print("❌ Snapshot '\(snapId)' not found.")
                exitCLI(1)
            }

            let lockedUntil = Date().addingTimeInterval(Double(days) * 86400)
            try await db.updateSnapshotLockedUntil(id: snapId, lockedUntil: lockedUntil)

            let snapURL = profile.destinationURL.appendingPathComponent(snap.snapshotPath)
            let storage = APFSFileSystemProvider()
            try? storage.setImmutable(at: snapURL, immutable: true, recursive: true)

            let df = ISO8601DateFormatter()
            print("🔒 Snapshot '\(snapId)' locked with WORM immutability.")
            print("   Protected until: \(df.string(from: lockedUntil)) (\(days) days)")
        } catch {
            print("❌ Failed to lock snapshot: \(error.localizedDescription)")
            exitCLI(1)
        }
    }

    static func handleUnlock(_ args: [String]) async {
        guard let snapId = getOption("--snapshot", from: args) else {
            print("❌ Missing required parameter: --snapshot <id>")
            exitCLI(1)
        }
        let profileName = getOption("--profile", from: args)

        let store = ProfileStore.shared
        let profiles = store.loadProfiles()
        guard !profiles.isEmpty else {
            print(L10n.t(.cliNoProfiles))
            exitCLI(1)
        }

        let profile = profileName.flatMap { target in
            profiles.first(where: { $0.name.lowercased() == target.lowercased() || $0.id.uuidString.lowercased() == target.lowercased() })
        } ?? profiles[0]

        let dbPath = profile.destinationURL.appendingPathComponent(".otterkeep/manifest.sqlite").path
        let db = DatabaseEngine()
        do {
            try await db.open(at: dbPath)
            let snaps = try await db.listSnapshots()
            guard let snap = snaps.first(where: { $0.id == snapId }) else {
                print("❌ Snapshot '\(snapId)' not found.")
                exitCLI(1)
            }

            try await db.updateSnapshotLockedUntil(id: snapId, lockedUntil: nil)

            let snapURL = profile.destinationURL.appendingPathComponent(snap.snapshotPath)
            let storage = APFSFileSystemProvider()
            try? storage.setImmutable(at: snapURL, immutable: false, recursive: true)

            print("🔓 Snapshot '\(snapId)' unlocked.")
        } catch {
            print("❌ Failed to unlock snapshot: \(error.localizedDescription)")
            exitCLI(1)
        }
    }

    // MARK: - Photos Backup

    /// Manages headless Apple Photos library backups, status inspection, and snapshot history.
    /// - Parameter args: Command-line arguments passed to the photos subcommand.
    static func handlePhotos(_ args: [String]) async {
        let sub = args.first ?? "status"
        let store = PhotosProfileStore.shared
        let config = store.loadConfiguration()

        switch sub {
        case "status":
            print("📸 Apple Photos Backup Status\n")
            print("   • Enabled:            \(config.isEnabled)")
            print("   • Destination:        \(config.destinationURL.path(percentEncoded: false))")
            print("   • Destination Valid:  \(FileManager.default.fileExists(atPath: config.destinationURL.path(percentEncoded: false)))")
            print("   • Buffer Guard:       \(config.maxInFlightCacheBytes / 1024 / 1024) MB")
            let sched = config.schedule
            let schedStatus = sched.isEnabled ? "\(sched.frequency.rawValue)" : L10n.t(.scheduleNotScheduled)
            print("   • Schedule:           \(schedStatus)")
            if let last = sched.lastRunDate {
                print("   • Last Run:           \(ISO8601DateFormatter().string(from: last))")
            } else {
                print("   • Last Run:           \(L10n.t(.cliNeverRun))")
            }
            exitCLI(0)

        case "backup":
            print("📸 Starting Apple Photos backup...")
            print("🎯 Destination: \(config.destinationURL.path(percentEncoded: false))\n")

            let storage = APFSFileSystemProvider()
            let database = DatabaseEngine()
            let coordinator = PhotosBackupCoordinator(storage: storage, dbEngine: database)

            do {
                let summary = try await coordinator.executeBackup(configuration: config) { progress in
                    if progress.totalAssetsCount > 0 {
                        let pct = Int(progress.progressFraction * 100)
                        let file = progress.currentAssetFilename.isEmpty ? "" : " - \(progress.currentAssetFilename)"
                        print("\r[\(progress.phaseDescription)] \(pct)% (\(progress.processedAssetsCount)/\(progress.totalAssetsCount))\(file)", terminator: "")
                        fflush(stdout)
                    }
                }
                print("\n\n✅ Apple Photos backup completed successfully:")
                print("   • New downloaded:    \(summary.newDownloadedCount) (\(formatBytes(summary.newDownloadedBytes)))")
                print("   • Cloned via CoW:    \(summary.reflinkClonedCount) (\(formatBytes(summary.reflinkClonedBytes)))")
                print("   • Errors:            \(summary.errorCount)")
                print("   • Duration:          \(String(format: "%.1f", summary.durationSeconds)) s")

                var updated = config
                updated.schedule.lastRunDate = Date()
                try? store.saveConfiguration(updated)

                NotificationDeliveryService.shared.notifyPhotosBackupCompleted(
                    copiedCount: summary.newDownloadedCount + summary.reflinkClonedCount,
                    durationSec: summary.durationSeconds
                )
                exitCLI(0)
            } catch {
                print("\n❌ Photos backup failed: \(error.localizedDescription)")
                NotificationDeliveryService.shared.notifyPhotosBackupFailed(errorMessage: error.localizedDescription)
                exitCLI(1)
            }

        case "snapshots", "list":
            let db = DatabaseEngine()
            let unifiedPath = config.destinationURL.appendingPathComponent(".otterkeep/manifest.sqlite").path(percentEncoded: false)
            if FileManager.default.fileExists(atPath: unifiedPath) {
                try? await db.open(at: unifiedPath)
                let snaps = (try? await db.listSnapshots()) ?? []
                if snaps.isEmpty {
                    print(L10n.t(.noSnapshotsAvailable))
                } else {
                    print("📸 Photos Snapshots (\(snaps.count)):")
                    let df = ISO8601DateFormatter()
                    for s in snaps {
                        print("• [\(s.id)]  \(df.string(from: s.timestamp))  \(s.totalFiles) \(L10n.t(.assetsCountUnit))  \(formatBytes(s.totalBytes))  (\(s.snapshotPath))")
                    }
                }
            } else {
                print(L10n.t(.noSnapshotsAvailable))
            }
            exitCLI(0)

        default:
            print(L10n.format(.cliUnknownSubcommand, sub))
            exitCLI(1)
        }
    }

    // MARK: - Prune / Retention

    /// Prunes expired snapshots for a profile according to configured retention limits or custom keep threshold.
    /// - Parameter args: Command-line arguments.
    static func handlePrune(_ args: [String]) async {
        let profileName = getOption("--profile", from: args)
        let keepStr = getOption("--keep", from: args)

        let store = ProfileStore.shared
        let profiles = store.loadProfiles()
        guard !profiles.isEmpty else {
            print(L10n.t(.cliNoProfiles))
            exitCLI(1)
        }

        let profile: BackupProfile
        if let target = profileName {
            guard let matched = profiles.first(where: { $0.name.lowercased() == target.lowercased() || $0.id.uuidString.lowercased() == target.lowercased() }) else {
                print(L10n.format(.cliProfileNotFound, target))
                exitCLI(1)
            }
            profile = matched
        } else {
            profile = profiles[0]
        }

        let keepCount = keepStr.flatMap(Int.init)
        var policy = profile.pruningPolicy
        if let maxKeep = keepCount {
            policy.isAutoPruningEnabled = true
            policy.maxSnapshotsToKeep = maxKeep
        }
        let retainLabel = keepCount ?? policy.maxSnapshotsToKeep ?? 5
        print("🧹 Pruning snapshots for profile '\(profile.name)' (Retaining latest \(retainLabel))...")

        let storage = APFSFileSystemProvider()
        let database = DatabaseEngine()
        let dbPath = profile.destinationURL.appendingPathComponent(".otterkeep/manifest.sqlite").path(percentEncoded: false)
        try? await database.open(at: dbPath)
        let retention = RetentionManager(storage: storage, database: database)

        do {
            let prunedIds = try await retention.applyRetentionPolicy(destinationURL: profile.destinationURL, policy: policy)
            if prunedIds.isEmpty {
                print("ℹ️ No snapshots required pruning. All snapshots within retention limit.")
            } else {
                print("✅ Retention pruning completed successfully:")
                print("   • Pruned snapshots: \(prunedIds.count)")
                for id in prunedIds {
                    print("     - \(id)")
                }
                NotificationDeliveryService.shared.notifyPruningCompleted(profileName: profile.name, prunedCount: prunedIds.count)
            }
            exitCLI(0)
        } catch {
            print("❌ Pruning failed: \(error.localizedDescription)")
            exitCLI(1)
        }
    }

    // MARK: - Daemon & LaunchAgent

    /// Manages macOS launchd background agent registration and status.
    /// - Parameter args: Arguments passed to daemon subcommand.
    static func handleDaemon(_ args: [String]) {
        let sub = args.first ?? "status"
        let manager = DaemonServiceManager.shared

        switch sub {
        case "status":
            print("⚙️ OtterKeep LaunchAgent Status\n")
            print("   • Installed:  \(manager.isDaemonEnabled)")
            print("   • Label:      \(DaemonServiceManager.agentLabel)")
            print("   • Interval:   900 seconds (15 minutes)")
            print("   • Schedule:   Periodic Catch-Up & Auto-Backup")
            let plistPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents/\(DaemonServiceManager.agentLabel).plist").path
            print("   • Plist Path: \(plistPath)")
            exitCLI(0)

        case "install", "enable":
            do {
                try manager.registerDaemon()
                print("✅ Successfully installed and activated OtterKeep background LaunchAgent.")
                print("   The agent will run 'otterkeep schedule check' periodically every 15 minutes.")
                exitCLI(0)
            } catch {
                print("❌ Failed to install LaunchAgent: \(error.localizedDescription)")
                exitCLI(1)
            }

        case "uninstall", "disable":
            manager.unregisterDaemon()
            print("✅ Successfully unloaded and removed OtterKeep background LaunchAgent.")
            exitCLI(0)

        case "check":
            Task {
                await handleSchedule(["check"])
            }

        default:
            print(L10n.format(.cliUnknownSubcommand, sub))
            exitCLI(1)
        }
    }

    // MARK: - Doctor / Diagnostic Audit

    /// Performs a comprehensive system diagnostic audit checking permissions, disk space, and capabilities.
    static func handleDoctor() async {
        print("🩺 OtterKeep System Health & Diagnostic Audit\n")

        // 1. macOS System & Engine Version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        print("💻 Operating System: macOS \(osVersion)")
        print("🦦 OtterKeep Engine: v\(CoreEngine.version) (Build \(CoreEngine.buildNumber))")
        print("   ├── OtterKeepStorage:  v\(CoreEngine.storageVersion)")
        print("   ├── OtterKeepDatabase: v\(CoreEngine.databaseVersion)")
        print("   ├── OtterKeepCore:     v\(CoreEngine.coreVersion)")
        print("   ├── OtterKeepUI:       v\(CoreEngine.uiVersion)")
        print("   └── OtterKeepCLI:      v\(CoreEngine.cliVersion)\n")

        // 2. Full Disk Access & File System Permissions
        print("🔐 Permissions & TCC:")
        let testPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support").path
        let isFDA = access(testPath, R_OK) == 0
        if isFDA {
            print("   ✅ Full Disk Access / Filesystem Read: GRANTED")
        } else {
            print("   ⚠️ Full Disk Access: RESTRICTED or DENIED")
            print("      Action: Open System Settings > Privacy & Security > Full Disk Access and add OtterKeep.")
        }

        // 3. Profiles & Destination Capability Audit
        let store = ProfileStore.shared
        let profiles = store.loadProfiles()
        print("\n📁 Backup Profiles Audit (\(profiles.count)):")
        let storage = APFSFileSystemProvider()

        for (idx, p) in profiles.enumerated() {
            print("   [\(idx + 1)] Profile: \(p.name)")
            let srcExists = FileManager.default.fileExists(atPath: p.sourceURL.path(percentEncoded: false))
            let dstExists = FileManager.default.fileExists(atPath: p.destinationURL.path(percentEncoded: false))

            print("       • Source:      \(srcExists ? "✅ Accessible" : "❌ NOT FOUND") (\(p.sourceURL.path))")
            if srcExists, let srcCaps = try? await storage.capabilities(at: p.sourceURL) {
                print("         FS Format:   \(srcCaps.fsTypeName.uppercased()) (Precision: \(srcCaps.timestampToleranceSeconds)s)")
            }
            print("       • Destination: \(dstExists ? "✅ Mounted" : "⚠️ UNMOUNTED / NOT FOUND") (\(p.destinationURL.path))")

            if dstExists {
                if let caps = try? await storage.capabilities(at: p.destinationURL) {
                    let fsLabel = caps.fsTypeName.uppercased()
                    let roLabel = caps.isReadOnly ? " [READ-ONLY ⚠️]" : " [READ-WRITE ✅]"
                    let cowStatus = caps.supportsAPFSClone ? "✅ Supported (APFS clonefile)" : (caps.isExFAT ? "ℹ️ Fallback Stream Copy (exFAT)" : "⚠️ Unsupported CoW (Fallback Copy)")
                    print("         FS Format:   \(fsLabel)\(roLabel)")
                    print("       • CoW Clones:  \(cowStatus)")
                }
                if let capacity = try? storage.storageCapacity(at: p.destinationURL) {
                    let freeMb = capacity.availableBytes / 1024 / 1024
                    let spaceStatus = freeMb > 2048 ? "✅ \(formatBytes(capacity.availableBytes)) free" : "⚠️ LOW DISK SPACE (\(formatBytes(capacity.availableBytes)))"
                    print("       • Free Space:  \(spaceStatus)")
                }
            }
        }


        // 4. Background Daemon
        print("\n⚙️ Background Daemon:")
        let isDaemon = DaemonServiceManager.shared.isDaemonEnabled
        print("   • LaunchAgent: \(isDaemon ? "✅ Installed & Active (900s interval)" : "ℹ️ Not installed (Run 'otterkeep daemon install' to enable)")")

        print("\n🎉 Doctor diagnostic audit complete.")
        exitCLI(0)
    }

    // MARK: - Helpers

    /// Extracts the value following an option flag in an argument list.
    /// - Parameters:
    ///   - option: The option flag to search for (e.g. `--profile`).
    ///   - args: The argument array.
    /// - Returns: The argument value string if present, or `nil`.
    static func getOption(_ option: String, from args: [String]) -> String? {
        guard let idx = args.firstIndex(of: option), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    /// Formats a byte count into a human-readable file size string (e.g., "1.2 MB").
    /// - Parameter bytes: The raw byte count.
    /// - Returns: Localized and formatted byte count string.
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
