import Foundation

public enum PrivilegedPMSetCommandError: Error, Equatable, Sendable {
    case invalidPowerSource(Int)
    case invalidMode(Int)
    case invalidControlStyle(Int)
    case highPowerUnavailableInLegacyMode
}

/// The complete privileged command allow-list. The helper never receives these
/// arguments over XPC; it derives them from validated integer enums only.
public enum PrivilegedPMSetCommand {
    public static let executablePath = "/usr/bin/pmset"

    public static func arguments(for request: GovernorPowerModeRequest) throws -> [String] {
        guard let source = GovernorPowerHelperPowerSource(rawValue: request.sourceRawValue) else {
            throw PrivilegedPMSetCommandError.invalidPowerSource(request.sourceRawValue)
        }
        guard (0 ... 2).contains(request.modeRawValue) else {
            throw PrivilegedPMSetCommandError.invalidMode(request.modeRawValue)
        }
        guard let controlStyle = GovernorPowerHelperControlStyle(
            rawValue: request.controlStyleRawValue
        ) else {
            throw PrivilegedPMSetCommandError.invalidControlStyle(request.controlStyleRawValue)
        }

        switch controlStyle {
        case .unifiedPowerMode:
            return [source.commandFlag, "powermode", String(request.modeRawValue)]

        case .legacyLowPowerMode:
            guard request.modeRawValue != 2 else {
                throw PrivilegedPMSetCommandError.highPowerUnavailableInLegacyMode
            }
            return [source.commandFlag, "lowpowermode", String(request.modeRawValue)]
        }
    }
}
