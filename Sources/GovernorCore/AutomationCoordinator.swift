import Foundation

/// Owns the complete read -> decide -> optional write -> confirm transaction.
///
/// The actor remains re-entrancy-safe while its system client is suspended: timer
/// evaluations are coalesced, and disable/termination requests wait until the active
/// transaction has completed its confirmation read before restoration begins.
public actor AutomationCoordinator {
    private enum StopIntent {
        case disable
        case terminate
    }

    private let powerSystem: any PowerSystemClient
    private let displayBrightness: any DisplayBrightnessClient
    private let historyStore: any SwitchHistoryStore

    private var status: AutomationStatus = .disabled
    private var currentPower: PowerSnapshot?
    private var lastConfirmedMode: PowerMode?
    private var takeoverMode: PowerMode?
    private var manualOverrideSeen = false
    private var brightnessBeforeLowPower: DisplayBrightnessSnapshot?
    private var switchInFlight = false
    private var lastSwitchReason: DecisionReason?
    private var lastError: AutomationFailure?
    private var config: AutomationConfig
    private var history: [SwitchHistoryEntry] = []

    private var sessionIsActive = false
    private var operationInProgress = false
    private var pendingActivity: ActivitySnapshot?
    private var pendingWarmupRefresh = false
    private var pendingResumeRequested = false
    private var pendingResumeActivity: ActivitySnapshot?
    private var pendingActivityReadFailure = false
    private var pendingStop: StopIntent?
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        powerSystem: any PowerSystemClient,
        displayBrightness: any DisplayBrightnessClient = NoOpDisplayBrightnessClient(),
        historyStore: any SwitchHistoryStore = NoOpSwitchHistoryStore(),
        config: AutomationConfig = .default
    ) {
        self.powerSystem = powerSystem
        self.displayBrightness = displayBrightness
        self.historyStore = historyStore
        self.config = config
    }

    public func snapshot() -> AutomationStateSnapshot {
        AutomationStateSnapshot(
            status: status,
            currentPower: currentPower,
            lastConfirmedMode: lastConfirmedMode,
            takeoverMode: takeoverMode,
            manualOverrideSeen: manualOverrideSeen,
            switchInFlight: switchInFlight,
            lastSwitchReason: lastSwitchReason,
            lastError: lastError,
            config: config,
            history: history
        )
    }

    /// Loads the persisted switch history and performs one read-only system refresh.
    /// Automation always remains disabled after bootstrap.
    public func bootstrap() async {
        guard !operationInProgress else { return }
        operationInProgress = true

        do {
            history = Array(try await historyStore.loadHistory().suffix(20))
            lastSwitchReason = history.last?.reason
        } catch {
            enterError(.historyReadFailed)
            await completeOperationAndDrain()
            return
        }

        do {
            currentPower = try await powerSystem.readSnapshot()
            lastConfirmedMode = currentPower?.mode
            status = .disabled
            lastError = nil
        } catch {
            enterError(readFailure(for: error))
        }

        await completeOperationAndDrain()
    }

    /// Starts a new takeover session. Authorization is requested only from this
    /// explicit user action, never from timer evaluations or failed writes.
    public func enableAutomation(activity: ActivitySnapshot?) async {
        guard !sessionIsActive, !operationInProgress else { return }
        operationInProgress = true
        status = .starting
        lastError = nil

        do {
            try await powerSystem.authorize()
        } catch {
            enterError(permissionFailure(for: error))
            clearSession(preservingPendingStop: true)
            await completeOperationAndDrain()
            return
        }

        // A disable/termination request made while authorization was open wins
        // before the initial system read and before a takeover session exists.
        if pendingStop != nil {
            clearSession(preservingPendingStop: true)
            await completeOperationAndDrain()
            return
        }

        let initialPower: PowerSnapshot
        do {
            initialPower = try await powerSystem.readSnapshot()
        } catch {
            enterError(readFailure(for: error))
            clearSession(preservingPendingStop: true)
            await completeOperationAndDrain()
            return
        }

        sessionIsActive = true
        takeoverMode = initialPower.mode
        lastConfirmedMode = initialPower.mode
        currentPower = initialPower
        manualOverrideSeen = false

        if pendingStop != nil {
            status = .starting
        } else if let activity {
            status = .running
            await performEvaluation(
                activity: activity,
                initialPower: initialPower,
                detectManualChange: false
            )
        } else {
            // No instantaneous value is substituted for the required 15-second window.
            status = .starting
            await performWarmupRefresh(
                initialPower: initialPower,
                detectManualChange: false
            )
        }

        await completeOperationAndDrain()
    }

    /// Coalesces timer events while another read/write/confirm transaction is active.
    public func evaluate(activity: ActivitySnapshot) async {
        guard sessionIsActive else {
            switch status {
            case .disabled:
                // A complete sample is still not authority to write while disabled.
                // Keep only the displayed system truth current.
                await refreshWithoutActivity()

            case .starting where operationInProgress:
                // Authorization and the initial system read can outlive an input
                // poll. Preserve the newest activity sample for the drain pass.
                pendingActivity = activity

            case .starting, .running, .pausedForManualChange, .restoring,
                 .errorStopped:
                return
            }
            return
        }

        if operationInProgress {
            pendingActivity = activity
            return
        }

        switch status {
        case .running, .starting:
            operationInProgress = true
            status = .running
            await performEvaluation(activity: activity)
            await completeOperationAndDrain()

        case .pausedForManualChange:
            // Keep the displayed actual mode current while paused, but never write.
            operationInProgress = true
            do {
                let actual = try await powerSystem.readSnapshot()
                currentPower = actual
                lastConfirmedMode = actual.mode
            } catch {
                enterError(readFailure(for: error))
            }
            await completeOperationAndDrain()

        case .disabled, .restoring, .errorStopped:
            return
        }
    }

    /// Refreshes system facts when an activity sample is temporarily unavailable.
    /// Disabled automation performs a read-only display refresh. A starting
    /// session still detects manual changes and applies only the safe High Power
    /// availability fallback.
    public func refreshWithoutActivity() async {
        if case .errorStopped = status {
            return
        }

        if operationInProgress {
            pendingWarmupRefresh = true
            return
        }

        switch status {
        case .disabled:
            operationInProgress = true
            do {
                let actual = try await powerSystem.readSnapshot()
                currentPower = actual
                lastConfirmedMode = actual.mode
                status = .disabled
            } catch {
                enterError(readFailure(for: error))
            }
            await completeOperationAndDrain()

        case .starting:
            guard sessionIsActive else { return }
            operationInProgress = true
            await performWarmupRefresh()
            await completeOperationAndDrain()

        case .pausedForManualChange:
            operationInProgress = true
            do {
                let actual = try await powerSystem.readSnapshot()
                currentPower = actual
                lastConfirmedMode = actual.mode
            } catch {
                enterError(readFailure(for: error))
            }
            await completeOperationAndDrain()

        case .running, .restoring, .errorStopped:
            return
        }
    }

    public func updateConfig(
        _ newConfig: AutomationConfig,
        activity: ActivitySnapshot?
    ) async {
        config = newConfig
        guard sessionIsActive, let activity else { return }

        if operationInProgress {
            pendingActivity = activity
            return
        }
        await evaluate(activity: activity)
    }

    /// Resumes from a manual-change pause without clearing the session's sticky
    /// manual-override marker. That marker must continue to block takeover restoration.
    public func resumeAutomation(activity: ActivitySnapshot?) async {
        guard sessionIsActive, status == .pausedForManualChange else { return }

        if operationInProgress {
            pendingResumeRequested = true
            pendingResumeActivity = activity
            return
        }

        operationInProgress = true
        let actual: PowerSnapshot
        do {
            actual = try await powerSystem.readSnapshot()
        } catch {
            enterError(readFailure(for: error))
            await completeOperationAndDrain()
            return
        }

        currentPower = actual
        lastConfirmedMode = actual.mode
        status = activity == nil ? .starting : .running

        if let activity {
            await performEvaluation(
                activity: activity,
                initialPower: actual,
                detectManualChange: false
            )
        } else {
            await performWarmupRefresh(
                initialPower: actual,
                detectManualChange: false
            )
        }
        await completeOperationAndDrain()
    }

    public func disableAutomation() async {
        await requestStop(.disable)
    }

    public func prepareForTermination() async {
        await requestStop(.terminate)
    }

    /// Stops an active session after the activity input source fails. Timer loops
    /// must not call this repeatedly or attempt automatic recovery.
    public func stopForActivityReadFailure() {
        if case .errorStopped = status {
            return
        }
        if operationInProgress {
            pendingActivityReadFailure = true
            pendingActivity = nil
            pendingWarmupRefresh = false
            return
        }
        enterError(.systemReadFailed)
    }

    private func requestStop(_ intent: StopIntent) async {
        if operationInProgress, sessionIsActive || status == .starting {
            pendingActivity = nil
            pendingWarmupRefresh = false
            pendingResumeRequested = false
            pendingResumeActivity = nil
            if pendingStop != .terminate {
                pendingStop = intent
            }
            await withCheckedContinuation { continuation in
                stopWaiters.append(continuation)
            }
            return
        }

        guard sessionIsActive else {
            if intent == .disable {
                status = .disabled
                lastError = nil
            }
            return
        }

        if operationInProgress {
            pendingActivity = nil
            pendingWarmupRefresh = false
            pendingResumeRequested = false
            pendingResumeActivity = nil
            if pendingStop != .terminate {
                pendingStop = intent
            }
            await withCheckedContinuation { continuation in
                stopWaiters.append(continuation)
            }
            return
        }

        operationInProgress = true
        await performStop(intent)
        operationInProgress = false
        resumeStopWaiters()
    }

    private func performEvaluation(
        activity: ActivitySnapshot,
        initialPower: PowerSnapshot? = nil,
        detectManualChange: Bool = true
    ) async {
        let actual: PowerSnapshot
        if let initialPower {
            actual = initialPower
        } else {
            do {
                actual = try await powerSystem.readSnapshot()
            } catch {
                enterError(readFailure(for: error))
                return
            }
        }

        let expected = lastConfirmedMode
        if detectManualChange, let expected, actual.mode != expected {
            currentPower = actual
            lastConfirmedMode = actual.mode
            manualOverrideSeen = true
            if config.pauseOnManualPowerModeChange {
                status = .pausedForManualChange
                return
            }
        }

        currentPower = actual
        lastConfirmedMode = actual.mode

        let decision: PowerDecision
        do {
            decision = try DecisionEngine.decide(
                power: actual,
                activity: activity,
                config: config
            )
        } catch {
            enterError(.invalidDecisionInput)
            return
        }

        await performAutomaticSwitch(
            decision: decision,
            actual: actual,
            successStatus: .running
        )
    }

    private func performWarmupRefresh(
        initialPower: PowerSnapshot? = nil,
        detectManualChange: Bool = true
    ) async {
        let actual: PowerSnapshot
        if let initialPower {
            actual = initialPower
        } else {
            do {
                actual = try await powerSystem.readSnapshot()
            } catch {
                enterError(readFailure(for: error))
                return
            }
        }

        let expected = lastConfirmedMode
        if detectManualChange, let expected, actual.mode != expected {
            currentPower = actual
            lastConfirmedMode = actual.mode
            manualOverrideSeen = true
            if config.pauseOnManualPowerModeChange {
                status = .pausedForManualChange
                return
            }
        }

        currentPower = actual
        lastConfirmedMode = actual.mode

        guard actual.mode == .highPower, !actual.highPowerAvailable else {
            status = .starting
            return
        }

        await performAutomaticSwitch(
            decision: PowerDecision(
                targetMode: .automatic,
                reason: .highPowerBecameUnavailable
            ),
            actual: actual,
            successStatus: .starting
        )
    }

    private func performAutomaticSwitch(
        decision: PowerDecision,
        actual: PowerSnapshot,
        successStatus: AutomationStatus
    ) async {
        guard decision.targetMode != actual.mode else {
            status = successStatus
            return
        }

        guard decision.targetMode != .highPower || actual.highPowerAvailable else {
            // Defense in depth: never emit a High Power request when unavailable.
            enterError(.invalidDecisionInput)
            return
        }

        // A stop or input failure that arrived while the initial read was
        // suspended wins before any system write starts.
        guard pendingStop == nil, !pendingActivityReadFailure else { return }

        // Capture the user's current brightness immediately before Governor
        // enters Low Power. The display service is intentionally best-effort:
        // unsupported hardware or an unavailable API must not stop automation.
        let capturedBrightness: DisplayBrightnessSnapshot?
        if config.restoreBrightnessAfterLowPower,
           actual.mode != .lowPower,
           decision.targetMode == .lowPower
        {
            capturedBrightness = await displayBrightness.captureCurrentBrightness()
        } else {
            capturedBrightness = nil
        }

        // Brightness capture suspends the actor, so a stop or activity-source
        // failure that arrived during that read still wins before the write.
        guard pendingStop == nil, !pendingActivityReadFailure else { return }

        switchInFlight = true
        do {
            try await powerSystem.requestMode(
                decision.targetMode,
                source: actual.source,
                controlStyle: actual.controlStyle
            )
        } catch {
            switchInFlight = false
            enterError(requestFailure(for: error))
            return
        }

        let confirmed: PowerSnapshot
        do {
            confirmed = try await powerSystem.readSnapshot()
        } catch {
            switchInFlight = false
            enterError(.confirmationReadFailed)
            return
        }
        switchInFlight = false

        guard confirmed.mode == decision.targetMode else {
            currentPower = confirmed
            lastConfirmedMode = confirmed.mode
            enterError(
                .confirmationMismatch(
                    expected: decision.targetMode,
                    actual: confirmed.mode
                )
            )
            return
        }

        currentPower = confirmed
        lastConfirmedMode = confirmed.mode
        if confirmed.mode == .lowPower, let capturedBrightness {
            brightnessBeforeLowPower = capturedBrightness
        } else if actual.mode == .lowPower, confirmed.mode != .lowPower {
            await restoreBrightnessAfterLowPower()
        }
        lastSwitchReason = decision.reason
        history.append(
            SwitchHistoryEntry(
                timestamp: confirmed.observedAt,
                oldMode: actual.mode,
                newMode: confirmed.mode,
                reason: decision.reason
            )
        )
        history = Array(history.suffix(20))

        do {
            try await historyStore.saveHistory(history)
            status = successStatus
        } catch {
            enterError(.historyWriteFailed)
        }
    }

    private func performStop(_ intent: StopIntent) async {
        let previousStatus = status
        status = .restoring

        // Teardown restoration is a lifecycle operation, not an automatic rule
        // evaluation. It remains eligible after an error stop when the system's
        // current mode can still be confirmed and no manual override occurred.
        guard !manualOverrideSeen, previousStatus != .pausedForManualChange else {
            clearSession()
            status = .disabled
            return
        }
        guard let takeoverMode, let expected = lastConfirmedMode else {
            clearSession()
            status = .disabled
            return
        }

        let actual: PowerSnapshot
        do {
            actual = try await powerSystem.readSnapshot()
        } catch {
            clearSession(keepingCurrentState: true)
            enterError(readFailure(for: error))
            return
        }

        currentPower = actual
        if actual.mode != expected {
            // An external change raced with shutdown. Never overwrite it.
            lastConfirmedMode = actual.mode
            manualOverrideSeen = true
            clearSession(keepingCurrentState: true)
            status = .disabled
            return
        }

        lastConfirmedMode = actual.mode
        guard actual.mode != takeoverMode else {
            clearSession(keepingCurrentState: true)
            status = .disabled
            return
        }

        guard takeoverMode != .highPower || actual.highPowerAvailable else {
            clearSession(keepingCurrentState: true)
            enterError(.highPowerUnavailableForRestoration)
            return
        }

        switchInFlight = true
        do {
            try await powerSystem.requestMode(
                takeoverMode,
                source: actual.source,
                controlStyle: actual.controlStyle
            )
        } catch {
            switchInFlight = false
            clearSession(keepingCurrentState: true)
            enterError(requestFailure(for: error))
            return
        }

        let confirmed: PowerSnapshot
        do {
            confirmed = try await powerSystem.readSnapshot()
        } catch {
            switchInFlight = false
            clearSession(keepingCurrentState: true)
            enterError(.confirmationReadFailed)
            return
        }
        switchInFlight = false

        currentPower = confirmed
        lastConfirmedMode = confirmed.mode
        guard confirmed.mode == takeoverMode else {
            clearSession(keepingCurrentState: true)
            enterError(
                .confirmationMismatch(expected: takeoverMode, actual: confirmed.mode)
            )
            return
        }

        if actual.mode == .lowPower, confirmed.mode != .lowPower {
            await restoreBrightnessAfterLowPower()
        }

        // Restoration is intentionally not added to automatic-switch history.
        clearSession(keepingCurrentState: true)
        status = .disabled

        _ = intent // Both user disable and normal termination share the same contract.
    }

    private func completeOperationAndDrain() async {
        if let stop = pendingStop {
            pendingStop = nil
            pendingActivity = nil
            pendingResumeActivity = nil
            await performStop(stop)
            operationInProgress = false
            resumeStopWaiters()
            return
        }

        if pendingActivityReadFailure {
            pendingActivityReadFailure = false
            enterError(.systemReadFailed)
            operationInProgress = false
            return
        }

        if pendingResumeRequested,
           sessionIsActive,
           status == .pausedForManualChange
        {
            let resume = pendingResumeActivity
            pendingResumeRequested = false
            pendingResumeActivity = nil
            operationInProgress = false
            await resumeAutomation(activity: resume)
            return
        }

        if let activity = pendingActivity,
           sessionIsActive,
           status == .running || status == .starting
        {
            pendingActivity = nil
            operationInProgress = false
            await evaluate(activity: activity)
            return
        }

        if pendingWarmupRefresh {
            pendingWarmupRefresh = false
            operationInProgress = false
            await refreshWithoutActivity()
            return
        }

        pendingActivity = nil
        pendingWarmupRefresh = false
        pendingResumeRequested = false
        pendingResumeActivity = nil
        pendingActivityReadFailure = false
        operationInProgress = false
    }

    private func clearSession(
        keepingCurrentState: Bool = false,
        preservingPendingStop: Bool = false
    ) {
        sessionIsActive = false
        takeoverMode = nil
        pendingActivity = nil
        pendingWarmupRefresh = false
        pendingResumeRequested = false
        pendingResumeActivity = nil
        pendingActivityReadFailure = false
        if !preservingPendingStop {
            pendingStop = nil
        }
        switchInFlight = false
        brightnessBeforeLowPower = nil
        if !keepingCurrentState {
            lastConfirmedMode = currentPower?.mode
        }
    }

    private func resumeStopWaiters() {
        let waiters = stopWaiters
        stopWaiters.removeAll(keepingCapacity: true)
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func enterError(_ failure: AutomationFailure) {
        status = .errorStopped(failure)
        lastError = failure
        switchInFlight = false
        pendingActivity = nil
        pendingWarmupRefresh = false
        pendingResumeRequested = false
        pendingResumeActivity = nil
        pendingActivityReadFailure = false
    }

    private func restoreBrightnessAfterLowPower() async {
        guard let snapshot = brightnessBeforeLowPower else { return }
        // Consume the snapshot before suspension so a queued lifecycle action
        // cannot apply the same stale value twice.
        brightnessBeforeLowPower = nil
        guard config.restoreBrightnessAfterLowPower else { return }
        await displayBrightness.restoreBrightness(
            snapshot,
            after: AutomationConfig.clampedBrightnessRestoreDelay(
                config.brightnessRestoreDelayMilliseconds
            )
        )
    }

    private func permissionFailure(for error: any Error) -> AutomationFailure {
        if let failure = error as? PowerSystemClientFailure, failure == .readFailed {
            return .systemReadFailed
        }
        return .permissionDenied
    }

    private func readFailure(for error: any Error) -> AutomationFailure {
        if let failure = error as? PowerSystemClientFailure, failure == .permissionDenied {
            return .permissionDenied
        }
        return .systemReadFailed
    }

    private func requestFailure(for error: any Error) -> AutomationFailure {
        if let failure = error as? PowerSystemClientFailure, failure == .permissionDenied {
            return .permissionDenied
        }
        return .switchRequestFailed
    }
}
