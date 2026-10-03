import Foundation
import CryptoKit

/// Helper for generating AWS Signature Version 4 (SigV4) headers for S3-compatible cloud endpoints (Pure Swift, zero external dependencies).
public enum S3Signer: Sendable {
    private static let iso8601BasicFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    private static let dateStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    /// Computes SHA256 hex string for a given Data payload.
    public static func sha256Hex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Computes HMAC-SHA256 given a key and data.
    private static func hmacSHA256(key: Data, data: Data) -> Data {
        let key = SymmetricKey(data: key)
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return Data(signature)
    }

    /// Generates the AWS SigV4 Authorization header and associated required headers (x-amz-date, x-amz-content-sha256).
    /// - Parameters:
    ///   - method: HTTP Method (GET, PUT, HEAD, DELETE, POST).
    ///   - url: Target URL with host and path.
    ///   - headers: Existing HTTP headers dictionary.
    ///   - payload: Request body data.
    ///   - accessKey: S3 Access Key ID.
    ///   - secretKey: S3 Secret Access Key.
    ///   - region: S3 Region (e.g. "us-east-1", "eu-central-1", "auto").
    ///   - service: Service name (default: "s3").
    ///   - date: Request timestamp (default: current date).
    /// - Returns: Dictionary of signed headers to attach to the URLRequest.
    public static func signRequestHeaders(
        method: String,
        url: URL,
        headers: [String: String] = [:],
        payload: Data,
        accessKey: String,
        secretKey: String,
        region: String,
        service: String = "s3",
        date: Date = Date()
    ) -> [String: String] {
        let amzDate = iso8601BasicFormatter.string(from: date)
        let dateStamp = dateStampFormatter.string(from: date)
        let payloadHash = sha256Hex(for: payload)

        var finalHeaders = headers
        finalHeaders["x-amz-date"] = amzDate
        finalHeaders["x-amz-content-sha256"] = payloadHash

        guard let host = url.host else {
            return finalHeaders
        }

        let portSuffix: String
        if let port = url.port, port != 80 && port != 443 {
            portSuffix = ":\(port)"
        } else {
            portSuffix = ""
        }
        finalHeaders["host"] = host + portSuffix

        // 1. Create Canonical Headers & Signed Headers list
        let sortedHeaderKeys = finalHeaders.keys.map { $0.lowercased() }.sorted()
        let canonicalHeaders = sortedHeaderKeys.map { key -> String in
            let matchingOriginalKey = finalHeaders.keys.first { $0.lowercased() == key } ?? key
            let val = finalHeaders[matchingOriginalKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "\(key):\(val)\n"
        }.joined()

        let signedHeaders = sortedHeaderKeys.joined(separator: ";")

        // 2. Canonical URI
        var canonicalURI = url.path
        if canonicalURI.isEmpty {
            canonicalURI = "/"
        }
        // Normalize multiple slashes and percent encode if needed
        let encodedURI = canonicalURI.split(separator: "/", omittingEmptySubsequences: false).map {
            $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")

        // 3. Canonical Query String
        var canonicalQuery = ""
        if let query = url.query {
            let queryItems = query.split(separator: "&").map { String($0) }
            let sortedQuery = queryItems.sorted()
            canonicalQuery = sortedQuery.joined(separator: "&")
        }

        // 4. Canonical Request
        let canonicalRequest = [
            method.uppercased(),
            encodedURI.isEmpty ? "/" : encodedURI,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let canonicalRequestHash = sha256Hex(for: Data(canonicalRequest.utf8))

        // 5. String to Sign
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            canonicalRequestHash
        ].joined(separator: "\n")

        // 6. Calculate Signature Key
        let kSecret = Data("AWS4\(secretKey)".utf8)
        let kDate = hmacSHA256(key: kSecret, data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))

        let signatureData = hmacSHA256(key: kSigning, data: Data(stringToSign.utf8))
        let signatureHex = signatureData.map { String(format: "%02x", $0) }.joined()

        // 7. Authorization Header
        let authHeader = "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signatureHex)"
        finalHeaders["Authorization"] = authHeader

        return finalHeaders
    }
}
