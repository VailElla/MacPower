import Foundation
import GovernorCore
import Testing
@testable import Governor

@Suite
struct ActivityMonitorTests {
    @Test
    func testPublishesIdleSnapshotImmediately() async throws {
        let monitor = ActivityMonitor(idleReader: { 42 })
        let snapshot = try await monitor.sample()
        let confirmed = try #require(snapshot)
        #expect(confirmed.userIdleDuration == 42)
    }

    @Test
    func testRejectsInvalidIdleDuration() async throws {
        let monitor = ActivityMonitor(idleReader: { .nan })

        do {
            _ = try await monitor.sample()
            Issue.record("Expected invalid idle duration to throw.")
        } catch {
            #expect(error as? ActivityMonitorError == .idleReadFailed)
        }
    }
}
