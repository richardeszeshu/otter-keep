import Foundation

/// Core namespace and versioning umbrella for the OtterKeep engine.
public struct CoreEngine: Sendable {
    /// Semantic version identifier of the OtterKeep core engine.
    public static let version = "1.0.0"
    
    /// Application display name.
    public static let appName = "OtterKeep"
    
    /// Main macOS bundle identifier.
    public static let bundleIdentifier = "com.otterkeep.desktop"
    
    /// Initializes a `CoreEngine` instance.
    public init() {}
}

public typealias OtterKeepEngine = CoreEngine
