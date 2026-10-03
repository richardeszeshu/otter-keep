import Foundation
import ServiceManagement
import os

/// Manager controlling the headless background daemon and launchd LaunchAgent lifecycle.
public final class DaemonServiceManager: @unchecked Sendable {
    public static let shared = DaemonServiceManager()
    private let logger = Logger(subsystem: "com.otterkeep", category: "DaemonService")

    public static let agentLabel = "com.otterkeep.daemon"

    private var launchAgentURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(Self.agentLabel).plist")
    }

    private init() {}

    /// Checks whether the background headless agent plist is currently installed.
    public var isDaemonEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    /// Registers and installs the headless background LaunchAgent plist into `~/Library/LaunchAgents/`.
    /// - Parameter cliBinaryPath: Optional custom path to `otterkeep` CLI executable.
    public func registerDaemon(cliBinaryPath: String? = nil) throws {
        let binaryPath = cliBinaryPath ?? resolveDefaultCLIPath()

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.agentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(binaryPath)</string>
                <string>schedule</string>
                <string>check</string>
            </array>
            <key>StartInterval</key>
            <integer>900</integer>
            <key>RunAtLoad</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(FileManager.default.homeDirectoryForCurrentUser.path)/.otterkeep/daemon.log</string>
            <key>StandardErrorPath</key>
            <string>\(FileManager.default.homeDirectoryForCurrentUser.path)/.otterkeep/daemon_err.log</string>
        </dict>
        </plist>
        """

        let parentDir = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let dotDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".otterkeep")
        try FileManager.default.createDirectory(at: dotDir, withIntermediateDirectories: true)

        try plistContent.write(to: launchAgentURL, atomically: true, encoding: .utf8)
        logger.info("Successfully installed background LaunchAgent plist at: \(self.launchAgentURL.path)")

        // Load with launchctl
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", "-w", launchAgentURL.path]
        try? process.run()
        process.waitUntilExit()
    }

    /// Unregisters and removes the headless background LaunchAgent plist.
    public func unregisterDaemon() {
        if isDaemonEnabled {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["unload", "-w", launchAgentURL.path]
            try? process.run()
            process.waitUntilExit()

            try? FileManager.default.removeItem(at: launchAgentURL)
            logger.info("Successfully unregistered background LaunchAgent plist.")
        }
    }

    private func resolveDefaultCLIPath() -> String {
        // 1. Check if otterkeep is in /usr/local/bin or ~/.local/bin
        let localBin = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/otterkeep").path
        if FileManager.default.fileExists(atPath: localBin) { return localBin }

        let usrLocal = "/usr/local/bin/otterkeep"
        if FileManager.default.fileExists(atPath: usrLocal) { return usrLocal }

        // 2. Fallback inside app bundle if available
        let appBundleCLI = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/otterkeep").path
        if FileManager.default.fileExists(atPath: appBundleCLI) { return appBundleCLI }

        return "/usr/local/bin/otterkeep"
    }
}
