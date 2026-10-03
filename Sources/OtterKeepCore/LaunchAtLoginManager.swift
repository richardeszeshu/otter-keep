import Foundation
import ServiceManagement

/// Manager for configuring automatic system startup (Launch at Login) via `SMAppService` or LaunchAgent property lists.
public final class LaunchAtLoginManager: @unchecked Sendable {
    /// Shared singleton instance.
    public static let shared = LaunchAtLoginManager()

    private let fileManager = FileManager.default
    private let agentLabel = "com.otterkeep.app"

    private var launchAgentURL: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    private init() {}

    /// Gets or sets whether Launch at Login is enabled.
    public var isEnabled: Bool {
        get {
            if isRunningInsideAppBundle {
                return SMAppService.mainApp.status == .enabled
            }
            return fileManager.fileExists(atPath: launchAgentURL.path)
        }
        set {
            setLaunchAtLogin(enabled: newValue)
        }
    }

    /// Registers or unregisters the app for launch at login.
    /// - Parameter enabled: True to enable, false to disable.
    public func setLaunchAtLogin(enabled: Bool) {
        if isRunningInsideAppBundle {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
                return
            } catch {
                // Fallback to LaunchAgent plist on registration failure
            }
        }

        // Developer / CLI binary fallback via user LaunchAgent plist
        if enabled {
            installLaunchAgent()
        } else {
            removeLaunchAgent()
        }
    }

    private var isRunningInsideAppBundle: Bool {
        let bundleURL = Bundle.main.bundleURL
        return bundleURL.pathExtension == "app"
    }

    private func installLaunchAgent() {
        let agentDir = launchAgentURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: agentDir.path) {
            try? fileManager.createDirectory(at: agentDir, withIntermediateDirectories: true)
        }

        let executablePath = CommandLine.arguments.first ?? Bundle.main.executablePath ?? "/usr/local/bin/otterkeep"
        let plistDict: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "StandardErrorPath": fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".otterkeep/agent_err.log").path,
            "StandardOutPath": fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".otterkeep/agent_out.log").path
        ]

        if let data = try? PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0) {
            try? data.write(to: launchAgentURL, options: .atomic)
        }
    }

    private func removeLaunchAgent() {
        if fileManager.fileExists(atPath: launchAgentURL.path) {
            try? fileManager.removeItem(at: launchAgentURL)
        }
    }
}
