import Foundation

/// 3-2-1 backup rule evaluation status.
public enum ComplianceStatus: Sendable, Equatable {
    /// Full 3-2-1 compliance achieved: >= 3 copies across >= 2 media types with at least 1 off-site / cloud copy.
    case compliant
    /// Partial compliance: multiple copies or destinations exist, but does not meet full 3-2-1 threshold.
    case partial
    /// Local copy only: no external or offsite redundancy configured.
    case localOnly
}

/// User-facing descriptive representation of 3-2-1 compliance status.
public enum Rule321Compliance: Sendable, Equatable {
    case compliant(description: String)
    case partial(description: String)
    case localOnly(description: String)
}

/// Detailed compliance report for a backup profile evaluating 3-2-1 invariants.
public struct ComplianceReport: Sendable, Equatable {
    /// Overall 3-2-1 compliance rating.
    public let status: ComplianceStatus
    /// Total number of copies (source + local destination + active secondary destinations).
    public let totalCopies: Int
    /// Number of distinct storage media classes represented.
    public let distinctMediaCount: Int
    /// Identifier tags of all active storage media classes.
    public let mediaTypes: Set<String>
    /// Whether an off-site, remote, or cloud destination is configured and enabled.
    public let hasOffsite: Bool
    /// Count of enabled secondary replication destinations.
    public let activeRemoteCount: Int
    /// Display names of all active secondary replication destinations.
    public let activeRemoteNames: [String]

    public init(
        status: ComplianceStatus,
        totalCopies: Int,
        distinctMediaCount: Int,
        mediaTypes: Set<String>,
        hasOffsite: Bool,
        activeRemoteCount: Int,
        activeRemoteNames: [String]
    ) {
        self.status = status
        self.totalCopies = totalCopies
        self.distinctMediaCount = distinctMediaCount
        self.mediaTypes = mediaTypes
        self.hasOffsite = hasOffsite
        self.activeRemoteCount = activeRemoteCount
        self.activeRemoteNames = activeRemoteNames
    }

    /// Maps to UI domain `Rule321Compliance` representation.
    public var rule321Status: Rule321Compliance {
        switch status {
        case .compliant:
            let names = activeRemoteNames.joined(separator: ", ")
            let desc = names.isEmpty ? L10n.t(.rule321StatusCompliant) : "\(L10n.t(.rule321StatusCompliant)): \(names)"
            return .compliant(description: desc)
        case .partial:
            return .partial(description: L10n.t(.rule321StatusPartial))
        case .localOnly:
            return .localOnly(description: L10n.t(.rule321StatusLocalOnly))
        }
    }

    public var copiesCount: Int { totalCopies }
    public var mediaTypesCount: Int { distinctMediaCount }
    public var mediaTypeIdentifiers: Set<String> { mediaTypes }
    public var activeRemoteDestinationsCount: Int { activeRemoteCount }
}

/// Evaluator calculating compliance against the industry-standard 3-2-1 Backup Rule:
/// - 3 copies of data (source, local destination, secondary copies)
/// - 2 different storage media types (local disk, network share, cloud object storage)
/// - 1 copy off-site / in the cloud
public enum ComplianceEvaluator: Sendable {

    /// Evaluates 3-2-1 backup compliance for a given `BackupProfile`.
    /// - Parameter profile: The backup profile to analyze.
    /// - Returns: A comprehensive `ComplianceReport`.
    public static func evaluate(profile: BackupProfile) -> ComplianceReport {
        // Base setup: Source (1) + Local Destination (1) = 2 base copies
        var copies = 2
        var mediaTypes: Set<String> = ["local_source", "local_destination"]
        var hasOffsite = false

        let activeDestinations = profile.copyJobConfig.isEnabled
            ? profile.copyJobConfig.destinations.filter { $0.isEnabled }
            : []

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

        let status: ComplianceStatus
        if copies >= 3 && mediaTypes.count >= 2 && hasOffsite {
            status = .compliant
        } else if hasOffsite || !activeDestinations.isEmpty {
            status = .partial
        } else {
            status = .localOnly
        }

        return ComplianceReport(
            status: status,
            totalCopies: copies,
            distinctMediaCount: mediaTypes.count,
            mediaTypes: mediaTypes,
            hasOffsite: hasOffsite,
            activeRemoteCount: activeDestinations.count,
            activeRemoteNames: activeDestinations.map { $0.name }
        )
    }
}
