import Foundation
import AppKit
import GovernorCore
import Testing
@testable import Governor

@Suite("App model activity routing")
@MainActor
struct AppModelTests {
    @Test
    func automationSettingsRequestCreatesAVIsibleWindow() async {
        let sampler = ScriptedActivitySampler(steps: [], fallback: nil)
        let client = AppModelPowerClient(current: makePower(.automatic))
        let fixture = makeFixture(sampler: sampler, client: client)
        defer { clearSuite(named: fixture.suiteName) }

        AppLifecycle.shared.model = fixture.model
        AppLifecycle.shared.showAutomationSettings()

        let expectedTitle = AppText.automationSettingsTitle(
            LanguageSettings.shared.language
        )
        let settingsWindow = NSApp.windows.first { $0.title == expectedTitle }
        #expect(settingsWindow?.isVisible == true)
        #expect(settingsWindow?.styleMask.contains(.resizable) == true)
        #expect(
            settingsWindow?.contentMinSize
                == AppLifecycle.automationSettingsMinimumContentSize
        )
        #expect(containsScrollView(in: settingsWindow?.contentView))
        AppLifecycle.shared.updateAutomationSettingsWindowTitle(for: .english)
        #expect(settingsWindow?.title == "Automation")
        AppLifecycle.shared.updateAutomationSettingsWindowTitle(for: .chinese)
        #expect(settingsWindow?.title == "自动切换")
        settingsWindow?.close()
    }

    @Test
    func automationSettingsInitialSizeStaysWithinAvailableScreenHeight() {
        let compactScreen = NSRect(x: 0, y: 0, width: 1_280, height: 600)
        let compactContentSize = AppLifecycle.automationSettingsInitialContentSize(
            for: compactScreen
        )
        let spaciousContentSize = AppLifecycle.automationSettingsInitialContentSize(
            for: NSRect(x: 0, y: 0, width: 1_280, height: 1_000)
        )

        #expect(compactContentSize == NSSize(width: 500, height: 552))
        #expect(
            spaciousContentSize
                == AppLifecycle.automationSettingsPreferredContentSize
        )
    }

    @Test
    func switchingFromMinutesToSecondsKeepsTheValueAndUpdatesTheThreshold() async {
        let sampler = ScriptedActivitySampler(steps: [], fallback: nil)
        let client = AppModelPowerClient(current: makePower(.automatic))
        let fixture = makeFixture(sampler: sampler, client: client)

        fixture.model.start()
        #expect(await eventually { await sampler.sampleCount() >= 1 })
        #expect(fixture.model.idleTimeValue == 5)
        #expect(fixture.model.idleTimeUnit == .minutes)

        fixture.model.setIdleTimeUnit(.seconds)

        #expect(
            await eventually {
                fixture.model.state.config.idleThreshold == 5
            }
        )
        #expect(fixture.model.idleTimeValue == 5)
        #expect(fixture.model.idleTimeUnit == .seconds)

        await fixture.model.prepareForTermination()
        clearSuite(named: fixture.suiteName)
    }

    @Test
    func brightnessRestoreSettingsClampAndPersist() async {
        let sampler = ScriptedActivitySampler(steps: [], fallback: nil)
        let client = AppModelPowerClient(current: makePower(.automatic))
        let fixture = makeFixture(sampler: sampler, client: client)

        fixture.model.start()
        #expect(await eventually { await sampler.sampleCount() >= 1 })
        #expect(fixture.model.restoreBrightnessAfterLowPower)
        #expect(fixture.model.brightnessRestoreDelayMilliseconds == 0)

        fixture.model.setBrightnessRestoreDelayMilliseconds(1_001)
        #expect(
            await eventually {
                fixture.model.state.config.brightnessRestoreDelayMilliseconds == 1_000
            }
        )
        #expect(fixture.model.brightnessRestoreDelayMilliseconds == 1_000)

        fixture.model.setRestoreBrightnessAfterLowPower(false)
        #expect(
            await eventually {
                !fixture.model.state.config.restoreBrightnessAfterLowPower
            }
        )

        fixture.model.setBrightnessRestoreDelayMilliseconds(-1)
        #expect(
            await eventually {
                fixture.model.state.config.brightnessRestoreDelayMilliseconds == 0
            }
        )

        let saved = await UserDefaultsAutomationSettingsStore(
            suiteName: fixture.suiteName
        ).loadConfig()
        #expect(!saved.restoreBrightnessAfterLowPower)
        #expect(saved.brightnessRestoreDelayMilliseconds == 0)

        await fixture.model.prepareForTermination()
        clearSuite(named: fixture.suiteName)
    }

    @Test
    func pollingIntervalsUseSeparateDefaultsAndPreserveDurationAcrossUnits() async {
        let sampler = ScriptedActivitySampler(steps: [], fallback: nil)
        let client = AppModelPowerClient(current: makePower(.automatic))
        let fixture = makeFixture(
            sampler: sampler,
            client: client,
            fastPollingInterval: nil
        )

        fixture.model.start()
        #expect(await eventually { await sampler.sampleCount() >= 1 })
        #expect(fixture.model.activePollingIntervalUnit == .seconds)
        #expect(fixture.model.activePollingIntervalValue == 5)
        #expect(fixture.model.idlePollingIntervalUnit == .seconds)
        #expect(fixture.model.idlePollingIntervalValue == 1)
        #expect(
            fixture.model.pollingInterval(
                after: makeActivity(cpu: 40, idle: 299, time: 1)
            ) == 5
        )
        #expect(
            fixture.model.pollingInterval(
                after: makeActivity(cpu: 40, idle: 300, time: 1)
            ) == 1
        )

        fixture.model.setActivePollingIntervalUnit(.minutes)
        #expect(
            abs(fixture.model.activePollingIntervalValue - (5.0 / 60))
                < 0.000_001
        )
        #expect(
            await eventually {
                await UserDefaultsAutomationSettingsStore(
                    suiteName: fixture.suiteName
                ).loadActivePollingIntervalUnit() == .minutes
            }
        )
        #expect(fixture.model.state.config.activePollingInterval == 5)

        fixture.model.setIdlePollingIntervalValue(2)
        #expect(
            await eventually {
                fixture.model.state.config.idlePollingInterval == 2
            }
        )
        #expect(
            fixture.model.pollingInterval(
                after: makeActivity(cpu: 40, idle: 300, time: 2)
            ) == 2
        )

        let saved = await UserDefaultsAutomationSettingsStore(
            suiteName: fixture.suiteName
        ).loadConfig()
        #expect(saved.activePollingInterval == 5)
        #expect(saved.idlePollingInterval == 2)

        fixture.model.setIdlePollingIntervalUnit(.minutes)
        #expect(fixture.model.idlePollingIntervalUnit == .seconds)

        await fixture.model.prepareForTermination()
        clearSuite(named: fixture.suiteName)
    }

    @Test
    func restoreDefaultSettingsResetsAndPersistsAllRuleOptions() async {
        let sampler = ScriptedActivitySampler(steps: [], fallback: nil)
        let client = AppModelPowerClient(current: makePower(.automatic))
        let fixture = makeFixture(sampler: sampler, client: client)
        let customConfig = AutomationConfig(
            idleThreshold: 12,
            activePollingInterval: 0.5,
            idlePollingInterval: 2,
            activePowerMode: .automatic,
            idlePowerMode: .highPower,
            pauseOnManualPowerModeChange: true,
            restoreBrightnessAfterLowPower: false,
            brightnessRestoreDelayMilliseconds: 725
        )
        let store = UserDefaultsAutomationSettingsStore(
            suiteName: fixture.suiteName
        )
        await store.saveConfig(
            customConfig,
            idleTimeUnit: .seconds,
            activePollingIntervalUnit: .milliseconds,
            idlePollingIntervalUnit: .milliseconds
        )

        fixture.model.start()
        #expect(
            await eventually {
                fixture.model.state.config == customConfig
            }
        )

        fixture.model.restoreDefaultSettings()

        #expect(
            await eventually {
                fixture.model.state.config == .default
            }
        )
        #expect(fixture.model.idleTimeValue == 5)
        #expect(fixture.model.idleTimeUnit == .minutes)
        #expect(fixture.model.activePollingIntervalValue == 5)
        #expect(fixture.model.activePollingIntervalUnit == .seconds)
        #expect(fixture.model.idlePollingIntervalValue == 1)
        #expect(fixture.model.idlePollingIntervalUnit == .seconds)
        #expect(fixture.model.activePowerMode == .highPower)
        #expect(fixture.model.idlePowerMode == .lowPower)
        #expect(!fixture.model.pauseOnManualPowerModeChange)
        #expect(fixture.model.restoreBrightnessAfterLowPower)
        #expect(fixture.model.brightnessRestoreDelayMilliseconds == 0)
        #expect(await store.loadConfig() == .default)
        #expect(await store.loadIdleTimeUnit() == .minutes)
        #expect(await store.loadActivePollingIntervalUnit() == .seconds)
        #expect(await store.loadIdlePollingIntervalUnit() == .seconds)

        await fixture.model.prepareForTermination()
        clearSuite(named: fixture.suiteName)
    }

    @Test
    func enableUsesTheSampleCapturedAfterTheUserAction() async {
        let sampler = ScriptedActivitySampler(
            steps: [
                .value(makeActivity(cpu: 40, idle: 300, time: 1)),
                .value(makeActivity(cpu: 70, idle: 0, time: 2)),
            ],
            fallback: makeActivity(cpu: 70, idle: 0, time: 3)
        )
        let client = AppModelPowerClient(current: makePower(.automatic))
        let fixture = makeFixture(sampler: sampler, client: client)

        fixture.model.start()
        #expect(await eventually { await sampler.sampleCount() >= 1 })

        fixture.model.setAutomationEnabled(true)
        #expect(await eventually { await client.recordedModes().first == .highPower })

        let modes = await client.recordedModes()
        #expect(modes.first == .highPower)
        #expect(fixture.model.state.status == .running)

        await fixture.model.prepareForTermination()
        clearSuite(named: fixture.suiteName)
    }

    @Test
    func resumeUsesTheSampleCapturedAfterTheResumeClick() async {
        let lowActive = makeActivity(cpu: 40, idle: 0, time: 1)
        let sampler = ScriptedActivitySampler(
            steps: [
                .value(lowActive),
                .value(lowActive),
                .value(lowActive),
                .value(makeActivity(cpu: 70, idle: 0, time: 4)),
            ],
            fallback: makeActivity(cpu: 70, idle: 0, time: 5)
        )
        let client = AppModelPowerClient(current: makePower(.automatic))
        let fixture = makeFixture(sampler: sampler, client: client)

        fixture.model.start()
        #expect(await eventually { await sampler.sampleCount() >= 1 })
        fixture.model.setAutomationEnabled(true)
        #expect(await eventually { fixture.model.state.status == .running })

        await client.setCurrent(makePower(.lowPower, time: 2))

        fixture.model.setPauseOnManualPowerModeChange(true)
        #expect(
            await eventually {
                fixture.model.state.config.pauseOnManualPowerModeChange
            }
        )
        fixture.model.setIdlePowerMode(.automatic)
        #expect(await eventually { fixture.model.isPaused })

        fixture.model.resumeAutomation()
        #expect(await eventually { await client.recordedModes().first == .highPower })
        #expect(await eventually { fixture.model.state.status == .running })

        let modes = await client.recordedModes()
        #expect(modes == [.highPower, .highPower])

        await fixture.model.prepareForTermination()
        clearSuite(named: fixture.suiteName)
    }

    @Test
    func configChangeUsesTheSampleCapturedAfterTheSettingChange() async {
        let highCPU = makeActivity(cpu: 70, idle: 0, time: 1)
        let sampler = ScriptedActivitySampler(
            steps: [
                .value(highCPU),
                .value(highCPU),
                .value(makeActivity(cpu: 40, idle: 0, time: 3)),
            ],
            fallback: makeActivity(cpu: 40, idle: 0, time: 4)
        )
        let client = AppModelPowerClient(current: makePower(.highPower))
        let fixture = makeFixture(sampler: sampler, client: client)

        fixture.model.start()
        #expect(await eventually { await sampler.sampleCount() >= 1 })
        fixture.model.setAutomationEnabled(true)
        #expect(await eventually { fixture.model.state.status == .running })

        fixture.model.setActivePowerMode(.automatic)
        #expect(await eventually { await client.recordedModes().first == .automatic })

        let modes = await client.recordedModes()
        #expect(modes.first == .automatic)

        await fixture.model.prepareForTermination()
        clearSuite(named: fixture.suiteName)
    }

    @Test
    func nilSampleRefreshesWhileDisabledAndUsesWarmupRulesWhenEnabled() async {
        let sampler = ScriptedActivitySampler(
            steps: [.value(nil), .value(nil)],
            fallback: nil
        )
        let client = AppModelPowerClient(
            current: makePower(.highPower, highPowerAvailable: false)
        )
        let fixture = makeFixture(sampler: sampler, client: client)

        fixture.model.start()
        #expect(await eventually { await client.counts().reads >= 2 })
        let disabledCounts = await client.counts()
        #expect(disabledCounts.requests == 0)
        #expect(fixture.model.state.status == .disabled)

        fixture.model.setAutomationEnabled(true)
        #expect(await eventually { await client.recordedModes().first == .automatic })

        let modes = await client.recordedModes()
        #expect(modes == [.automatic])
        #expect(fixture.model.state.status == .starting)

        await fixture.model.prepareForTermination()
        clearSuite(named: fixture.suiteName)
    }

    @Test
    func activityFailureStopsTheMonitorWithoutAutomaticRetry() async {
        let active = makeActivity(cpu: 40, idle: 0, time: 1)
        let sampler = ScriptedActivitySampler(
            steps: [.value(active), .value(active), .failure],
            fallback: active
        )
        let client = AppModelPowerClient(current: makePower(.automatic))
        let fixture = makeFixture(sampler: sampler, client: client)

        fixture.model.start()
        #expect(await eventually { await sampler.sampleCount() >= 1 })
        fixture.model.setAutomationEnabled(true)
        #expect(await eventually { fixture.model.state.status == .running })
        #expect(
            await eventually(timeout: .seconds(2)) {
                fixture.model.state.status == .errorStopped(.systemReadFailed)
            }
        )

        let callsAfterFailure = await sampler.sampleCount()
        let countsAfterFailure = await client.counts()
        try? await Task.sleep(for: .milliseconds(1_200))

        let callsAfterRetryOpportunity = await sampler.sampleCount()
        let countsAfterRetryOpportunity = await client.counts()
        let resetCount = await sampler.resetCount()
        #expect(callsAfterRetryOpportunity == callsAfterFailure)
        #expect(countsAfterRetryOpportunity == countsAfterFailure)
        #expect(resetCount == 1)

        await fixture.model.prepareForTermination()
        clearSuite(named: fixture.suiteName)
    }

    private func makeFixture(
        sampler: ScriptedActivitySampler,
        client: AppModelPowerClient,
        fastPollingInterval: TimeInterval? = 0.25
    ) -> (model: AppModel, suiteName: String) {
        let suiteName = "Governor.AppModelTests.\(UUID().uuidString)"
        clearSuite(named: suiteName)
        if let fastPollingInterval,
           let defaults = UserDefaults(suiteName: suiteName)
        {
            defaults.set(
                fastPollingInterval,
                forKey: "MacPower.settings.activePollingIntervalSeconds"
            )
            defaults.set(
                fastPollingInterval,
                forKey: "MacPower.settings.idlePollingIntervalSeconds"
            )
        }
        let coordinator = AutomationCoordinator(powerSystem: client)
        let model = AppModel(
            coordinator: coordinator,
            activityMonitor: sampler,
            settingsStore: UserDefaultsAutomationSettingsStore(suiteName: suiteName)
        )
        return (model, suiteName)
    }

    private func clearSuite(named suiteName: String) {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    private func containsScrollView(in view: NSView?) -> Bool {
        guard let view else { return false }
        return view is NSScrollView
            || view.subviews.contains { containsScrollView(in: $0) }
    }

    private func eventually(
        timeout: Duration = .seconds(1),
        _ condition: () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }
}

private enum ScriptedActivityStep: Sendable {
    case value(ActivitySnapshot?)
    case failure
}

private enum ScriptedActivityError: Error, Sendable {
    case expected
}

private actor ScriptedActivitySampler: ActivitySampling {
    private var steps: [ScriptedActivityStep]
    private let fallback: ActivitySnapshot?
    private var samples = 0
    private var resets = 0

    init(steps: [ScriptedActivityStep], fallback: ActivitySnapshot?) {
        self.steps = steps
        self.fallback = fallback
    }

    func sample() throws -> ActivitySnapshot? {
        samples += 1
        guard !steps.isEmpty else { return fallback }
        switch steps.removeFirst() {
        case let .value(snapshot):
            return snapshot
        case .failure:
            throw ScriptedActivityError.expected
        }
    }

    func reset() {
        resets += 1
    }

    func sampleCount() -> Int { samples }

    func resetCount() -> Int { resets }
}

private actor AppModelPowerClient: PowerSystemClient {
    private var current: PowerSnapshot
    private var authorizationCount = 0
    private var readCount = 0
    private var requestedModes: [PowerMode] = []

    init(current: PowerSnapshot) {
        self.current = current
    }

    func authorize() {
        authorizationCount += 1
    }

    func readSnapshot() -> PowerSnapshot {
        readCount += 1
        return current
    }

    func requestMode(
        _ mode: PowerMode,
        source: PowerSource,
        controlStyle: PowerControlStyle
    ) {
        requestedModes.append(mode)
        current = PowerSnapshot(
            mode: mode,
            source: source,
            controlStyle: controlStyle,
            highPowerAvailable: current.highPowerAvailable,
            observedAt: current.observedAt.addingTimeInterval(1)
        )
    }

    func setCurrent(_ snapshot: PowerSnapshot) {
        current = snapshot
    }

    func recordedModes() -> [PowerMode] { requestedModes }

    func counts() -> (authorizations: Int, reads: Int, requests: Int) {
        (authorizationCount, readCount, requestedModes.count)
    }
}

private func makePower(
    _ mode: PowerMode,
    highPowerAvailable: Bool = true,
    time: TimeInterval = 1
) -> PowerSnapshot {
    PowerSnapshot(
        mode: mode,
        source: .charger,
        controlStyle: .unifiedPowermode,
        highPowerAvailable: highPowerAvailable,
        observedAt: Date(timeIntervalSince1970: time)
    )
}

private func makeActivity(
    cpu _: Double,
    idle: TimeInterval,
    time: TimeInterval
) -> ActivitySnapshot {
    ActivitySnapshot(
        userIdleDuration: idle,
        observedAt: Date(timeIntervalSince1970: time)
    )
}
