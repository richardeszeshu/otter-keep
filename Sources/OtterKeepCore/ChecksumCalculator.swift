import Foundation
import CryptoKit

/// Cryptographic hash utility computing SHA-256 digests via memory-efficient streaming.
public enum ChecksumCalculator: Sendable {
    /// Computes the SHA-256 cryptographic checksum for a file using a streaming 1 MB chunked buffer.
    /// - Parameter fileURL: Target file URL to read.
    /// - Returns: Lowercase hexadecimal SHA-256 digest string.
    public static func computeSHA256(for fileURL: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? fileHandle.close()
        }

        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1 MB streaming buffer

        while true {
            let data = try fileHandle.read(upToCount: bufferSize)
            guard let data = data, !data.isEmpty else {
                break
            }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Computes the SHA-256 cryptographic checksum for in-memory data.
    /// - Parameter data: Target Data buffer to hash.
    /// - Returns: Lowercase hexadecimal SHA-256 digest string.
    public static func computeSHA256(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
