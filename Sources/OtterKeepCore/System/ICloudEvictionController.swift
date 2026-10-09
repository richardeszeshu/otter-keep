import Foundation
import os
import OtterKeepStorage

/// Structured errors encountered during iCloud Drive dataless file management.
public enum ICloudError: Error, Sendable, LocalizedError, Equatable {
    /// Timed out while awaiting item download from iCloud.
    case downloadTimeout(String)
    /// Failed to initiate ubiquitous item download.
    case downloadFailed(String, String)
    /// Failed to evict ubiquitous item from local cache.
    case evictionFailed(String, String)
    /// Free storage space on the local drive is below the safe threshold.
    case lowDiskSpace(availableBytes: Int64, requiredBytes: Int64)

    /// Human-readable localized error description.
    public var errorDescription: String? {
        switch self {
        case .downloadTimeout(let path):
            return "iCloud download timeout: \(path)"
        case .downloadFailed(let path, let msg):
            return "iCloud download error (\(path)): \(msg)"
        case .evictionFailed(let path, let msg):
            return "iCloud local cache eviction error (\(path)): \(msg)"
        case .lowDiskSpace(let avail, let req):
            return "Low disk space for iCloud download. Available: \(avail / 1024 / 1024) MB, Required: \(req / 1024 / 1024) MB"
        }
    }
}

/// Actor-isolated controller managing ubiquitous iCloud Drive files, pre-download space safeguards, and immediate post-backup eviction.
public actor ICloudEvictionController {
    private let storage: FileSystemProvider
    private let logger = Logger(subsystem: "com.otterkeep", category: "iCloudController")

    /// Minimum free storage threshold (in bytes) required before initiating an iCloud download.
    public let minFreeDiskSpaceThreshold: Int64
    /// Default download timeout in seconds.
    public let downloadTimeoutSeconds: Double

    /// Initializes an `ICloudEvictionController`.
    /// - Parameters:
    ///   - storage: Filesystem provider.
    ///   - minFreeDiskSpaceThreshold: Minimum free disk bytes required (default: 2 GB).
    ///   - downloadTimeoutSeconds: Base download timeout in seconds (default: 30.0).
    public init(
        storage: FileSystemProvider = DefaultFileSystemProvider(),
        minFreeDiskSpaceThreshold: Int64 = 2 * 1024 * 1024 * 1024, // 2 GB
        downloadTimeoutSeconds: Double = 30.0
    ) {
        self.storage = storage
        self.minFreeDiskSpaceThreshold = minFreeDiskSpaceThreshold
        self.downloadTimeoutSeconds = downloadTimeoutSeconds
    }

    /// Active in-flight download tasks ensuring no file is downloaded simultaneously more than once.
    private var inFlightDownloads: [String: Task<Void, Error>] = [:]

    /// Set of item paths pre-warmed or triggered for download during backup so they are reliably evicted afterwards.
    private var prewarmedURLs: Set<String> = []

    /// Pre-warms ubiquitous downloads in batch, triggering macOS `bird` to fetch items ahead of time.
    public func prewarmUbiquitousItems(urls: [URL]) {
        for url in urls {
            let (isUbiquitous, isDataless) = checkICloudStatus(at: url)
            if isUbiquitous && (isDataless || !isItemActuallyDownloaded(at: url)) {
                let pathKey = url.standardizedFileURL.path
                prewarmedURLs.insert(pathKey)
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }
    }

    /// Verifies whether an item is truly downloaded on disk by querying both URL resource values and Darwin stat flags.
    public func isItemActuallyDownloaded(at url: URL) -> Bool {
        var checkURL = url
        checkURL.removeAllCachedResourceValues()

        let path = checkURL.standardizedFileURL.path(percentEncoded: false)
        var st = stat()
        if lstat(path, &st) == 0 {
            // Darwin SF_DATALESS = 0x40000000
            let isDataless = (st.st_flags & UInt32(0x40000000)) != 0
            if isDataless {
                return false
            }
            if (st.st_mode & S_IFMT) == S_IFDIR || st.st_blocks > 0 || st.st_size == 0 {
                return true
            }
        }

        if let values = try? checkURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey]) {
            if values.isUbiquitousItem != true { return true }
            if values.ubiquitousItemDownloadingStatus == .current || values.ubiquitousItemDownloadingStatus == .downloaded {
                return true
            }
            if values.ubiquitousItemDownloadingStatus == .notDownloaded {
                return false
            }
        }
        return false
    }

    /// Internal download coalescing method: ensures only a single Task downloads the given file.
    public func downloadItemWithDeduplication(at url: URL) async throws {
        let key = url.standardizedFileURL.path

        if let existing = inFlightDownloads[key] {
            logger.debug("Reusing active in-flight download for: \(url.lastPathComponent)")
            try await existing.value
            return
        }

        let downloadTask = Task<Void, Error> {
            try Task.checkCancellation()
            let (isUbiquitous, _) = self.checkICloudStatus(at: url)
            guard isUbiquitous else { return }
            if self.isItemActuallyDownloaded(at: url) {
                return
            }
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            let timeout = self.timeoutForFile(at: url)
            try await self.waitForDownloadCompletion(at: url, timeout: timeout)
        }

        inFlightDownloads[key] = downloadTask

        do {
            try await withTaskCancellationHandler {
                try await downloadTask.value
            } onCancel: {
                downloadTask.cancel()
            }
            inFlightDownloads.removeValue(forKey: key)
        } catch {
            inFlightDownloads.removeValue(forKey: key)
            throw error
        }
    }

    /// Dynamically computes a download timeout scaled to file size with a safe 60s base.
    /// - Parameter url: File URL.
    /// - Returns: Timeout duration in seconds.
    public func timeoutForFile(at url: URL) -> Double {
        let size: Int64
        if let meta = try? storage.metadata(at: url) {
            size = meta.size
        } else if let res = try? url.resourceValues(forKeys: [.fileSizeKey]), let s = res.fileSize {
            size = Int64(s)
        } else {
            size = 0
        }

        let baseTimeout = max(60.0, downloadTimeoutSeconds)
        let sizeMB = Double(size) / (1024 * 1024)
        let scaled = sizeMB * 3.0 // ~3 s per MB estimate
        return max(baseTimeout, scaled)
    }

    /// Checks whether a file is ubiquitous in iCloud and whether its data is currently evicted (dataless).
    /// - Parameter url: File URL to check.
    /// - Returns: Tuple indicating whether the item is ubiquitous and whether it is dataless.
    public func checkICloudStatus(at url: URL) -> (isUbiquitous: Bool, isDataless: Bool) {
        var checkURL = url
        checkURL.removeAllCachedResourceValues()

        let path = checkURL.standardizedFileURL.path(percentEncoded: false)
        var st = stat()
        let statAvailable = lstat(path, &st) == 0
        let isDatalessByStat = statAvailable && ((st.st_flags & UInt32(0x40000000)) != 0)

        if let values = try? checkURL.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]), values.isUbiquitousItem == true {
            let isDataless = isDatalessByStat || (values.ubiquitousItemDownloadingStatus == .notDownloaded)
            return (true, isDataless)
        }

        if isDatalessByStat {
            return (true, true)
        }

        return (false, false)
    }

    /// Generates candidate URLs for eviction, checking both direct user-space path and Mobile Documents container path.
    private func candidateURLsForEviction(for url: URL) -> [URL] {
        var candidates = [url]
        let stdURL = url.standardizedFileURL
        if stdURL.path != url.path {
            candidates.append(stdURL)
        }

        let path = stdURL.path(percentEncoded: false)
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let cloudDocsRoot = "\(home)/Library/Mobile Documents/com~apple~CloudDocs"

        if path.hasPrefix("\(home)/Documents") {
            let sub = String(path.dropFirst("\(home)/Documents".count))
            candidates.append(URL(fileURLWithPath: "\(cloudDocsRoot)/Documents\(sub)"))
        } else if path.hasPrefix("\(home)/Desktop") {
            let sub = String(path.dropFirst("\(home)/Desktop".count))
            candidates.append(URL(fileURLWithPath: "\(cloudDocsRoot)/Desktop\(sub)"))
        }
        return candidates
    }

    /// Robustly evicts an item from local disk cache to reclaim storage space, with retries and verification.
    public func evictUbiquitousItemWithRetry(at url: URL, maxRetries: Int = 5) async {
        var lastError: Error?
        let candidateURLs = candidateURLsForEviction(for: url)

        for attempt in 1...maxRetries {
            for targetURL in candidateURLs {
                do {
                    try FileManager.default.evictUbiquitousItem(at: targetURL)
                    logger.info("Local eviction requested successfully (attempt \(attempt)): \(targetURL.lastPathComponent)")

                    // Allow brief grace period for kernel / bird daemon to commit dataless state
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms

                    if !self.isItemActuallyDownloaded(at: url) {
                        logger.info("Local storage reclaimed successfully for: \(url.lastPathComponent)")
                        return
                    }
                } catch {
                    lastError = error
                    logger.debug("Eviction attempt \(attempt) failed for \(targetURL.lastPathComponent): \(error.localizedDescription)")

                    // Even if FileManager.default.evictUbiquitousItem threw (e.g. Cocoa Error 257 on newer macOS
                    // where the daemon processes the request asynchronously or via detached domain),
                    // check if the file became dataless:
                    try? await Task.sleep(nanoseconds: 150_000_000) // 150 ms
                    if !self.isItemActuallyDownloaded(at: url) {
                        logger.info("Local storage reclaimed successfully despite notification: \(url.lastPathComponent)")
                        return
                    }

                    // Fallback attempt via brctl evict if available and file is ubiquitous
                    let isUbiquitous = self.checkICloudStatus(at: targetURL).isUbiquitous || self.checkICloudStatus(at: url).isUbiquitous
                    if isUbiquitous {
                        let path = targetURL.standardizedFileURL.path(percentEncoded: false)
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/brctl")
                        process.arguments = ["evict", path]
                        process.standardOutput = FileHandle.nullDevice
                        process.standardError = FileHandle.nullDevice
                        try? process.run()
                        process.waitUntilExit()

                        try? await Task.sleep(nanoseconds: 100_000_000)
                        if !self.isItemActuallyDownloaded(at: url) {
                            logger.info("Local storage reclaimed via brctl for: \(url.lastPathComponent)")
                            return
                        }
                    }
                }
            }

            if attempt < maxRetries {
                try? await Task.sleep(nanoseconds: UInt64(attempt * 100_000_000))
            }
        }

        if !self.isItemActuallyDownloaded(at: url) {
            logger.info("Local storage confirmed reclaimed on final check for: \(url.lastPathComponent)")
            return
        }

        let errMsg = lastError?.localizedDescription ?? "Item remained downloaded on disk after \(maxRetries) eviction attempts"
        logger.warning("Notice: Local eviction failed after \(maxRetries) retries (\(url.lastPathComponent)): \(errMsg)")
        LogManager.shared.log(
            "Notice: Failed to evict local iCloud cache for '\(url.lastPathComponent)': \(errMsg)",
            level: .warning,
            category: "iCloud"
        )
    }

    /// Processes an item according to the configured iCloud strategy, downloading and evicting if dataless.
    /// - Parameters:
    ///   - sourceURL: Source item URL.
    ///   - destinationURL: Destination item URL.
    ///   - strategy: Selected iCloud backup strategy.
    ///   - wasOriginallyDataless: Explicit flag indicating whether the item was dataless during scanning.
    ///   - onProgress: Optional progress callback.
    public func processUbiquitousItem(
        sourceURL: URL,
        destinationURL: URL,
        strategy: ICloudBackupStrategy,
        wasOriginallyDataless: Bool? = nil,
        onProgress: (@Sendable (Int64) -> Void)? = nil
    ) async throws {
        try Task.checkCancellation()

        let (isUbiquitous, isDataless) = checkICloudStatus(at: sourceURL)

        guard isUbiquitous else {
            // Standard non-iCloud file copy
            try await storage.copyItemPreservingMetadata(at: sourceURL, to: destinationURL, progress: onProgress)
            return
        }

        let pathKey = sourceURL.standardizedFileURL.path
        let isPrewarmed = prewarmedURLs.contains(pathKey)
        let isDownloaded = isItemActuallyDownloaded(at: sourceURL)
        let needsEviction = wasOriginallyDataless ?? (isDataless || isPrewarmed || !isDownloaded)

        // If the item was not dataless originally and is already downloaded locally,
        // it is a user file that resides permanently on disk: copy directly without eviction.
        if !needsEviction && isDownloaded {
            logger.debug("iCloud file was already available locally: \(sourceURL.lastPathComponent)")
            try await storage.copyItemPreservingMetadata(at: sourceURL, to: destinationURL, progress: onProgress)
            return
        }

        switch strategy {
        case .metadataOnly:
            logger.warning("WARNING: '\(sourceURL.lastPathComponent)' was backed up as metadata/placeholder only. Cloud contents are not backed up locally!")
            LogManager.shared.log(
                "WARNING: '\(sourceURL.lastPathComponent)' was backed up as metadata/placeholder only. Cloud contents are not backed up locally!",
                level: .warning,
                category: "iCloud"
            )

            // Create empty placeholder and write xattr
            let parentDir = destinationURL.deletingLastPathComponent()
            try storage.createDirectory(at: parentDir)
            FileManager.default.createFile(atPath: destinationURL.standardizedFileURL.path(percentEncoded: false), contents: Data(), attributes: nil)
            let attrs = (try? storage.getExtendedAttributes(at: sourceURL)) ?? [:]
            var updatedAttrs = attrs
            updatedAttrs["com.otterkeep.icloud.placeholder"] = "true".data(using: .utf8)
            try? storage.setExtendedAttributes(updatedAttrs, at: destinationURL)

        case .downloadAndEvict:
            logger.info("Downloading and evicting dataless iCloud item: \(sourceURL.lastPathComponent)")
            // 1. Verify free disk space threshold (accounting for file size + buffer)
            let capacity = try storage.storageCapacity(at: sourceURL.deletingLastPathComponent())
            let fileSize: Int64
            if let meta = try? storage.metadata(at: sourceURL) {
                fileSize = meta.size
            } else if let res = try? sourceURL.resourceValues(forKeys: [.fileSizeKey]), let s = res.fileSize {
                fileSize = Int64(s)
            } else {
                fileSize = 0
            }
            let requiredBytes = minFreeDiskSpaceThreshold + fileSize
            if capacity.freeBytes < requiredBytes {
                throw ICloudError.lowDiskSpace(
                    availableBytes: capacity.freeBytes,
                    requiredBytes: requiredBytes
                )
            }

            // 2. Start ubiquitous download and await completion with in-flight deduplication if not yet downloaded
            do {
                if !isDownloaded {
                    try await downloadItemWithDeduplication(at: sourceURL)
                }

                // 3. Copy to destination
                try await storage.copyItemPreservingMetadata(at: sourceURL, to: destinationURL, progress: onProgress)

                // 4. Evict local cache immediately to reclaim disk space
                await evictUbiquitousItemWithRetry(at: sourceURL)
                prewarmedURLs.remove(pathKey)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // If download threw an error or timed out, double-check whether the file actually finished downloading:
                var checkURL = sourceURL
                checkURL.removeAllCachedResourceValues()

                if isItemActuallyDownloaded(at: checkURL) {
                    logger.info("iCloud file became available just in time: \(sourceURL.lastPathComponent)")
                    try await storage.copyItemPreservingMetadata(at: sourceURL, to: destinationURL, progress: onProgress)
                    await evictUbiquitousItemWithRetry(at: sourceURL)
                    prewarmedURLs.remove(pathKey)
                    return
                }

                // If download really failed, store metadata placeholder fallback so item is preserved
                logger.warning("iCloud download failed/timed out for '\(sourceURL.lastPathComponent)' (\(error.localizedDescription)). Storing metadata placeholder fallback.")
                LogManager.shared.log(
                    "WARNING: iCloud download failed for '\(sourceURL.lastPathComponent)' (\(error.localizedDescription)). Saved metadata placeholder fallback so the item is preserved in backup.",
                    level: .warning,
                    category: "iCloud"
                )

                let parentDir = destinationURL.deletingLastPathComponent()
                try storage.createDirectory(at: parentDir)
                FileManager.default.createFile(atPath: destinationURL.standardizedFileURL.path(percentEncoded: false), contents: Data(), attributes: nil)
                let attrs = (try? storage.getExtendedAttributes(at: sourceURL)) ?? [:]
                var updatedAttrs = attrs
                updatedAttrs["com.otterkeep.icloud.placeholder"] = "true".data(using: .utf8)
                updatedAttrs["com.otterkeep.icloud.fallback_reason"] = error.localizedDescription.data(using: .utf8)
                try? storage.setExtendedAttributes(updatedAttrs, at: destinationURL)

                // Safeguard: Always attempt eviction for items that were originally dataless or prewarmed
                if needsEviction {
                    await evictUbiquitousItemWithRetry(at: sourceURL)
                    prewarmedURLs.remove(pathKey)
                }
            }
        }
    }

    private func waitForDownloadCompletion(at url: URL, timeout: Double) async throws {
        var deadline = ContinuousClock.now + .seconds(timeout)
        var pollURL = url

        while ContinuousClock.now < deadline {
            try Task.checkCancellation()

            pollURL.removeAllCachedResourceValues()

            if isItemActuallyDownloaded(at: pollURL) {
                return
            }

            if let values = try? pollURL.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey,
                .ubiquitousItemDownloadingErrorKey
            ]) {
                if let error = values.ubiquitousItemDownloadingError {
                    throw ICloudError.downloadFailed(pollURL.path, error.localizedDescription)
                }

                if values.ubiquitousItemDownloadingStatus == .current || values.ubiquitousItemDownloadingStatus == .downloaded {
                    return
                }

                // If actively downloading, dynamically grant extra time so in-flight transfers do not time out
                if values.ubiquitousItemIsDownloading == true {
                    deadline = max(deadline, ContinuousClock.now + .seconds(60.0))
                }
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100 ms poll
        }

        // Final check before throwing timeout
        pollURL.removeAllCachedResourceValues()
        if isItemActuallyDownloaded(at: pollURL) {
            return
        }

        throw ICloudError.downloadTimeout(pollURL.path)
    }
}
