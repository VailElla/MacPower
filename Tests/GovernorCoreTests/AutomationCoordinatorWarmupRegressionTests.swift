import Testing
@testable import GovernorCore

@Suite("Automation coordinator warm-up and lifecycle regressions")
struct AutomationCoordinatorWarmupRegressionTests {
    @Test func disabledEvaluationRefreshesActualModeWithoutWriting() async {
        let client = ScriptedPowerSystemClient(
            current: makePower(.lowPower, highPowerAvailable: false)
        )
        let coordinator = AutomationCoordinator(powerSystem: client)

        await coordinator.evaluate(activity: makeActivity(cpu: 70, idle: 3_600))

        let state = await coordinator.snapshot()
        let counts = await client.counts()
        #expect(state.status == .disabled)
        #expect(state.currentPower?.mode == .lowPower)
        #expect(state.lastConfirmedMode == .lowPower)
        #expect(counts.authorizations == 0)
        #expect(counts.reads == 1)
        #expect(counts.requests == 0)
    }

    @Test func disabledRefreshFailureStopsAndDoesNotRetry() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        await client.enqueueRead(.failure(.readFailed))
        let coordinator = AutomationCoordinator(powerSystem: client)

        await coordinator.refreshWithoutActivity()
        let failedCounts = await client.counts()
        await coordinator.refreshWithoutActivity()
        await coordinator.evaluate(activity: makeActivity(cpu: 40, idle: 0))

        let state = await coordinator.snapshot()
        let finalCounts = await client.counts()
        #expect(state.status == .errorStopped(.systemReadFailed))
        #expect(finalCounts.reads == failedCounts.reads)
        #expect(finalCounts.requests == 0)
    }

    @Test func warmupAppliesOnlyHighPowerAvailabilityRule() async {
        let client = ScriptedPowerSystemClient(
            current: makePower(.highPower, highPowerAvailable: false)
        )
        let coordinator = AutomationCoordinator(powerSystem: client)

        await coordinator.enableAutomation(activity: nil)

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        #expect(state.status == .starting)
        #expect(state.currentPower?.mode == .automatic)
        #expect(state.lastSwitchReason == .highPowerBecameUnavailable)
        #expect(requests.map(\.mode) == [.automatic])
        #expect(state.history.count == 1)
    }

    @Test func warmupRefreshDetectsManualModeChangeAndPauses() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let coordinator = AutomationCoordinator(
            powerSystem: client,
            config: AutomationConfig(
                activePowerMode: .automatic,
                pauseOnManualPowerModeChange: true
            )
        )
        await coordinator.enableAutomation(activity: nil)
        await client.setCurrent(makePower(.lowPower, time: 1_001))

        await coordinator.refreshWithoutActivity()

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        #expect(state.status == .pausedForManualChange)
        #expect(state.manualOverrideSeen)
        #expect(state.currentPower?.mode == .lowPower)
        #expect(requests.isEmpty)
    }

    @Test func completeSampleArrivingDuringAuthorizationIsRetained() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let gate = AsyncGate()
        await client.setAuthorizationGate(gate)
        let coordinator = AutomationCoordinator(powerSystem: client)

        let enableTask = Task {
            await coordinator.enableAutomation(activity: nil)
        }
        let authorizationStarted = await waitUntil {
            (await client.counts()).authorizations == 1
        }
        #expect(authorizationStarted)

        await coordinator.evaluate(activity: makeActivity(cpu: 70, idle: 0))
        await gate.open()
        await enableTask.value

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        #expect(state.status == .running)
        #expect(requests.map(\.mode) == [.highPower])
    }

    @Test func activityFailureQueuedBehindSwitchWinsAfterConfirmation() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let gate = AsyncGate()
        await client.setRequestGate(gate)
        let coordinator = AutomationCoordinator(powerSystem: client)

        let enableTask = Task {
            await coordinator.enableAutomation(activity: makeActivity(cpu: 70, idle: 0))
        }
        let requestStarted = await waitUntil { (await client.counts()).requests == 1 }
        #expect(requestStarted)
        await coordinator.stopForActivityReadFailure()

        await gate.open()
        await enableTask.value

        let state = await coordinator.snapshot()
        let counts = await client.counts()
        #expect(state.status == .errorStopped(.systemReadFailed))
        #expect(state.currentPower?.mode == .highPower)
        #expect(counts.requests == 1)
        #expect(state.history.count == 1)
    }

    @Test func activityFailureWithoutSessionStillStopsWithoutRetry() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let coordinator = AutomationCoordinator(powerSystem: client)

        await coordinator.stopForActivityReadFailure()
        await coordinator.refreshWithoutActivity()
        await coordinator.evaluate(activity: makeActivity(cpu: 40, idle: 0))

        let state = await coordinator.snapshot()
        let counts = await client.counts()
        #expect(state.status == .errorStopped(.systemReadFailed))
        #expect(counts.reads == 0)
        #expect(counts.requests == 0)
    }

    @Test func disablingAfterConfirmedErrorStoppedSwitchRestoresTakeover() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let historyStore = RecordingHistoryStore()
        await historyStore.setSaveError(TestFailure.expected)
        let coordinator = AutomationCoordinator(
            powerSystem: client,
            historyStore: historyStore
        )
        await coordinator.enableAutomation(activity: makeActivity(cpu: 40, idle: 300))

        await coordinator.disableAutomation()

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        #expect(state.status == .disabled)
        #expect(state.currentPower?.mode == .automatic)
        #expect(requests.map(\.mode) == [.lowPower, .automatic])
    }

    @Test func terminationAfterActivityFailureRestoresTakeover() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let coordinator = AutomationCoordinator(powerSystem: client)
        await coordinator.enableAutomation(activity: makeActivity(cpu: 40, idle: 300))
        await coordinator.stopForActivityReadFailure()

        await coordinator.prepareForTermination()

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        #expect(state.status == .disabled)
        #expect(state.currentPower?.mode == .automatic)
        #expect(requests.map(\.mode) == [.lowPower, .automatic])
    }

    @Test func disableWaitsForAuthorizationAndPreventsInitialRead() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let gate = AsyncGate()
        await client.setAuthorizationGate(gate)
        let coordinator = AutomationCoordinator(powerSystem: client)
        let completion = CompletionFlag()

        let enableTask = Task { await coordinator.enableAutomation(activity: nil) }
        let authorizationStarted = await waitUntil {
            (await client.counts()).authorizations == 1
        }
        #expect(authorizationStarted)
        let disableTask = Task {
            await coordinator.disableAutomation()
            await completion.markComplete()
        }
        for _ in 0..<100 { await Task.yield() }
        #expect(!(await completion.isComplete()))

        await gate.open()
        await enableTask.value
        await disableTask.value

        let state = await coordinator.snapshot()
        let counts = await client.counts()
        #expect(state.status == .disabled)
        #expect(await completion.isComplete())
        #expect(counts.reads == 0)
        #expect(counts.requests == 0)
    }

    @Test func disableWaitsForInitialReadBeforeClosingSession() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let gate = AsyncGate()
        await client.setReadGate(gate)
        let coordinator = AutomationCoordinator(powerSystem: client)
        let completion = CompletionFlag()

        let enableTask = Task { await coordinator.enableAutomation(activity: nil) }
        let readStarted = await waitUntil { (await client.counts()).reads == 1 }
        #expect(readStarted)
        let disableTask = Task {
            await coordinator.disableAutomation()
            await completion.markComplete()
        }
        for _ in 0..<100 { await Task.yield() }
        #expect(!(await completion.isComplete()))

        await gate.open()
        await enableTask.value
        await disableTask.value

        let state = await coordinator.snapshot()
        let counts = await client.counts()
        #expect(state.status == .disabled)
        #expect(await completion.isComplete())
        #expect(counts.requests == 0)
    }

    @Test func queuedResumeWithoutActivityIsNotDropped() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let coordinator = AutomationCoordinator(
            powerSystem: client,
            config: AutomationConfig(
                activePowerMode: .automatic,
                pauseOnManualPowerModeChange: true
            )
        )
        await coordinator.enableAutomation(activity: makeActivity(cpu: 40, idle: 0))
        await client.setCurrent(makePower(.lowPower, time: 1_001))
        await coordinator.evaluate(activity: makeActivity(cpu: 40, idle: 0))

        let gate = AsyncGate()
        await client.setReadGate(gate)
        let pausedPoll = Task {
            await coordinator.evaluate(activity: makeActivity(cpu: 40, idle: 0))
        }
        let readStarted = await waitUntil { (await client.counts()).reads == 3 }
        #expect(readStarted)
        await coordinator.resumeAutomation(activity: nil)

        await gate.open()
        await pausedPoll.value

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        #expect(state.status == .starting)
        #expect(state.manualOverrideSeen)
        #expect(state.currentPower?.mode == .lowPower)
        #expect(requests.isEmpty)
    }
}
