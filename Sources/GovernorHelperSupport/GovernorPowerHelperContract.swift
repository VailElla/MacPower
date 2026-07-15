import Foundation

/// Immutable names shared by the app, its bundle layout, and the privileged daemon.
///
/// Keep these values in one module so the app cannot accidentally address a different
/// Mach service than the one packaged in `Contents/Library/LaunchDaemons`.
public enum GovernorPowerHelperContract {
    public static let appBundleIdentifier = "com.ella.MacPower"
    public static let helperSigningIdentifier = "com.ella.Governor.PowerHelper"
    public static let helperExecutableName = "GovernorPowerHelper"
    public static let daemonPlistName = "com.ella.Governor.PowerHelper.plist"
    public static let machServiceName = "com.ella.Governor.PowerHelper"
    public static let helperCodeRequirementInfoKey = "GovernorHelperCodeRequirement"
    public static let clientCodeRequirementEnvironmentVariable =
        "GOVERNOR_CLIENT_CODE_REQUIREMENT"
}

/// The only power-source values the root helper recognizes.
public enum GovernorPowerHelperPowerSource: Int, Sendable, CaseIterable {
    case battery = 0
    case charger = 1
    case ups = 2

    var commandFlag: String {
        switch self {
        case .battery: "-b"
        case .charger: "-c"
        case .ups: "-u"
        }
    }
}

/// The two `pmset` syntaxes Governor supports on macOS.
public enum GovernorPowerHelperControlStyle: Int, Sendable, CaseIterable {
    case unifiedPowerMode = 0
    case legacyLowPowerMode = 1
}

/// Secure-coding XPC input. It deliberately has no command, argument, path, or
/// environment fields: the daemon constructs its fixed invocation itself.
@objc(GovernorPowerModeRequest)
public final class GovernorPowerModeRequest: NSObject, NSSecureCoding, @unchecked Sendable {
    public static let supportsSecureCoding = true

    public let sourceRawValue: Int
    public let modeRawValue: Int
    public let controlStyleRawValue: Int

    public init(sourceRawValue: Int, modeRawValue: Int, controlStyleRawValue: Int) {
        self.sourceRawValue = sourceRawValue
        self.modeRawValue = modeRawValue
        self.controlStyleRawValue = controlStyleRawValue
        super.init()
    }

    public required init?(coder: NSCoder) {
        guard coder.containsValue(forKey: "sourceRawValue"),
              coder.containsValue(forKey: "modeRawValue"),
              coder.containsValue(forKey: "controlStyleRawValue")
        else {
            return nil
        }
        sourceRawValue = coder.decodeInteger(forKey: "sourceRawValue")
        modeRawValue = coder.decodeInteger(forKey: "modeRawValue")
        controlStyleRawValue = coder.decodeInteger(forKey: "controlStyleRawValue")
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(sourceRawValue, forKey: "sourceRawValue")
        coder.encode(modeRawValue, forKey: "modeRawValue")
        coder.encode(controlStyleRawValue, forKey: "controlStyleRawValue")
    }
}

public enum GovernorPowerHelperResponseCode: Int, Sendable {
    case success = 0
    case invalidRequest = 1
    case launchFailed = 2
    case commandFailed = 3
}

/// Secure-coding reply that intentionally returns a small, non-sensitive status
/// code instead of root process output.
@objc(GovernorPowerModeResponse)
public final class GovernorPowerModeResponse: NSObject, NSSecureCoding, @unchecked Sendable {
    public static let supportsSecureCoding = true

    public let codeRawValue: Int

    public init(code: GovernorPowerHelperResponseCode) {
        codeRawValue = code.rawValue
        super.init()
    }

    public required init?(coder: NSCoder) {
        codeRawValue = coder.decodeInteger(forKey: "codeRawValue")
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(codeRawValue, forKey: "codeRawValue")
    }

    public var code: GovernorPowerHelperResponseCode {
        GovernorPowerHelperResponseCode(rawValue: codeRawValue) ?? .commandFailed
    }
}

/// The daemon exposes exactly one XPC selector. No selector accepts a path,
/// shell fragment, arbitrary `pmset` key, or process arguments.
@objc(GovernorPowerHelperProtocol)
public protocol GovernorPowerHelperProtocol {
    func applyPowerMode(
        _ request: GovernorPowerModeRequest,
        reply: @escaping (GovernorPowerModeResponse) -> Void
    )
}
