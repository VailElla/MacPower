@preconcurrency import Foundation
import GovernorHelperSupport

enum PMSetHelperClientError: Error, Equatable, Sendable {
    case missingHelperCodeRequirement
    case connectionFailed
    case requestRejected(GovernorPowerHelperResponseCode)
}

/// Sends one already-validated power-mode request to the privileged daemon.
///
/// A fresh connection keeps a failed or revoked daemon from becoming a retained
/// authority. Both sides enforce code-signing requirements before accepting a
/// message, and the daemon still validates the closed request enum again.
struct PMSetHelperClient: Sendable {
    func apply(_ request: GovernorPowerModeRequest) async throws {
        guard let helperRequirement = Bundle.main.object(
            forInfoDictionaryKey: GovernorPowerHelperContract.helperCodeRequirementInfoKey
        ) as? String, !helperRequirement.isEmpty else {
            throw PMSetHelperClientError.missingHelperCodeRequirement
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let connection = NSXPCConnection(
                machServiceName: GovernorPowerHelperContract.machServiceName,
                options: .privileged
            )
            let pending = PendingXPCRequest(connection: connection, continuation: continuation)
            connection.remoteObjectInterface = GovernorPowerHelperXPCInterface.make()
            connection.setCodeSigningRequirement(helperRequirement)
            connection.interruptionHandler = { [pending] in
                pending.finish(.failure(PMSetHelperClientError.connectionFailed))
            }
            connection.invalidationHandler = { [pending] in
                pending.finish(.failure(PMSetHelperClientError.connectionFailed))
            }
            connection.activate()

            let proxy = connection.remoteObjectProxyWithErrorHandler { [pending] _ in
                pending.finish(.failure(PMSetHelperClientError.connectionFailed))
            }
            guard let helper = proxy as? GovernorPowerHelperProtocol else {
                pending.finish(.failure(PMSetHelperClientError.connectionFailed))
                return
            }
            helper.applyPowerMode(request) { [pending] response in
                if response.code == .success {
                    pending.finish(.success(()))
                } else {
                    pending.finish(.failure(PMSetHelperClientError.requestRejected(response.code)))
                }
            }
        }
    }
}

private final class PendingXPCRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private let connection: NSXPCConnection

    init(connection: NSXPCConnection, continuation: CheckedContinuation<Void, Error>) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        guard let continuation else { return }
        connection.invalidate()
        continuation.resume(with: result)
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
