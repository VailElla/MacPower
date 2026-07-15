import Testing
@testable import GovernorCore

@Suite("Automation coordinator errors and concurrency")
struct AutomationCoordinatorErrorAndConcurrencyTests {
    @Test func authorizationFailureStopsWithoutReadingWritingOrRetrying() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        await client.setAuthorizationResult(.failure(.permissionDenied))
        let coordinator = AutomationCoordinator(powerSystem: client)

        await coordinator.enableAutomation(activity: makeActivity(cpu: 70, idle: 0))
        await coordinator.evaluate(activity: makeActivity(cpu: 70, idle: 0))

        let state = await coordinator.snapshot()
        let counts = await client.counts()
        #expect(state.status == .errorStopped(.permissionDenied))
        #expect(state.lastError == .permissionDenied)
        #expect(counts.authorizations == 1)
        #expect(counts.reads == 0)
        #expect(counts.requests == 0)
    }

    @Test func enableReadFailureStopsWithoutWriting() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        await client.enqueueRead(.failure(.readFailed))
        let coordinator = AutomationCoordinator(powerSystem: client)

        await coordinator.enableAutomation(activity: makeActivity(cpu: 70, idle: 0))

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        #expect(state.status == .errorStopped(.systemReadFailed))
        #expect(requests.isEmpty)
    }

    @Test func evaluationReadFailureStopsAndSubsequentTicksDoNotRetry() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let coordinator = AutomationCoordinator(
            powerSystem: client,
            config: AutomationConfig(activePowerMode: .automatic)
        )
        await coordinator.enableAutomation(activity: makeActivity(cpu: 40, idle: 0))
        await client.enqueueRead(.failure(.readFailed))

        await coordinator.evaluate(activity: makeActivity(cpu: 40, idle: 300))
        let countsAfterFailure = await client.counts()
        await coordinator.evaluate(activity: makeActivity(cpu: 40, idle: 300))
        let countsAfterRetryOpportunity = await client.counts()
        let state = await coordinator.snapshot()

        #expect(state.status == .errorStopped(.systemReadFailed))
        #expect(countsAfterRetryOpportunity.reads == countsAfterFailure.reads)
        #expect(countsAfterRetryOpportunity.requests == 0)
    }

    @Test func invalidIdleDurationStopsBeforeWriting() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let coordinator = AutomationCoordinator(powerSystem: client)

        await coordinator.enableAutomation(
            activity: makeActivity(cpu: 70, idle: -1)
        )

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        #expect(state.status == .errorStopped(.invalidDecisionInput))
        #expect(requests.isEmpty)
    }

    @Test func switchRequestFailureStopsWithoutHistoryOrRetry() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        await client.enqueueRequestResult(.failure(.requestFailed))
        let coordinator = AutomationCoordinator(powerSystem: client)

        await coordinator.enableAutomation(activity: makeActivity(cpu: 70, idle: 0))
        await coordinator.evaluate(activity: makeActivity(cpu: 70, idle: 0))

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        #expect(state.status == .errorStopped(.switchRequestFailed))
        #expect(requests.count == 1)
        #expect(state.history.isEmpty)
    }

    @Test func confirmationReadFailureStopsWithoutHistory() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        await client.enqueueRead(.success(makePower(.automatic)))
        await client.enqueueRead(.failure(.readFailed))
        let coordinator = AutomationCoordinator(powerSystem: client)

        await coordinator.enableAutomation(activity: makeActivity(cpu: 70, idle: 0))

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        #expect(state.status == .errorStopped(.confirmationReadFailed))
        #expect(requests.count == 1)
        #expect(state.history.isEmpty)
    }

    @Test func confirmationMismatchStopsAndUsesReadbackAsActualTruth() async {
        let initial = makePower(.automatic)
        let client = ScriptedPowerSystemClient(current: initial)
        await client.setAutomaticallyAppliesRequests(false)
        let coordinator = AutomationCoordinator(powerSystem: client)

        await coordinator.enableAutomation(activity: makeActivity(cpu: 70, idle: 0))

        let state = await coordinator.snapshot()
        #expect(
            state.status ==
                .errorStopped(.confirmationMismatch(expected: .highPower, actual: .automatic))
        )
        #expect(state.currentPower?.mode == .automatic)
        #expect(state.lastConfirmedMode == .automatic)
        #expect(state.history.isEmpty)
    }

    @Test func historySaveFailureStopsOnlyAfterConfirmedSwitch() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let historyStore = RecordingHistoryStore()
        await historyStore.setSaveError(TestFailure.expected)
        let coordinator = AutomationCoordinator(
            powerSystem: client,
            historyStore: historyStore
        )

        await coordinator.enableAutomation(activity: makeActivity(cpu: 40, idle: 300))

        let state = await coordinator.snapshot()
        #expect(state.status == .errorStopped(.historyWriteFailed))
        #expect(state.currentPower?.mode == .lowPower)
        #expect(state.history.count == 1)
    }

    @Test func restorationRequestFailureDoesNotRetry() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        await client.enqueueRequestResult(.success(()))
        await client.enqueueRequestResult(.failure(.requestFailed))
        let coordinator = AutomationCoordinator(powerSystem: client)
        await coordinator.enableAutomation(activity: makeActivity(cpu: 40, idle: 300))

        await coordinator.disableAutomation()
        await coordinator.evaluate(activity: makeActivity(cpu: 40, idle: 300))

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        #expect(state.status == .errorStopped(.switchRequestFailed))
        #expect(state.lastError == .switchRequestFailed)
        #expect(requests.map(\.mode) == [.lowPower, .automatic])
    }

    @Test func restorationConfirmationMismatchStopsAndDoesNotLogRestore() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let coordinator = AutomationCoordinator(powerSystem: client)
        await coordinator.enableAutomation(activity: makeActivity(cpu: 40, idle: 300))
        await client.setAutomaticallyAppliesRequests(false)

        await coordinator.disableAutomation()

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        #expect(
            state.status ==
                .errorStopped(.confirmationMismatch(expected: .automatic, actual: .lowPower))
        )
        #expect(state.history.count == 1)
        #expect(requests.map(\.mode) == [.lowPower, .automatic])
    }

    @Test func concurrentEvaluationsAreCoalescedAndNeverOverlapWrites() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let gate = AsyncGate()
        await client.setRequestGate(gate)
        let coordinator = AutomationCoordinator(powerSystem: client)

        let enableTask = Task {
            await coordinator.enableAutomation(activity: makeActivity(cpu: 70, idle: 0))
        }
        let requestStarted = await waitUntil {
            (await client.counts()).requests == 1
        }
        #expect(requestStarted)

        await coordinator.evaluate(activity: makeActivity(cpu: 40, idle: 300))
        await coordinator.evaluate(activity: makeActivity(cpu: 70, idle: 0))

        let inFlightState = await coordinator.snapshot()
        let blockedCounts = await client.counts()
        #expect(inFlightState.switchInFlight)
        #expect(blockedCounts.requests == 1)
        #expect(blockedCounts.maximumActive == 1)

        await gate.open()
        await enableTask.value

        let finalCounts = await client.counts()
        let finalState = await coordinator.snapshot()
        #expect(finalCounts.requests == 1)
        #expect(finalCounts.maximumActive == 1)
        #expect(finalState.status == .running)
    }

    @Test func changedPendingDecisionRunsOnlyAfterFirstConfirmation() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let gate = AsyncGate()
        await client.setRequestGate(gate)
        let coordinator = AutomationCoordinator(
            powerSystem: client,
            config: AutomationConfig(activePowerMode: .highPower, idlePowerMode: .lowPower)
        )

        let enableTask = Task {
            await coordinator.enableAutomation(activity: makeActivity(cpu: 70, idle: 0))
        }
        let requestStarted = await waitUntil { (await client.counts()).requests == 1 }
        #expect(requestStarted)
        await coordinator.evaluate(activity: makeActivity(cpu: 40, idle: 300))

        await gate.open()
        await enableTask.value

        let requests = await client.recordedRequests()
        let counts = await client.counts()
        #expect(requests.map(\.mode) == [.highPower, .lowPower])
        #expect(counts.maximumActive == 1)
    }

    @Test func disableWaitsForInFlightConfirmationThenRestoresWithoutOverlap() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let gate = AsyncGate()
        await client.setRequestGate(gate)
        let coordinator = AutomationCoordinator(powerSystem: client)

        let enableTask = Task {
            await coordinator.enableAutomation(activity: makeActivity(cpu: 40, idle: 300))
        }
        let requestStarted = await waitUntil { (await client.counts()).requests == 1 }
        #expect(requestStarted)

        let completion = CompletionFlag()
        let disableTask = Task {
            await coordinator.disableAutomation()
            await completion.markComplete()
        }
        for _ in 0..<100 { await Task.yield() }
        let completedWhileBlocked = await completion.isComplete()
        #expect(!completedWhileBlocked)

        await gate.open()
        await enableTask.value
        await disableTask.value

        let requests = await client.recordedRequests()
        let counts = await client.counts()
        let completed = await completion.isComplete()
        let state = await coordinator.snapshot()
        #expect(requests.map(\.mode) == [.lowPower, .automatic])
        #expect(counts.maximumActive == 1)
        #expect(completed)
        #expect(state.status == .disabled)
    }
}
