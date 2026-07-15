import CoreGraphics
import Foundation
import GovernorCore

/// Testable boundary for the activity source consumed by `AppModel`.
///
/// The live implementation remains the actor-backed `ActivityMonitor`; tests can
/// inject a scripted actor without replacing any power-system behavior.
protocol ActivitySampling: Sendable {
    func sample() async throws -> ActivitySnapshot?
    func reset() async
}

/// Reads the current HID idle duration from the macOS combined session event
/// source. The active and idle power-mode choices are explicit user settings,
/// so CPU load is intentionally not part of this signal.
public actor ActivityMonitor {
    typealias IdleReader = @Sendable () -> TimeInterval

    private let idleReader: IdleReader

    public init() {
        idleReader = {
            CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                // Quartz defines kCGAnyInputEventType as the all-bits-set
                // sentinel; `.null` would measure only synthetic null events.
                eventType: CGEventType(rawValue: UInt32.max)!
            )
        }
    }

    init(idleReader: @escaping IdleReader) {
        self.idleReader = idleReader
    }

    /// Captures one activity sample at the user-configured polling interval.
    public func sample() throws -> ActivitySnapshot? {
        let idleDuration = idleReader()
        guard idleDuration.isFinite, idleDuration >= 0 else {
            throw ActivityMonitorError.idleReadFailed
        }

        return ActivitySnapshot(
            userIdleDuration: idleDuration,
            observedAt: Date()
        )
    }

    /// Kept for the shared sampling protocol; no rolling state needs clearing.
    public func reset() {}
}

extension ActivityMonitor: ActivitySampling {}

enum ActivityMonitorError: Error, Equatable, LocalizedError, Sendable {
    case idleReadFailed

    var errorDescription: String? {
        switch self {
        case .idleReadFailed:
            "Unable to read the user's idle duration."
        }
    }
}
