import Foundation
import GovernorCore

public enum IdleTimeUnit: String, CaseIterable, Sendable {
    case minutes
    case seconds

    func displayText(in language: AppLanguage) -> String {
        switch self {
        case .minutes:
            AppText.choose(language, english: "minutes", chinese: "分钟")
        case .seconds:
            AppText.choose(language, english: "seconds", chinese: "秒")
        }
    }

    var secondsPerUnit: TimeInterval {
        switch self {
        case .minutes:
            60
        case .seconds:
            1
        }
    }
}

public enum PollingIntervalUnit: String, CaseIterable, Sendable {
    case milliseconds
    case seconds
    case minutes

    static let activeOptions = allCases
    static let idleOptions: [PollingIntervalUnit] = [.milliseconds, .seconds]

    func displayText(in language: AppLanguage) -> String {
        switch self {
        case .milliseconds:
            AppText.choose(language, english: "milliseconds", chinese: "毫秒")
        case .seconds:
            AppText.choose(language, english: "seconds", chinese: "秒")
        case .minutes:
            AppText.choose(language, english: "minutes", chinese: "分钟")
        }
    }

    var secondsPerUnit: TimeInterval {
        switch self {
        case .milliseconds:
            0.001
        case .seconds:
            1
        case .minutes:
            60
        }
    }
}

/// Persists the durable first-version decision settings. Automation is
/// intentionally a session state: a new process starts disabled and can request
/// its session-scoped administrator authorization only after an explicit click.
public actor UserDefaultsAutomationSettingsStore {
    private enum Key {
        // Retain the original keys so Governor upgrades preserve existing
        // automation preferences while the bundle identity remains stable.
        static let idleThreshold = "MacPower.settings.idleThresholdSeconds"
        static let idleTimeUnit = "MacPower.settings.idleTimeUnit"
        static let activePollingInterval =
            "MacPower.settings.activePollingIntervalSeconds"
        static let idlePollingInterval =
            "MacPower.settings.idlePollingIntervalSeconds"
        static let activePollingIntervalUnit =
            "MacPower.settings.activePollingIntervalUnit"
        static let idlePollingIntervalUnit =
            "MacPower.settings.idlePollingIntervalUnit"
        static let activePowerMode = "MacPower.settings.activePowerMode"
        static let idlePowerMode = "MacPower.settings.idlePowerMode"
        static let pauseOnManualPowerModeChange =
            "MacPower.settings.pauseOnManualPowerModeChange"
        static let restoreBrightnessAfterLowPower =
            "MacPower.settings.restoreBrightnessAfterLowPower"
        static let brightnessRestoreDelayMilliseconds =
            "MacPower.settings.brightnessRestoreDelayMilliseconds"
    }

    private let defaults: UserDefaults

    public init() {
        defaults = .standard
    }

    /// Creates and owns a defaults suite without transferring a non-Sendable
    /// `UserDefaults` reference across an actor boundary. Intended for isolated
    /// tests and previews.
    public init(suiteName: String) {
        guard let suiteDefaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create UserDefaults suite: \(suiteName)")
        }
        defaults = suiteDefaults
    }

    public func loadConfig() -> AutomationConfig {
        let idleThreshold: TimeInterval
        if defaults.object(forKey: Key.idleThreshold) != nil {
            let stored = defaults.double(forKey: Key.idleThreshold)
            idleThreshold = stored.isFinite
                && stored >= 1
                && stored <= TimeInterval(Int.max) * 60
                ? stored
                : AutomationConfig.default.idleThreshold
        } else {
            idleThreshold = AutomationConfig.default.idleThreshold
        }

        let restoreBrightnessAfterLowPower: Bool
        if defaults.object(forKey: Key.restoreBrightnessAfterLowPower) != nil {
            restoreBrightnessAfterLowPower = defaults.bool(
                forKey: Key.restoreBrightnessAfterLowPower
            )
        } else {
            restoreBrightnessAfterLowPower =
                AutomationConfig.default.restoreBrightnessAfterLowPower
        }

        let brightnessRestoreDelayMilliseconds: Int
        if defaults.object(forKey: Key.brightnessRestoreDelayMilliseconds) != nil {
            let stored = defaults.integer(
                forKey: Key.brightnessRestoreDelayMilliseconds
            )
            brightnessRestoreDelayMilliseconds =
                AutomationConfig.brightnessRestoreDelayRange.contains(stored)
                ? stored
                : AutomationConfig.default.brightnessRestoreDelayMilliseconds
        } else {
            brightnessRestoreDelayMilliseconds =
                AutomationConfig.default.brightnessRestoreDelayMilliseconds
        }

        return AutomationConfig(
            idleThreshold: idleThreshold,
            activePollingInterval: loadPollingInterval(
                forKey: Key.activePollingInterval,
                fallback: AutomationConfig.default.activePollingInterval
            ),
            idlePollingInterval: loadPollingInterval(
                forKey: Key.idlePollingInterval,
                fallback: AutomationConfig.default.idlePollingInterval
            ),
            activePowerMode: loadPowerMode(
                forKey: Key.activePowerMode,
                fallback: AutomationConfig.default.activePowerMode
            ),
            idlePowerMode: loadPowerMode(
                forKey: Key.idlePowerMode,
                fallback: AutomationConfig.default.idlePowerMode
            ),
            pauseOnManualPowerModeChange: defaults.bool(
                forKey: Key.pauseOnManualPowerModeChange
            ),
            restoreBrightnessAfterLowPower: restoreBrightnessAfterLowPower,
            brightnessRestoreDelayMilliseconds: brightnessRestoreDelayMilliseconds
        )
    }

    public func loadIdleTimeUnit() -> IdleTimeUnit {
        guard let stored = defaults.string(forKey: Key.idleTimeUnit) else {
            return .minutes
        }
        return IdleTimeUnit(rawValue: stored) ?? .minutes
    }

    public func loadActivePollingIntervalUnit() -> PollingIntervalUnit {
        loadPollingIntervalUnit(
            forKey: Key.activePollingIntervalUnit,
            allowedUnits: PollingIntervalUnit.activeOptions
        )
    }

    public func loadIdlePollingIntervalUnit() -> PollingIntervalUnit {
        loadPollingIntervalUnit(
            forKey: Key.idlePollingIntervalUnit,
            allowedUnits: PollingIntervalUnit.idleOptions
        )
    }

    public func saveConfig(
        _ config: AutomationConfig,
        idleTimeUnit: IdleTimeUnit = .minutes,
        activePollingIntervalUnit: PollingIntervalUnit = .seconds,
        idlePollingIntervalUnit: PollingIntervalUnit = .seconds
    ) {
        guard config.idleThreshold.isFinite,
              config.idleThreshold >= 1,
              config.idleThreshold <= TimeInterval(Int.max) * 60,
              AutomationConfig.pollingIntervalRange.contains(
                  config.activePollingInterval
              ),
              AutomationConfig.pollingIntervalRange.contains(
                  config.idlePollingInterval
              ),
              AutomationConfig.brightnessRestoreDelayRange.contains(
                  config.brightnessRestoreDelayMilliseconds
              )
        else {
            return
        }
        defaults.set(config.idleThreshold, forKey: Key.idleThreshold)
        defaults.set(idleTimeUnit.rawValue, forKey: Key.idleTimeUnit)
        defaults.set(
            config.activePollingInterval,
            forKey: Key.activePollingInterval
        )
        defaults.set(
            config.idlePollingInterval,
            forKey: Key.idlePollingInterval
        )
        defaults.set(
            activePollingIntervalUnit.rawValue,
            forKey: Key.activePollingIntervalUnit
        )
        defaults.set(
            normalizedIdlePollingIntervalUnit(idlePollingIntervalUnit).rawValue,
            forKey: Key.idlePollingIntervalUnit
        )
        defaults.set(config.activePowerMode.rawValue, forKey: Key.activePowerMode)
        defaults.set(config.idlePowerMode.rawValue, forKey: Key.idlePowerMode)
        defaults.set(
            config.pauseOnManualPowerModeChange,
            forKey: Key.pauseOnManualPowerModeChange
        )
        defaults.set(
            config.restoreBrightnessAfterLowPower,
            forKey: Key.restoreBrightnessAfterLowPower
        )
        defaults.set(
            config.brightnessRestoreDelayMilliseconds,
            forKey: Key.brightnessRestoreDelayMilliseconds
        )
    }

    private func loadPowerMode(forKey key: String, fallback: PowerMode) -> PowerMode {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return PowerMode(rawValue: defaults.integer(forKey: key)) ?? fallback
    }

    private func loadPollingInterval(
        forKey key: String,
        fallback: TimeInterval
    ) -> TimeInterval {
        guard defaults.object(forKey: key) != nil else { return fallback }
        let stored = defaults.double(forKey: key)
        guard stored.isFinite,
              AutomationConfig.pollingIntervalRange.contains(stored)
        else {
            return fallback
        }
        return stored
    }

    private func loadPollingIntervalUnit(
        forKey key: String,
        allowedUnits: [PollingIntervalUnit]
    ) -> PollingIntervalUnit {
        guard let stored = defaults.string(forKey: key) else {
            return .seconds
        }
        guard let unit = PollingIntervalUnit(rawValue: stored),
              allowedUnits.contains(unit)
        else {
            return .seconds
        }
        return unit
    }

    private func normalizedIdlePollingIntervalUnit(
        _ unit: PollingIntervalUnit
    ) -> PollingIntervalUnit {
        PollingIntervalUnit.idleOptions.contains(unit) ? unit : .seconds
    }
}

/// Stores only confirmed automatic switches and enforces the product limit at
/// both write and read boundaries. Entries are preserved in caller order.
public actor UserDefaultsSwitchHistoryStore: SwitchHistoryStore {
    public static let maximumEntryCount = 20

    private enum Key {
        // See UserDefaultsAutomationSettingsStore.Key for the compatibility rationale.
        static let history = "MacPower.automaticSwitchHistory"
    }

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        defaults = .standard
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    /// Creates and owns a defaults suite without transferring a non-Sendable
    /// `UserDefaults` reference across an actor boundary. Intended for isolated
    /// tests and previews.
    public init(suiteName: String) {
        guard let suiteDefaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create UserDefaults suite: \(suiteName)")
        }
        defaults = suiteDefaults
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    public func loadHistory() async throws -> [SwitchHistoryEntry] {
        guard let data = defaults.data(forKey: Key.history) else { return [] }
        let decoded = try decoder.decode([SwitchHistoryEntry].self, from: data)
        return Array(decoded.suffix(Self.maximumEntryCount))
    }

    public func saveHistory(_ history: [SwitchHistoryEntry]) async throws {
        let limited = Array(history.suffix(Self.maximumEntryCount))
        let data = try encoder.encode(limited)
        defaults.set(data, forKey: Key.history)
    }
}
