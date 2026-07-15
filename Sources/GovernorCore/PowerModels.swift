import Foundation

/// The values accepted by macOS' unified `powermode` setting.
public enum PowerMode: Int, CaseIterable, Codable, Hashable, Sendable {
    case automatic = 0
    case lowPower = 1
    case highPower = 2

    public var powermodeValue: Int { rawValue }
}
/// The currently active macOS power source. Mode writes must target this source only.
public enum PowerSource: String, CaseIterable, Codable, Sendable {
    case charger
    case battery
    case ups
}

/// The syntax supported by the current Mac and current power source.
public enum PowerControlStyle: String, Codable, Sendable {
    /// macOS exposes the unified `powermode` value (0/1/2).
    case unifiedPowermode

    /// macOS exposes only the legacy boolean `lowpowermode` value.
    case lowPowerOnly
}

/// A fresh read of the system's actual power state.
public struct PowerSnapshot: Equatable, Codable, Sendable {
    public let mode: PowerMode
    public let source: PowerSource
    public let controlStyle: PowerControlStyle
    public let highPowerAvailable: Bool
    public let observedAt: Date

    public init(
        mode: PowerMode,
        source: PowerSource,
        controlStyle: PowerControlStyle,
        highPowerAvailable: Bool,
        observedAt: Date = Date()
    ) {
        self.mode = mode
        self.source = source
        self.controlStyle = controlStyle
        self.highPowerAvailable = highPowerAvailable
        self.observedAt = observedAt
    }
}
