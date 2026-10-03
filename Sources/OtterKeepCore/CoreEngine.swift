import Foundation

/// Core namespace and versioning umbrella for the OtterKeep engine.
public struct CoreEngine: Sendable {
    /// Semantic version identifier of the OtterKeep application (main product version).
    public static let version = "1.2.0"

    /// Internal build sequence number.
    public static let buildNumber = "1200"

    /// Subsystem versions:
    public static let coreVersion = "1.1.0"
    public static let cliVersion = "1.0.0"
    public static let uiVersion = "1.2.0"

    /// Application display name.
    public static let appName = "OtterKeep"

    /// Main macOS bundle identifier.
    public static let bundleIdentifier = "com.otterkeep.desktop"

    /// Initializes a `CoreEngine` instance.
    public init() {}
}

public typealias OtterKeepEngine = CoreEngine
