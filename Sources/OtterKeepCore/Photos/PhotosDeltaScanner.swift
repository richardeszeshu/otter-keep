import Foundation
import Photos
import OtterKeepDatabase

/// Scans the Apple Photos library, discovers album hierarchies, and computes differential delta actions.
public final class PhotosDeltaScanner: Sendable {

    /// Initializes a new `PhotosDeltaScanner`.
    public init() {}

    /// Discovers all user and smart albums, mapping asset identifiers to their containing album names.
    /// - Returns: A dictionary mapping `AssetLocalIdentifier` to an array of album name strings.
    public func mapAssetAlbums() -> [String: [String]] {
        var albumMap: [String: [String]] = [:]

        // 1. User created albums
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let title = collection.localizedTitle ?? "Untitled Album"
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            assets.enumerateObjects { asset, _, _ in
                albumMap[asset.localIdentifier, default: []].append(title)
            }
        }

        // 2. Smart albums (Favorites, Panoramas, Screenshots, etc.)
        let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        smartAlbums.enumerateObjects { collection, _, _ in
            if let title = collection.localizedTitle, !title.isEmpty {
                let assets = PHAsset.fetchAssets(in: collection, options: nil)
                assets.enumerateObjects { asset, _, _ in
                    albumMap[asset.localIdentifier, default: []].append(title)
                }
            }
        }

        return albumMap
    }

    /// Queries photo and video assets from PhotoKit adhering to the profile configuration filters.
    /// - Parameter configuration: Photos profile configuration.
    /// - Returns: An array of discovered photo asset metadata descriptors.
    public func scanAssets(configuration: PhotosBackupConfiguration) -> [ScannedPhotoAssetItem] {
        let albumMap = mapAssetAlbums()

        let fetchOptions = PHFetchOptions()
        fetchOptions.includeHiddenAssets = configuration.includeHiddenAlbum
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let allAssets = PHAsset.fetchAssets(with: fetchOptions)
        var scannedItems: [ScannedPhotoAssetItem] = []
        scannedItems.reserveCapacity(allAssets.count)

        allAssets.enumerateObjects { asset, _, _ in
            // Filter hidden assets if excluded by configuration
            if !configuration.includeHiddenAlbum && asset.isHidden {
                return
            }

            let resources = PHAssetResource.assetResources(for: asset)
            let originalResource = resources.first { $0.type == .photo || $0.type == .video } ?? resources.first
            let originalFilename = originalResource?.originalFilename ?? "asset_\(asset.localIdentifier.prefix(8)).dat"

            let mediaTypeStr: String
            switch asset.mediaType {
            case .image: mediaTypeStr = "image"
            case .video: mediaTypeStr = "video"
            case .audio: mediaTypeStr = "audio"
            default: mediaTypeStr = "unknown"
            }

            let isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
            let hasAdjustments = resources.contains { $0.type == .adjustmentData || $0.type == .fullSizePhoto || $0.type == .fullSizeVideo }

            // Estimate file size from resource metadata
            var estimatedSize: Int64 = 0
            if let res = originalResource, let sizeVal = res.value(forKey: "fileSize") as? NSNumber {
                estimatedSize = sizeVal.int64Value
            }
            if estimatedSize <= 0 {
                estimatedSize = asset.mediaType == .video ? 50 * 1024 * 1024 : 5 * 1024 * 1024
            }

            let item = ScannedPhotoAssetItem(
                localIdentifier: asset.localIdentifier,
                originalFilename: originalFilename,
                creationDate: asset.creationDate,
                modificationDate: asset.modificationDate ?? asset.creationDate ?? Date(),
                mediaType: mediaTypeStr,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                duration: asset.duration,
                isFavorite: asset.isFavorite,
                isHidden: asset.isHidden,
                isLivePhoto: isLivePhoto,
                hasAdjustments: hasAdjustments,
                albums: albumMap[asset.localIdentifier] ?? [],
                estimatedSizeBytes: estimatedSize
            )
            scannedItems.append(item)
        }

        return scannedItems
    }

    /// Resolves the destination relative file path based on layout structure and asset metadata.
    /// - Parameters:
    ///   - item: The scanned asset.
    ///   - structure: Chosen folder structure strategy.
    ///   - isEdited: True if generating the relative path for the adjusted/edited version.
    /// - Returns: A relative path string (e.g. "Originals/2026/09/IMG_0001.HEIC").
    public func resolveRelativePath(for item: ScannedPhotoAssetItem, structure: PhotosExportStructure, isEdited: Bool = false) -> String {
        let prefix = isEdited ? "Adjusted" : "Originals"
        let date = item.creationDate ?? item.modificationDate
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = String(format: "%02d", calendar.component(.month, from: date))

        let filename: String
        if isEdited {
            let baseName = (item.originalFilename as NSString).deletingPathExtension
            let ext = (item.originalFilename as NSString).pathExtension.isEmpty ? "jpg" : (item.originalFilename as NSString).pathExtension
            filename = "\(baseName)_edited.\(ext)"
        } else {
            filename = item.originalFilename
        }

        switch structure {
        case .dateHierarchy:
            return "\(prefix)/\(year)/\(month)/\(filename)"
        case .albumHierarchy:
            let primaryAlbum = item.albums.first ?? "Unsorted"
            let sanitizedAlbum = primaryAlbum.replacingOccurrences(of: "/", with: "_")
            return "\(prefix)/Albums/\(sanitizedAlbum)/\(filename)"
        case .flat:
            let cleanId = item.localIdentifier.replacingOccurrences(of: "/", with: "_")
            return "\(prefix)/\(cleanId)_\(filename)"
        }
    }

    /// Compares scanned assets against the previous snapshot index to generate the optimal delta action plan.
    /// - Parameters:
    ///   - scannedItems: List of scanned photo assets.
    ///   - previousIndex: Dictionary of previously recorded assets mapped by localIdentifier.
    ///   - configuration: Profile configuration settings.
    /// - Returns: An array of `PhotoAssetAction` commands.
    public func computeDeltaActions(
        scannedItems: [ScannedPhotoAssetItem],
        previousIndex: [String: PhotosAssetRecord],
        configuration: PhotosBackupConfiguration
    ) -> [PhotoAssetAction] {
        var actions: [PhotoAssetAction] = []
        actions.reserveCapacity(scannedItems.count)

        for item in scannedItems {
            let relativePath = resolveRelativePath(for: item, structure: configuration.exportStructure, isEdited: false)

            if let prev = previousIndex[item.localIdentifier] {
                // Change detection: if modification dates match (within 1 second tolerance), clone via APFS reflink
                let timeDiff = abs(prev.modificationTime.timeIntervalSince(item.modificationDate))
                if timeDiff < 1.0 {
                    actions.append(.cloneReflink(previousRecord: prev, relativePath: relativePath))
                    continue
                }
            }

            // New or modified asset requiring full download
            actions.append(.downloadAndExport(item: item, relativePath: relativePath))
        }

        return actions
    }
}
