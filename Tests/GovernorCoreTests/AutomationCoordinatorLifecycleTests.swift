import Foundation
import Testing
@testable import GovernorCore

@Suite("Automation coordinator lifecycle")
struct AutomationCoordinatorLifecycleTests {
    @Test func enableCapturesTakeoverBeforeFirstConfirmedAutomaticSwitch() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let historyStore = RecordingHistoryStore()
        let coordinator = AutomationCoordinator(
            powerSystem: client,
            historyStore: historyStore,
            config: AutomationConfig(activePowerMode: .automatic)
        )

        await coordinator.enableAutomation(activity: makeActivity(cpu: 40, idle: 300))

        let state = await coordinator.snapshot()
        let authorizationCount = await client.authorizationCount
        #expect(state.status == .running)
        #expect(state.takeoverMode == .automatic)
        #expect(state.lastConfirmedMode == .lowPower)
        #expect(state.currentPower?.mode == .lowPower)
        #expect(state.history.count == 1)
        #expect(state.history.first?.oldMode == .automatic)
        #expect(state.history.first?.newMode == .lowPower)
        #expect(authorizationCount == 1)
    }

    @Test func warmupDoesNotSubstituteInstantaneousCPUValue() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let coordinator = AutomationCoordinator(powerSystem: client)

        await coordinator.enableAutomation(activity: nil)

        var state = await coordinator.snapshot()
        let warmupRequests = await client.recordedRequests()
        #expect(state.status == .starting)
        #expect(warmupRequests.isEmpty)

        await coordinator.evaluate(activity: makeActivity(cpu: 40, idle: 300))
        state = await coordinator.snapshot()
        #expect(state.status == .running)
        #expect(state.currentPower?.mode == .lowPower)
    }

    @Test func exitingLowPowerRestoresBrightnessCapturedBeforeEntry() async {
        let client = ScriptedPowerSystemClient(current: makePower(.highPower))
        let brightnessSnapshot = DisplayBrightnessSnapshot(
            levelsByDisplayID: [1: 0.62]
        )
        let displayBrightness = RecordingDisplayBrightnessClient(
            captureResult: brightnessSnapshot
        )
        let coordinator = AutomationCoordinator(
            powerSystem: client,
            displayBrightness: displayBrightness,
            config: AutomationConfig(
                activePowerMode: .highPower,
                idlePowerMode: .lowPower
            )
        )

        await coordinator.enableAutomation(activity: makeActivity(cpu: 40, idle: 300))

        var state = await coordinator.snapshot()
        var restored = await displayBrightness.recordedRestores()
        #expect(state.currentPower?.mode == .lowPower)
        #expect(await displayBrightness.captureCount == 1)
        #expect(restored.isEmpty)

        await coordinator.evaluate(activity: makeActivity(cpu: 70, idle: 0))

        state = await coordinator.snapshot()
        restored = await displayBrightness.recordedRestores()
        let requests = await client.recordedRequests()
        #expect(state.status == .running)
        #expect(state.currentPower?.mode == .highPower)
        #expect(requests.map(\.mode) == [.lowPower, .highPower])
        #expect(
            restored == [
                .init(
                    snapshot: brightnessSnapshot,
                    delayMilliseconds: 0
                ),
            ]
        )
    }

    @Test func configuredBrightnessRestoreDelayIsPassedToDisplayService() async {
        let client = ScriptedPowerSystemClient(current: makePower(.highPower))
        let brightnessSnapshot = DisplayBrightnessSnapshot(
            levelsByDisplayID: [1: 0.5]
        )
        let displayBrightness = RecordingDisplayBrightnessClient(
            captureResult: brightnessSnapshot
        )
        let coordinator = AutomationCoordinator(
            powerSystem: client,
            displayBrightness: displayBrightness,
            config: AutomationConfig(
                activePowerMode: .highPower,
                idlePowerMode: .lowPower,
                brightnessRestoreDelayMilliseconds: 0
            )
        )

        await coordinator.enableAutomation(activity: makeActivity(cpu: 40, idle: 300))
        await coordinator.evaluate(activity: makeActivity(cpu: 70, idle: 0))

        let restored = await displayBrightness.recordedRestores()
        #expect(restored.first?.delayMilliseconds == 0)
    }

    @Test func disabledBrightnessRestoreDoesNotCaptureOrWriteBrightness() async {
        let client = ScriptedPowerSystemClient(current: makePower(.highPower))
        let displayBrightness = RecordingDisplayBrightnessClient(
            captureResult: DisplayBrightnessSnapshot(levelsByDisplayID: [1: 0.5])
        )
        let coordinator = AutomationCoordinator(
            powerSystem: client,
            displayBrightness: displayBrightness,
            config: AutomationConfig(
                activePowerMode: .highPower,
                idlePowerMode: .lowPower,
                restoreBrightnessAfterLowPower: false
            )
        )

        await coordinator.enableAutomation(activity: makeActivity(cpu: 40, idle: 300))
        await coordinator.evaluate(activity: makeActivity(cpu: 70, idle: 0))

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        let restored = await displayBrightness.recordedRestores()
        #expect(state.currentPower?.mode == .highPower)
        #expect(requests.map(\.mode) == [.lowPower, .highPower])
        #expect(await displayBrightness.captureCount == 0)
        #expect(restored.isEmpty)
    }

    @Test func unavailableBrightnessAccessDoesNotBlockPowerModeSwitches() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let displayBrightness = RecordingDisplayBrightnessClient(captureResult: nil)
        let coordinator = AutomationCoordinator(
            powerSystem: client,
            displayBrightness: displayBrightness,
            config: AutomationConfig(
                activePowerMode: .highPower,
                idlePowerMode: .lowPower
            )
        )

        await coordinator.enableAutomation(activity: makeActivity(cpu: 40, idle: 300))
        await coordinator.evaluate(activity: makeActivity(cpu: 70, idle: 0))

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        let restored = await displayBrightness.recordedRestores()
        #expect(state.status == .running)
        #expect(state.currentPower?.mode == .highPower)
        #expect(requests.map(\.mode) == [.lowPower, .highPower])
        #expect(await displayBrightness.captureCount == 1)
        #expect(restored.isEmpty)
    }

    @Test func targetEqualToActualSendsNoRequestAndCreatesNoHistory() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let coordinator = AutomationCoordinator(
            powerSystem: client,
            config: AutomationConfig(activePowerMode: .automatic)
        )

        await coordinator.enableAutomation(activity: makeActivity(cpu: 40, idle: 0))

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        #expect(state.status == .running)
        #expect(requests.isEmpty)
        #expect(state.history.isEmpty)
        #expect(state.lastSwitchReason == nil)
    }

    @Test func highPowerUnavailableNeverSendsHighPowerAndUsesCurrentSourceAndStyle() async {
        let initial = makePower(
            .lowPower,
            source: .battery,
            controlStyle: .lowPowerOnly,
            highPowerAvailable: false
        )
        let client = ScriptedPowerSystemClient(current: initial)
        let coordinator = AutomationCoordinator(
            powerSystem: client,
            config: AutomationConfig(activePowerMode: .automatic, idlePowerMode: .highPower)
        )

        await coordinator.enableAutomation(activity: makeActivity(cpu: 70, idle: 3_600))

        let requests = await client.recordedRequests()
        #expect(
            requests ==
                [.init(mode: .automatic, source: .battery, controlStyle: .lowPowerOnly)]
        )
        #expect(!requests.contains(where: { $0.mode == .highPower }))
    }

    @Test func manualModeChangePausesBeforeDecisionAndDoesNotWriteBack() async {
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
        await coordinator.evaluate(activity: makeActivity(cpu: 70, idle: 3_600))

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        #expect(state.status == .pausedForManualChange)
        #expect(state.manualOverrideSeen)
        #expect(state.currentPower?.mode == .lowPower)
        #expect(state.lastConfirmedMode == .lowPower)
        #expect(requests.isEmpty)
    }

    @Test func manualChangePausesEvenWhenExternalModeMatchesRuleTarget() async {
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
        await coordinator.evaluate(activity: makeActivity(cpu: 40, idle: 300))

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        #expect(state.status == .pausedForManualChange)
        #expect(requests.isEmpty)
    }

    @Test func manualModeChangeDoesNotPauseByDefaultAndContinuesEvaluation() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let coordinator = AutomationCoordinator(
            powerSystem: client,
            config: AutomationConfig(activePowerMode: .automatic, idlePowerMode: .highPower)
        )
        await coordinator.enableAutomation(activity: makeActivity(cpu: 40, idle: 0))

        await client.setCurrent(makePower(.lowPower, time: 1_001))
        await coordinator.evaluate(activity: makeActivity(cpu: 70, idle: 3_600))

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        #expect(state.status == .running)
        #expect(state.manualOverrideSeen)
        #expect(state.currentPower?.mode == .highPower)
        #expect(requests.map(\.mode) == [.highPower])
    }

    @Test func pausedPollingRefreshesDisplayWithoutWriting() async {
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

        await client.setCurrent(makePower(.highPower, time: 1_002))
        await coordinator.evaluate(activity: makeActivity(cpu: 40, idle: 0))

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        #expect(state.status == .pausedForManualChange)
        #expect(state.currentPower?.mode == .highPower)
        #expect(requests.isEmpty)
    }

    @Test func resumeAcceptsFreshBaselineButManualMarkerRemainsStickyAndBlocksRestore() async {
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
        await coordinator.resumeAutomation(activity: makeActivity(cpu: 40, idle: 0))

        var state = await coordinator.snapshot()
        var requests = await client.recordedRequests()
        #expect(state.status == .running)
        #expect(state.manualOverrideSeen)
        #expect(state.currentPower?.mode == .automatic)
        #expect(requests.map(\.mode) == [.automatic])

        await coordinator.disableAutomation()

        state = await coordinator.snapshot()
        requests = await client.recordedRequests()
        #expect(state.status == .disabled)
        #expect(requests.map(\.mode) == [.automatic])
    }

    @Test func cleanDisableRestoresTakeoverModeAndDoesNotLogRestoration() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let historyStore = RecordingHistoryStore()
        let coordinator = AutomationCoordinator(
            powerSystem: client,
            historyStore: historyStore,
            config: AutomationConfig(activePowerMode: .automatic)
        )
        await coordinator.enableAutomation(activity: makeActivity(cpu: 40, idle: 300))

        await coordinator.disableAutomation()

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        let saves = await historyStore.saves()
        #expect(state.status == .disabled)
        #expect(state.currentPower?.mode == .automatic)
        #expect(state.takeoverMode == nil)
        #expect(requests.map(\.mode) == [.lowPower, .automatic])
        #expect(state.history.count == 1)
        #expect(saves.last?.count == 1)
    }

    @Test func terminationUsesSameCleanRestorationContract() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let coordinator = AutomationCoordinator(powerSystem: client)
        await coordinator.enableAutomation(activity: makeActivity(cpu: 40, idle: 300))

        await coordinator.prepareForTermination()

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        #expect(state.status == .disabled)
        #expect(requests.map(\.mode) == [.lowPower, .automatic])
    }

    @Test func shutdownReadDetectsUnseenExternalChangeAndSkipsRestore() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let coordinator = AutomationCoordinator(powerSystem: client)
        await coordinator.enableAutomation(activity: makeActivity(cpu: 40, idle: 300))
        await client.setCurrent(makePower(.highPower, time: 1_003))

        await coordinator.disableAutomation()

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        #expect(state.status == .disabled)
        #expect(state.currentPower?.mode == .highPower)
        #expect(requests.map(\.mode) == [.lowPower])
    }

    @Test func bootstrapCapsLoadedHistoryAtTwentyNewestEntries() async {
        let entries = (0..<25).map { index in
            SwitchHistoryEntry(
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                oldMode: .automatic,
                newMode: .lowPower,
                reason: index == 24 ? .idleThresholdReached : .userActive
            )
        }
        let historyStore = RecordingHistoryStore(history: entries)
        let coordinator = AutomationCoordinator(
            powerSystem: ScriptedPowerSystemClient(current: makePower(.automatic)),
            historyStore: historyStore
        )

        await coordinator.bootstrap()

        let state = await coordinator.snapshot()
        #expect(state.status == .disabled)
        #expect(state.history.count == 20)
        #expect(state.history.first?.timestamp == Date(timeIntervalSince1970: 5))
        #expect(state.history.last?.timestamp == Date(timeIntervalSince1970: 24))
        #expect(state.lastSwitchReason == .idleThresholdReached)
    }

    @Test func twentyOneConfirmedAutomaticSwitchesKeepOnlyNewestTwenty() async {
        let client = ScriptedPowerSystemClient(current: makePower(.automatic))
        let historyStore = RecordingHistoryStore()
        let coordinator = AutomationCoordinator(
            powerSystem: client,
            historyStore: historyStore,
            config: AutomationConfig(activePowerMode: .automatic)
        )

        await coordinator.enableAutomation(activity: makeActivity(cpu: 40, idle: 300))
        for index in 1..<21 {
            let idle: TimeInterval = index.isMultiple(of: 2) ? 300 : 0
            await coordinator.evaluate(activity: makeActivity(cpu: 40, idle: idle))
        }

        let state = await coordinator.snapshot()
        let requests = await client.recordedRequests()
        let saves = await historyStore.saves()
        #expect(requests.count == 21)
        #expect(state.history.count == 20)
        #expect(state.history.first?.oldMode == .lowPower)
        #expect(state.history.first?.newMode == .automatic)
        #expect(state.history.last?.newMode == .lowPower)
        #expect(saves.last?.count == 20)
    }
}
