import Foundation
import GovernorCore
import GovernorHelperSupport

/// Reads and writes the real macOS power mode through `/usr/bin/pmset`.
///
/// Every request is based on a fresh system snapshot. Writes are sent only for
/// the currently active source, never through a shell, and are confirmed by a
/// second `pmset -g live` read before this method reports success.
public actor PMSetPowerSystemClient: PowerSystemClient {
    private let commandRunner: PMSetCommandRunner
    private let helperClient: PMSetHelperClient
    private var switchInFlight = false

    public init() {
        commandRunner = PMSetCommandRunner()
        helperClient = PMSetHelperClient()
    }

    /// Registers the bundled daemon only when it has never been registered.
    ///
    /// Call this only in direct response to enabling automation. Once approved,
    /// Service Management retains the daemon across app restarts and lock/unlock
    /// events; timer evaluations and later enables never request a new password.
    public func authorize() async throws {
        do {
            try await GovernorPowerHelperInstaller.system.ensureAvailable()
        } catch {
            throw PowerSystemClientFailure.permissionDenied
        }
    }

    public func readSnapshot() async throws -> PowerSnapshot {
        do {
            return try await readSnapshotUnmapped()
        } catch {
            throw PowerSystemClientFailure.readFailed
        }
    }

    public func requestMode(
        _ mode: PowerMode,
        source: PowerSource,
        controlStyle: PowerControlStyle
    ) async throws {
        // Actor methods are reentrant at suspension points, so the explicit flag
        // is required in addition to actor isolation.
        guard !switchInFlight else {
            throw PowerSystemClientFailure.requestFailed
        }
        switchInFlight = true
        defer { switchInFlight = false }

        do {
            let before = try await readSnapshotUnmapped()

            // The source or supported syntax may have changed since the
            // coordinator's preceding read. Do not write stale `-b/-c/-u` data.
            guard before.source == source, before.controlStyle == controlStyle else {
                throw PowerSystemClientFailure.requestFailed
            }

            // Enforce the no-op rule at the final system boundary as well.
            guard before.mode != mode else { return }

            // A live capability read is the only authority for High Power. No
            // High Power request is constructed when it is unavailable.
            if mode == .highPower, !before.highPowerAvailable {
                throw PowerSystemClientFailure.requestFailed
            }

            let request = GovernorPowerModeRequest(
                sourceRawValue: source.helperRawValue,
                modeRawValue: mode.powermodeValue,
                controlStyleRawValue: controlStyle.helperRawValue
            )
            // Validate the same closed allow-list locally before the daemon
            // repeats that validation at its root boundary.
            _ = try PrivilegedPMSetCommand.arguments(for: request)
            try await helperClient.apply(request)

            let confirmed = try await readSnapshotUnmapped()
            guard confirmed.mode == mode else {
                throw PowerSystemClientFailure.requestFailed
            }
        } catch let failure as PowerSystemClientFailure {
            throw failure
        } catch let error as PMSetHelperClientError {
            switch error {
            case .connectionFailed:
                throw PowerSystemClientFailure.permissionDenied
            default:
                throw PowerSystemClientFailure.requestFailed
            }
        } catch {
            throw PowerSystemClientFailure.requestFailed
        }
    }

    private func readSnapshotUnmapped() async throws -> PowerSnapshot {
        // These reads are intentionally sequential. The capability header is
        // checked against the separately reported live source, rejecting a
        // snapshot if the machine changed power sources during observation.
        let sourceOutput = try await commandRunner.run(arguments: PMSetArguments.readPowerSource)
        let liveOutput = try await commandRunner.run(arguments: PMSetArguments.readLive)
        let capabilitiesOutput = try await commandRunner.run(
            arguments: PMSetArguments.readCapabilities
        )

        let source = try PMSetOutputParser.parseCurrentPowerSource(sourceOutput)
        let live = try PMSetOutputParser.parseLiveState(liveOutput)
        let capabilities = try PMSetOutputParser.parseCapabilities(capabilitiesOutput)

        guard source == capabilities.source,
              let mode = PowerMode(rawValue: live.modeValue)
        else {
            throw PowerSystemClientFailure.readFailed
        }

        let controlStyle = live.controlStyle.coreValue
        return PowerSnapshot(
            mode: mode,
            source: source.coreValue,
            controlStyle: controlStyle,
            highPowerAvailable: controlStyle == .unifiedPowermode
                && capabilities.supportsHighPower,
            observedAt: Date()
        )
    }
}

private extension PowerSource {
    var helperRawValue: Int {
        switch self {
        case .charger: GovernorPowerHelperPowerSource.charger.rawValue
        case .battery: GovernorPowerHelperPowerSource.battery.rawValue
        case .ups: GovernorPowerHelperPowerSource.ups.rawValue
        }
    }
}

private extension PMSetParsedPowerSource {
    var coreValue: PowerSource {
        switch self {
        case .ac: .charger
        case .battery: .battery
        case .ups: .ups
        }
    }
}

private extension PowerControlStyle {
    var helperRawValue: Int {
        switch self {
        case .unifiedPowermode: GovernorPowerHelperControlStyle.unifiedPowerMode.rawValue
        case .lowPowerOnly: GovernorPowerHelperControlStyle.legacyLowPowerMode.rawValue
        }
    }
}

private extension PMSetParsedControlStyle {
    var coreValue: PowerControlStyle {
        switch self {
        case .unifiedPowerMode: .unifiedPowermode
        case .legacyLowPowerMode: .lowPowerOnly
        }
    }
}
