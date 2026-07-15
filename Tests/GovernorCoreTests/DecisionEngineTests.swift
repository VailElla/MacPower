import Testing
@testable import GovernorCore

@Suite("Decision engine")
struct DecisionEngineTests {
    private let defaultConfig = AutomationConfig()

    @Test func defaultActivePlanUsesHighPower() throws {
        let decision = try DecisionEngine.decide(
            power: makePower(.automatic),
            activity: makeActivity(cpu: 0, idle: 0),
            config: defaultConfig
        )

        #expect(decision.targetMode == .highPower)
        #expect(decision.reason == .userActive)
    }

    @Test func idlePlanDoesNotDependOnCPUUsage() throws {
        let decision = try DecisionEngine.decide(
            power: makePower(.automatic),
            activity: makeActivity(cpu: 100, idle: 300),
            config: defaultConfig
        )

        #expect(decision.targetMode == .lowPower)
        #expect(decision.reason == .idleThresholdReached)
    }

    @Test func configuredActivePlanIsUsedBeforeIdleThreshold() throws {
        let config = AutomationConfig(activePowerMode: .automatic, idlePowerMode: .lowPower)
        let decision = try DecisionEngine.decide(
            power: makePower(.lowPower),
            activity: makeActivity(cpu: 80, idle: 299.999),
            config: config
        )

        #expect(decision.targetMode == .automatic)
        #expect(decision.reason == .userActive)
    }

    @Test func configuredIdlePlanIsUsedAtIdleThreshold() throws {
        let config = AutomationConfig(activePowerMode: .highPower, idlePowerMode: .automatic)
        let decision = try DecisionEngine.decide(
            power: makePower(.highPower),
            activity: makeActivity(cpu: 0, idle: 300),
            config: config
        )

        #expect(decision.targetMode == .automatic)
        #expect(decision.reason == .idleThresholdReached)
    }

    @Test func unavailableHighPowerFallsBackForActivePlan() throws {
        let decision = try DecisionEngine.decide(
            power: makePower(.automatic, highPowerAvailable: false),
            activity: makeActivity(cpu: 0, idle: 0),
            config: defaultConfig
        )

        #expect(decision.targetMode == .automatic)
        #expect(decision.reason == .highPowerBecameUnavailable)
    }

    @Test func unavailableHighPowerFallsBackForIdlePlan() throws {
        let config = AutomationConfig(activePowerMode: .automatic, idlePowerMode: .highPower)
        let decision = try DecisionEngine.decide(
            power: makePower(.lowPower, highPowerAvailable: false),
            activity: makeActivity(cpu: 0, idle: 300),
            config: config
        )

        #expect(decision.targetMode == .automatic)
        #expect(decision.reason == .highPowerBecameUnavailable)
    }

    @Test func invalidActivityAndConfigInputsAreRejected() {
        #expect(throws: DecisionEngineError.invalidIdleDuration) {
            try DecisionEngine.decide(
                power: makePower(.automatic),
                activity: makeActivity(cpu: 0, idle: -1),
                config: defaultConfig
            )
        }
        #expect(throws: DecisionEngineError.invalidIdleThreshold) {
            try DecisionEngine.decide(
                power: makePower(.automatic),
                activity: makeActivity(cpu: 0, idle: 0),
                config: AutomationConfig(idleThreshold: -.infinity)
            )
        }
    }
}
