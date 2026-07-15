import Foundation
import GovernorCore
import Testing
@testable import Governor

@Suite
struct UserDefaultsStoresTests {
    @Test
    func testSettingsDefaultAndRoundTrip() async throws {
        let suiteName = makeEmptySuiteName()
        defer { clearSuite(named: suiteName) }
        let store = UserDefaultsAutomationSettingsStore(suiteName: suiteName)

        let initial = await store.loadConfig()
        #expect(initial == .default)
        #expect(!initial.pauseOnManualPowerModeChange)
        #expect(initial.restoreBrightnessAfterLowPower)
        #expect(initial.brightnessRestoreDelayMilliseconds == 0)
        #expect(initial.activePollingInterval == 5)
        #expect(initial.idlePollingInterval == 1)
        #expect(await store.loadActivePollingIntervalUnit() == .seconds)
        #expect(await store.loadIdlePollingIntervalUnit() == .seconds)

        let changed = AutomationConfig(
            idleThreshold: 12 * 60,
            activePollingInterval: 0.5,
            idlePollingInterval: 60,
            activePowerMode: .automatic,
            idlePowerMode: .highPower,
            pauseOnManualPowerModeChange: true,
            restoreBrightnessAfterLowPower: false,
            brightnessRestoreDelayMilliseconds: 725
        )
        await store.saveConfig(
            changed,
            activePollingIntervalUnit: .minutes,
            idlePollingIntervalUnit: .seconds
        )
        let loaded = await store.loadConfig()
        #expect(loaded == changed)
        #expect(await store.loadIdleTimeUnit() == .minutes)
        #expect(await store.loadActivePollingIntervalUnit() == .minutes)
        #expect(await store.loadIdlePollingIntervalUnit() == .seconds)
    }

    @Test
    func testSettingsPersistsSecondsUnitAndSubminuteThreshold() async throws {
        let suiteName = makeEmptySuiteName()
        defer { clearSuite(named: suiteName) }
        let store = UserDefaultsAutomationSettingsStore(suiteName: suiteName)
        let changed = AutomationConfig(
            idleThreshold: 5,
            activePowerMode: .lowPower,
            idlePowerMode: .automatic
        )

        await store.saveConfig(changed, idleTimeUnit: .seconds)

        #expect(await store.loadConfig() == changed)
        #expect(await store.loadIdleTimeUnit() == .seconds)
    }

    @Test
    func testInvalidStoredBrightnessDelayFallsBackToDefault() async throws {
        let suiteName = makeEmptySuiteName()
        defer { clearSuite(named: suiteName) }
        let writer = UserDefaults(suiteName: suiteName)!
        writer.set(
            1_001,
            forKey: "MacPower.settings.brightnessRestoreDelayMilliseconds"
        )
        let store = UserDefaultsAutomationSettingsStore(suiteName: suiteName)

        let loaded = await store.loadConfig()

        #expect(loaded.brightnessRestoreDelayMilliseconds == 0)
    }

    @Test
    func testInvalidStoredPollingIntervalsFallBackToDefaults() async throws {
        let suiteName = makeEmptySuiteName()
        defer { clearSuite(named: suiteName) }
        let writer = UserDefaults(suiteName: suiteName)!
        writer.set(
            0,
            forKey: "MacPower.settings.activePollingIntervalSeconds"
        )
        writer.set(
            3_601,
            forKey: "MacPower.settings.idlePollingIntervalSeconds"
        )
        let store = UserDefaultsAutomationSettingsStore(suiteName: suiteName)

        let loaded = await store.loadConfig()

        #expect(loaded.activePollingInterval == 5)
        #expect(loaded.idlePollingInterval == 1)
    }

    @Test
    func testLegacyIdleMinutesUnitMigratesToSeconds() async throws {
        let suiteName = makeEmptySuiteName()
        defer { clearSuite(named: suiteName) }
        let writer = UserDefaults(suiteName: suiteName)!
        writer.set(
            60,
            forKey: "MacPower.settings.idlePollingIntervalSeconds"
        )
        writer.set(
            "minutes",
            forKey: "MacPower.settings.idlePollingIntervalUnit"
        )
        let store = UserDefaultsAutomationSettingsStore(suiteName: suiteName)

        #expect(await store.loadConfig().idlePollingInterval == 60)
        #expect(await store.loadIdlePollingIntervalUnit() == .seconds)
    }

    @Test
    func testHistoryKeepsOnlyMostRecentTwentyEntries() async throws {
        let suiteName = makeEmptySuiteName()
        defer { clearSuite(named: suiteName) }
        let store = UserDefaultsSwitchHistoryStore(suiteName: suiteName)
        let entries = (0 ..< 25).map { index in
            SwitchHistoryEntry(
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                oldMode: .automatic,
                newMode: .lowPower,
                reason: .idleThresholdReached
            )
        }

        try await store.saveHistory(entries)
        let loaded = try await store.loadHistory()

        #expect(loaded.count == 20)
        #expect(loaded.first?.timestamp == Date(timeIntervalSince1970: 5))
        #expect(loaded.last?.timestamp == Date(timeIntervalSince1970: 24))
    }

    @Test
    func testCorruptHistoryIsReportedAsReadFailure() async throws {
        let suiteName = makeEmptySuiteName()
        defer { clearSuite(named: suiteName) }
        writeCorruptHistory(toSuiteNamed: suiteName)
        let store = UserDefaultsSwitchHistoryStore(suiteName: suiteName)

        do {
            _ = try await store.loadHistory()
            Issue.record("Expected corrupt history to throw.")
        } catch {
            #expect(error is DecodingError)
        }
    }

    private func makeEmptySuiteName() -> String {
        let suiteName = "GovernorServiceTests.\(UUID().uuidString)"
        clearSuite(named: suiteName)
        return suiteName
    }

    private func clearSuite(named suiteName: String) {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    private func writeCorruptHistory(toSuiteNamed suiteName: String) {
        let writer = UserDefaults(suiteName: suiteName)!
        writer.set(Data("not-json".utf8), forKey: "MacPower.automaticSwitchHistory")
    }
}
