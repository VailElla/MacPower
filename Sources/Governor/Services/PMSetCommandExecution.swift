import Darwin
import Foundation
import Security

struct PMSetCommandRunner: Sendable {
    func run(arguments: [String]) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let outputPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: PMSetArguments.executablePath)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            do {
                try process.run()
            } catch {
                throw PMSetExecutionError.launchFailed(error.localizedDescription)
            }

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)

            guard process.terminationReason == .exit, process.terminationStatus == 0 else {
                throw PMSetExecutionError.commandFailed(
                    status: process.terminationStatus,
                    output: output.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            return output
        }.value
    }
}

enum PMSetExecutionError: Error, Equatable, LocalizedError, Sendable {
    case launchFailed(String)
    case commandFailed(status: Int32, output: String)
    case authorizationNotRequested
    case authorizationFailed(OSStatus)
    case deprecatedExecutorUnavailable
    case privilegedLaunchFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .launchFailed(message):
            "Unable to launch pmset: \(message)"
        case let .commandFailed(status, output):
            output.isEmpty
                ? "pmset exited with status \(status)."
                : "pmset exited with status \(status): \(output)"
        case .authorizationNotRequested:
            "Administrator authorization has not been granted for this session."
        case let .authorizationFailed(status):
            "Administrator authorization failed (OSStatus \(status))."
        case .deprecatedExecutorUnavailable:
            "The local privileged execution API is unavailable on this macOS version."
        case let .privilegedLaunchFailed(status):
            "Unable to launch privileged pmset (OSStatus \(status))."
        }
    }
}

/// Session-scoped local-v1 privilege bridge.
///
/// IMPORTANT: `AuthorizationExecuteWithPrivileges` has been deprecated since
/// macOS 10.7 and is unavailable to Swift source at compile time. This local
/// first version uses it as a session-scoped bridge, so the code resolves
/// that exact Security.framework symbol dynamically. It must be replaced by a
/// signed and notarized `SMAppService` LaunchDaemon before distribution.
///
/// The authorization interaction happens only in `authorizeOnce()`. A denial or
/// failure is retained for the life of this object, and privileged execution uses
/// no interaction flags, so failed writes cannot cause repeated password prompts.
actor SessionAuthorizationExecutor {
    // AuthorizationRef is an opaque Security.framework handle. Access remains
    // actor-isolated; unchecked conformance only permits final cleanup from the
    // actor's nonisolated deinitializer under Swift 6.
    private enum State: @unchecked Sendable {
        case notAttempted
        case authorized(AuthorizationRef)
        case failed(PMSetExecutionError)
    }

    private var state: State = .notAttempted

    deinit {
        if case let .authorized(reference) = state {
            AuthorizationFree(reference, [.destroyRights])
        }
    }

    func authorizeOnce() throws {
        switch state {
        case .authorized:
            return
        case let .failed(error):
            throw error
        case .notAttempted:
            break
        }

        var reference: AuthorizationRef?
        let createStatus = AuthorizationCreate(nil, nil, [], &reference)
        guard createStatus == errAuthorizationSuccess, let reference else {
            let error = PMSetExecutionError.authorizationFailed(createStatus)
            state = .failed(error)
            throw error
        }

        let copyStatus: OSStatus = kAuthorizationRightExecute.withCString { rightName in
            var item = AuthorizationItem(
                name: rightName,
                valueLength: 0,
                value: nil,
                flags: 0
            )
            return withUnsafeMutablePointer(to: &item) { items in
                var rights = AuthorizationRights(count: 1, items: items)
                return AuthorizationCopyRights(
                    reference,
                    &rights,
                    nil,
                    [.interactionAllowed, .extendRights, .preAuthorize],
                    nil
                )
            }
        }

        guard copyStatus == errAuthorizationSuccess else {
            AuthorizationFree(reference, [.destroyRights])
            let error = PMSetExecutionError.authorizationFailed(copyStatus)
            state = .failed(error)
            throw error
        }

        state = .authorized(reference)
    }

    func execute(arguments: [String]) throws -> String {
        let reference: AuthorizationRef
        switch state {
        case let .authorized(value):
            reference = value
        case let .failed(error):
            throw error
        case .notAttempted:
            throw PMSetExecutionError.authorizationNotRequested
        }

        guard let function = Self.authorizationExecuteFunction else {
            throw PMSetExecutionError.deprecatedExecutorUnavailable
        }

        let cArguments = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
            .allocate(capacity: arguments.count + 1)
        defer { cArguments.deallocate() }

        for (index, argument) in arguments.enumerated() {
            cArguments[index] = strdup(argument)
        }
        cArguments[arguments.count] = nil
        defer {
            for index in arguments.indices {
                free(cArguments[index])
            }
        }

        // The imported legacy signature incorrectly treats argv entries as
        // non-optional. The backing allocation above is explicitly NULL-terminated.
        let importedArguments = UnsafeRawPointer(cArguments)
            .assumingMemoryBound(to: UnsafeMutablePointer<CChar>.self)
        var communicationsPipe: UnsafeMutablePointer<FILE>?

        let status = PMSetArguments.executablePath.withCString { executablePath in
            function(reference, executablePath, 0, importedArguments, &communicationsPipe)
        }
        guard status == errAuthorizationSuccess else {
            throw PMSetExecutionError.privilegedLaunchFailed(status)
        }

        guard let communicationsPipe else {
            return ""
        }
        let handle = FileHandle(
            fileDescriptor: fileno(communicationsPipe),
            closeOnDealloc: false
        )
        let data = handle.readDataToEndOfFile()
        fclose(communicationsPipe)
        return String(decoding: data, as: UTF8.self)
    }

    private typealias AuthorizationExecuteFunction = @convention(c) (
        AuthorizationRef,
        UnsafePointer<CChar>,
        UInt32,
        UnsafePointer<UnsafeMutablePointer<CChar>>,
        UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
    ) -> OSStatus

    private static let authorizationExecuteFunction: AuthorizationExecuteFunction? = {
        guard let handle = dlopen(
            "/System/Library/Frameworks/Security.framework/Security",
            RTLD_LAZY | RTLD_LOCAL
        ) else {
            return nil
        }
        guard let symbol = dlsym(handle, "AuthorizationExecuteWithPrivileges") else {
            return nil
        }
        return unsafeBitCast(symbol, to: AuthorizationExecuteFunction.self)
    }()
}
