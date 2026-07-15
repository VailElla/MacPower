import Foundation
import Testing
@testable import GovernorHelperSupport

@Suite("Privileged pmset helper allow-list")
struct PrivilegedPMSetCommandTests {
    @Test func buildsOnlyTheSupportedUnifiedPowerModeCommands() throws {
        for source in GovernorPowerHelperPowerSource.allCases {
            for mode in 0 ... 2 {
                let request = GovernorPowerModeRequest(
                    sourceRawValue: source.rawValue,
                    modeRawValue: mode,
                    controlStyleRawValue: GovernorPowerHelperControlStyle.unifiedPowerMode.rawValue
                )
                let arguments = try PrivilegedPMSetCommand.arguments(for: request)
                #expect(arguments.count == 3)
                #expect(arguments[1] == "powermode")
                #expect(arguments[2] == String(mode))
                #expect(["-b", "-c", "-u"].contains(arguments[0]))
            }
        }
    }

    @Test func buildsOnlyTheSupportedLegacyLowPowerCommands() throws {
        for source in GovernorPowerHelperPowerSource.allCases {
            for mode in 0 ... 1 {
                let request = GovernorPowerModeRequest(
                    sourceRawValue: source.rawValue,
                    modeRawValue: mode,
                    controlStyleRawValue: GovernorPowerHelperControlStyle.legacyLowPowerMode.rawValue
                )
                let arguments = try PrivilegedPMSetCommand.arguments(for: request)
                #expect(arguments.count == 3)
                #expect(arguments[1] == "lowpowermode")
                #expect(arguments[2] == String(mode))
                #expect(["-b", "-c", "-u"].contains(arguments[0]))
            }
        }
    }

    @Test func rejectsEveryOutOfAllowListValue() {
        let invalidSource = GovernorPowerModeRequest(
            sourceRawValue: 99,
            modeRawValue: 0,
            controlStyleRawValue: GovernorPowerHelperControlStyle.unifiedPowerMode.rawValue
        )
        #expect(throws: PrivilegedPMSetCommandError.invalidPowerSource(99)) {
            try PrivilegedPMSetCommand.arguments(for: invalidSource)
        }

        let invalidMode = GovernorPowerModeRequest(
            sourceRawValue: GovernorPowerHelperPowerSource.battery.rawValue,
            modeRawValue: 99,
            controlStyleRawValue: GovernorPowerHelperControlStyle.unifiedPowerMode.rawValue
        )
        #expect(throws: PrivilegedPMSetCommandError.invalidMode(99)) {
            try PrivilegedPMSetCommand.arguments(for: invalidMode)
        }

        let invalidControlStyle = GovernorPowerModeRequest(
            sourceRawValue: GovernorPowerHelperPowerSource.battery.rawValue,
            modeRawValue: 0,
            controlStyleRawValue: 99
        )
        #expect(throws: PrivilegedPMSetCommandError.invalidControlStyle(99)) {
            try PrivilegedPMSetCommand.arguments(for: invalidControlStyle)
        }

        let legacyHighPower = GovernorPowerModeRequest(
            sourceRawValue: GovernorPowerHelperPowerSource.battery.rawValue,
            modeRawValue: 2,
            controlStyleRawValue: GovernorPowerHelperControlStyle.legacyLowPowerMode.rawValue
        )
        #expect(throws: PrivilegedPMSetCommandError.highPowerUnavailableInLegacyMode) {
            try PrivilegedPMSetCommand.arguments(for: legacyHighPower)
        }
    }

    @Test func rejectsSecureCodingRequestsWithMissingFields() throws {
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: NSNumber(value: 0),
            requiringSecureCoding: true
        )
        let coder = try NSKeyedUnarchiver(forReadingFrom: data)
        defer { coder.finishDecoding() }

        #expect(GovernorPowerModeRequest(coder: coder) == nil)
    }
}
