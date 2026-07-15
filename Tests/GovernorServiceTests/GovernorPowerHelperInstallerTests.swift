import Testing
@testable import Governor

@Suite("SMAppService helper registration")
struct GovernorPowerHelperInstallerTests {
    @Test
    @MainActor
    func registersAtMostOnceWhileApprovalIsPendingAcrossAppRelaunches() {
        let service = FakeGovernorPowerHelperService(
            status: .notRegistered,
            statusAfterRegister: .requiresApproval
        )

        let firstInstall = GovernorPowerHelperInstaller(service: service)
        #expect(throws: GovernorPowerHelperInstallationError.requiresApproval) {
            try firstInstall.ensureAvailable()
        }
        #expect(service.registerCount == 1)

        // A new app process observes the persisted Service Management status.
        // It must not try a second privileged registration just because the user
        // has not approved the first request yet.
        let relaunchedApp = GovernorPowerHelperInstaller(service: service)
        #expect(throws: GovernorPowerHelperInstallationError.requiresApproval) {
            try relaunchedApp.ensureAvailable()
        }
        #expect(service.registerCount == 1)
    }

    @Test
    @MainActor
    func enabledHelperSkipsRegistrationOnEveryFutureEnable() throws {
        let service = FakeGovernorPowerHelperService(
            status: .enabled,
            statusAfterRegister: .enabled
        )
        let installer = GovernorPowerHelperInstaller(service: service)

        try installer.ensureAvailable()
        try installer.ensureAvailable()

        #expect(service.registerCount == 0)
    }

    @Test
    @MainActor
    func newlyRegisteredEnabledHelperSucceedsWithoutRepeatedInteraction() throws {
        let service = FakeGovernorPowerHelperService(
            status: .notRegistered,
            statusAfterRegister: .enabled
        )
        let installer = GovernorPowerHelperInstaller(service: service)

        try installer.ensureAvailable()
        try installer.ensureAvailable()

        #expect(service.registerCount == 1)
    }

    @Test
    @MainActor
    func missingBundleDaemonFailsClosedWithoutRegistration() {
        let service = FakeGovernorPowerHelperService(
            status: .notFound,
            statusAfterRegister: .enabled
        )
        let installer = GovernorPowerHelperInstaller(service: service)

        #expect(throws: GovernorPowerHelperInstallationError.helperNotFound) {
            try installer.ensureAvailable()
        }
        #expect(service.registerCount == 0)
    }
}

@MainActor
private final class FakeGovernorPowerHelperService: GovernorPowerHelperServiceManaging {
    private(set) var status: GovernorPowerHelperServiceStatus
    private let statusAfterRegister: GovernorPowerHelperServiceStatus
    private(set) var registerCount = 0

    init(
        status: GovernorPowerHelperServiceStatus,
        statusAfterRegister: GovernorPowerHelperServiceStatus
    ) {
        self.status = status
        self.statusAfterRegister = statusAfterRegister
    }

    func register() {
        registerCount += 1
        status = statusAfterRegister
    }
}
