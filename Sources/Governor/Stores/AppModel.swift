import Combine
import Foundation
import GovernorCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: AutomationStateSnapshot
    @Published private(set) var idleTimeValue: Int
    @Published private(set) var idleTimeUnit: IdleTimeUnit
    @Published private(set) var activePollingIntervalValue: Double
    @Published private(set) var activePollingIntervalUnit: PollingIntervalUnit
    @Published private(set) var idlePollingIntervalValue: Double
    @Published private(set) var idlePollingIntervalUnit: PollingIntervalUnit
    @Published private(set) var activePowerMode: PowerMode
    @Published private(set) var idlePowerMode: PowerMode
    @Published private(set) var pauseOnManualPowerModeChange: Bool
    @Published private(set) var restoreBrightnessAfterLowPower: Bool
    @Published private(set) var brightnessRestoreDelayMilliseconds: Int

    private let coordinator: AutomationCoordinator
    private let activityMonitor: any ActivitySampling
    private let settingsStore: UserDefaultsAutomationSettingsStore

    private var monitorTask: Task<Void, Never>?
    private var monitorGeneration: UInt64 = 0
    private var hasStarted = false
    private var automationActionInProgress = false

    static func live() -> AppModel {
        let powerSystem = PMSetPowerSystemClient()
        let settingsStore = UserDefaultsAutomationSettingsStore()
        let historyStore = UserDefaultsSwitchHistoryStore()
        return AppModel(
            coordinator: AutomationCoordinator(
                powerSystem: powerSystem,
                displayBrightness: SystemDisplayBrightnessClient(),
                historyStore: historyStore
            ),
            activityMonitor: ActivityMonitor(),
            settingsStore: settingsStore
        )
    }

    init(
        coordinator: AutomationCoordinator,
        activityMonitor: any ActivitySampling,
        settingsStore: UserDefaultsAutomationSettingsStore
    ) {
        self.coordinator = coordinator
        self.activityMonitor = activityMonitor
        self.settingsStore = settingsStore
        state = AutomationStateSnapshot(
            status: .disabled,
            currentPower: nil,
            lastConfirmedMode: nil,
            takeoverMode: nil,
            manualOverrideSeen: false,
            switchInFlight: false,
            lastSwitchReason: nil,
            lastError: nil,
            config: .default,
            history: []
        )
        idleTimeValue = Int(AutomationConfig.default.idleThreshold / 60)
        idleTimeUnit = .minutes
        activePollingIntervalUnit = .seconds
        activePollingIntervalValue =
            AutomationConfig.default.activePollingInterval
            / PollingIntervalUnit.seconds.secondsPerUnit
        idlePollingIntervalUnit = .seconds
        idlePollingIntervalValue =
            AutomationConfig.default.idlePollingInterval
            / PollingIntervalUnit.seconds.secondsPerUnit
        activePowerMode = AutomationConfig.default.activePowerMode
        idlePowerMode = AutomationConfig.default.idlePowerMode
        pauseOnManualPowerModeChange =
            AutomationConfig.default.pauseOnManualPowerModeChange
        restoreBrightnessAfterLowPower =
            AutomationConfig.default.restoreBrightnessAfterLowPower
        brightnessRestoreDelayMilliseconds =
            AutomationConfig.default.brightnessRestoreDelayMilliseconds
    }

    deinit {
        monitorTask?.cancel()
    }

    var actualModeText: String {
        let language = LanguageSettings.shared.language
        return state.currentPower?.mode.displayText(in: language)
            ?? AppText.unknown(language)
    }

    var automationStatusText: String {
        state.status.displayText(in: LanguageSettings.shared.language)
    }

    var lastSwitchReasonText: String {
        let language = LanguageSettings.shared.language
        return state.lastSwitchReason?.displayText(in: language)
            ?? AppText.none(language)
    }

    var menuBarSystemImage: String {
        state.currentPower?.mode.menuBarSystemImage ?? "bolt.circle"
    }

    /// A takeover mode exists only after authorization and the enable-time
    /// baseline read both succeeded. This avoids showing the toggle as enabled
    /// for a bootstrap/authorization error that has no active session.
    var isAutomationEnabled: Bool {
        state.takeoverMode != nil
    }

    var isPaused: Bool {
        state.status.isPaused
    }

    var isHighPowerCurrentlyAvailable: Bool {
        state.currentPower?.highPowerAvailable ?? true
    }

    /// The helper requires a one-time explicit approval in System Settings.
    /// This flag intentionally reflects a stopped automation transaction rather
    /// than attempting another registration or authorization interaction.
    var requiresHelperApproval: Bool {
        state.status == .errorStopped(.permissionDenied)
    }

    func openHelperApprovalSettings() {
        GovernorPowerHelperInstaller.openApprovalSettings()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        Task { [weak self] in
            guard let self else { return }
            let savedConfig = await settingsStore.loadConfig()
            let savedIdleTimeUnit = await settingsStore.loadIdleTimeUnit()
            let savedActivePollingIntervalUnit =
                await settingsStore.loadActivePollingIntervalUnit()
            let savedIdlePollingIntervalUnit =
                await settingsStore.loadIdlePollingIntervalUnit()
            applyConfigToUI(
                savedConfig,
                idleTimeUnit: savedIdleTimeUnit,
                activePollingIntervalUnit: savedActivePollingIntervalUnit,
                idlePollingIntervalUnit: savedIdlePollingIntervalUnit
            )
            await coordinator.updateConfig(savedConfig, activity: nil)
            await coordinator.bootstrap()
            await refreshState()
            ensureMonitorRunning()
        }
    }

    func setAutomationEnabled(_ enabled: Bool) {
        guard enabled != isAutomationEnabled, !automationActionInProgress else { return }
        automationActionInProgress = true

        Task { [weak self] in
            guard let self else { return }
            if enabled {
                let activity: ActivitySnapshot?
                do {
                    activity = try await activityMonitor.sample()
                } catch {
                    await handleActivityReadFailure()
                    automationActionInProgress = false
                    return
                }
                ensureMonitorRunning()
                await coordinator.enableAutomation(activity: activity)
            } else {
                await coordinator.disableAutomation()
            }
            await refreshState()
            automationActionInProgress = false
        }
    }

    func setIdleTimeValue(_ value: Int) {
        let clamped = max(value, 1)
        guard idleTimeValue != clamped else { return }
        idleTimeValue = clamped
        saveAndApplyConfig()
    }

    func setIdleTimeUnit(_ unit: IdleTimeUnit) {
        guard idleTimeUnit != unit else { return }
        idleTimeUnit = unit
        saveAndApplyConfig()
    }

    func setActivePollingIntervalValue(_ value: Double) {
        let seconds = AutomationConfig.clampedPollingInterval(
            value * activePollingIntervalUnit.secondsPerUnit
        )
        let normalizedValue = seconds / activePollingIntervalUnit.secondsPerUnit
        guard activePollingIntervalValue != normalizedValue else { return }
        activePollingIntervalValue = normalizedValue
        saveAndApplyConfig(restartMonitor: true)
    }

    func setActivePollingIntervalUnit(_ unit: PollingIntervalUnit) {
        guard activePollingIntervalUnit != unit else { return }
        let seconds = activePollingIntervalValue
            * activePollingIntervalUnit.secondsPerUnit
        activePollingIntervalUnit = unit
        activePollingIntervalValue = seconds / unit.secondsPerUnit
        saveAndApplyConfig(restartMonitor: true)
    }

    func setIdlePollingIntervalValue(_ value: Double) {
        let seconds = AutomationConfig.clampedPollingInterval(
            value * idlePollingIntervalUnit.secondsPerUnit
        )
        let normalizedValue = seconds / idlePollingIntervalUnit.secondsPerUnit
        guard idlePollingIntervalValue != normalizedValue else { return }
        idlePollingIntervalValue = normalizedValue
        saveAndApplyConfig(restartMonitor: true)
    }

    func setIdlePollingIntervalUnit(_ unit: PollingIntervalUnit) {
        let normalizedUnit = PollingIntervalUnit.idleOptions.contains(unit)
            ? unit
            : .seconds
        guard idlePollingIntervalUnit != normalizedUnit else { return }
        let seconds = idlePollingIntervalValue
            * idlePollingIntervalUnit.secondsPerUnit
        idlePollingIntervalUnit = normalizedUnit
        idlePollingIntervalValue = seconds / normalizedUnit.secondsPerUnit
        saveAndApplyConfig(restartMonitor: true)
    }

    func setActivePowerMode(_ mode: PowerMode) {
        guard activePowerMode != mode else { return }
        activePowerMode = mode
        saveAndApplyConfig()
    }

    func setIdlePowerMode(_ mode: PowerMode) {
        guard idlePowerMode != mode else { return }
        idlePowerMode = mode
        saveAndApplyConfig()
    }

    func setPauseOnManualPowerModeChange(_ enabled: Bool) {
        guard pauseOnManualPowerModeChange != enabled else { return }
        pauseOnManualPowerModeChange = enabled
        saveAndApplyConfig()
    }

    func setRestoreBrightnessAfterLowPower(_ enabled: Bool) {
        guard restoreBrightnessAfterLowPower != enabled else { return }
        restoreBrightnessAfterLowPower = enabled
        saveAndApplyConfig()
    }

    func setBrightnessRestoreDelayMilliseconds(_ milliseconds: Int) {
        let clamped = AutomationConfig.clampedBrightnessRestoreDelay(milliseconds)
        guard brightnessRestoreDelayMilliseconds != clamped else { return }
        brightnessRestoreDelayMilliseconds = clamped
        saveAndApplyConfig()
    }

    func restoreDefaultSettings() {
        applyConfigToUI(
            .default,
            idleTimeUnit: .minutes,
            activePollingIntervalUnit: .seconds,
            idlePollingIntervalUnit: .seconds
        )
        saveAndApplyConfig(restartMonitor: true)
    }

    func resumeAutomation() {
        guard isPaused else { return }
        Task { [weak self] in
            guard let self else { return }
            let activity: ActivitySnapshot?
            do {
                activity = try await activityMonitor.sample()
            } catch {
                await handleActivityReadFailure()
                return
            }
            await coordinator.resumeAutomation(activity: activity)
            await refreshState()
        }
    }

    func prepareForTermination() async {
        cancelMonitor()
        await coordinator.prepareForTermination()
        await refreshState()
    }

    private func saveAndApplyConfig(restartMonitor: Bool = false) {
        let newConfig = currentConfig
        let newIdleTimeUnit = idleTimeUnit
        let newActivePollingIntervalUnit = activePollingIntervalUnit
        let newIdlePollingIntervalUnit = idlePollingIntervalUnit
        Task { [weak self] in
            guard let self else { return }
            await settingsStore.saveConfig(
                newConfig,
                idleTimeUnit: newIdleTimeUnit,
                activePollingIntervalUnit: newActivePollingIntervalUnit,
                idlePollingIntervalUnit: newIdlePollingIntervalUnit
            )
            let activity: ActivitySnapshot?
            do {
                activity = try await activityMonitor.sample()
            } catch {
                await coordinator.updateConfig(newConfig, activity: nil)
                await handleActivityReadFailure()
                return
            }
            await coordinator.updateConfig(newConfig, activity: activity)
            if activity == nil {
                await coordinator.refreshWithoutActivity()
            }
            if restartMonitor {
                cancelMonitor()
                ensureMonitorRunning()
            }
            await refreshState()
        }
    }

    private var currentConfig: AutomationConfig {
        AutomationConfig(
            idleThreshold: TimeInterval(idleTimeValue) * idleTimeUnit.secondsPerUnit,
            activePollingInterval: AutomationConfig.clampedPollingInterval(
                activePollingIntervalValue * activePollingIntervalUnit.secondsPerUnit
            ),
            idlePollingInterval: AutomationConfig.clampedPollingInterval(
                idlePollingIntervalValue * idlePollingIntervalUnit.secondsPerUnit
            ),
            activePowerMode: activePowerMode,
            idlePowerMode: idlePowerMode,
            pauseOnManualPowerModeChange: pauseOnManualPowerModeChange,
            restoreBrightnessAfterLowPower: restoreBrightnessAfterLowPower,
            brightnessRestoreDelayMilliseconds: brightnessRestoreDelayMilliseconds
        )
    }

    private func applyConfigToUI(
        _ config: AutomationConfig,
        idleTimeUnit: IdleTimeUnit,
        activePollingIntervalUnit: PollingIntervalUnit,
        idlePollingIntervalUnit: PollingIntervalUnit
    ) {
        self.idleTimeUnit = idleTimeUnit
        let roundedValue = Int(
            (config.idleThreshold / idleTimeUnit.secondsPerUnit).rounded()
        )
        idleTimeValue = max(roundedValue, 1)
        self.activePollingIntervalUnit = activePollingIntervalUnit
        activePollingIntervalValue = AutomationConfig.clampedPollingInterval(
            config.activePollingInterval
        ) / activePollingIntervalUnit.secondsPerUnit
        let normalizedIdlePollingIntervalUnit =
            PollingIntervalUnit.idleOptions.contains(idlePollingIntervalUnit)
            ? idlePollingIntervalUnit
            : .seconds
        self.idlePollingIntervalUnit = normalizedIdlePollingIntervalUnit
        idlePollingIntervalValue = AutomationConfig.clampedPollingInterval(
            config.idlePollingInterval
        ) / normalizedIdlePollingIntervalUnit.secondsPerUnit
        activePowerMode = config.activePowerMode
        idlePowerMode = config.idlePowerMode
        pauseOnManualPowerModeChange = config.pauseOnManualPowerModeChange
        restoreBrightnessAfterLowPower = config.restoreBrightnessAfterLowPower
        brightnessRestoreDelayMilliseconds =
            AutomationConfig.clampedBrightnessRestoreDelay(
                config.brightnessRestoreDelayMilliseconds
            )
    }

    private func ensureMonitorRunning() {
        guard monitorTask == nil else { return }

        monitorGeneration &+= 1
        let generation = monitorGeneration
        monitorTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let nextPollingInterval: TimeInterval
                do {
                    let activity = try await activityMonitor.sample()
                    nextPollingInterval = pollingInterval(after: activity)
                    guard !Task.isCancelled, monitorGeneration == generation else {
                        clearMonitor(ifCurrent: generation)
                        return
                    }
                    if let activity {
                        await coordinator.evaluate(activity: activity)
                    } else {
                        await coordinator.refreshWithoutActivity()
                    }
                    await refreshState()
                } catch {
                    guard !Task.isCancelled, monitorGeneration == generation else {
                        clearMonitor(ifCurrent: generation)
                        return
                    }
                    await handleActivityReadFailure()
                    return
                }

                do {
                    try await Task.sleep(for: .seconds(nextPollingInterval))
                } catch {
                    clearMonitor(ifCurrent: generation)
                    return
                }
            }
            clearMonitor(ifCurrent: generation)
        }
    }

    private func refreshState() async {
        state = await coordinator.snapshot()
    }

    func pollingInterval(after activity: ActivitySnapshot?) -> TimeInterval {
        let config = currentConfig
        guard let activity,
              activity.userIdleDuration >= config.idleThreshold
        else {
            return config.activePollingInterval
        }
        return config.idlePollingInterval
    }

    private func handleActivityReadFailure() async {
        cancelMonitor()
        await activityMonitor.reset()
        await coordinator.stopForActivityReadFailure()
        await refreshState()
    }

    private func cancelMonitor() {
        monitorGeneration &+= 1
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func clearMonitor(ifCurrent generation: UInt64) {
        guard monitorGeneration == generation else { return }
        monitorTask = nil
    }
}
