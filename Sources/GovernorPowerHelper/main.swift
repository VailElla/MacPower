import Darwin
import Foundation
import GovernorHelperSupport

private final class GovernorPowerHelperService: NSObject, GovernorPowerHelperProtocol {
    func applyPowerMode(
        _ request: GovernorPowerModeRequest,
        reply: @escaping (GovernorPowerModeResponse) -> Void
    ) {
        do {
            let arguments = try PrivilegedPMSetCommand.arguments(for: request)
            try runFixedPMSet(arguments: arguments)
            reply(GovernorPowerModeResponse(code: .success))
        } catch is PrivilegedPMSetCommandError {
            reply(GovernorPowerModeResponse(code: .invalidRequest))
        } catch PMSetRootExecutionError.launchFailed {
            reply(GovernorPowerModeResponse(code: .launchFailed))
        } catch {
            reply(GovernorPowerModeResponse(code: .commandFailed))
        }
    }

    private func runFixedPMSet(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: PrivilegedPMSetCommand.executablePath)
        process.arguments = arguments
        process.environment = [:]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw PMSetRootExecutionError.launchFailed
        }

        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw PMSetRootExecutionError.commandFailed
        }
    }
}

private enum PMSetRootExecutionError: Error {
    case launchFailed
    case commandFailed
}

private final class GovernorPowerHelperListener: NSObject, NSXPCListenerDelegate {
    private let service = GovernorPowerHelperService()

    func listener(
        _: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = GovernorPowerHelperXPCInterface.make()
        connection.exportedObject = service
        connection.activate()
        return true
    }
}

private enum GovernorPowerHelperXPCInterface {
    static func make() -> NSXPCInterface {
        let interface = NSXPCInterface(with: GovernorPowerHelperProtocol.self)
        let selector = #selector(GovernorPowerHelperProtocol.applyPowerMode(_:reply:))
        interface.setClasses(
            NSSet(object: GovernorPowerModeRequest.self) as! Set<AnyHashable>,
            for: selector,
            argumentIndex: 0,
            ofReply: false
        )
        interface.setClasses(
            NSSet(object: GovernorPowerModeResponse.self) as! Set<AnyHashable>,
            for: selector,
            argumentIndex: 0,
            ofReply: true
        )
        return interface
    }
}

@main
private enum GovernorPowerHelperMain {
    static func main() {
        guard let clientRequirement = ProcessInfo.processInfo.environment[
            GovernorPowerHelperContract.clientCodeRequirementEnvironmentVariable
        ], !clientRequirement.isEmpty else {
            // Do not expose a root Mach service without its sealed client identity gate.
            exit(EXIT_FAILURE)
        }

        let listener = NSXPCListener(
            machServiceName: GovernorPowerHelperContract.machServiceName
        )
        // macOS performs this check before the delegate receives a connection.
        listener.setConnectionCodeSigningRequirement(clientRequirement)
        let delegate = GovernorPowerHelperListener()
        listener.delegate = delegate
        listener.activate()
        RunLoop.current.run()
    }
}
