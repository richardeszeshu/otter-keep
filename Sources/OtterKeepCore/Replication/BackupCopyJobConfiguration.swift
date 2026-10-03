import Foundation

/// Trigger mechanism for the 3-2-1 secondary replication copy job.
public enum CopyJobTrigger: String, Codable, Sendable, CaseIterable {
    /// Automatically starts replication immediately after the primary local APFS backup completes.
    case onPrimarySuccess = "onPrimarySuccess"
    /// Runs on a dedicated scheduled window or periodic timer.
    case scheduled = "scheduled"
    /// Only triggers when initiated manually by the user.
    case manual = "manual"

    public var localizedKey: L10n.Key {
        switch self {
        case .onPrimarySuccess: return .copyJobTriggerOnPrimary
        case .scheduled: return .copyJobTriggerScheduled
        case .manual: return .copyJobTriggerManual
        }
    }

    public var localizedTitle: String {
        L10n.t(localizedKey)
    }
}

/// Network policy rules governing when background replication is permitted.
public enum CopyJobNetworkPolicy: String, Codable, Sendable, CaseIterable {
    /// Only replicates on unmetered connections (Wi-Fi or Wired Ethernet, pauses on Hotspot / Low Data Mode).
    case unmeteredOnly = "unmeteredOnly"
    /// Replicates over any available internet connection.
    case allowAny = "allowAny"

    public var localizedKey: L10n.Key {
        switch self {
        case .unmeteredOnly: return .copyJobPolicyUnmetered
        case .allowAny: return .copyJobPolicyAny
        }
    }

    public var localizedTitle: String {
        L10n.t(localizedKey)
    }
}

/// Configuration settings for the 3-2-1 Backup Copy Job replication engine.
public struct BackupCopyJobConfiguration: Codable, Sendable, Equatable {
    /// Whether the automated backup copy job is enabled for this profile.
    public var isEnabled: Bool
    /// Execution trigger mode.
    public var trigger: CopyJobTrigger
    /// Network constraint policy (unmetered vs any).
    public var networkPolicy: CopyJobNetworkPolicy
    /// Whether replication should pause when running on battery power.
    public var requireACPower: Bool
    /// Maximum upload bandwidth limit in bytes per second (0 for unlimited).
    public var maxBandwidthBytesPerSec: Int64
    /// List of configured remote destinations (S3 buckets, NAS shares).
    public var destinations: [RemoteDestination]
    /// Allowed Wi-Fi network SSIDs (empty allows any non-disallowed network).
    public var allowedWiFiSSIDs: [String]
    /// Disallowed Wi-Fi network SSIDs (replication is paused on these).
    public var disallowedWiFiSSIDs: [String]
    /// Whether replication automatically pauses on metered/hotspot connections.
    public var pauseOnMeteredNetwork: Bool
    /// Whether replication packages the entire snapshot into a single compressed archive (.tar.zst / .tar.gz).
    public var archivePackagingEnabled: Bool
    /// Compression level for archive packaging (1 = fast, 3 = balanced, 9 = maximum).
    public var archiveCompressionLevel: Int

    public init(
        isEnabled: Bool = false,
        trigger: CopyJobTrigger = .onPrimarySuccess,
        networkPolicy: CopyJobNetworkPolicy = .unmeteredOnly,
        requireACPower: Bool = false,
        maxBandwidthBytesPerSec: Int64 = 0,
        destinations: [RemoteDestination] = [],
        allowedWiFiSSIDs: [String] = [],
        disallowedWiFiSSIDs: [String] = [],
        pauseOnMeteredNetwork: Bool = true,
        archivePackagingEnabled: Bool = false,
        archiveCompressionLevel: Int = 3
    ) {
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.networkPolicy = networkPolicy
        self.requireACPower = requireACPower
        self.maxBandwidthBytesPerSec = maxBandwidthBytesPerSec
        self.destinations = destinations
        self.allowedWiFiSSIDs = allowedWiFiSSIDs
        self.disallowedWiFiSSIDs = disallowedWiFiSSIDs
        self.pauseOnMeteredNetwork = pauseOnMeteredNetwork
        self.archivePackagingEnabled = archivePackagingEnabled
        self.archiveCompressionLevel = archiveCompressionLevel
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled, trigger, networkPolicy, requireACPower, maxBandwidthBytesPerSec, destinations
        case allowedWiFiSSIDs, disallowedWiFiSSIDs, pauseOnMeteredNetwork
        case archivePackagingEnabled, archiveCompressionLevel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        self.trigger = try container.decodeIfPresent(CopyJobTrigger.self, forKey: .trigger) ?? .onPrimarySuccess
        self.networkPolicy = try container.decodeIfPresent(CopyJobNetworkPolicy.self, forKey: .networkPolicy) ?? .unmeteredOnly
        self.requireACPower = try container.decodeIfPresent(Bool.self, forKey: .requireACPower) ?? false
        self.maxBandwidthBytesPerSec = try container.decodeIfPresent(Int64.self, forKey: .maxBandwidthBytesPerSec) ?? 0
        self.destinations = try container.decodeIfPresent([RemoteDestination].self, forKey: .destinations) ?? []
        self.allowedWiFiSSIDs = try container.decodeIfPresent([String].self, forKey: .allowedWiFiSSIDs) ?? []
        self.disallowedWiFiSSIDs = try container.decodeIfPresent([String].self, forKey: .disallowedWiFiSSIDs) ?? []
        self.pauseOnMeteredNetwork = try container.decodeIfPresent(Bool.self, forKey: .pauseOnMeteredNetwork) ?? true
        self.archivePackagingEnabled = try container.decodeIfPresent(Bool.self, forKey: .archivePackagingEnabled) ?? false
        self.archiveCompressionLevel = try container.decodeIfPresent(Int.self, forKey: .archiveCompressionLevel) ?? 3
    }
}

