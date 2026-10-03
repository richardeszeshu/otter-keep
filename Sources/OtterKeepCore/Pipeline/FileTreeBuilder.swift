import Foundation
import OtterKeepDatabase

/// Hierarchical tree node model for the snapshot file explorer and file timeline views.
public struct FileTreeNode: Identifiable, Sendable, Equatable {
    /// Unique identifier (relative path string).
    public let id: String
    /// File or directory display name.
    public let name: String
    /// Full relative path from the backup root.
    public let relativePath: String
    /// Indicates whether the node is a directory.
    public let isDirectory: Bool
    /// Aggregated file size in bytes (sum of children for directories).
    public var fileSize: Int64
    /// Last modification timestamp.
    public var modificationTime: Date
    /// Associated underlying catalog record if this node represents a file.
    public var record: FileCatalogRecord?
    /// Child nodes (nil for leaf files, array for directories).
    public var children: [FileTreeNode]?

    /// Initializes a `FileTreeNode`.
    public init(
        id: String,
        name: String,
        relativePath: String,
        isDirectory: Bool,
        fileSize: Int64 = 0,
        modificationTime: Date = Date(),
        record: FileCatalogRecord? = nil,
        children: [FileTreeNode]? = nil
    ) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.fileSize = fileSize
        self.modificationTime = modificationTime
        self.record = record
        self.children = children
    }
}

/// High-efficiency hierarchical tree reconstruction and search utility.
public enum FileTreeBuilder {
    /// Builds a hierarchical directory tree in O(N) time from a flat list of catalog records.
    /// - Parameter records: Flat array of `FileCatalogRecord` entries.
    /// - Returns: Hierarchical array of root-level `FileTreeNode` items with nested children.
    public static func buildTree(from records: [FileCatalogRecord]) -> [FileTreeNode] {
        guard !records.isEmpty else { return [] }

        var nodesByPath: [String: FileTreeNode] = [:]
        var childPathsByParent: [String: [String]] = [:]
        var rootPaths: [String] = []

        // 1. Iterate records and initialize intermediate nodes
        for record in records {
            let path = record.relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !path.isEmpty else { continue }

            let components = path.split(separator: "/").map(String.init)
            var currentPath = ""

            for (index, component) in components.enumerated() {
                let parentPath = currentPath
                currentPath = currentPath.isEmpty ? component : "\(currentPath)/\(component)"
                let isLeaf = (index == components.count - 1)

                if nodesByPath[currentPath] == nil {
                    let isDir = isLeaf ? record.isDirectory : true
                    let size = isLeaf ? record.fileSize : 0
                    let mtime = isLeaf ? record.modificationTime : Date()
                    let rec = isLeaf ? record : nil

                    let node = FileTreeNode(
                        id: currentPath,
                        name: component,
                        relativePath: currentPath,
                        isDirectory: isDir,
                        fileSize: size,
                        modificationTime: mtime,
                        record: rec,
                        children: isDir ? [] : nil
                    )
                    nodesByPath[currentPath] = node

                    if parentPath.isEmpty {
                        if !rootPaths.contains(currentPath) {
                            rootPaths.append(currentPath)
                        }
                    } else {
                        if childPathsByParent[parentPath] == nil {
                            childPathsByParent[parentPath] = []
                        }
                        if !childPathsByParent[parentPath]!.contains(currentPath) {
                            childPathsByParent[parentPath]!.append(currentPath)
                        }
                    }
                } else if isLeaf {
                    var existing = nodesByPath[currentPath]!
                    existing.fileSize = record.fileSize
                    existing.modificationTime = record.modificationTime
                    existing.record = record
                    nodesByPath[currentPath] = existing
                }
            }
        }

        // 2. Assemble tree recursively from the roots down
        func assembleNode(path: String) -> FileTreeNode {
            guard var node = nodesByPath[path] else {
                return FileTreeNode(id: path, name: (path as NSString).lastPathComponent, relativePath: path, isDirectory: false)
            }

            if let childPaths = childPathsByParent[path], !childPaths.isEmpty {
                let children = childPaths.map { assembleNode(path: $0) }
                // Sort directories first, then files alphabetically
                node.children = children.sorted { a, b in
                    if a.isDirectory != b.isDirectory {
                        return a.isDirectory && !b.isDirectory
                    }
                    return a.name.localizedStandardCompare(b.name) == .orderedAscending
                }
                // Aggregate directory total size
                node.fileSize = node.children?.reduce(0) { $0 + $1.fileSize } ?? 0
            }
            return node
        }

        let roots = rootPaths.map { assembleNode(path: $0) }
        return roots.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Builds a hierarchical directory tree from a flat list of relative path strings.
    /// - Parameter paths: Array of relative path strings.
    /// - Returns: Hierarchical array of root-level `FileTreeNode` items.
    public static func buildTree(from paths: [String]) -> [FileTreeNode] {
        let dummyRecords = paths.map { path in
            FileCatalogRecord(
                snapshotId: "",
                relativePath: path,
                fileSize: 0,
                modificationTime: Date(),
                inode: 0,
                checksum: nil,
                isDirectory: false,
                isSymlink: false
            )
        }
        return buildTree(from: dummyRecords)
    }

    /// Filters a tree hierarchy according to a search query matching filenames or path components.
    /// - Parameters:
    ///   - nodes: Input array of tree nodes.
    ///   - query: Search string.
    /// - Returns: Filtered tree preserving ancestor directories of matching nodes.
    public static func filterTree(_ nodes: [FileTreeNode], query: String) -> [FileTreeNode] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nodes }

        var result: [FileTreeNode] = []

        for node in nodes {
            let nameMatches = node.name.localizedCaseInsensitiveContains(trimmed) ||
                              node.relativePath.localizedCaseInsensitiveContains(trimmed)

            if node.isDirectory {
                let filteredChildren = filterTree(node.children ?? [], query: trimmed)
                if nameMatches || !filteredChildren.isEmpty {
                    var copy = node
                    copy.children = filteredChildren
                    result.append(copy)
                }
            } else if nameMatches {
                result.append(node)
            }
        }

        return result
    }

    /// Flattens matching leaf files from a tree for quick list presentation.
    /// - Parameters:
    ///   - nodes: Input array of tree nodes.
    ///   - query: Search query filter.
    /// - Returns: Sorted flat list of matching leaf file nodes.
    public static func flattenMatchingFiles(from nodes: [FileTreeNode], query: String) -> [FileTreeNode] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var matches: [FileTreeNode] = []

        func traverse(_ node: FileTreeNode) {
            let isMatch = trimmed.isEmpty ||
                          node.name.localizedCaseInsensitiveContains(trimmed) ||
                          node.relativePath.localizedCaseInsensitiveContains(trimmed)

            if !node.isDirectory && isMatch {
                matches.append(node)
            }
            if let children = node.children {
                for child in children {
                    traverse(child)
                }
            }
        }

        for n in nodes {
            traverse(n)
        }

        return matches.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
