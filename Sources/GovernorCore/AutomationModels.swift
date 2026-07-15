import Foundation

/// The current user-activity input consumed by one decision.
public struct ActivitySnapshot: Equatable, Codable, Sendable {
    public let userIdleDuration: TimeInterval
    public let observedAt: Date

    public init(
        userIdleDuration: TimeInterval,
        observedAt: Date = Date()
    ) {
        self.userIdleDuration = userIdleDuration
        self.observedAt = observedAt
    }
}
public struct AutomationConfig: Equatable, Codable, Sendable {
    public static let brightnessRestoreDelayRange = 0 ... 1_000
    public static let defaultBrightnessRestoreDelayMilliseconds = 0
    public static let pollingIntervalRange: ClosedRange<TimeInterval> =
        0.1 ... 60 * 60
    public static let defaultActivePollingInterval: TimeInterval = 5
    public static let defaultIdlePollingInterval: TimeInterval = 1
    public static let `default` = AutomationConfig()

    public var idleThreshold: TimeInterval
    public var activePollingInterval: TimeInterval
    public var idlePollingInterval: TimeInterval
    public var activePowerMode: PowerMode
    public var idlePowerMode: PowerMode
    public var pauseOnManualPowerModeChange: Bool
    public var restoreBrightnessAfterLowPower: Bool
    public var brightnessRestoreDelayMilliseconds: Int

    public init(
        idleThreshold: TimeInterval = 5 * 60,
        activePollingInterval: TimeInterval = Self.defaultActivePollingInterval,
        idlePollingInterval: TimeInterval = Self.defaultIdlePollingInterval,
        activePowerMode: PowerMode = .highPower,
        idlePowerMode: PowerMode = .lowPower,
        pauseOnManualPowerModeChange: Bool = false,
        restoreBrightnessAfterLowPower: Bool = true,
        brightnessRestoreDelayMilliseconds: Int =
            Self.defaultBrightnessRestoreDelayMilliseconds
    ) {
        self.idleThreshold = idleThreshold
        self.activePollingInterval = activePollingInterval
        self.idlePollingInterval = idlePollingInterval
        self.activePowerMode = activePowerMode
        self.idlePowerMode = idlePowerMode
        self.pauseOnManualPowerModeChange = pauseOnManualPowerModeChange
        self.restoreBrightnessAfterLowPower = restoreBrightnessAfterLowPower
        self.brightnessRestoreDelayMilliseconds = brightnessRestoreDelayMilliseconds
    }

    public static func clampedBrightnessRestoreDelay(_ milliseconds: Int) -> Int {
        min(
            max(milliseconds, brightnessRestoreDelayRange.lowerBound),
            brightnessRestoreDelayRange.upperBound
        )
    }

    public static func clampedPollingInterval(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return pollingIntervalRange.lowerBound }
        return min(
            max(seconds, pollingIntervalRange.lowerBound),
            pollingIntervalRange.upperBound
        )
    }
}

public enum DecisionReason: String, Equatable, Codable, Sendable {
    case highPowerBecameUnavailable
    case idleThresholdReached
    case userActive
}

public struct PowerDecision: Equatable, Sendable {
    public let targetMode: PowerMode
    public let reason: DecisionReason

    public init(targetMode: PowerMode, reason: DecisionReason) {
        self.targetMode = targetMode
        self.reason = reason
    }
}

public enum AutomationFailure: Error, Equatable, Sendable {
    case permissionDenied
    case systemReadFailed
    case invalidDecisionInput
    case switchRequestFailed
    case confirmationReadFailed
    case confirmationMismatch(expected: PowerMode, actual: PowerMode)
    case historyReadFailed
    case historyWriteFailed
    case highPowerUnavailableForRestoration
}

public enum AutomationStatus: Equatable, Sendable {
    case disabled
    case starting
    case running
    case pausedForManualChange
    case restoring
    case errorStopped(AutomationFailure)
}

/// One confirmed automatic switch. Attempts, no-ops and takeover restoration are excluded.
public struct SwitchHistoryEntry: Equatable, Codable, Sendable {
    public let timestamp: Date
    public let oldMode: PowerMode
    public let newMode: PowerMode
    public let reason: DecisionReason

    public init(
        timestamp: Date,
        oldMode: PowerMode,
        newMode: PowerMode,
        reason: DecisionReason
    ) {
        self.timestamp = timestamp
        self.oldMode = oldMode
        self.newMode = newMode
        self.reason = reason
    }
}

/// Immutable UI-facing state produced by `AutomationCoordinator`.
public struct AutomationStateSnapshot: Equatable, Sendable {
    public let status: AutomationStatus
    public let currentPower: PowerSnapshot?
    public let lastConfirmedMode: PowerMode?
    public let takeoverMode: PowerMode?
    public let manualOverrideSeen: Bool
    public let switchInFlight: Bool
    public let lastSwitchReason: DecisionReason?
    public let lastError: AutomationFailure?
    public let config: AutomationConfig
    public let history: [SwitchHistoryEntry]

    public init(
        status: AutomationStatus,
        currentPower: PowerSnapshot?,
        lastConfirmedMode: PowerMode?,
        takeoverMode: PowerMode?,
        manualOverrideSeen: Bool,
        switchInFlight: Bool,
        lastSwitchReason: DecisionReason?,
        lastError: AutomationFailure?,
        config: AutomationConfig,
        history: [SwitchHistoryEntry]
    ) {
        self.status = status
        self.currentPower = currentPower
        self.lastConfirmedMode = lastConfirmedMode
        self.takeoverMode = takeoverMode
        self.manualOverrideSeen = manualOverrideSeen
        self.switchInFlight = switchInFlight
        self.lastSwitchReason = lastSwitchReason
        self.lastError = lastError
        self.config = config
        self.history = history
    }
}
