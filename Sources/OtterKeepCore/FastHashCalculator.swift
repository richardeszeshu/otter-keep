import Foundation
import CryptoKit

/// High-performance hash calculator offering multi-tiered hashing and sampling integrity checks.
public enum FastHashCalculator: Sendable {
    /// Default byte sample window for partial hash calculation (8 KB).
    public static let defaultSampleSize = 8192

    /// Computes a fast partial sampling hash for large files by reading head, middle, and tail byte blocks.
    /// For files smaller than 3 * sampleSize, computes full SHA-256.
    /// - Parameters:
    ///   - fileURL: Target file URL to read.
    ///   - sampleSize: Byte size for each sampling slice (default: 8192 bytes).
    /// - Returns: Hexadecimal SHA-256 digest of sampled regions.
    public static func computeSamplingHash(for fileURL: URL, sampleSize: Int = defaultSampleSize) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? fileHandle.close()
        }

        let fileSize = try fileHandle.seekToEnd()
        let threshold = UInt64(sampleSize * 3)

        // For small files, compute standard full SHA-256
        if fileSize <= threshold {
            try fileHandle.seek(toOffset: 0)
            var hasher = SHA256()
            while true {
                let data = try fileHandle.read(upToCount: sampleSize)
                guard let data = data, !data.isEmpty else { break }
                hasher.update(data: data)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }

        var hasher = SHA256()

        // 1. Head sample
        try fileHandle.seek(toOffset: 0)
        if let head = try fileHandle.read(upToCount: sampleSize) {
            hasher.update(data: head)
        }

        // 2. Middle sample
        let midOffset = (fileSize / 2) - UInt64(sampleSize / 2)
        try fileHandle.seek(toOffset: midOffset)
        if let mid = try fileHandle.read(upToCount: sampleSize) {
            hasher.update(data: mid)
        }

        // 3. Tail sample
        let tailOffset = fileSize - UInt64(sampleSize)
        try fileHandle.seek(toOffset: tailOffset)
        if let tail = try fileHandle.read(upToCount: sampleSize) {
            hasher.update(data: tail)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Verifies whether the source file content exactly matches the expected previous cryptographic checksum.
    /// - Parameters:
    ///   - sourceURL: Source file URL to inspect.
    ///   - expectedChecksum: Previous known SHA-256 checksum string.
    /// - Returns: `true` if checksums match, `false` otherwise.
    public static func contentMatches(sourceURL: URL, expectedChecksum: String?) -> Bool {
        guard let expected = expectedChecksum, !expected.isEmpty else {
            return false
        }
        guard let current = try? ChecksumCalculator.computeSHA256(for: sourceURL) else {
            return false
        }
        return current.caseInsensitiveCompare(expected) == .orderedSame
    }

    /// Verifies whether the source file sparse sampling hash matches the expected previous sampled hash.
    /// - Parameters:
    ///   - sourceURL: Source file URL to inspect.
    ///   - expectedSamplingHash: Previous known sampling hash string.
    /// - Returns: `true` if sampled hashes match, `false` otherwise.
    public static func samplingMatches(sourceURL: URL, expectedSamplingHash: String?) -> Bool {
        guard let expected = expectedSamplingHash, !expected.isEmpty else {
            return false
        }
        guard let current = try? computeSamplingHash(for: sourceURL) else {
            return false
        }
        return current.caseInsensitiveCompare(expected) == .orderedSame
    }
}
