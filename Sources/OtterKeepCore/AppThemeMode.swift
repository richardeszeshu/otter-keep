import Foundation

/// Supported application theme appearance modes.
public enum AppThemeMode: String, CaseIterable, Codable, Sendable {
    /// Dynamically follows the macOS system appearance (light or dark).
    case system = "system"
    /// Forces classic light appearance.
    case light = "light"
    /// Forces tuned dark appearance with harmonious palette on dark surfaces.
    case dark = "dark"

    public var id: String { rawValue }
}
