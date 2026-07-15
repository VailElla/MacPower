import Foundation
@testable import GovernorCore

enum TestFailure: Error, Equatable, Sendable {
    case expected
}

actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

actor CompletionFlag {
    private var value = false

    func markComplete() {
        value = true
    }

    func isComplete() -> Bool {
        value
    }
}

actor ScriptedPowerSystemClient: PowerSystemClient {
    struct Request: Equatable, Sendable {
        let mode: PowerMode
        let source: PowerSource
        let controlStyle: PowerControlStyle
    }

    private var current: PowerSnapshot
    private var queuedReads: [Result<PowerSnapshot, PowerSystemClientFailure>] = []
    private var queuedRequestResults: [Result<Void, PowerSystemClientFailure>] = []
    private var authorizationResult: Result<Void, PowerSystemClientFailure> = .success(())
    private var authorizationGate: AsyncGate?
    private var readGate: AsyncGate?
    private var requestGate: AsyncGate?
    private var automaticallyAppliesRequests = true

    private(set) var authorizationCount = 0
    private(set) var readCount = 0
    private(set) var requests: [Request] = []
    private(set) var activeRequestCount = 0
    private(set) var maximumActiveRequestCount = 0

    init(current: PowerSnapshot) {
        self.current = current
    }

    func authorize() async throws {
        authorizationCount += 1
        if let authorizationGate {
            await authorizationGate.wait()
        }
        try authorizationResult.get()
    }

    func readSnapshot() async throws -> PowerSnapshot {
        readCount += 1
        if let readGate {
            await readGate.wait()
        }
        if !queuedReads.isEmpty {
            let result = queuedReads.removeFirst()
            let snapshot = try result.get()
            current = snapshot
            return snapshot
        }
        return current
    }

    func requestMode(
        _ mode: PowerMode,
        source: PowerSource,
        controlStyle: PowerControlStyle
    ) async throws {
        requests.append(Request(mode: mode, source: source, controlStyle: controlStyle))
        activeRequestCount += 1
        maximumActiveRequestCount = max(maximumActiveRequestCount, activeRequestCount)

        if let requestGate {
            await requestGate.wait()
        }

        let result: Result<Void, PowerSystemClientFailure>
        if queuedRequestResults.isEmpty {
            result = .success(())
        } else {
            result = queuedRequestResults.removeFirst()
        }

        activeRequestCount -= 1
        try result.get()

        if automaticallyAppliesRequests {
            current = PowerSnapshot(
                mode: mode,
                source: source,
                controlStyle: controlStyle,
                highPowerAvailable: current.highPowerAvailable,
                observedAt: current.observedAt.addingTimeInterval(1)
            )
        }
    }

    func enqueueRead(_ result: Result<PowerSnapshot, PowerSystemClientFailure>) {
        queuedReads.append(result)
    }

    func enqueueRequestResult(_ result: Result<Void, PowerSystemClientFailure>) {
        queuedRequestResults.append(result)
    }

    func setAuthorizationResult(_ result: Result<Void, PowerSystemClientFailure>) {
        authorizationResult = result
    }

    func setAuthorizationGate(_ gate: AsyncGate?) {
        authorizationGate = gate
    }

    func setReadGate(_ gate: AsyncGate?) {
        readGate = gate
    }

    func setRequestGate(_ gate: AsyncGate?) {
        requestGate = gate
    }

    func setAutomaticallyAppliesRequests(_ value: Bool) {
        automaticallyAppliesRequests = value
    }

    func setCurrent(_ snapshot: PowerSnapshot) {
        current = snapshot
    }

    func recordedRequests() -> [Request] {
        requests
    }

    func counts() -> (authorizations: Int, reads: Int, requests: Int, maximumActive: Int) {
        (authorizationCount, readCount, requests.count, maximumActiveRequestCount)
    }
}

actor RecordingDisplayBrightnessClient: DisplayBrightnessClient {
    struct RestoreRequest: Equatable, Sendable {
        let snapshot: DisplayBrightnessSnapshot
        let delayMilliseconds: Int
    }

    private let captureResult: DisplayBrightnessSnapshot?
    private(set) var captureCount = 0
    private(set) var restoreRequests: [RestoreRequest] = []

    init(captureResult: DisplayBrightnessSnapshot?) {
        self.captureResult = captureResult
    }

    func captureCurrentBrightness() -> DisplayBrightnessSnapshot? {
        captureCount += 1
        return captureResult
    }

    func restoreBrightness(
        _ snapshot: DisplayBrightnessSnapshot,
        after delayMilliseconds: Int
    ) {
        restoreRequests.append(
            RestoreRequest(
                snapshot: snapshot,
                delayMilliseconds: delayMilliseconds
            )
        )
    }

    func recordedRestores() -> [RestoreRequest] {
        restoreRequests
    }
}

actor RecordingHistoryStore: SwitchHistoryStore {
    private var loadedHistory: [SwitchHistoryEntry]
    private var loadError: (any Error & Sendable)?
    private var saveError: (any Error & Sendable)?
    private(set) var savedHistories: [[SwitchHistoryEntry]] = []

    init(history: [SwitchHistoryEntry] = []) {
        loadedHistory = history
    }

    func loadHistory() async throws -> [SwitchHistoryEntry] {
        if let loadError { throw loadError }
        return loadedHistory
    }

    func saveHistory(_ history: [SwitchHistoryEntry]) async throws {
        savedHistories.append(history)
        if let saveError { throw saveError }
        loadedHistory = history
    }

    func setLoadError(_ error: (any Error & Sendable)?) {
        loadError = error
    }

    func setSaveError(_ error: (any Error & Sendable)?) {
        saveError = error
    }

    func saves() -> [[SwitchHistoryEntry]] {
        savedHistories
    }
}

func makePower(
    _ mode: PowerMode,
    source: PowerSource = .charger,
    controlStyle: PowerControlStyle = .unifiedPowermode,
    highPowerAvailable: Bool = true,
    time: TimeInterval = 1_000
) -> PowerSnapshot {
    PowerSnapshot(
        mode: mode,
        source: source,
        controlStyle: controlStyle,
        highPowerAvailable: highPowerAvailable,
        observedAt: Date(timeIntervalSince1970: time)
    )
}

func makeActivity(
    cpu _: Double,
    idle: TimeInterval,
    window _: TimeInterval = 15
) -> ActivitySnapshot {
    ActivitySnapshot(
        userIdleDuration: idle,
        observedAt: Date(timeIntervalSince1970: 2_000)
    )
}

func waitUntil(
    iterations: Int = 10_000,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<iterations {
        if await condition() { return true }
        await Task.yield()
    }
    return false
}
