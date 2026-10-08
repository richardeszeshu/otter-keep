import Foundation
import OtterKeepStorage
import OtterKeepDatabase

/// Formatter converting raw low-level filesystem, database, and system errors into user-friendly localized messages.
public struct LocalizedAppError: Sendable {
    /// Localized error title.
    public let title: String
    /// Localized detailed description.
    public let message: String
    /// Actionable remediation advice for the user, if available.
    public let remediation: String?
    /// Whether this error was caused by missing macOS Full Disk Access (TCC) or permission denial.
    public let isPermissionError: Bool
    /// Whether this error was caused by insufficient disk space.
    public let isSpaceError: Bool

    /// Formats any thrown error into a structured `LocalizedAppError`.
    /// - Parameter error: Thrown error instance.
    /// - Returns: Localized and actionable error presentation model.
    public static func format(_ error: Error) -> LocalizedAppError {
        if let fsError = error as? FileSystemError {
            switch fsError {
            case .permissionDenied(let path):
                return LocalizedAppError(
                    title: L10n.t(.errPermissionDeniedTitle),
                    message: L10n.format(.errPermissionDeniedMessage, path),
                    remediation: L10n.t(.errPermissionDeniedRemediation),
                    isPermissionError: true,
                    isSpaceError: false
                )
            case .notEnoughSpace(let required, let available):
                let reqStr = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
                let availStr = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
                return LocalizedAppError(
                    title: L10n.t(.errNotEnoughSpaceTitle),
                    message: L10n.format(.errNotEnoughSpaceMessage, reqStr, availStr),
                    remediation: L10n.t(.errNotEnoughSpaceRemediation),
                    isPermissionError: false,
                    isSpaceError: true
                )
            case .itemNotFound(let path):
                return LocalizedAppError(
                    title: L10n.t(.errItemNotFoundTitle),
                    message: L10n.format(.errItemNotFoundMessage, path),
                    remediation: L10n.t(.errItemNotFoundRemediation),
                    isPermissionError: false,
                    isSpaceError: false
                )
            case .cloneFailed(let path, _, let msg):
                return LocalizedAppError(
                    title: L10n.t(.errCloneFailedTitle),
                    message: "\(path): \(msg)",
                    remediation: L10n.t(.errCloneFailedRemediation),
                    isPermissionError: false,
                    isSpaceError: false
                )
            default:
                break
            }
        }

        if let dbError = error as? DatabaseError {
            return LocalizedAppError(
                title: L10n.t(.errDatabaseTitle),
                message: dbError.localizedDescription,
                remediation: L10n.t(.errDatabaseRemediation),
                isPermissionError: false,
                isSpaceError: false
            )
        }

        let desc = error.localizedDescription
        return LocalizedAppError(
            title: L10n.t(.errGenericTitle),
            message: desc,
            remediation: nil,
            isPermissionError: desc.contains("Operation not permitted") || desc.contains("Permission denied"),
            isSpaceError: desc.contains("No space left on device")
        )
    }
}
