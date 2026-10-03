import Foundation
import IOKit.pwr_mgt

/// Thread-safe power management assertion preventing macOS idle system sleep and App Nap during active backup operations.
public final class PowerManagementAssertion: @unchecked Sendable {
    private var assertionID: IOPMAssertionID = 0
    private var activityToken: NSObjectProtocol?
    private let lock = NSLock()

    /// Initializes a `PowerManagementAssertion` instance.
    public init() {}

    /// Begins power assertion, preventing idle sleep.
    /// - Parameter reason: Descriptive reason string recorded in system power assertions (`pmset -g assertions`).
    public func begin(reason: String) {
        lock.lock()
        defer { lock.unlock() }
        guard assertionID == 0 else { return }

        let cfReason = reason as CFString
        _ = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            cfReason,
            &assertionID
        )

        self.activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated, .suddenTerminationDisabled],
            reason: reason
        )
    }

    /// Ends active power assertion, allowing normal system sleep cycles to resume.
    public func end() {
        lock.lock()
        defer { lock.unlock() }
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    deinit {
        end()
    }
}
