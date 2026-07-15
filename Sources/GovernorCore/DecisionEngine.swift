import Foundation

public enum DecisionEngineError: Error, Equatable, Sendable {
    case invalidIdleDuration
    case invalidIdleThreshold
}

public enum DecisionEngine {
    public static func decide(
        power: PowerSnapshot,
        activity: ActivitySnapshot,
        config: AutomationConfig
    ) throws -> PowerDecision {
        try validate(activity: activity, config: config)

        let requestedMode: PowerMode
        let reason: DecisionReason
        if activity.userIdleDuration >= config.idleThreshold {
            requestedMode = config.idlePowerMode
            reason = .idleThresholdReached
        } else {
            requestedMode = config.activePowerMode
            reason = .userActive
        }

        guard requestedMode == .highPower, !power.highPowerAvailable else {
            return PowerDecision(targetMode: requestedMode, reason: reason)
        }

        // High Power is a preference, not a request to bypass a live capability
        // check. A temporarily unavailable High Power environment uses Automatic.
        return PowerDecision(
            targetMode: .automatic,
            reason: .highPowerBecameUnavailable
        )
    }

    private static func validate(
        activity: ActivitySnapshot,
        config: AutomationConfig
    ) throws {
        guard activity.userIdleDuration.isFinite, activity.userIdleDuration >= 0 else {
            throw DecisionEngineError.invalidIdleDuration
        }

        guard config.idleThreshold.isFinite, config.idleThreshold >= 0 else {
            throw DecisionEngineError.invalidIdleThreshold
        }
    }
}
