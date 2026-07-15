import Foundation
import GovernorCore

/// Reads and writes the real macOS power mode through `/usr/bin/pmset`.
///
/// Every request is based on a fresh system snapshot. Writes are sent only for
/// the currently active source, never through a shell, and are confirmed by a
/// second `pmset -g live` read before this method reports success.
public actor PMSetPowerSystemClient: PowerSystemClient {
    private let commandRunner: PMSetCommandRunner
    private let authorizationExecutor: SessionAuthorizationExecutor
    private var switchInFlight = false

    public init() {
        commandRunner = PMSetCommandRunner()
        authorizationExecutor = SessionAuthorizationExecutor()
    }

    /// Requests administrator approval once for this client session.
    ///
    /// Call this only in direct response to the user enabling automation. A
    /// denial is remembered for this process lifetime, so later evaluations do
    /// not repeatedly present an authorization dialog.
    public func authorize() async throws {
        do {
            try await authorizationExecutor.authorizeOnce()
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

            let arguments = try PMSetArguments.write(
                source: source.parsedValue,
                modeValue: mode.powermodeValue,
                controlStyle: controlStyle.parsedValue
            )
            _ = try await authorizationExecutor.execute(arguments: arguments)

            let confirmed = try await readSnapshotUnmapped()
            guard confirmed.mode == mode else {
                throw PowerSystemClientFailure.requestFailed
            }
        } catch let failure as PowerSystemClientFailure {
            throw failure
        } catch let error as PMSetExecutionError {
            switch error {
            case .authorizationNotRequested, .authorizationFailed:
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
    var parsedValue: PMSetParsedPowerSource {
        switch self {
        case .charger: .ac
        case .battery: .battery
        case .ups: .ups
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
    var parsedValue: PMSetParsedControlStyle {
        switch self {
        case .unifiedPowermode: .unifiedPowerMode
        case .lowPowerOnly: .legacyLowPowerMode
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
