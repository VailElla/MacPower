import Foundation

enum PMSetParsedPowerSource: String, Equatable, Sendable {
    case battery = "Battery Power"
    case ac = "AC Power"
    case ups = "UPS Power"

    var commandFlag: String {
        switch self {
        case .battery: "-b"
        case .ac: "-c"
        case .ups: "-u"
        }
    }
}

enum PMSetParsedControlStyle: Equatable, Sendable {
    case unifiedPowerMode
    case legacyLowPowerMode
}

struct PMSetParsedLiveState: Equatable, Sendable {
    /// macOS' unified encoding: 0 = Automatic, 1 = Low Power, 2 = High Power.
    let modeValue: Int
    let controlStyle: PMSetParsedControlStyle
}

struct PMSetParsedCapabilities: Equatable, Sendable {
    let source: PMSetParsedPowerSource
    let supportsLowPower: Bool
    let supportsHighPower: Bool
}

enum PMSetParseError: Error, Equatable, LocalizedError {
    case missingCurrentPowerSource
    case unknownPowerSource(String)
    case missingLivePowerMode
    case invalidPowerMode(String)
    case conflictingPowerModes
    case missingCapabilitiesHeader

    var errorDescription: String? {
        switch self {
        case .missingCurrentPowerSource:
            "pmset did not report the current power source."
        case let .unknownPowerSource(value):
            "pmset reported an unknown power source: \(value)."
        case .missingLivePowerMode:
            "pmset did not report the live power mode."
        case let .invalidPowerMode(value):
            "pmset reported an invalid power mode: \(value)."
        case .conflictingPowerModes:
            "pmset reported conflicting live power modes."
        case .missingCapabilitiesHeader:
            "pmset did not report the capabilities power source."
        }
    }
}

enum PMSetOutputParser {
    static func parseCurrentPowerSource(_ output: String) throws -> PMSetParsedPowerSource {
        let prefix = "Now drawing from '"

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix(prefix), line.hasSuffix("'") else { continue }

            let start = line.index(line.startIndex, offsetBy: prefix.count)
            let end = line.index(before: line.endIndex)
            return try parsePowerSourceName(String(line[start..<end]))
        }

        throw PMSetParseError.missingCurrentPowerSource
    }

    static func parseLiveState(_ output: String) throws -> PMSetParsedLiveState {
        var result: PMSetParsedLiveState?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let fields = rawLine.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2 else { continue }

            let style: PMSetParsedControlStyle
            let allowedValues: ClosedRange<Int>
            switch fields[0] {
            case "powermode":
                style = .unifiedPowerMode
                allowedValues = 0 ... 2
            case "lowpowermode":
                style = .legacyLowPowerMode
                allowedValues = 0 ... 1
            default:
                continue
            }

            let rawValue = String(fields[1])
            guard let value = Int(rawValue), allowedValues.contains(value) else {
                throw PMSetParseError.invalidPowerMode(rawValue)
            }

            let candidate = PMSetParsedLiveState(modeValue: value, controlStyle: style)
            if let result, result != candidate {
                throw PMSetParseError.conflictingPowerModes
            }
            result = candidate
        }

        guard let result else {
            throw PMSetParseError.missingLivePowerMode
        }
        return result
    }

    static func parseCapabilities(_ output: String) throws -> PMSetParsedCapabilities {
        let headerPrefix = "Capabilities for "
        var source: PMSetParsedPowerSource?
        var features = Set<String>()

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix(headerPrefix), line.hasSuffix(":") {
                let start = line.index(line.startIndex, offsetBy: headerPrefix.count)
                let end = line.index(before: line.endIndex)
                source = try parsePowerSourceName(String(line[start..<end]))
                continue
            }

            if !line.isEmpty {
                features.insert(line.lowercased())
            }
        }

        guard let source else {
            throw PMSetParseError.missingCapabilitiesHeader
        }

        return PMSetParsedCapabilities(
            source: source,
            supportsLowPower: features.contains("lowpowermode"),
            supportsHighPower: features.contains("highpowermode")
        )
    }

    private static func parsePowerSourceName(_ value: String) throws -> PMSetParsedPowerSource {
        guard let source = PMSetParsedPowerSource(rawValue: value) else {
            throw PMSetParseError.unknownPowerSource(value)
        }
        return source
    }
}

enum PMSetArgumentError: Error, Equatable, LocalizedError {
    case invalidMode(Int)
    case highPowerUnavailableInLegacyMode

    var errorDescription: String? {
        switch self {
        case let .invalidMode(value):
            "Invalid power mode value: \(value)."
        case .highPowerUnavailableInLegacyMode:
            "High Power is unavailable with the legacy low-power control."
        }
    }
}

enum PMSetArguments {
    static let executablePath = "/usr/bin/pmset"
    static let readLive = ["-g", "live"]
    static let readCapabilities = ["-g", "cap"]
    static let readPowerSource = ["-g", "batt"]

    static func write(
        source: PMSetParsedPowerSource,
        modeValue: Int,
        controlStyle: PMSetParsedControlStyle
    ) throws -> [String] {
        guard (0 ... 2).contains(modeValue) else {
            throw PMSetArgumentError.invalidMode(modeValue)
        }

        switch controlStyle {
        case .unifiedPowerMode:
            return [source.commandFlag, "powermode", String(modeValue)]
        case .legacyLowPowerMode:
            guard modeValue != 2 else {
                throw PMSetArgumentError.highPowerUnavailableInLegacyMode
            }
            return [source.commandFlag, "lowpowermode", String(modeValue)]
        }
    }
}
