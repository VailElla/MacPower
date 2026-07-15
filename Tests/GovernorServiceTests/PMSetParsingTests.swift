import Testing
@testable import Governor

@Suite
struct PMSetParsingTests {
    @Test
    func testParsesUnifiedLiveMode() throws {
        let state = try PMSetOutputParser.parseLiveState(
            """
            System-wide power settings:
             SleepDisabled 0
            Currently in use:
             powermode            2
            """
        )

        #expect(state == PMSetParsedLiveState(modeValue: 2, controlStyle: .unifiedPowerMode))
    }

    @Test
    func testParsesLegacyLowPowerMode() throws {
        let state = try PMSetOutputParser.parseLiveState(" lowpowermode 1\n")
        #expect(state == PMSetParsedLiveState(modeValue: 1, controlStyle: .legacyLowPowerMode))
    }

    @Test
    func testRejectsOutOfRangeMode() {
        do {
            _ = try PMSetOutputParser.parseLiveState(" powermode 3\n")
            Issue.record("Expected an invalid power-mode error.")
        } catch {
            #expect(error as? PMSetParseError == .invalidPowerMode("3"))
        }
    }

    @Test
    func testParsesCurrentSourceAndCapabilities() throws {
        let source = try PMSetOutputParser.parseCurrentPowerSource(
            """
            Now drawing from 'AC Power'
             -InternalBattery-0 80%; AC attached
            """
        )
        let capabilities = try PMSetOutputParser.parseCapabilities(
            """
            Capabilities for AC Power:
             sleep
             lowpowermode
             highpowermode
            """
        )

        #expect(source == .ac)
        #expect(
            capabilities
                == PMSetParsedCapabilities(
                    source: .ac,
                    supportsLowPower: true,
                    supportsHighPower: true
                )
        )
    }

    @Test
    func testExposesOnlyReadOnlyAppSideArguments() {
        #expect(PMSetArguments.executablePath == "/usr/bin/pmset")
        #expect(PMSetArguments.readPowerSource == ["-g", "batt"])
        #expect(PMSetArguments.readLive == ["-g", "live"])
        #expect(PMSetArguments.readCapabilities == ["-g", "cap"])
    }
}
