import Foundation

/// Token bucket based rate limiter for network stream reads and writes (Smart Throttling).
public actor BandwidthThrottler {
    /// Maximum allowed bytes per second (0 means unlimited).
    public private(set) var maxBytesPerSecond: Int64
    private var availableTokens: Double
    private var lastRefillTime: ContinuousClock.Instant

    public init(maxBytesPerSecond: Int64 = 0) {
        self.maxBytesPerSecond = maxBytesPerSecond
        self.availableTokens = Double(maxBytesPerSecond)
        self.lastRefillTime = ContinuousClock.now
    }

    /// Dynamically updates the rate limit.
    public func setRateLimit(maxBytesPerSecond: Int64) {
        self.maxBytesPerSecond = maxBytesPerSecond
        self.availableTokens = Double(maxBytesPerSecond)
        self.lastRefillTime = ContinuousClock.now
    }

    /// Requests permission to transfer `byteCount` bytes, throttling execution via async sleep if necessary.
    public func throttle(byteCount: Int64) async {
        guard maxBytesPerSecond > 0, byteCount > 0 else { return }

        while true {
            let now = ContinuousClock.now
            let elapsed = Double((now - lastRefillTime).components.attoseconds) / 1e18 + Double((now - lastRefillTime).components.seconds)
            lastRefillTime = now

            availableTokens = min(Double(maxBytesPerSecond), availableTokens + (elapsed * Double(maxBytesPerSecond)))

            if availableTokens >= Double(byteCount) {
                availableTokens -= Double(byteCount)
                return
            }

            let needed = Double(byteCount) - availableTokens
            let waitSeconds = needed / Double(maxBytesPerSecond)
            let waitNanoseconds = UInt64(waitSeconds * 1_000_000_000)

            try? await Task.sleep(nanoseconds: max(1_000_000, waitNanoseconds))
        }
    }
}
